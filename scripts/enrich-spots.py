#!/usr/bin/env python3
"""enrich-spots.py — fetch a representative photo for each spot.

Strategy (per spot):
  1. If `officialUrl` exists → fetch and parse `og:image`
  2. Else → query Wikipedia (ja) page-images by spot name
  3. Else → leave blank (manual / Google Places API later)

Output: data/spot-photos.json    { "<spot_id>": { "photo": "<url>", "source": "og|wiki" } }
"""
from __future__ import annotations
import json, re, ssl, sys, time, urllib.parse, urllib.request
from html.parser import HTMLParser
from pathlib import Path

try:
    import certifi
    SSL_CTX = ssl.create_default_context(cafile=certifi.where())
except ImportError:
    SSL_CTX = ssl.create_default_context()

ROOT = Path(__file__).resolve().parent.parent
SPOTS_JS = ROOT / "spots-data.js"
OUT = ROOT / "data" / "spot-photos.json"

UA = "KODOCO/0.1 (personal aggregator; +https://github.com/99letters)"
DELAY = 0.5
MAX_BYTES = 524288


def fetch(url: str) -> bytes:
    req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "text/html,application/json"})
    with urllib.request.urlopen(req, timeout=20, context=SSL_CTX) as r:
        return r.read(MAX_BYTES)


# ── parse spots-data.js (simple regex; handles current handwritten format) ──
SPOT_BLOCK_RE = re.compile(r"\{\s*id:'([^']+)'.*?\}", re.DOTALL)
NAME_RE = re.compile(r"name:'([^']+)'")
OFFICIAL_RE = re.compile(r"officialUrl:'([^']+)'")


def parse_spots() -> list[dict]:
    text = SPOTS_JS.read_text(encoding="utf-8")
    spots = []
    for m in SPOT_BLOCK_RE.finditer(text):
        block = m.group(0)
        sid = m.group(1)
        name_m = NAME_RE.search(block)
        official_m = OFFICIAL_RE.search(block)
        spots.append({
            "id": sid,
            "name": name_m.group(1) if name_m else "",
            "officialUrl": official_m.group(1) if official_m else None,
        })
    return spots


# ── og:image extraction ─────────────────────────────────────
class OgFinder(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.image: str | None = None

    def handle_starttag(self, tag, attrs):
        if tag != "meta":
            return
        d = dict(attrs)
        prop = (d.get("property") or d.get("name") or "").lower()
        if prop in ("og:image", "twitter:image") and not self.image:
            self.image = d.get("content")


def og_image_from(url: str) -> str | None:
    try:
        html = fetch(url).decode("utf-8", errors="replace")
    except Exception as e:
        print(f"  fetch failed: {e}", file=sys.stderr)
        return None
    p = OgFinder()
    try:
        p.feed(html)
    except Exception:
        pass
    if not p.image:
        return None
    # resolve relative to absolute
    return urllib.parse.urljoin(url, p.image)


# ── Wikipedia (ja) page-image lookup ─────────────────────────
WIKI_API = "https://ja.wikipedia.org/w/api.php"


_GENERIC_TOKENS = {"公園", "施設", "センター", "ホール", "美術館", "博物館", "館", "店", "市", "町"}


def _extract_proper_nouns(name: str) -> list[str]:
    """連続漢字 2 文字以上の塊から、一般名詞を除いたものを返す。"""
    chunks = re.findall(r"[一-龥]{2,}", name)
    out = []
    for c in chunks:
        # generic な末尾語を剥ぐ (e.g., '矢橋帰帆島公園' → '矢橋帰帆島')
        for g in sorted(_GENERIC_TOKENS, key=len, reverse=True):
            if c.endswith(g) and len(c) > len(g):
                c = c[: -len(g)]
                break
        if c and c not in _GENERIC_TOKENS and len(c) >= 2:
            out.append(c)
    # カタカナ塊 4 文字以上も拾う (店名など)
    out.extend(re.findall(r"[ァ-ヴー]{4,}", name))
    return out


def _title_relevant(query: str, candidate: str) -> bool:
    """search 結果タイトル candidate が query のスポットを指してそうか判定。"""
    if not candidate:
        return False
    if query in candidate or candidate in query:
        return True
    keywords = _extract_proper_nouns(query)
    if not keywords:
        # 漢字 / カタカナ塊が無いケース。完全一致 fallback
        return query == candidate
    # 固有名詞の少なくとも 1 つが候補タイトルに含まれる
    return any(k in candidate for k in keywords)


def wiki_image_for(name: str) -> str | None:
    """1) direct title (with redirects)
       2) variants (parens stripped, before space)
       3) loose search → only adopt results whose title contains a proper-noun chunk
    """
    img = _wiki_pageimage(name)
    if img:
        return img
    variants = []
    for stripper in [
        lambda s: re.sub(r"[（(].*?[)）]", "", s).strip(),
        lambda s: re.sub(r"\s.*$", "", s),
    ]:
        v = stripper(name)
        if v and v != name and v not in variants:
            variants.append(v)
    for v in variants:
        img = _wiki_pageimage(v)
        if img:
            return img
    # loose search with strict relevance filter
    params = {
        "action": "query", "list": "search",
        "srsearch": name, "srlimit": "5", "format": "json",
    }
    try:
        data = json.loads(fetch(f"{WIKI_API}?{urllib.parse.urlencode(params)}").decode())
    except Exception:
        return None
    for hit in data.get("query", {}).get("search", []):
        title = hit.get("title", "")
        if not _title_relevant(name, title):
            continue
        img = _wiki_pageimage(title)
        if img:
            return img
    return None


def _wiki_pageimage(title: str) -> str | None:
    params = {
        "action": "query", "titles": title,
        "prop": "pageimages", "pithumbsize": "800",
        "format": "json", "redirects": "1",
    }
    try:
        data = json.loads(fetch(f"{WIKI_API}?{urllib.parse.urlencode(params)}").decode())
    except Exception:
        return None
    for k, v in (data.get("query", {}).get("pages") or {}).items():
        if k == "-1":
            continue
        thumb = v.get("thumbnail")
        if thumb and thumb.get("source"):
            return thumb["source"]
    return None


# ── main ────────────────────────────────────────────────────
def main() -> None:
    spots = parse_spots()
    print(f"loaded {len(spots)} spots")

    existing = {}
    if OUT.exists():
        existing = json.loads(OUT.read_text())

    updated = dict(existing)
    n_og, n_wiki, n_skip = 0, 0, 0

    for i, s in enumerate(spots, 1):
        sid = s["id"]
        if sid in updated and updated[sid].get("photo"):
            continue  # already enriched
        photo, src = None, None
        if s["officialUrl"]:
            print(f"[{i}/{len(spots)}] og: {s['name']} ← {s['officialUrl']}")
            photo = og_image_from(s["officialUrl"])
            if photo:
                src = "og"; n_og += 1
            time.sleep(DELAY)
        if not photo:
            print(f"[{i}/{len(spots)}] wiki: {s['name']}")
            photo = wiki_image_for(s["name"])
            if photo:
                src = "wiki"; n_wiki += 1
            time.sleep(DELAY)
        if photo:
            updated[sid] = {"photo": photo, "source": src, "name": s["name"]}
        else:
            n_skip += 1
            print(f"  no photo for {s['name']}", file=sys.stderr)
        # checkpoint every 20
        if (i % 20) == 0:
            OUT.write_text(json.dumps(updated, ensure_ascii=False, indent=2))

    OUT.write_text(json.dumps(updated, ensure_ascii=False, indent=2))
    print()
    print(f"og: {n_og}, wiki: {n_wiki}, missing: {n_skip}")
    print(f"total stored: {len(updated)} / {len(spots)} -> {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()

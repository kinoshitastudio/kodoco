# KODOCO Supabase セットアップ手順

完全に Atelier とは別の Supabase project を立てる前提。Atelier には一切影響しない。

---

## Step 0. Supabase project 作成

1. [supabase.com](https://supabase.com) にログイン
2. New project → 名前: `kodoco`、region: `Tokyo (ap-northeast-1)`
3. DB password はランダム生成、保存
4. project ready まで 1〜2 分待つ
5. **Project Settings → API** で以下をメモ:
   - `Project URL` （例: `https://xxxxxxxxxxxxxxx.supabase.co`）
   - `anon public key`（`eyJhbGc...` で始まる長い文字列）

---

## Step 1. SQL を順に実行

Supabase Dashboard → **SQL Editor** → **New query** で以下を **順番通り** に貼り付けて Run:

| 順 | ファイル | 内容 |
|---|---|---|
| 1 | `01_profiles_with_tos.sql` | profiles テーブル + auto-create trigger + TOS field + admin role |
| 2 | `02_user_state.sql` | お気に入り・解禁状態・achievements を JSONB 単一行で保持 |
| 3 | `03_reviews.sql` | 口コミテーブル + モデレーション status |
| 4 | `04_user_spots.sql` | ユーザー投稿スポット + pending/approved/rejected フロー |

各ファイル末尾の「確認用クエリ」を Run して、テーブルが作られたか確認。

---

## Step 2. 自分を admin に昇格

最初のサインアップで自分のアカウントが auto-create される（`profiles.role='user'`）。

それを Dashboard の SQL Editor で admin に昇格させる:

```sql
-- 自分の admin email に置換してから実行してください
update public.profiles
set role = 'admin'
where id = (select id from auth.users where email = '<YOUR_ADMIN_EMAIL>');
```

---

## Step 3. アプリ側 client 接続

`app.html` に Supabase JS client を追加 + URL/anon key を埋め込み（次フェーズ）。

```html
<script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>
<script>
  const SUPABASE_URL = '__YOUR_PROJECT_URL__';
  const SUPABASE_ANON_KEY = '__YOUR_ANON_KEY__';
  const sb = supabase.createClient(SUPABASE_URL, SUPABASE_ANON_KEY);
</script>
```

---

## テーブル相関図

```
auth.users (Supabase 管理)
    │
    │ 1:1
    ▼
public.profiles
  id, handle, display_name, avatar_url, role, tos_accepted_at
    │
    │ 1:1
    ├─→ public.kodoco_user_state
    │     state JSONB (favorites / unlockedChars / achievements / settings)
    │
    │ 1:N
    ├─→ public.kodoco_reviews
    │     spot_id, rating, body, status (published/flagged/removed)
    │
    │ 1:N
    └─→ public.kodoco_user_spots
          data JSONB, status (pending/approved/rejected)
```

---

## RLS まとめ

| テーブル | 読 | 書 (insert) | 編集 (update) | 削除 |
|---|---|---|---|---|
| `profiles` | 全員 | 自分のみ | 自分のみ | 自分のみ |
| `kodoco_user_state` | 自分のみ | 自分のみ | 自分のみ | 自分のみ |
| `kodoco_reviews` | 全員 (publishedのみ) | 認証済 | 自分の row | 自分 / admin |
| `kodoco_user_spots` | 全員 (approvedのみ) | 認証済 (status=pending) | 自分の pending / admin | 自分 (pending/rejected) / admin |

---

## ロールバック (やり直したい時)

すべてのテーブルを drop:

```sql
drop table if exists public.kodoco_user_spots cascade;
drop table if exists public.kodoco_reviews cascade;
drop table if exists public.kodoco_user_state cascade;
drop table if exists public.profiles cascade;
drop function if exists public.handle_new_user cascade;
drop function if exists public.is_admin cascade;
drop function if exists public.kodoco_user_state_touch cascade;
drop function if exists public.kodoco_reviews_touch cascade;
drop function if exists public.kodoco_user_spots_touch cascade;
```

そして 01〜04 を再実行。

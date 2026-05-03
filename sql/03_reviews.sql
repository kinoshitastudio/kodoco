-- KODOCO — Phase 3: reviews テーブル（口コミ）
-- Supabase SQL Editor で New query → 全コピペ → Run
--
-- 各スポットに対する口コミ。ユーザー1人で複数スポットに複数 review 投稿可。
-- 同じ user × 同じ spot で 2件以上書ける（再訪レビュー）。
-- モデレーション: status 列で 'published' / 'flagged' / 'removed'。
-- 公開は published のみ。flagged は report 件数閾値で auto-flag（後述）。

create table if not exists public.kodoco_reviews (
  id uuid primary key default gen_random_uuid(),
  spot_id text not null,                      -- 'yabashi', 'asoble', etc. (spots-data.js の id)
  user_id uuid not null references auth.users(id) on delete cascade,
  user_handle text,                           -- 表示用スナップショット
  rating smallint check (rating between 1 and 5),
  body text not null check (char_length(body) between 1 and 2000),
  age_groups int[],                           -- 投稿時点の子どもの年齢グループ
  visited_on date,                            -- 訪問日（任意）
  status text not null default 'published'
    check (status in ('published', 'flagged', 'removed')),
  flag_count int not null default 0,
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create index if not exists reviews_spot_idx on public.kodoco_reviews (spot_id, created_at desc);
create index if not exists reviews_user_idx on public.kodoco_reviews (user_id, created_at desc);
create index if not exists reviews_status_idx on public.kodoco_reviews (status);

alter table public.kodoco_reviews enable row level security;

-- ──────────────── ポリシー ────────────────
-- 公開 review は全員（未認証含む）が読める
drop policy if exists reviews_select_published on public.kodoco_reviews;
create policy reviews_select_published on public.kodoco_reviews
  for select using (
    status = 'published'
    or user_id = auth.uid()      -- 自分の review は flagged/removed でも見える
    or public.is_admin()         -- admin は全部見える
  );

-- 認証済みユーザーのみ insert
drop policy if exists reviews_owner_insert on public.kodoco_reviews;
create policy reviews_owner_insert on public.kodoco_reviews
  for insert with check (user_id = auth.uid());

-- 自分の review のみ編集（status は触れない、別途 admin only に分離可能）
drop policy if exists reviews_owner_update on public.kodoco_reviews;
create policy reviews_owner_update on public.kodoco_reviews
  for update
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- 自分の review のみ削除（admin も削除可）
drop policy if exists reviews_owner_delete on public.kodoco_reviews;
create policy reviews_owner_delete on public.kodoco_reviews
  for delete using (user_id = auth.uid() or public.is_admin());

-- admin は status / flag_count の更新可（モデレーション）
drop policy if exists reviews_admin_moderate on public.kodoco_reviews;
create policy reviews_admin_moderate on public.kodoco_reviews
  for update using (public.is_admin()) with check (public.is_admin());

-- ──────────────── トリガー: updated_at ────────────────
create or replace function public.kodoco_reviews_touch()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

drop trigger if exists kodoco_reviews_touch_trg on public.kodoco_reviews;
create trigger kodoco_reviews_touch_trg
  before update on public.kodoco_reviews
  for each row execute procedure public.kodoco_reviews_touch();

-- ──────────────── 確認用クエリ ────────────────
-- select spot_id, count(*) from public.kodoco_reviews where status='published' group by spot_id;
-- select * from public.kodoco_reviews order by created_at desc limit 10;

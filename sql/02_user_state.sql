-- KODOCO — Phase 2: user_state テーブル
-- Supabase SQL Editor で New query → 全コピペ → Run
--
-- 各ユーザーの localStorage 全体（お気に入り・解禁キャラ・achievements 等）を
-- 単一行 / ユーザー で JSONB 保持する戦略。
-- 端末をまたいで同期できる + サーバー側でアグリゲートしやすい。
--
-- 想定される state 構造（厳密なスキーマは strict にせず、JSONB で柔軟運用）:
--   {
--     "favorites": ["yabashi", "asoble", ...],
--     "unlockedChars": ["hana", "kuro"],
--     "achievements": { "favorites_count": 5, "reviews_count": 3, "spots_added": 1 },
--     "settings": { "mascot": "kodo", "theme": "warm" },
--     "children": [{ "age": 2, "name": "..." }],
--     "lastSeenAt": "2026-05-03T..."
--   }

create table if not exists public.kodoco_user_state (
  user_id uuid primary key references auth.users(id) on delete cascade,
  state jsonb not null default '{}'::jsonb,
  updated_at timestamptz default now()
);

alter table public.kodoco_user_state enable row level security;

-- 自分の state は全権限。他人の state は触れない（プライベート）
drop policy if exists user_state_owner on public.kodoco_user_state;
create policy user_state_owner on public.kodoco_user_state
  for all
  using (user_id = auth.uid())
  with check (user_id = auth.uid());

-- updated_at 自動更新
create or replace function public.kodoco_user_state_touch()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  return new;
end $$;

drop trigger if exists kodoco_user_state_touch_trg on public.kodoco_user_state;
create trigger kodoco_user_state_touch_trg
  before update on public.kodoco_user_state
  for each row execute procedure public.kodoco_user_state_touch();

-- ──────────────── 確認用クエリ ────────────────
-- select user_id, jsonb_object_keys(state) as keys from public.kodoco_user_state;
-- select count(*) from public.kodoco_user_state;

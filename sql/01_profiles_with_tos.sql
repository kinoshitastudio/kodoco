-- KODOCO — Phase 1: profiles + auto-create trigger + TOS field + admin role
-- Supabase SQL Editor で New query → 全コピペ → Run
--
-- 流れ:
--   STEP 1: profiles テーブル作成（auth.users と 1:1）
--   STEP 2: handle_new_user trigger（auth.users INSERT 時に profiles 自動作成）
--   STEP 3: RLS ポリシー（自分のプロフィールは編集可、他人のは見るだけ）
--   STEP 4: is_admin() ヘルパー関数（モデレーション用）

-- ──────────────── STEP 1: profiles テーブル ────────────────
create table if not exists public.profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  handle text not null,
  display_name text,
  avatar_url text,
  role text not null default 'user' check (role in ('user', 'admin')),
  tos_accepted_at timestamptz,
  created_at timestamptz default now()
);

create index if not exists profiles_handle_idx on public.profiles (handle);

-- ──────────────── STEP 2: auth.users INSERT → profiles auto-create ────────────────
create or replace function public.handle_new_user()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  insert into public.profiles (id, handle, display_name, created_at)
  values (
    new.id,
    coalesce(
      (new.raw_user_meta_data ->> 'handle'),
      split_part(new.email, '@', 1),
      'visitor'
    ),
    coalesce(
      (new.raw_user_meta_data ->> 'display_name'),
      (new.raw_user_meta_data ->> 'handle'),
      split_part(new.email, '@', 1),
      'visitor'
    ),
    now()
  )
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute procedure public.handle_new_user();

-- ──────────────── STEP 3: RLS ポリシー ────────────────
alter table public.profiles enable row level security;

-- 全員プロフィールは見える（handle と avatar が口コミ等で表示されるため）
drop policy if exists profiles_select_all on public.profiles;
create policy profiles_select_all on public.profiles
  for select using (true);

-- 自分のプロフィールのみ insert / update / delete 可
drop policy if exists profiles_owner_insert on public.profiles;
create policy profiles_owner_insert on public.profiles
  for insert with check (id = auth.uid());

drop policy if exists profiles_owner_update on public.profiles;
create policy profiles_owner_update on public.profiles
  for update using (id = auth.uid()) with check (id = auth.uid());

drop policy if exists profiles_owner_delete on public.profiles;
create policy profiles_owner_delete on public.profiles
  for delete using (id = auth.uid());

-- ──────────────── STEP 4: is_admin() ヘルパー ────────────────
-- モデレーション用。user_spots の approve など admin-only 操作で使う。
create or replace function public.is_admin()
returns boolean
language sql
stable
security definer
set search_path = public
as $$
  select coalesce(
    (select role = 'admin' from public.profiles where id = auth.uid()),
    false
  );
$$;

-- ──────────────── 確認用クエリ ────────────────
-- select count(*) from public.profiles;
-- select id, handle, role, tos_accepted_at from public.profiles;

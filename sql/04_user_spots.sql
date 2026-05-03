-- KODOCO — Phase 4: user_spots テーブル（ユーザー投稿スポット）
-- Supabase SQL Editor で New query → 全コピペ → Run
--
-- ユーザーが「このスポット追加して！」と申請するための table。
-- status: 'pending' で投稿 → admin が 'approved' に変更すると本番反映 →
-- アプリ側で「公式 spots-data.js + approved な user_spots」をマージ表示。
-- 'rejected' は表示しない（ユーザーには却下理由を見せる）。

create table if not exists public.kodoco_user_spots (
  id uuid primary key default gen_random_uuid(),
  user_id uuid not null references auth.users(id) on delete cascade,
  user_handle text,                           -- 表示用スナップショット
  data jsonb not null,                        -- spots-data.js と同じスキーマ:
                                              --   { name, cat, loc, addr, hours, desc,
                                              --     keywords, ageGroups, lat, lng, ... }
  status text not null default 'pending'
    check (status in ('pending', 'approved', 'rejected')),
  reject_reason text,                         -- admin が rejected にした時の理由
  approved_at timestamptz,
  approved_by uuid references auth.users(id),
  created_at timestamptz default now(),
  updated_at timestamptz default now()
);

create index if not exists user_spots_status_idx on public.kodoco_user_spots (status, created_at desc);
create index if not exists user_spots_user_idx on public.kodoco_user_spots (user_id, created_at desc);

alter table public.kodoco_user_spots enable row level security;

-- ──────────────── ポリシー ────────────────
-- approved な spot は全員見える / pending の spot は owner と admin のみ
drop policy if exists user_spots_select on public.kodoco_user_spots;
create policy user_spots_select on public.kodoco_user_spots
  for select using (
    status = 'approved'
    or user_id = auth.uid()
    or public.is_admin()
  );

-- 認証済みユーザーのみ insert（status は強制 pending、初期値）
drop policy if exists user_spots_owner_insert on public.kodoco_user_spots;
create policy user_spots_owner_insert on public.kodoco_user_spots
  for insert with check (user_id = auth.uid() and status = 'pending');

-- pending な自分の spot のみ data 編集可（approved 後は admin のみ）
drop policy if exists user_spots_owner_update on public.kodoco_user_spots;
create policy user_spots_owner_update on public.kodoco_user_spots
  for update
  using (user_id = auth.uid() and status = 'pending')
  with check (user_id = auth.uid() and status = 'pending');

-- 自分の spot のみ削除（pending/rejected のみ、approved 後は admin に依頼）
drop policy if exists user_spots_owner_delete on public.kodoco_user_spots;
create policy user_spots_owner_delete on public.kodoco_user_spots
  for delete using (
    (user_id = auth.uid() and status in ('pending', 'rejected'))
    or public.is_admin()
  );

-- admin は全 row の status / data を update 可（モデレーション）
drop policy if exists user_spots_admin_moderate on public.kodoco_user_spots;
create policy user_spots_admin_moderate on public.kodoco_user_spots
  for update using (public.is_admin()) with check (public.is_admin());

-- ──────────────── トリガー ────────────────
create or replace function public.kodoco_user_spots_touch()
returns trigger language plpgsql as $$
begin
  new.updated_at = now();
  -- approved に変わったら approved_at と approved_by を埋める
  if new.status = 'approved' and (old.status is null or old.status <> 'approved') then
    new.approved_at = now();
    new.approved_by = auth.uid();
  end if;
  return new;
end $$;

drop trigger if exists kodoco_user_spots_touch_trg on public.kodoco_user_spots;
create trigger kodoco_user_spots_touch_trg
  before update on public.kodoco_user_spots
  for each row execute procedure public.kodoco_user_spots_touch();

-- ──────────────── 確認用クエリ ────────────────
-- select status, count(*) from public.kodoco_user_spots group by status;
-- select id, user_handle, data->>'name' as name, status from public.kodoco_user_spots order by created_at desc;

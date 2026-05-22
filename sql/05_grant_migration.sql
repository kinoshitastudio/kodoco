-- KODOCO — Phase 5: 明示的 GRANT（Supabase Data API 継続対応）
-- 期限: 2026-10-30（既存プロジェクトへの要件）
-- Supabase SQL Editor で New query → 全コピペ → Run
--
-- 背景:
--   Supabase が Data API (REST) の権限モデルを厳格化。
--   既存プロジェクトは 2026-10-30 までに anon / authenticated ロールへの
--   明示的 GRANT が必要。対応しないと REST API 経由のクエリが動かなくなる。

-- ──────────────── profiles ────────────────
-- 全ユーザーが handle / avatar を見る必要がある（口コミ表示用）
GRANT SELECT ON public.profiles TO anon, authenticated;
-- 自分のプロフィールのみ更新（RLS で owner 制限済み）
GRANT INSERT, UPDATE, DELETE ON public.profiles TO authenticated;

-- ──────────────── kodoco_user_state ────────────────
-- ログイン済みユーザーのみアクセス（likes / children 保存）
GRANT SELECT, INSERT, UPDATE ON public.kodoco_user_state TO authenticated;

-- ──────────────── kodoco_reviews ────────────────
-- 口コミは全員が見る、書くのはログイン済みのみ
GRANT SELECT ON public.kodoco_reviews TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.kodoco_reviews TO authenticated;

-- ──────────────── kodoco_user_spots ────────────────
-- スポット投稿は全員が見る（approved のみ RLS で制限）、投稿はログイン済みのみ
GRANT SELECT ON public.kodoco_user_spots TO anon, authenticated;
GRANT INSERT, UPDATE, DELETE ON public.kodoco_user_spots TO authenticated;

-- ──────────────── 確認用クエリ ────────────────
-- SELECT grantee, table_name, privilege_type
-- FROM information_schema.role_table_grants
-- WHERE table_schema = 'public'
--   AND grantee IN ('anon', 'authenticated')
-- ORDER BY table_name, grantee, privilege_type;

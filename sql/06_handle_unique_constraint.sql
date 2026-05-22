-- KODOCO — Phase 6: profiles.handle UNIQUE 制約 + 衝突回避トリガー
-- Supabase SQL Editor で New query → 全コピペ → Run
--
-- 前提: 重複 handle が存在しないことを確認済み（2026-05-22）
--   SELECT handle, COUNT(*) FROM public.profiles GROUP BY handle HAVING COUNT(*) > 1;
--   → 0 rows

-- ──────────────── STEP 1: UNIQUE 制約追加 ────────────────
ALTER TABLE public.profiles
  ADD CONSTRAINT profiles_handle_unique UNIQUE (handle);

-- ──────────────── STEP 2: handle_new_user トリガー更新 ────────────────
-- 衝突時に _2, _3, ... サフィックスで一意な handle を生成する
CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS trigger
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  base_handle text;
  candidate   text;
  suffix      int := 2;
BEGIN
  base_handle := coalesce(
    (new.raw_user_meta_data ->> 'handle'),
    split_part(new.email, '@', 1),
    'visitor'
  );

  -- 使用可能文字のみ残す（英数字 + _ + - + .）
  base_handle := regexp_replace(base_handle, '[^a-zA-Z0-9_\-\.]', '', 'g');
  IF base_handle = '' THEN base_handle := 'user'; END IF;

  candidate := base_handle;

  -- 衝突する限りサフィックスを付け直す
  WHILE EXISTS (SELECT 1 FROM public.profiles WHERE handle = candidate) LOOP
    candidate := base_handle || '_' || suffix;
    suffix := suffix + 1;
  END LOOP;

  INSERT INTO public.profiles (id, handle, display_name, created_at)
  VALUES (
    new.id,
    candidate,
    coalesce(
      (new.raw_user_meta_data ->> 'display_name'),
      (new.raw_user_meta_data ->> 'handle'),
      split_part(new.email, '@', 1),
      'visitor'
    ),
    now()
  )
  ON CONFLICT (id) DO NOTHING;

  RETURN new;
END $$;

-- ──────────────── 確認用クエリ ────────────────
-- SELECT constraint_name, constraint_type
-- FROM information_schema.table_constraints
-- WHERE table_schema = 'public' AND table_name = 'profiles';

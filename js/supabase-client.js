// KODOCO Supabase クライアント初期化
// 使い方:
//   <script src="https://cdn.jsdelivr.net/npm/@supabase/supabase-js@2"></script>
//   <script src="js/supabase-config.js"></script>
//   <script src="js/supabase-client.js"></script>
//
// 利用例:
//   const { data, error } = await window.kodocoSupabase
//     .from('kodoco_reviews')
//     .select('*')
//     .eq('spot_id', 'yabashi')
//     .order('created_at', { ascending: false });

(function () {
  if (typeof supabase === 'undefined' || typeof supabase.createClient !== 'function') {
    console.error('[kodoco] supabase-js が読み込まれていません');
    return;
  }
  if (!window.KODOCO_SUPABASE_URL || !window.KODOCO_SUPABASE_KEY) {
    console.error('[kodoco] supabase-config.js が読み込まれていません');
    return;
  }
  window.kodocoSupabase = supabase.createClient(
    window.KODOCO_SUPABASE_URL,
    window.KODOCO_SUPABASE_KEY,
    {
      auth: {
        persistSession: true,
        autoRefreshToken: true,
        detectSessionInUrl: true,
        storageKey: 'kodoco_auth',
      },
    }
  );

  window.kodocoSession = null;
  window.kodocoUser = null;

  // ── 同期的に localStorage キャッシュから session を復元 ──
  // 目的: getSession() の非同期解決を待たずに「ログイン後のUI」を初期描画。
  // これがないと毎回 ログアウト UI が一瞬チラ見えする (auth flash)。
  try {
    const raw = localStorage.getItem('kodoco_auth');
    if (raw) {
      const parsed = JSON.parse(raw);
      const cachedSession = (parsed && (parsed.currentSession || parsed.session)) || parsed;
      if (cachedSession && cachedSession.user) {
        // expires_at が過去でなければキャッシュを信用
        const exp = cachedSession.expires_at;
        const stillValid = !exp || (exp * 1000 > Date.now());
        if (stillValid) {
          window.kodocoSession = cachedSession;
          window.kodocoUser = cachedSession.user;
        }
      }
    }
  } catch (_) {}

  // auth-ready は DOMContentLoaded 後に発火 (bottom script の listener 登録に間に合わせる)
  const fireReady = () => {
    document.dispatchEvent(new CustomEvent('kodoco:auth-ready', { detail: { user: window.kodocoUser } }));
  };
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', fireReady, { once: true });
  } else {
    setTimeout(fireReady, 0);
  }

  // 真のセッションを非同期で確認 → キャッシュとずれていれば auth-change で訂正
  window.kodocoSupabase.auth.getSession().then(({ data }) => {
    const newSession = data.session || null;
    const newUser = newSession ? newSession.user : null;
    const oldUserId = window.kodocoUser ? window.kodocoUser.id : null;
    const newUserId = newUser ? newUser.id : null;
    window.kodocoSession = newSession;
    window.kodocoUser = newUser;
    if (oldUserId !== newUserId) {
      document.dispatchEvent(new CustomEvent('kodoco:auth-change', { detail: { event: 'INITIAL_SESSION', user: newUser } }));
    }
  });

  // セッション変化を監視 → イベント発火 (INITIAL_SESSION は上で処理済なので重複回避)
  window.kodocoSupabase.auth.onAuthStateChange((event, session) => {
    if (event === 'INITIAL_SESSION') return;
    window.kodocoSession = session || null;
    window.kodocoUser = session ? session.user : null;
    document.dispatchEvent(new CustomEvent('kodoco:auth-change', { detail: { event, user: window.kodocoUser } }));
  });

  console.log('[kodoco] Supabase client initialized');
})();

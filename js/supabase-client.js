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

  // 現在のセッション (ログイン状態) を取得
  window.kodocoSession = null;
  window.kodocoUser = null;
  window.kodocoSupabase.auth.getSession().then(({ data }) => {
    window.kodocoSession = data.session || null;
    window.kodocoUser = data.session ? data.session.user : null;
    document.dispatchEvent(new CustomEvent('kodoco:auth-ready', { detail: { user: window.kodocoUser } }));
  });

  // セッション変化を監視 → イベント発火
  window.kodocoSupabase.auth.onAuthStateChange((event, session) => {
    window.kodocoSession = session || null;
    window.kodocoUser = session ? session.user : null;
    document.dispatchEvent(new CustomEvent('kodoco:auth-change', { detail: { event, user: window.kodocoUser } }));
  });

  console.log('[kodoco] Supabase client initialized');
})();

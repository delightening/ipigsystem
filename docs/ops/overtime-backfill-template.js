/**
 * 加班補休「補登」腳本範本
 * ============================================================================
 * 用途：由 admin 代多位同仁補登歷史加班單，並一路走完送審 → 兩階段核准，
 *       讓補休時數正式入帳（comp_time_balances）。
 *
 * 為什麼需要這支腳本：
 *   系統的 POST /hr/overtime 把 user_id 寫死成「當前登入者」，沒有代建 API。
 *   因此補登只能靠 admin 的「角色扮演（impersonate）」逐一切換身分建立，
 *   走完整流程後資料才與同仁自己操作完全等價（稽核鏈亦完整）。
 *
 * ── 使用方式 ────────────────────────────────────────────────────────────────
 *   1. 在「已登入 admin」的系統分頁按 F12 → Console
 *   2. 填好下方 CONFIG.PLAN（姓名 + 日期 + 類型），存檔後整段貼上執行
 *   3. 先用 DRY_RUN = true 預覽，確認無誤再改 false 實跑
 *   4. 執行時會跳一次密碼框（換 reauth token，5 分鐘有效，可重複使用）
 *      密碼只送到本系統的 /auth/confirm-password，不會外流
 *
 * ── 重要規則（踩過的坑，別再踩）─────────────────────────────────────────────
 *   • 補休時數由「加班類型」決定，不是自己填：
 *       A=平日 → 0h ／ B=休息日 → 0h ／ C=國定假日 → 8h ／ D=天災 → 8h
 *     要補休 8 小時，類型必須是 C 或 D（見 services/hr/overtime.rs）
 *   • 起訖時間只影響「實際工時」欄位，不影響補休時數（C/D 按天計，固定 8h）
 *   • 模擬登入後 CSRF cookie 仍綁「舊身分」，直接 POST 會回 419。
 *     每次切換身分後必須打一個 GET 換發（腳本已用 syncCsrf() 處理）
 *   • reauth token 只有 5 分鐘，但可重複使用 → 腳本把 6 次模擬集中在前段
 *   • 補休效期 = 加班日 + 365 天
 *   • 重跑防呆已由系統接手（R86-2）：同一人／同一天／同一起訖時間只能有一筆
 *     有效加班單，重複建單會被 409 擋下（訊息「這個時段已有一筆加班紀錄」），
 *     腳本會把該列標為失敗、不會重複入帳。仍建議重跑前先看一眼 DB 現況，
 *     確認上一輪停在哪裡。
 *   • 真的補錯而且已核准 → 請負責人在「加班紀錄」頁按「作廢」（需填理由），
 *     補休餘額會一併收回；補休若已被請假用掉則會擋下，要先取消該假單。
 * ============================================================================
 */
(async () => {
  // ══ CONFIG：每次補登只需要改這一段 ═══════════════════════════════════════
  const CONFIG = {
    /** true = 只預覽不寫入（強烈建議先跑一次） */
    DRY_RUN: true,

    /** 加班起訖時間（HH:MM:SS）。只影響「實際工時」欄位 */
    START_TIME: '07:30:00',
    END_TIME: '12:00:00',

    /** 各類型的加班事由（reason 為必填欄位） */
    REASON: {
      A: '平日加班（補登）',
      B: '休息日值班（補登）',
      C: '國定假日值班（補登）',
      D: '颱風天災值班（補登）',
    },

    /**
     * 補登清單：用「顯示名稱」即可，腳本會自動查 user id。
     * rows 格式：['YYYY-MM-DD', '類型']
     *
     * 範例（用完請清空）：
     *   { name: '王小明', rows: [['2027-01-01', 'C'], ['2027-07-10', 'D']] },
     */
    PLAN: [
      // { name: '', rows: [['', 'C']] },
    ],
  };
  // ══ 以下不用改 ═══════════════════════════════════════════════════════════

  const csrf = () =>
    decodeURIComponent((document.cookie.match(/csrf_token=([^;]+)/) || [])[1] || '');

  async function api(method, path, body, extra = {}) {
    const res = await fetch('/api/v1' + path, {
      method,
      credentials: 'include',
      headers: { 'Content-Type': 'application/json', 'X-CSRF-Token': csrf(), ...extra },
      body: body ? JSON.stringify(body) : undefined,
    });
    const txt = await res.text();
    if (!res.ok) throw new Error(`${method} ${path} → ${res.status} ${txt}`);
    return txt ? JSON.parse(txt) : null;
  }

  /** GET 免 CSRF 檢查，其回應會換發「綁定當前身分」的 csrf_token cookie */
  const syncCsrf = () => api('GET', '/me');

  const created = [];
  const problems = [];

  try {
    // ── 0. 前置檢查 ──────────────────────────────────────────────────────
    if (!CONFIG.PLAN.length) {
      console.warn('CONFIG.PLAN 是空的，請先填入補登清單。');
      return;
    }
    const badType = CONFIG.PLAN.flatMap((p) =>
      p.rows.filter(([, t]) => !['A', 'B', 'C', 'D'].includes(t)).map(([d, t]) => `${p.name} ${d} 類型「${t}」無效`)
    );
    if (badType.length) { badType.forEach((m) => console.error(m)); return; }

    const zeroComp = CONFIG.PLAN.flatMap((p) =>
      p.rows.filter(([, t]) => t === 'A' || t === 'B').map(([d, t]) => `${p.name} ${d} 為類型 ${t} → 補休 0 小時`)
    );
    if (zeroComp.length) {
      console.warn('⚠️ 下列項目不會產生補休（僅 C/D 給 8 小時）：');
      zeroComp.forEach((m) => console.warn('   ' + m));
    }

    // ── 1. 姓名 → user id ────────────────────────────────────────────────
    const users = await api('GET', '/users?per_page=500');
    const idOf = (name) => {
      const hits = users.filter((u) => u.display_name === name);
      if (hits.length === 0) throw new Error(`找不到同仁「${name}」`);
      if (hits.length > 1) throw new Error(`同名同仁「${name}」有 ${hits.length} 位，請改用 id 指定`);
      return hits[0].id;
    };
    const plan = CONFIG.PLAN.map((p) => ({ ...p, id: idOf(p.name) }));
    const total = plan.reduce((s, p) => s + p.rows.length, 0);
    const expectComp = plan.reduce(
      (s, p) => s + p.rows.filter(([, t]) => t === 'C' || t === 'D').length * 8, 0);

    console.log(`%c補登預覽：${plan.length} 位同仁、${total} 筆、補休合計 ${expectComp} 小時`,
      'font-weight:bold');
    console.table(plan.flatMap((p) =>
      p.rows.map(([d, t]) => ({
        同仁: p.name, 日期: d, 類型: t,
        補休: t === 'C' || t === 'D' ? 8 : 0,
        事由: CONFIG.REASON[t],
      }))
    ));

    if (CONFIG.DRY_RUN) {
      console.log('%c這是 DRY_RUN 預覽，未寫入任何資料。確認無誤後把 DRY_RUN 改為 false 再執行。',
        'color:orange;font-weight:bold');
      return;
    }

    // ── 2. 換 reauth token（唯一需要密碼的一步）──────────────────────────
    const pw = prompt('請輸入你的登入密碼（用於換取 5 分鐘的 reauth token）');
    if (!pw) { console.warn('已取消。'); return; }
    const { reauth_token } = await api('POST', '/auth/confirm-password', { password: pw });
    if (!reauth_token) throw new Error('未取得 reauth_token');
    console.log('%c✓ reauth token 取得，開始補登', 'color:green');

    // ── 3. 逐位同仁：模擬 → 建單 → 送審 → 退出 ──────────────────────────
    for (const person of plan) {
      await api('POST', `/users/${person.id}/impersonate`, null, { 'X-Reauth-Token': reauth_token });
      await syncCsrf();  // 關鍵：換發綁定「被模擬者」的 CSRF token
      console.log(`→ 已模擬 ${person.name}，建立 ${person.rows.length} 筆`);

      for (const [date, type] of person.rows) {
        const rec = await api('POST', '/hr/overtime', {
          overtime_date: date,
          start_time: CONFIG.START_TIME,
          end_time: CONFIG.END_TIME,
          overtime_type: type,
          reason: CONFIG.REASON[type],
        });
        await api('POST', `/hr/overtime/${rec.id}/submit`);
        created.push({ name: person.name, date, type, id: rec.id });
        console.log(`   ✓ ${date} ${type} 已送審`);
      }

      await api('POST', '/auth/stop-impersonate');
      await syncCsrf();  // 換回綁定 admin 的 CSRF token
    }
    console.log(`%c✓ 建立完成：${created.length} 筆已送審`, 'color:green');

    // ── 4. 切回 admin：兩階段核准（行政 → 負責人）───────────────────────
    for (const c of created) {
      try {
        await api('POST', `/hr/overtime/${c.id}/approve`);   // → pending_admin
        await api('POST', `/hr/overtime/${c.id}/approve`);   // → approved（補休入帳）
        console.log(`   ✓ ${c.name} ${c.date} 已核准`);
      } catch (e) {
        problems.push(`${c.name} ${c.date} 核准失敗：${e.message}`);
        console.error(`   ✗ ${c.name} ${c.date}`, e.message);
      }
    }

    // ── 5. 驗收 ─────────────────────────────────────────────────────────
    const list = await api('GET', '/hr/overtime?view_all=true&per_page=500');
    const rows = (list.data || []).filter((r) => created.some((c) => c.id === r.id));
    const byStatus = rows.reduce((a, r) => ((a[r.status] = (a[r.status] || 0) + 1), a), {});
    const compTotal = rows.reduce((s, r) => s + Number(r.comp_time_hours || 0), 0);

    console.log('%c===== 補登結果 =====', 'font-weight:bold');
    console.table(rows.map((r) => ({
      同仁: r.user_name, 日期: r.overtime_date, 類型: r.overtime_type,
      工時: r.hours, 補休: r.comp_time_hours, 狀態: r.status,
    })));
    console.log('狀態統計：', byStatus);
    console.log(`補休合計：${compTotal} 小時（預期 ${expectComp}）`);
    if (problems.length) {
      console.warn('有問題的項目：'); problems.forEach((p) => console.warn(' - ' + p));
    }
  } catch (e) {
    console.error('%c✗ 中斷：' + e.message, 'color:red');
    console.warn('已建立的紀錄：', created);
    console.warn('若因 reauth 逾時（5 分鐘）中斷，直接重新執行即可：已建立的那幾筆會被系統的');
    console.warn('防重規則擋下（409「這個時段已有一筆加班紀錄」）並標為失敗，不會重複入帳。');
  }
})();

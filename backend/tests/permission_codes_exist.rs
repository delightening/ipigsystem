//! 防呆：**程式碼裡出現的每一個權限碼，都必須真的存在於 `permissions` 表**。
//!
//! ## 為什麼需要這個測試
//!
//! 2026-08-08 稽核（`docs/audit/dead-permission-codes-2026-08-08.md`）發現
//! **11 個死權限碼** —— 被 `require_permission!` / `has_permission` 檢查，
//! 卻從來不在 `permissions` 表裡。`has_permission` 對它們永遠回 `false`，
//! 功能只靠 `is_admin()` 短路才能用：「只有管理員做得到」是意外，不是設計。
//! 其中 `facility.manage` 有 19 個呼叫點且零 fallback，整個設施管理模組
//! 在無人察覺下變成管理員專屬。
//!
//! 根因是**兩端都是裸字串、沒有交叉驗證**：
//!
//! 1. `ensure_all_role_permissions` 的授予 SQL 是
//!    `INSERT ... SELECT ... FROM roles CROSS JOIN permissions WHERE p.code = ANY($2)`。
//!    JOIN 的是 `permissions` 表 —— 清單裡有不存在的碼時 JOIN 直接不產生列，
//!    **沒有錯誤、沒有警告、`rows_affected` 少一筆也沒人看**。
//! 2. handler 那端寫 `require_permission!(user, "some.new.code")` 時，
//!    同樣沒有任何機制確認這個字串真的存在。
//!
//! 於是打錯字或漏補目錄不會有任何徵兆：啟動正常、CI 全綠、功能悄悄變成管理員專屬，
//! 幾個月後才有人發現。本測試把那個沉默的失敗變成紅燈。
//!
//! ## 為什麼用原始碼掃描而不是別的做法
//!
//! 理想上這該由型別系統擋（像前端的 `permissions.generated.ts` + `PermissionCode`）。
//! 後端要做到那樣得把所有權限碼變成編譯期常數並改寫 396 個呼叫點，成本高得多。
//! 掃字串是務實的折衷：抓得到同一類錯誤，且新增權限時零額外負擔。

use std::collections::BTreeSet;
use std::path::{Path, PathBuf};

use sqlx::PgPool;

/// 只認 `TEST_DATABASE_URL`；未設時才收明顯是測試庫的 `DATABASE_URL`（名稱含 `test`）。
fn test_database_url() -> String {
    let (url, source) = match std::env::var("TEST_DATABASE_URL") {
        Ok(url) => (url, "TEST_DATABASE_URL"),
        Err(_) => (
            std::env::var("DATABASE_URL")
                .expect("TEST_DATABASE_URL 與 DATABASE_URL 皆未設定，無法驗證權限碼。"),
            "DATABASE_URL",
        ),
    };
    let db_name = url
        .rsplit('/')
        .next()
        .and_then(|tail| tail.split(['?', '#']).next())
        .unwrap_or_default();
    assert!(
        db_name.contains("test"),
        "{source} 指向的資料庫 `{db_name}` 不像測試庫（名稱不含 test）。\
         本測試會跑 migration 與 seed，拒絕在可能是 prod 的連線上執行。"
    );
    url
}

/// 遞迴收集 `src/` 下所有 `.rs` 檔。
fn rust_sources(dir: &Path, out: &mut Vec<PathBuf>) {
    let Ok(entries) = std::fs::read_dir(dir) else {
        return;
    };
    for entry in entries.flatten() {
        let path = entry.path();
        if path.is_dir() {
            rust_sources(&path, out);
        } else if path.extension().is_some_and(|e| e == "rs") {
            out.push(path);
        }
    }
}

/// 一個權限碼長什麼樣：小寫 / 數字 / 底線的區段，以 `.` 分隔，至少兩段。
///
/// 刻意保守：寧可漏抓也不要把不相干的字串（訊息、SQL 片段）當成權限碼，
/// 否則這個測試會變成每次改文案都要來安撫的噪音來源。
fn looks_like_permission_code(s: &str) -> bool {
    let parts: Vec<&str> = s.split('.').collect();
    parts.len() >= 2
        && parts.iter().all(|p| {
            !p.is_empty()
                && p.chars()
                    .all(|c| c.is_ascii_lowercase() || c.is_ascii_digit() || c == '_')
        })
}

/// 從一行程式碼中，抓出**授權檢查用**的權限碼字面值。
///
/// 只認三種呼叫形式，不是無差別抓所有含 `.` 的字串：
///   - `require_permission!(user, "code")`
///   - `has_permission("code")`
///   - `.has_permission("code")`
fn extract_from_line(line: &str) -> Vec<String> {
    let mut found = Vec::new();
    for marker in ["require_permission!", "has_permission"] {
        let mut rest = line;
        while let Some(idx) = rest.find(marker) {
            rest = &rest[idx + marker.len()..];
            // 取這個呼叫後面第一個字串字面值
            let Some(open) = rest.find('"') else { break };
            let after = &rest[open + 1..];
            let Some(close) = after.find('"') else { break };
            let candidate = &after[..close];
            if looks_like_permission_code(candidate) {
                found.push(candidate.to_string());
            }
            rest = &after[close..];
        }
    }
    found
}

async fn seeded_pool() -> PgPool {
    dotenvy::dotenv().ok();
    let pool = PgPool::connect(&test_database_url())
        .await
        .expect("connect test db");
    sqlx::migrate!("./migrations")
        .run(&pool)
        .await
        .expect("run migrations");
    // 目錄補齊就發生在這裡；不跑它的話等於在驗 migration 而非驗實際啟動後的狀態
    erp_backend::startup::ensure_required_permissions(&pool)
        .await
        .expect("ensure_required_permissions");
    pool
}

async fn existing_codes(pool: &PgPool) -> BTreeSet<String> {
    sqlx::query_scalar::<_, String>("SELECT code FROM permissions")
        .fetch_all(pool)
        .await
        .expect("read permissions")
        .into_iter()
        .collect()
}

/// handler / service 檢查的每一個權限碼都必須存在。
///
/// 失敗時的修法：把缺的碼加進 `startup/permissions.rs` 的 `required_permissions`，
/// **不要**把檢查改掉了事 —— 那只是把「悄悄變成管理員專屬」換成「悄悄沒有防護」。
#[tokio::test]
async fn every_checked_permission_code_exists() {
    let mut files = Vec::new();
    rust_sources(Path::new("src"), &mut files);
    assert!(
        !files.is_empty(),
        "掃不到 src/ 下的 .rs 檔，路徑或 CWD 有問題"
    );

    let mut referenced: BTreeSet<(String, String)> = BTreeSet::new();
    for path in &files {
        let Ok(content) = std::fs::read_to_string(path) else {
            continue;
        };
        for (n, line) in content.lines().enumerate() {
            for code in extract_from_line(line) {
                referenced.insert((code, format!("{}:{}", path.display(), n + 1)));
            }
        }
    }
    assert!(
        referenced.len() > 50,
        "只抓到 {} 個權限碼，明顯偏少 —— extract_from_line 可能失效了，\
         這種情況下測試會假綠，必須當成失敗處理",
        referenced.len()
    );

    let pool = seeded_pool().await;
    let existing = existing_codes(&pool).await;

    let missing: Vec<String> = referenced
        .iter()
        .filter(|(code, _)| !existing.contains(code))
        .map(|(code, at)| format!("  {code}  ({at})"))
        .collect();

    assert!(
        missing.is_empty(),
        "以下權限碼被程式碼檢查，但不存在於 permissions 表。\n\
         has_permission 對它們永遠回 false —— 功能會靜默變成「只有管理員做得到」，\n\
         而且啟動正常、CI 全綠、沒有任何徵兆。\n\
         修法：把它們加進 startup/permissions.rs 的 required_permissions，\n\
         不要把檢查刪掉了事。\n\n{}",
        missing.join("\n")
    );
}

/// 角色授予清單裡的每一個權限碼也必須存在。
///
/// 這條抓的是 `aup.review.reply` 那種：碼被寫進五個角色的清單，
/// 卻因為不在目錄裡，授予 SQL 的 JOIN 直接不產生列 —— 五筆授予全部靜默落空，
/// 「這五種角色應該能回覆審查意見」的意圖從來沒生效過。
#[tokio::test]
async fn every_granted_permission_code_exists() {
    let source =
        std::fs::read_to_string("src/startup/permissions.rs").expect("read startup/permissions.rs");

    // 授予清單長這樣：`                "aup.review.reply",`
    // ——整行只有一個字串字面值加逗號。目錄定義是 `("code", "name", ...)`，開頭是 `(`，
    // 以此區分兩者。
    let mut granted: BTreeSet<(String, usize)> = BTreeSet::new();
    for (n, line) in source.lines().enumerate() {
        let t = line.trim();
        if t.starts_with('(') || !t.starts_with('"') {
            continue;
        }
        let Some(rest) = t.strip_prefix('"') else {
            continue;
        };
        let Some(close) = rest.find('"') else {
            continue;
        };
        let code = &rest[..close];
        // 後面必須就是結尾（可能帶逗號），才算「清單元素」
        let tail = rest[close + 1..].trim();
        if !tail.is_empty() && tail != "," {
            continue;
        }
        if looks_like_permission_code(code) {
            granted.insert((code.to_string(), n + 1));
        }
    }
    assert!(
        granted.len() > 50,
        "只抓到 {} 個授予碼，明顯偏少 —— 解析可能失效，不可當綠燈",
        granted.len()
    );

    let pool = seeded_pool().await;
    let existing = existing_codes(&pool).await;

    let missing: Vec<String> = granted
        .iter()
        .filter(|(code, _)| !existing.contains(code))
        .map(|(code, line)| format!("  {code}  (startup/permissions.rs:{line})"))
        .collect();

    assert!(
        missing.is_empty(),
        "以下權限碼出現在角色授予清單中，但不存在於 permissions 表。\n\
         授予 SQL 是 `... FROM roles CROSS JOIN permissions WHERE p.code = ANY($2)`，\n\
         JOIN 不到就靜默不產生列 —— 那些角色永遠拿不到這個權限，且沒有任何錯誤訊息。\n\
         修法：把它們加進同檔的 required_permissions 目錄。\n\n{}",
        missing.join("\n")
    );
}

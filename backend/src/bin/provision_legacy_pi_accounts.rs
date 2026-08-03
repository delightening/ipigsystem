//! 一次性：為既有 legacy 匯入計畫的外部 PI 補建系統帳號並 relink `protocols.pi_user_id`。
//!
//! 只建立「待核准開通信」（`pi_account_invites` status=pending），**不寄信**；
//! 設定密碼信仍須 admin 於系統內核准後寄送（與線上開通流程一致）。
//!
//! 對象：`imported_at` 非空（補登匯入）+ `pi_user_id == created_by`（PI 仍掛在匯入者）
//! + `basic.pi.email` 有值。
//!
//! ## Usage
//! ```bash
//! # 本機（.env 提供 DATABASE_URL）：
//! cargo run --bin provision_legacy_pi_accounts -- --dry-run   # 僅預覽
//! cargo run --bin provision_legacy_pi_accounts                # 執行
//! # prod 容器內（compose 已設 DATABASE_URL_FILE）：
//! docker compose exec api /app/provision_legacy_pi_accounts --dry-run
//! ```

use anyhow::{Context, Result};
use sqlx::postgres::PgPoolOptions;
use uuid::Uuid;

use erp_backend::services::{AuditService, ProtocolService};
use erp_backend::ActorContext;

/// 讀取 secret：優先 `DATABASE_URL_FILE` 指向之檔案（prod Docker Secrets），
/// 否則回退 `DATABASE_URL` env var（本機 .env）。與 `config::read_secret` 一致。
fn read_database_url() -> Result<String> {
    if let Ok(path) = std::env::var("DATABASE_URL_FILE") {
        let content = std::fs::read_to_string(&path)
            .with_context(|| format!("Failed to read DATABASE_URL_FILE {path}"))?;
        return Ok(content.trim().to_string());
    }
    std::env::var("DATABASE_URL").context("DATABASE_URL（或 DATABASE_URL_FILE）must be set")
}

/// 讀取 AUDIT_HMAC_KEY：優先 `AUDIT_HMAC_KEY_FILE`（prod Docker Secrets），否則 env；
/// 長度 < 44 視為未設定（與 `config::read_secret` 的過濾一致）。
///
/// bin 工具預設不會載入 HMAC 金鑰 → 其經 service 寫入的 audit row `integrity_hash`
/// 為 NULL、無法進 HMAC chain 驗證（prod 曾觀察到 PROTOCOL_PI_PROVISIONED 兩筆如此）。
/// 載入金鑰後，bin 寫入的 audit 與主程式一致進鏈。
fn read_audit_hmac_key() -> Option<String> {
    std::env::var("AUDIT_HMAC_KEY_FILE")
        .ok()
        .and_then(|p| std::fs::read_to_string(p).ok())
        .map(|s| s.trim().to_string())
        .or_else(|| std::env::var("AUDIT_HMAC_KEY").ok())
        .filter(|s| s.len() >= 44)
}

#[tokio::main]
async fn main() -> Result<()> {
    dotenvy::dotenv().ok();
    let dry_run = std::env::args().any(|a| a == "--dry-run");

    let database_url = read_database_url()?;
    let pool = PgPoolOptions::new()
        .max_connections(2)
        .connect(&database_url)
        .await
        .context("Failed to connect to database")?;

    let rows: Vec<(Uuid, String, Option<String>)> = sqlx::query_as(
        r#"SELECT id, protocol_no,
                  NULLIF(working_content->'basic'->'pi'->>'email', '') AS pi_email
           FROM protocols
           WHERE imported_at IS NOT NULL
             AND pi_user_id = created_by
             AND NULLIF(working_content->'basic'->'pi'->>'email', '') IS NOT NULL
           ORDER BY created_at ASC"#,
    )
    .fetch_all(&pool)
    .await
    .context("Failed to query legacy imported protocols")?;

    println!("Found {} 筆 legacy 外部 PI 匯入計畫需開通帳號", rows.len());
    if rows.is_empty() {
        return Ok(());
    }

    if dry_run {
        for (id, no, email) in &rows {
            println!(
                "[dry-run] {} ({}) → PI email {}",
                no,
                id,
                email.as_deref().unwrap_or("?")
            );
        }
        println!("[dry-run] 共 {} 筆（未執行）", rows.len());
        return Ok(());
    }

    // 載入 HMAC 金鑰，讓本次 provision 寫入的 audit row 正確進 HMAC chain（否則 NULL hash）。
    match read_audit_hmac_key() {
        Some(key) => AuditService::init_hmac_key(Some(key)),
        None => {
            eprintln!(
                "⚠️  AUDIT_HMAC_KEY（或 AUDIT_HMAC_KEY_FILE，≥44 字元）未設定；\
                 本次寫入的 audit 將不進 HMAC chain（integrity_hash=NULL）。"
            );
            AuditService::init_hmac_key(None);
        }
    }

    let actor = ActorContext::System {
        reason: "legacy_pi_provision",
    };
    let (mut ok, mut created, mut linked, mut err) = (0u32, 0u32, 0u32, 0u32);
    for (id, no, _email) in &rows {
        match ProtocolService::provision_pi_account(&pool, &actor, *id).await {
            Ok((_uid, email, created_new)) => {
                ok += 1;
                if created_new {
                    created += 1;
                } else {
                    linked += 1;
                }
                println!(
                    "OK {} ({}) → {} {}",
                    no,
                    id,
                    email,
                    if created_new {
                        "[新帳號]"
                    } else {
                        "[連既有帳號]"
                    }
                );
            }
            Err(e) => {
                err += 1;
                eprintln!("ERR {} ({}): {}", no, id, e);
            }
        }
    }
    println!(
        "\n完成：成功 {ok}（新帳號 {created} / 連既有 {linked}），失敗 {err}。\
         所有開通信為 pending，待 admin 於系統內核准寄送設定密碼信。"
    );
    Ok(())
}

//! 一次性：依「週年前一天」規則重算所有特休額度（annual_leave_entitlements）的到期日。
//! 舊資料到期日落在到職週年「當天」（如 7/1），修正為「前一天」（6/30）；到期年仍為授予年 +2。
//! 缺到職日者不重算，改列為異常清單供通知補填。
//!
//! ## Usage
//! ```bash
//! # 先 dry-run 檢視變更（不寫入）
//! DATABASE_URL_FILE=../secrets/db_url_host.txt \
//!   cargo run --bin backfill_annual_leave_expiry -- --dry-run
//! # 確認無誤後正式執行（會寫稽核）
//! DATABASE_URL_FILE=../secrets/db_url_host.txt AUDIT_HMAC_KEY_FILE=../secrets/audit_hmac_key.txt \
//!   cargo run --bin backfill_annual_leave_expiry
//! ```

use anyhow::{Context, Result};
use sqlx::postgres::PgPoolOptions;

use erp_backend::services::{AuditService, HrService};
use erp_backend::ActorContext;

fn read_database_url() -> Result<String> {
    if let Ok(path) = std::env::var("DATABASE_URL_FILE") {
        return Ok(std::fs::read_to_string(&path)
            .with_context(|| format!("read DATABASE_URL_FILE {path}"))?
            .trim()
            .to_string());
    }
    std::env::var("DATABASE_URL").context("DATABASE_URL（或 DATABASE_URL_FILE）must be set")
}

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

    let pool = PgPoolOptions::new()
        .max_connections(2)
        .connect(&read_database_url()?)
        .await
        .context("connect db")?;

    if !dry_run {
        AuditService::init_hmac_key(read_audit_hmac_key());
    }
    let actor = ActorContext::System {
        reason: "annual_leave_expiry_recompute_backfill",
    };

    let report = HrService::recompute_annual_leave_expiries(&pool, &actor, dry_run)
        .await
        .context("recompute annual leave expiries")?;

    let tag = if dry_run { "[dry-run] " } else { "" };
    println!("{tag}到期日變更明細（共 {} 筆）：", report.changes.len());
    for c in &report.changes {
        println!(
            "  {} | {} 年度 | {} → {}",
            c.user_name, c.entitlement_year, c.old_expiry, c.new_expiry
        );
    }

    if !report.missing_hire_date.is_empty() {
        println!(
            "\n⚠️ 有特休額度但缺到職日（未重算，請通知補填）共 {} 人：",
            report.missing_hire_date.len()
        );
        for m in &report.missing_hire_date {
            println!(
                "  {} <{}> | 額度 {} 筆",
                m.display_name, m.email, m.entitlement_count
            );
        }
    }

    println!(
        "\n{tag}完成：更新 {}，未變動 {}，缺到職日 {} 人",
        report.updated,
        report.unchanged,
        report.missing_hire_date.len()
    );
    Ok(())
}

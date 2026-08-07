//! 置頂待辦對帳：把「置頂中、但關聯業務實體已不存在或已在終態」的通知降級。
//!
//! 用途有二：
//! 1. **一次性修補**——清掉 2026-08-07 事故留下的殘留待辦（巡場 retract/delete 未接
//!    解除 hook 造成）。
//! 2. **定期安全網**——各業務流程新增終態路徑時難免漏接解除 hook，本作業定期補救。
//!
//! 判斷依據是業務實體的真實狀態，不是使用者意願，因此不違反
//! 「待辦只能由系統偵測完成自動消失、使用者不可手動略過」的設計。
//!
//! ## Usage
//! ```bash
//! # 先 dry-run 核對筆數（不寫入）
//! DATABASE_URL_FILE=../secrets/db_url_host.txt \
//!   cargo run --bin reconcile_pinned_notifications -- --dry-run
//! # 筆數確認無誤後正式執行
//! DATABASE_URL_FILE=../secrets/db_url_host.txt \
//!   cargo run --bin reconcile_pinned_notifications
//! ```

use anyhow::{Context, Result};
use sqlx::postgres::PgPoolOptions;

use erp_backend::services::NotificationService;

fn read_database_url() -> Result<String> {
    if let Ok(path) = std::env::var("DATABASE_URL_FILE") {
        return Ok(std::fs::read_to_string(&path)
            .with_context(|| format!("read DATABASE_URL_FILE {path}"))?
            .trim()
            .to_string());
    }
    std::env::var("DATABASE_URL").context("DATABASE_URL（或 DATABASE_URL_FILE）must be set")
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

    let svc = NotificationService::new(pool);
    let report = svc
        .reconcile_pinned_notifications(dry_run)
        .await
        .context("reconcile pinned notifications")?;

    let tag = if dry_run { "[dry-run] " } else { "" };

    println!("{tag}待降級的孤兒待辦（共 {} 筆）：", report.resolved.len());
    for r in &report.resolved {
        println!(
            "  {} | {} | {} | {}",
            r.created_at.format("%Y-%m-%d %H:%M"),
            r.recipient_email,
            r.title,
            r.reason
        );
    }

    if !report.unknown_entity_types.is_empty() {
        println!("\n⚠️ 本作業不認得下列 entity_type，保守未做判斷（如有新待辦類型請補進 reconcile.rs）：");
        for (ty, n) in &report.unknown_entity_types {
            println!("  {ty} — {n} 筆");
        }
    }

    println!(
        "\n{tag}完成：降級 {} 筆，仍為合法待辦 {} 筆",
        report.resolved.len(),
        report.still_pending
    );
    Ok(())
}

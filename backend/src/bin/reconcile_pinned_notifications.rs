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

const USAGE: &str = "\
用法：reconcile_pinned_notifications [--dry-run]

  --dry-run   只查不寫，列出將被降級的孤兒待辦（上 prod 前用來核對筆數）
  --help      顯示本說明

環境變數：DATABASE_URL_FILE 或 DATABASE_URL
";

/// 嚴格剖析參數。
///
/// **不可用 `args().any(|a| a == "--dry-run")`**：那種寫法下任何拼錯
/// （`--dryrun`、`--dry_run`、`-dry-run`）都會被靜默忽略，於是「本來想預覽」
/// 變成「直接對 prod 資料庫寫入」。這支工具會 UPDATE notifications，
/// 誤觸的代價是真的改到正式資料。
fn parse_args() -> Result<bool> {
    let mut dry_run = false;
    for arg in std::env::args().skip(1) {
        match arg.as_str() {
            "--dry-run" => dry_run = true,
            "--help" | "-h" => {
                print!("{USAGE}");
                std::process::exit(0);
            }
            other => anyhow::bail!("未知參數 `{other}`\n\n{USAGE}"),
        }
    }
    Ok(dry_run)
}

#[tokio::main]
async fn main() -> Result<()> {
    dotenvy::dotenv().ok();
    let dry_run = parse_args()?;

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

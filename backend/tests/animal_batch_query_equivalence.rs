//! N+1 批次查詢與逐筆查詢的**等價性**回歸測試。
//!
//! 背景：`services/animal/{observation,weight,surgery}.rs` 新增了 `list_for_animals`，
//! 讓 `medical.rs` 的動物清單改為「一次批次查 + HashMap 分組」，取代原本每隻動物各查
//! 一次的 N+1 迴圈。這類改寫最容易出的錯不是編譯錯誤，而是**結果集語意悄悄變了**：
//! JOIN 型別選錯會多出或漏掉列、排序鍵不同會改變同一動物內的順序、沒有紀錄的動物
//! 可能整隻從結果中消失。
//!
//! 因此本檔不寫死預期輸出，而是直接斷言「批次版 == 逐筆版」——逐筆版是改寫前既有的
//! 行為基準，兩者對**任何**測試資料都必須一致。寫死預期值只能證明「在我想到的那幾筆
//! 資料上一致」，等價斷言才擋得住日後有人再改壞一次。
//!
//! 涵蓋（對應 CodeRabbit 於 PR #22 的三則 review）：
//! - 完全沒有紀錄的動物 → 兩版都必須回空 Vec，且該動物不可從結果中消失
//! - soft-deleted 紀錄（`deleted_at IS NOT NULL`）→ 兩版都必須排除
//! - 同一動物內的排序（event_date / measure_date / surgery_date DESC）
//! - 多隻動物混合時不會互相污染（A 的紀錄不會被分到 B）
//!
//! 比對方式：這些 model 未 derive `PartialEq`，改以 `serde_json::to_value` 比對完整
//! 結構與順序——不為了測試而去動 production model 的 derive。

use chrono::{Duration, Utc};
use rust_decimal::Decimal;
use serial_test::serial;
use sqlx::PgPool;
use std::collections::HashMap;
use uuid::Uuid;

use erp_backend::services::{
    AnimalObservationService, AnimalSurgeryService, AnimalWeightService,
};

/// **fail-closed**：未設 `TEST_DATABASE_URL` 直接中止，不 fallback 到 `DATABASE_URL`。
///
/// 既有測試多寫成 `TEST_DATABASE_URL` → `DATABASE_URL` 的 fallback，那正是 CLAUDE.md
/// 「禁止在 prod 跑 backend 整合測試」的觸發點——未設變數時會對 prod DB 跑 migration
/// 並寫入測試資料，污染正式表與稽核鏈（已列為 R84-15 待修）。新測試不複製該 pattern。
async fn setup_pool() -> PgPool {
    dotenvy::dotenv().ok();
    let url = std::env::var("TEST_DATABASE_URL").expect(
        "TEST_DATABASE_URL 必須設定且指向獨立的丟棄用資料庫；\
         本測試刻意不 fallback 到 DATABASE_URL，避免誤打 prod",
    );
    let pool = PgPool::connect(&url).await.expect("connect test db");
    sqlx::migrate!("./migrations")
        .run(&pool)
        .await
        .expect("run migrations on test db");
    pool
}

/// 建立一隻測試動物，回傳 id。
///
/// `breed` / `gender` 皆為 DB enum（`animal_breed` = miniature/white/LYD/other、
/// `animal_gender` = male/female），不可填自由文字。
async fn insert_animal(pool: &PgPool, tag: &str) -> Uuid {
    sqlx::query_scalar::<_, Uuid>(
        r#"INSERT INTO animals (ear_tag, breed, gender, entry_date)
           VALUES ($1, 'other', 'female', CURRENT_DATE)
           RETURNING id"#,
    )
    .bind(tag)
    .fetch_one(pool)
    .await
    .expect("insert animal")
}

/// 測試資料佈局，三種情境一次涵蓋：
/// - `rich`：多筆紀錄，且其中一筆為 soft-deleted（驗證排除 + 排序）
/// - `empty`：完全沒有任何紀錄（驗證不會整隻消失）
/// - `single`：僅一筆（驗證單筆情境與逐筆版一致）
struct Fixture {
    rich: Uuid,
    empty: Uuid,
    single: Uuid,
}

impl Fixture {
    fn ids(&self) -> Vec<Uuid> {
        vec![self.rich, self.empty, self.single]
    }
}

async fn seed(pool: &PgPool, prefix: &str) -> Fixture {
    let rich = insert_animal(pool, &format!("{prefix}-RICH")).await;
    let empty = insert_animal(pool, &format!("{prefix}-EMPTY")).await;
    let single = insert_animal(pool, &format!("{prefix}-SINGLE")).await;

    let now = Utc::now();
    for (animal, days, deleted) in [
        (rich, 1_i64, false),
        (rich, 3, false),
        (rich, 2, true), // soft-deleted：兩版都必須排除
        (single, 5, false),
    ] {
        let at = now - Duration::days(days);
        sqlx::query(
            r#"INSERT INTO animal_observations
                   (animal_id, event_date, record_type, content, deleted_at)
               VALUES ($1, $2, 'observation', 'batch-equivalence', $3)"#,
        )
        .bind(animal)
        .bind(at)
        .bind(if deleted { Some(now) } else { None })
        .execute(pool)
        .await
        .expect("insert observation");

        sqlx::query(
            r#"INSERT INTO animal_weights
                   (animal_id, measure_date, weight, deleted_at)
               VALUES ($1, $2, $3, $4)"#,
        )
        .bind(animal)
        .bind(at)
        .bind(Decimal::new(1000 + days, 1))
        .bind(if deleted { Some(now) } else { None })
        .execute(pool)
        .await
        .expect("insert weight");

        sqlx::query(
            r#"INSERT INTO animal_surgeries
                   (animal_id, surgery_date, surgery_site, deleted_at)
               VALUES ($1, $2, 'test-site', $3)"#,
        )
        .bind(animal)
        .bind(at)
        .bind(if deleted { Some(now) } else { None })
        .execute(pool)
        .await
        .expect("insert surgery");
    }

    Fixture {
        rich,
        empty,
        single,
    }
}

/// 把批次結果依 animal_id 分組（保持原順序），供與逐筆結果比對。
fn group_by<T, F>(rows: Vec<T>, key: F) -> HashMap<Uuid, Vec<T>>
where
    F: Fn(&T) -> Uuid,
{
    let mut m: HashMap<Uuid, Vec<T>> = HashMap::new();
    for r in rows {
        m.entry(key(&r)).or_default().push(r);
    }
    m
}

#[tokio::test]
#[serial]
async fn observation_batch_equals_per_animal() {
    let pool = setup_pool().await;
    let fx = seed(&pool, "OBS").await;

    let batched = group_by(
        AnimalObservationService::list_for_animals(&pool, &fx.ids())
            .await
            .expect("batch query"),
        |o| o.animal_id,
    );

    for id in fx.ids() {
        let per_item = AnimalObservationService::list(&pool, id, None)
            .await
            .expect("per-animal query");
        let from_batch = batched.get(&id).cloned().unwrap_or_default();

        assert_eq!(
            serde_json::to_value(&per_item).unwrap(),
            serde_json::to_value(&from_batch).unwrap(),
            "observation 批次與逐筆結果不一致（animal_id={id}）"
        );
    }

    // 空紀錄動物必須回空 Vec，而不是從結果中消失
    assert!(
        batched.get(&fx.empty).map(|v| v.is_empty()).unwrap_or(true),
        "沒有紀錄的動物不應出現在批次結果中"
    );
    // rich 有 3 筆但其中 1 筆 soft-deleted → 應只剩 2 筆
    assert_eq!(
        batched.get(&fx.rich).map(|v| v.len()).unwrap_or(0),
        2,
        "soft-deleted 的 observation 未被排除"
    );
}

#[tokio::test]
#[serial]
async fn weight_batch_equals_per_animal() {
    let pool = setup_pool().await;
    let fx = seed(&pool, "WGT").await;

    let batched = group_by(
        AnimalWeightService::list_for_animals(&pool, &fx.ids())
            .await
            .expect("batch query"),
        |w| w.animal_id,
    );

    for id in fx.ids() {
        let per_item = AnimalWeightService::list(&pool, id, None)
            .await
            .expect("per-animal query");
        let from_batch = batched.get(&id).cloned().unwrap_or_default();

        assert_eq!(
            serde_json::to_value(&per_item).unwrap(),
            serde_json::to_value(&from_batch).unwrap(),
            "weight 批次與逐筆結果不一致（animal_id={id}）"
        );
    }

    assert_eq!(
        batched.get(&fx.rich).map(|v| v.len()).unwrap_or(0),
        2,
        "soft-deleted 的 weight 未被排除"
    );
}

#[tokio::test]
#[serial]
async fn surgery_batch_equals_per_animal() {
    let pool = setup_pool().await;
    let fx = seed(&pool, "SRG").await;

    let batched = group_by(
        AnimalSurgeryService::list_for_animals(&pool, &fx.ids())
            .await
            .expect("batch query"),
        |s| s.animal_id,
    );

    for id in fx.ids() {
        let per_item = AnimalSurgeryService::list(&pool, id, None)
            .await
            .expect("per-animal query");
        let from_batch = batched.get(&id).cloned().unwrap_or_default();

        assert_eq!(
            serde_json::to_value(&per_item).unwrap(),
            serde_json::to_value(&from_batch).unwrap(),
            "surgery 批次與逐筆結果不一致（animal_id={id}）"
        );
    }

    assert_eq!(
        batched.get(&fx.rich).map(|v| v.len()).unwrap_or(0),
        2,
        "soft-deleted 的 surgery 未被排除"
    );
}

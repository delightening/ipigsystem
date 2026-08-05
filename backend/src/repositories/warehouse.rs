use rust_decimal::Decimal;
use sqlx::PgPool;
use uuid::Uuid;

use crate::{AppError, Result};

/// 依 id 查詢倉庫名稱（在 document/crud.rs 中出現 3 次）
pub async fn find_warehouse_name_by_id(pool: &PgPool, id: Uuid) -> Result<Option<String>> {
    let name = sqlx::query_scalar("SELECT name FROM warehouses WHERE id = $1")
        .bind(id)
        .fetch_optional(pool)
        .await
        .map_err(AppError::Database)?;
    Ok(name)
}

/// 倉庫底下仍有結存的儲位（供停用倉庫前的阻擋檢查）
#[derive(Debug, sqlx::FromRow)]
pub struct StockedLocation {
    pub code: String,
    pub name: Option<String>,
    pub on_hand_qty: Decimal,
}

/// 列出倉庫底下仍有結存的儲位。
///
/// 刻意**不**過濾 `storage_locations.is_active`：倉庫一旦停用，
/// 底下所有儲位（含已停用者）的庫存都會從庫存查詢樹與現況報表消失
/// （兩者皆 `WHERE warehouses.is_active = true`），停用儲位上的結存
/// 同樣會變成帳上有、畫面上找不到的隱形庫存。
pub async fn list_stocked_locations_tx(
    tx: &mut sqlx::Transaction<'_, sqlx::Postgres>,
    warehouse_id: Uuid,
) -> Result<Vec<StockedLocation>> {
    let rows = sqlx::query_as::<_, StockedLocation>(
        r#"
        SELECT sl.code, sl.name, SUM(sli.on_hand_qty) AS on_hand_qty
        FROM storage_locations sl
        JOIN storage_location_inventory sli ON sli.storage_location_id = sl.id
        WHERE sl.warehouse_id = $1
        GROUP BY sl.code, sl.name
        HAVING SUM(sli.on_hand_qty) > 0
        ORDER BY sl.code
        "#,
    )
    .bind(warehouse_id)
    .fetch_all(&mut **tx)
    .await
    .map_err(AppError::Database)?;
    Ok(rows)
}

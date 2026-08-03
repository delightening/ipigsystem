# R30-3 Design: Transactional Event Outbox

> **Status**: APPROVED (2026-05-02) — 待實作
> **Owner**: Jason
> **PR 切分**: PR-A infra → PR-B euthanasia 改用
> **依賴關係**: 是 R30-9b invalidate 通知的可選複用基礎（非必須）

---

## 1. 動機

`services/euthanasia.rs:795/865` 有 2 處 `tracing::warn!`：euthanasia 流程結束（`_oneshot` post-tx）後試圖發通知，失敗只 warn 不重試。

實際後果：
- IACUC chair 可能漏看「動物已執行安樂死」通知
- Audit log 寫了，但對外通知斷掉，GLP §58 觀察員無法即時掌握
- 無 retry / 無 dead-letter

更廣泛的問題：整個系統「tx 內想送外部訊息」的場景都缺乏 atomic 保證 — 每加一個通知點都要重做一次失敗處理 / retry 邏輯。

## 2. 決定

採 **Transactional Outbox pattern**：
- DB tx 內只寫 `event_outbox` row（< 1ms，無外部 I/O）
- 獨立 worker process 後續 poll outbox + 送外部訊息 + retry + dead-letter
- 命名用 `event_outbox`（通用），預留 future webhook / indexing / search reindex 等用例

## 3. Schema (`migrations/049_event_outbox.sql`)

```sql
CREATE TABLE event_outbox (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    -- 內容
    channel TEXT NOT NULL,           -- 'email' / 'line' / 'webhook' / 'reindex' (future)
    payload JSONB NOT NULL,          -- channel adapter 解析的訊息結構

    -- 狀態機: PENDING → SENDING → DONE | FAILED → DEAD
    status TEXT NOT NULL DEFAULT 'PENDING'
        CHECK (status IN ('PENDING','SENDING','DONE','FAILED','DEAD')),
    attempt_count INT NOT NULL DEFAULT 0,
    next_attempt_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    last_error TEXT,

    -- 追蹤
    enqueued_by UUID REFERENCES users(id),
    enqueued_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    started_at TIMESTAMPTZ,
    done_at TIMESTAMPTZ,

    -- 來源 entity（debug + IDOR + audit cross-ref）
    source_entity TEXT,              -- 'amendment' / 'euthanasia' / 'role' / 'signature'
    source_entity_id UUID
);

-- worker 取件用：只 index 待處理
CREATE INDEX idx_event_outbox_pending
    ON event_outbox (next_attempt_at)
    WHERE status IN ('PENDING','FAILED');

-- 監控/查詢用
CREATE INDEX idx_event_outbox_source ON event_outbox (source_entity, source_entity_id);
CREATE INDEX idx_event_outbox_status ON event_outbox (status, enqueued_at);

COMMENT ON TABLE event_outbox IS
'R30-3: Transactional outbox for guaranteed-delivery side effects (notifications, webhooks). Worker: bin/outbox_worker.rs';
```

對應 `migrations/down/049_event_outbox.sql`：`DROP TABLE event_outbox;`（**僅在 outbox 為空時可安全回退** — DROP TABLE 是資料破壞操作，PENDING / FAILED 事件會永久丟失。down 前必執行 `SELECT COUNT(*) FROM event_outbox WHERE status NOT IN ('DONE','DEAD');` 確認 = 0；否則先 drain worker 再 down）

## 4. Service API

```rust
// backend/src/services/outbox.rs (新檔)

pub struct OutboxService;

impl OutboxService {
    /// 在現有 tx 內排隊一筆事件。commit 失敗 → 整批 rollback（含 outbox row）。
    /// 回傳 outbox row id 供 caller 記到 audit / 後續查詢。
    pub async fn enqueue_tx(
        tx: &mut Transaction<'_, Postgres>,
        actor: &ActorContext,
        channel: &str,                    // 'email' / 'line' / ...
        payload: serde_json::Value,
        source: (&str, Uuid),             // (entity_type, entity_id)
    ) -> Result<Uuid>;

    /// Worker 用：取一批待處理事件並標記 SENDING。
    /// FOR UPDATE SKIP LOCKED 防止多 worker 重複取件。
    pub async fn claim_batch(
        pool: &PgPool,
        limit: i32,
    ) -> Result<Vec<OutboxEvent>>;

    /// Worker 用：標記成功。
    pub async fn mark_done(pool: &PgPool, id: Uuid) -> Result<()>;

    /// Worker 用：標記失敗 + 算下次嘗試時間 + dead-letter 判斷。
    pub async fn mark_failed(
        pool: &PgPool,
        id: Uuid,
        error: &str,
    ) -> Result<()>;
}
```

### `claim_batch` 確切 SQL（避免實作踩坑）

```sql
-- 必須的 WHERE：status 過濾 + next_attempt_at 過濾（否則會提前送出未到期重試）
WITH claimed AS (
    SELECT id
    FROM event_outbox
    WHERE status IN ('PENDING','FAILED')
      AND next_attempt_at <= NOW()
    ORDER BY next_attempt_at        -- 早到期的先取（fairness）
    LIMIT $1
    FOR UPDATE SKIP LOCKED          -- 多 worker 互斥（PG 9.5+）
)
UPDATE event_outbox o
SET status = 'SENDING',
    started_at = NOW()
    -- 注意：attempt_count 不在 claim 時遞增，由 mark_failed 在「失敗」當下遞增（見 Retry §）
FROM claimed
WHERE o.id = claimed.id
RETURNING o.*;
```

### 狀態轉移獨家責任（避免競態跳狀態）

| Transition | 唯一允許的 caller |
|---|---|
| `enqueue_tx` 寫入 `PENDING` | `OutboxService::enqueue_tx` |
| `PENDING/FAILED` → `SENDING` | `claim_batch` 唯一路徑 |
| `SENDING` → `DONE` | `mark_done` 唯一路徑 |
| `SENDING` → `FAILED` 或 `DEAD` | `mark_failed` 唯一路徑（含 next_attempt_at 計算） |
| `SENDING` (worker crash) → `PENDING` | `reset_stuck` cron（見 §9）|

Worker crash 中卡 `SENDING` 由 cron 補救（每 5min 跑：`UPDATE ... SET status='PENDING' WHERE status='SENDING' AND started_at < NOW() - interval '10 minutes'`）。

### Retry 策略

`attempt_count` 語意：**已失敗次數**（schema default 0 = 從未失敗過）。`mark_failed` 流程：
1. `attempt_count = attempt_count + 1`
2. 依新 `attempt_count` 對表算 `next_attempt_at`：

| `attempt_count` (失敗後值) | `next_attempt_at` 加 | 結果 status |
|---|---|---|
| 1（首次失敗） | +10s | `FAILED` |
| 2 | +1m | `FAILED` |
| 3 | +10m | `FAILED` |
| 4 | +1h | `FAILED` |
| 5 | +6h | `FAILED`（最後一次重試窗口） |
| 6（=已失敗 6 次） | — | `DEAD` 不再排 |

**總嘗試次數 = 6**（首次 + 5 次 retry）。Off-by-one 注意：
- `attempt_count = 0` → 首次嘗試
- 首次失敗後 `attempt_count = 1`，next_attempt_at +10s 等待 retry
- 第 6 次失敗（attempt_count = 5 → 6）→ status = DEAD，不再排

DEAD 不再 retry；alert 由 Prometheus `outbox_dead_count > 0` 觸發，人工介入。

### Idempotency

- **outbox row id** 即 idempotency key，worker 一律帶這個 id 給 channel adapter
- email 端：帶在 SMTP `Message-ID` header（同 id 重送 receiver 端 dedup）
- line 端：帶在 webhook payload，由 line bot 端 dedup（如有）
- 即使 channel 端不 dedup，因 status 機器（SENDING → DONE 一旦標記不會回 PENDING），同 worker 不會重送；多 worker 由 `FOR UPDATE SKIP LOCKED` 互斥

## 5. Worker (`bin/outbox_worker.rs`)

```rust
// 獨立 binary（與 backend 同 crate，重用 services/）
// CMD: bin/outbox_worker

use ipig_backend::{services::OutboxService, ...};

#[tokio::main]
async fn main() -> Result<()> {
    let cfg = Config::from_env()?;
    let pool = init_db_pool(&cfg).await?;
    let cancel = CancellationToken::new();
    install_signal_handlers(cancel.clone());

    let adapters = ChannelRegistry::new()
        .register("email", EmailAdapter::new(&cfg))
        .register("line", LineAdapter::new(&cfg));

    let adapters = Arc::new(adapters);
    let mut interval = tokio::time::interval(Duration::from_secs(5));
    const CONCURRENCY: usize = 10;

    loop {
        tokio::select! {
            _ = cancel.cancelled() => break,
            _ = interval.tick() => {}
        }

        let batch = OutboxService::claim_batch(&pool, 10).await?;

        // R30-3 (gemini PR #304 review): 並行處理 batch 內事件，
        // 避免單筆慢事件（如 SMTP timeout）阻塞同 batch 後續事件
        use futures::stream::StreamExt;
        futures::stream::iter(batch)
            .for_each_concurrent(CONCURRENCY, |event| {
                let pool = pool.clone();
                let adapters = adapters.clone();
                async move {
                    let result = adapters.send(&event).await;
                    let mark = match result {
                        Ok(_) => OutboxService::mark_done(&pool, event.id).await,
                        Err(e) => OutboxService::mark_failed(&pool, event.id, &e.to_string()).await,
                    };
                    if let Err(e) = mark {
                        // mark_done/failed 失敗 → log，下輪 reset_stuck cron 會補救
                        tracing::error!(event_id = %event.id, error = %e, "outbox mark failed");
                    }
                }
            })
            .await;
    }
    Ok(())
}
```

**並行性 trade-off**：
- ✅ 單筆慢不阻塞（10 筆並行，wall-time 由最慢者決定，非 sum）
- ✅ Channel adapter 自帶 timeout（如 SMTP 30s）— 並行後總批次 ≤ 30s
- ⚠️ DB connection pool 同時 10 個 mark_done/failed → 確認 pool size ≥ CONCURRENCY + 餘量
- ⚠️ 多 worker × 10 並行 = 重要 channel（如 SMTP）可能 rate-limit → 由 channel adapter 自負責 backoff
- 設 `CONCURRENCY: usize = 10` 與 `claim_batch(pool, 10)` 對齊 — 一批內全並行

### Channel Adapter trait

```rust
#[async_trait]
pub trait ChannelAdapter: Send + Sync {
    async fn send(&self, event: &OutboxEvent) -> Result<()>;
}
```

V1 實作：
- `EmailAdapter`：複用 `services/notification/email.rs` 的 SMTP code，payload schema = `{ to, template, vars }`
- `LineAdapter`：複用既有 line push code（如果有），payload schema = `{ user_id, text }`

V1 不實作（留 future）：
- `WebhookAdapter`
- `ReindexAdapter`

## 6. Docker (`Dockerfile.outbox-worker`)

```dockerfile
# 獨立 image，從 backend Dockerfile 複用 build stage 但 CMD 不同
# 路徑: backend/Dockerfile.outbox-worker

FROM rust:1.83-slim AS builder
WORKDIR /app
COPY backend/Cargo.toml backend/Cargo.lock ./
COPY backend/src ./src
COPY backend/migrations ./migrations
COPY backend/.sqlx ./.sqlx
ENV SQLX_OFFLINE=true
RUN cargo build --release --bin outbox_worker

FROM debian:bookworm-slim
RUN apt-get update && apt-get install -y ca-certificates && rm -rf /var/lib/apt/lists/*
COPY --from=builder /app/target/release/outbox_worker /usr/local/bin/
USER 1001
CMD ["outbox_worker"]
```

`docker-compose.yml` 加 service：
```yaml
ipig-outbox-worker:
  build:
    context: .
    dockerfile: backend/Dockerfile.outbox-worker
  depends_on: [ipig-db]
  environment:
    DATABASE_URL_FILE: /run/secrets/db_url
    SMTP_HOST: ...
    # 與 ipig-api 共用 secrets
  secrets: [db_url, db_password, smtp_password, ...]
  restart: unless-stopped
```

獨立 container，與 backend 解耦：
- backend OOM / restart 不影響 worker
- worker 可單獨 scale（多副本，靠 `SKIP LOCKED` 互斥）
- 部署 rolling update 可獨立進行

## 7. 監控

Prometheus metrics（worker exporter）：
| metric | 用途 |
|---|---|
| `outbox_pending_count` (gauge) | 待處理事件數 |
| `outbox_failed_count` (gauge) | FAILED 狀態事件數（可 retry） |
| `outbox_dead_count` (gauge) | DEAD 狀態事件數 → **alert > 0** |
| `outbox_send_duration_seconds` (histogram) | 每筆送出耗時 |
| `outbox_send_total{channel,status}` (counter) | 送出總數，含 channel + 結果 |

Grafana dashboard 加一個 panel；Alertmanager 規則：`outbox_dead_count > 0 for 5m` → email IT。

## 8. Migration / Rollout 計畫

### PR-A：Outbox infra（純新增，無破壞）
1. migration 049（建表）
2. `services/outbox.rs` + `bin/outbox_worker.rs` + `Dockerfile.outbox-worker`
3. `docker-compose.yml` + `docker-compose.prod.yml` 加 service
4. Tests：`OutboxService::enqueue_tx` unit + worker integration（fake adapter）
5. **Staging 驗證 1 週**：手動寫測試 row → 確認 worker 取出 + retry + dead-letter 行為

### PR-B：euthanasia 改用
1. `services/euthanasia.rs:795/865` 兩處 `tracing::warn!` → `OutboxService::enqueue_tx`
2. Tests：mock outbox enqueue 被呼叫
3. Staging 驗證 1 週確認真實 IACUC chair 收到通知

### 後續（不在 R30 範圍）
- amendment status change 通知改 outbox
- role/permission 變更通知改 outbox
- R30-9b 簽章 invalidate 通知改 outbox

## 9. 風險 / 開放問題

| 風險 | 緩解 |
|---|---|
| Worker 同 process 多 thread 取重 | `FOR UPDATE SKIP LOCKED` |
| Worker crash 中卡在 `SENDING` | timeout reset：超過 10min 仍 SENDING → 重設 PENDING（cron 跑） |
| Outbox 表暴漲 | DONE event 30 天後 archive；DEAD event 永久保留供稽核 |
| DB tx 寫 outbox 失敗 → 業務 tx rollback | 預期行為（atomic guarantee） |
| Worker 部署順序 | PR-A merge 後立即 staging 部署 worker；PR-B 之前 backend 不會寫 outbox，所以順序錯誤無害 |

## 10. 不在 scope

- 不做事件 ordering 保證（不同 outbox row 之間 commit order 依賴 enqueued_at，但 worker 不嚴格 FIFO）
- 不做 priority queue（所有事件平等，next_attempt_at 排序）
- 不做 multi-tenant 隔離（單一機構部署）
- channel adapter 不做 fancy retry（只回 Ok/Err，retry 由 outbox status 機器負責）

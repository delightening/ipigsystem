# 刪除兩筆錯誤送審匯入計劃 — 操作 Runbook

> 目標：刪除 `APIG-115011`、`APIG-115014`（皆為已匯入計劃、被錯誤送審），操作紀錄記為 admin 刪除。
> 結論先講：**用既有 admin 端點刪，不要用 raw SQL**（理由見 §0）。

## 0. 為什麼不用 raw SQL（重要）

`user_activity_logs` 是 **HMAC 鏈式 audit**，每日有 verifier 驗鏈完整性。

- **raw `DELETE FROM protocols`** → 刪得掉（FK CASCADE），但**不會留下任何 admin 刪除紀錄** → 不符合「操作紀錄以 admin 刪除」。
- **手動 `INSERT INTO user_activity_logs`** 補一筆 → 會用錯的 HMAC 前後雜湊 → **斷鏈**，verifier 隔天報 broken link。

系統已有專為此情境設計的端點 `DELETE /api/v1/protocols/{id}/imported`（`handlers/protocol/crud.rs:132`，R64-5c），它：
- 僅 admin 可呼叫；
- 守衛「可刪條件」= 匯入計劃 / 已駁回 / 草稿（這兩筆是匯入 → 通過，即使被誤送審）；
- 自動擋 amendments / 未刪除 byproduct 樣品；
- 在同一 tx 內寫**合法鏈式** `PROTOCOL_DELETED` audit（actor = 你這位 admin）；
- 硬刪，scaffold 子表由 FK CASCADE 連帶刪。

## 1. 預檢（read-only，先確認 UUID 與下游資料）

在 prod DB 跑：

```sql
SELECT
  p.id,
  p.application_no,
  p.iacuc_no,
  p.status,
  (p.imported_at IS NOT NULL)                                   AS imported,
  (SELECT count(*) FROM amendments a
     WHERE a.protocol_id = p.id)                                AS amendment_cnt,
  (SELECT count(*) FROM euthanasia_byproduct_samples b
     WHERE b.source_protocol_id = p.id AND b.deleted_at IS NULL) AS byproduct_cnt
FROM protocols p
WHERE p.application_no IN ('APIG-115011', 'APIG-115014');
```

- 預期 `imported = true`、`amendment_cnt = 0`、`byproduct_cnt = 0` → 端點會成功。
- 若任一 `cnt > 0` → 端點會擋（先處理變更/樣品，別硬刪）。
- 記下兩筆的 `id`（UUID）供下一步。

> 註：`animals` 以 `iacuc_no` 軟關聯（無 FK），不會 cascade。匯入後若已掛動物，請先確認那是否也是誤匯資料。

## 2. 執行刪除（admin 身分，逐筆呼叫端點）

用你的 admin JWT（登入後從瀏覽器 devtools 或 token 取得），對每個 UUID 呼叫：

```bash
curl -X DELETE "https://<PROD_HOST>/api/v1/protocols/<UUID-115011>/imported" \
  -H "Authorization: Bearer <ADMIN_JWT>"

curl -X DELETE "https://<PROD_HOST>/api/v1/protocols/<UUID-115014>/imported" \
  -H "Authorization: Bearer <ADMIN_JWT>"
```

- 成功回 `204 No Content`。
- 若回 `400`「計劃已有變更申請…」或「…廢棄物樣品紀錄…」→ 回到 §1 處理下游資料。

> 若維運工具 / 計劃詳情頁的 admin UI 已有「刪除匯入計劃」按鈕，直接點最省事（同一端點）。

## 3. 驗證

```sql
-- 應回 0 筆
SELECT id, application_no FROM protocols
WHERE application_no IN ('APIG-115011', 'APIG-115014');

-- 應各看到一筆 PROTOCOL_DELETED（actor = 你的 admin user_id）
SELECT created_at, actor_user_id, event_type, entity_name
FROM user_activity_logs
WHERE event_type = 'PROTOCOL_DELETED'
ORDER BY created_at DESC
LIMIT 5;
```

---

## 附錄：raw SQL fallback（**僅在端點不可用時**，且接受無 admin audit）

不建議。若真要走，至少包 transaction、依賴 FK CASCADE，並接受**不會有 admin 刪除紀錄**：

```sql
BEGIN;
-- 先確認只命中 2 筆
SELECT id, application_no, status FROM protocols
WHERE application_no IN ('APIG-115011', 'APIG-115014') FOR UPDATE;

-- RESTRICT/NO ACTION 子表需為 0（否則會 23503 失敗）：
--   euthanasia_byproduct_samples.source_protocol_id (RESTRICT)
--   016_glp_compliance 兩處無 ON DELETE 的 protocols FK
--   007_aup_protocol.sql:92 無 ON DELETE 的 FK
-- 其餘多為 CASCADE / SET NULL。

DELETE FROM protocols
WHERE application_no IN ('APIG-115011', 'APIG-115014');
-- 確認 DELETE 2 後再 COMMIT；否則 ROLLBACK
COMMIT;
```

> 走這條 = 沒有 `PROTOCOL_DELETED` audit，事後無法從 audit 追溯是誰刪的。故 §0 強烈建議走端點。

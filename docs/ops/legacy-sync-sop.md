# 舊站 → 新系統 資料同步 SOP（legacy-sync）

> 產出 2026-07-24。配套 skill：`/legacy-sync`（`.claude/skills/legacy-sync/`）。
> 專案背景記憶：`project_legacy_pigmodel_data_migration`。

## 0. 目的與定性（先讀）

- **舊站 `ipig.pigmodel.asia`（豬博士 iPig）= 正在線上使用的系統 = 權威來源，持續變動。**
- **新系統 `ipigsystem.asia` = 測試中 = 久未操作，部分欄位（如 pen）stale。**
- 本 SOP 目標：**把新系統持續追平到舊站的最新狀態**（結構＋紀錄＋文件），可重複執行。
- 成熟度標記：🟢=本 SOP 已實跑驗證；🟡=端點/做法已確認但尚未實跑，首次執行時需逐步驗證。

## 1. 同步範圍

計畫 ↔ 豬 ↔ 實驗狀態 ↔ 欄位（🟢）＋ 每隻豬 7 類紀錄（🟡）＋ 文件/附件（🟡）。
- 現行計畫＝舊站「審查完畢」分頁（`stage=b`，審查通過＋執行中）。過去（執行完畢）不同步。
- 豬＝活豬（未分配＋已分配＋實驗中）∪ 現行計畫的豬（含已犧牲）。

## 2. 前置

- 兩系統皆以 **admin 身分登入**（新系統 admin@ipigsystem.asia；舊站後台帳號）。走真實登入，不自簽 token。
- 瀏覽器同 profile（cookie 共用），用同一 session 操作。
- 舊站後台入口：計畫管理、豬隻管理。

## 3. 系統對照速查

| 主題 | 舊站 | 新系統 |
|---|---|---|
| 計畫狀態 | 審查中/審查完畢(現行)/執行完畢 | protocols.status = APPROVED / APPROVED_WITH_CONDITIONS |
| 豬狀態 | 未分配/已分配/實驗中/實驗完畢 | unassigned / (reserved=unassigned+reserved_protocol_id) / in_experiment / euthanized… |
| 品種 | 迷你豬/大白豬/李宋豬 | breed enum：`minipig` / `white` / … ；`其他`→breed_other |
| 唯一鍵 | 系統號（唯一）、耳號（跨批重複） | animals.id(UUID)、ear_tag(非唯一) |
| 稽核 | — | `user_activity_logs`（HMAC：integrity_hash/previous_hash，按季分區） |

**natural key 規則**：活（非終結）豬用**耳號**對映安全；已犧牲豬耳號會撞，需**系統號**或複合鍵（耳號＋進場日期＋品種＋性別）。（legacy_system_no 欄位規劃中，未落地。）

## 4. 核心技術 recipe

### 4.1 舊站抽取（read-only）

- **計畫清單**：`/admin/project?stage=b`（現行）。分頁 stage：a=審查中、b=審查完畢、c=執行完畢、e=所有。
- **豬清單**：`/admin/pig?stage=`（b=已分配、c=實驗中、d=完成實驗、e=所有、a=欄位圖）。
- **豬明細（7 類紀錄來源）**：`/admin/project/{計畫系統號}/pig/{豬系統號}`，頁內分頁：豬隻資料/觀察試驗/手術/體重/疫苗驅蟲/犧牲採樣/病理報告。
- **DataTable 陷阱**（舊站是 1.9-style server-side DataTables，id=`crudTable`）：
  - 每頁**上限 200**（設更大仍回 200）→ 大清單需分段：迴圈設 `fnSettings()._iDisplayStart` 不生效（fnDraw 會重設）；可行法＝`fnSettings()._iDisplayLength` 調大後 `fnDraw()`，**輪詢 `fnGetData().length` 直到到位**再讀。
  - 直接打 `/admin/pig/search` 需 legacy 參數且有 CSRF/method 限制，易 `{message}` 失敗——優先用 DataTable API。

### 4.2 新系統寫入（App 自己的 API，audit-safe）

- **base**：`https://ipigsystem.asia/api/v1/`
- **認證**：cookie（`fetch(url,{credentials:'include'})`，同源即帶）。
- **CSRF（關鍵陷阱）**：middleware double-submit。cookie `csrf_token`（非 httpOnly）之值，放進 header **`X-CSRF-Token`**。**token 每個回應輪替** → **務必在「最後一個 GET」之後、POST 之前才讀 cookie**，否則 419。（測試：heartbeat 可驗證帶法。）
- **絕不 raw SQL、不用「基本匯入」更新既有豬**（基本匯入是 insert-only，既有耳號直接擋）。一律走下表端點，經 `AuditService` 入稽核鏈。

| 動作 | 端點 | payload 重點 | 狀態 |
|---|---|---|---|
| 建豬 | `POST /animals` | CreateAnimalRequest：ear_tag/breed/gender/entry_date/entry_weight/pen_location 必填；birth_date 選填；force_create | 🟢 |
| 指派實驗 | `POST /animals/batch/assign` | `{animal_ids:[uuid], iacuc_no}`；只吃 unassigned；設 in_experiment＋experiment_date=today；冪等 | 🟢 |
| 預約(=舊「已分配」) | `POST /animals/batch/reserve` | `{animal_ids:[uuid], protocol_id}`（UUID，非 iacuc）；只吃 unassigned；設 reserved_protocol_id | 🟢 |
| 改欄位/狀態 | `PUT /animals/:id` | UpdateAnimalRequest（ear_tag/breed/gender/birth 建後不可改） | 🟡 |
| 觀察試驗 | `POST /animals/:id/observations` | CreateObservationRequest：event_date/record_type/content… | 🟡 |
| 手術 | `POST /animals/:id/surgeries` | — | 🟡 |
| 體重 | `POST /animals/:id/weights`（或批次匯入體重） | — | 🟡 |
| 疫苗/驅蟲 | `POST /animals/:id/vaccinations` | — | 🟡 |
| 犧牲/採樣 | `POST /animals/:id/sacrifice`（upsert）＋`/sacrifice/photos` | — | 🟡 |
| 病理報告 | `POST /animals/:id/pathology/attachments`（檔案） | multipart 上傳 | 🟡 |
| 文件/申請表 | `POST /protocols/:id/attachments`（檔案） | multipart 上傳 | 🟡 |

- 取豬 UUID：`GET /animals/reservable`（未分配池，含 id+ear_tag）。取 protocol UUID：DB `SELECT id FROM protocols WHERE iacuc_no=…`。

### 4.3 文件搬遷（🟡）

舊站附件需先下載（申請表/病理 PDF/病歷）→ 新系統對應 upload 端點以 multipart 上傳。下載檔案屬需授權動作；上傳走 upload_rate_limit。首次執行前先確認舊站附件的存取方式與新系統上傳欄位。

## 5. 執行流程

- **Phase A 抽取（舊站，只讀）**：現行計畫清單 → 各計畫豬清單（依狀態）→ 每隻豬明細（7 類紀錄）→ 附件清單。產出結構化 inventory。
- **Phase B 對帳（新系統）**：以耳號/iacuc 比對；DB `animals`（狀態/iacuc/pen）、`GET /animals/reservable`。標記 已存在/缺漏/值不一致。
- **Phase C 套用**（每步驟後 verify，prod 寫入前確認）：
  1. 缺漏豬 → `POST /animals` 建 → `batch/assign` 或 `batch/reserve`。
  2. 未掛計畫的活豬 → 依舊站狀態：實驗中→`batch/assign`；已分配→`batch/reserve`。
  3. 欄位/其他欄差異 → `PUT /animals/:id`。
  4. 7 類紀錄 → 各自 POST 端點（🟡，首跑先單筆驗證）。
  5. 文件 → upload 端點（🟡）。
- **Phase D 驗證**：見 §6。

## 6. 驗證 cookbook（DB，read-only；容器 `ipig-db`, db `ipig_db`, user postgres）

```sql
-- 各現行計畫 in_experiment 數
SELECT iacuc_no, count(*) FROM animals WHERE status='in_experiment' AND deleted_at IS NULL AND iacuc_no LIKE 'PIG-%' GROUP BY iacuc_no ORDER BY iacuc_no;
-- 某計畫預約
SELECT ear_tag,status,reserved_protocol_id FROM animals WHERE reserved_protocol_id=(SELECT id FROM protocols WHERE iacuc_no='PIG-XXXXX');
-- 稽核鏈：近期動物事件是否入鏈（hash 完整）
SELECT event_type, count(*), bool_and(integrity_hash IS NOT NULL AND previous_hash IS NOT NULL) all_chained
FROM user_activity_logs WHERE created_at > now()-interval '20 minutes' AND event_type LIKE 'ANIMAL%' GROUP BY event_type;
```
> 注意：`audit_logs` 是 impersonation 用，動物稽核在 `user_activity_logs`。`verify_audit_chain` bin 不在 prod api 映像。

## 7. 冪等與重跑

- `batch/assign`/`batch/reserve` 只動 unassigned → 已處理者自動略過，可安全重跑。
- 建豬前先以耳號＋（進場日期/品種）查重，避免重複建。
- 紀錄類重跑需先查該豬既有紀錄做去重（依 event_date＋type）。

## 8. 已知陷阱清單

1. CSRF token 每回應輪替——POST 前最後才讀 cookie（§4.2）。
2. 耳號跨批重複——活豬安全、已犧牲豬需系統號/複合鍵（§3）。
3. 舊站 DataTable 每頁上限 200、程式化 paging/sort 常被忽略（§4.1）。
4. 基本匯入 insert-only，不能更新既有豬（§4.2）。
5. reserve 需 protocol 為 APPROVED，且吃 protocol_id UUID 非 iacuc 字串。
6. 新系統 pen 可能 stale，以舊站（線上）為現況權威。

## 9. Backlog

- 4 隻公羊 825/826/827/828（無資料，待補）→ 新系統羊舍。
- `legacy_system_no` 欄位（永久 provenance/去重鍵）尚未落地（schema migration＝必問）。
- 6 隻欄位校正（677=A08/683=A09/814-817=B16-B19）待本流程套用。

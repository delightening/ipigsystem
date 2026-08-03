# 自助新建動物物種／品種（Self-service Animal Species）— 設計提案 v2

> 狀態：**設計待確認**（2026-07-25）。實作走獨立 PR（分階段）。
> **v2 更正**：v1 宣稱「`breed` 無商業邏輯分支」**有誤**。完整盤點後確認存在多處真實邏輯分支
> （匯入模糊比對、GLP 更正白名單、可用豬摘要硬編欄、前端 `'other'` 必填閘）。本版依實測重寫。

## 1. 目標

admin 在系統內新增動物物種／品種後，**立刻能建立該種動物**——不改 code、不改 enum、不跑 migration。
使用者拍板：**要動 schema 與 API**，讓 `breed` 也變成動態（不只 species_id）。

## 2. 現況（實測）

### 2.1 資料面（綠燈，阻力極小）

| 項目 | 實測 |
|---|---|
| 實際使用的 breed | 只有 `miniature`(122)、`white`(37)；**`LYD`/`other` 從未使用** |
| `breed_other` 有值 | **0 筆** → 可直接移除，零資料遺失 |
| `species_id` 已填 | 115/159；缺 44 筆，breed→species **1:1 對得上**，backfill 為確定性 UPDATE |
| species 主檔 | `pig`(頂層) → `miniature`/`white`(子)；`other`(頂層)。**無 `LYD` 物種列**（enum 有、主檔沒有）→ backfill 需補建 |

### 2.2 程式面（紅燈，規模大）
- **受影響檔案約 79**：後端 src 15、前端 src 26、測試 27（後端整合 18／in-src 5／Python 4）、Python print-pdf 7。
- **三套格式並存**：DB `miniature/white/LYD/other`｜API(serde) `minipig/white/lyd/other`｜中文 `迷你豬/白豬/LYD/其他`。
  翻譯邏輯**重複在 6 處**（`enums.rs`、`utils.rs`、`field_correction.rs`×2、`RequestCorrectionDialog.tsx`、`AnimalAddDialog.tsx`）。

### 2.3 十二項阻礙（依風險排序，摘要）
1. `animals.breed` **NOT NULL 無預設**（`006_animal_management.sql:41`）→ 動 DDL 時 18 個測試檔 INSERT 同時失效；**必須有 nullable 過渡**。
2. **GLP 欄位更正**（`field_correction.rs`）：兩份獨立硬編白名單（`:114-121` 驗證、`:303-318` 套用）＋稽核 `old_value` 快照（`:49-55`）。
   歷史 `animal_field_correction_requests` 存 DB-enum 字串，**不可改寫**（GLP 不可竄改），畫面須永遠能翻譯。
3. **匯入模糊比對**（`import_export.rs:49-63`）：中文標籤比對；**未知字串→`Other` 並把原字串塞進 `breed_other`**（`:336-353`）。
   為真實行為，非顯示。且範本輸出寫死 `"miniature"`（`:664,686,749,762`）。
4. **`AvailablePigSummary.by_breed` 以中文字串為 key**（`requests.rs:365`），由 4 個硬編 `COUNT(*) FILTER`（`query.rs:511-514`）產生，前端直接吃中文 key。需改 `GROUP BY species_id`。
5. **三套格式的 6 處重複翻譯**（見 2.2）——只改一半會靜默寫錯。
6. **`sqlx::Decode` 遇未知值硬失敗**（`enums.rs:117`）→ 過渡期任何一列超出 enum，動物列表全 500。
7. **`species.delete` 不擋引用**（`facility.rs:148-175`，僅 `is_active=false`）且 `list_species` 隱藏 inactive → species 一旦成真相源，停用物種會讓動物品種顯示變孤兒。
   **`create_species` 零驗證**（無 `Validate` derive）：重複 code 噴原始 DB 錯；無 parent 迴圈防護。
8. **`useBreedSpecies()` 把「品種」定義為 `parent_id !== null`**（`useBreedSpecies.ts:11`）→ admin 建的**頂層**物種（如山羊）在表單**看不到**；
   且 `AnimalAddDialog.tsx:184` 把 `code` 直送 `AnimalBreed` 欄位 → 新 code 會 **422**。
9. `repositories/ai.rs:181-209` 十段硬編 SQL 各選 `breed::text`；`services/ai.rs:280,286` 對 LLM 宣告 breed 可篩選/排序。
10. **跨服務契約**：`medical.rs` 原封序列化 `Animal` 給 Python print-pdf（`medical_record.py`/`surgery.py` 各有一份 `_BREED_ZH`）→ **需 lockstep 部署**，否則 GLP PDF 印代碼。
11. 前端 `AnimalFilters.tsx:112-121` **已缺 `lyd` 選項**（現存 bug）；`AvailablePigsPage.tsx:281-292` 用 exhaustive switch（改動會編譯錯）。
12. **`breed_other` 不在 migration 內**，由 `seed.rs:105-119` 開機 `ALTER TABLE` 加上 → 移除時要一併處理這段。

## 3. 目標終態

- **`species_id` = 動物種類的唯一真相源**（NOT NULL）。
- `species` 主檔階層表達 物種→品種（`豬→迷你豬/白豬`、`山羊`可無子層）。
- **`breed` 欄位、`animal_breed` type、`breed_other` 全部移除**。
- 顯示／篩選／匯入／匯出／AI／PDF 一律以 species 為準。

## 4. 分階段計畫（expand → contract）

> 理由：79 檔 × 12 阻礙一次上線，對單機 prod 風險過高；且阻礙 1、6 要求必須有 nullable/過渡期。
> 每階段獨立可上線、prod 全程綠。**使用者目標（自助）在 P1 即達成**。

### P1 — 自助可用（達成目標，低風險）
1. **species 主檔補強**：`create/update` 加驗證（code 唯一預檢、parent 迴圈防護）；**`delete` 擋有動物引用**；`SpeciesTab` 顯示「使用中」。
2. **表單改寫 `species_id`**：`useBreedSpecies` 改回傳**全部啟用物種**（含頂層）；選取寫 `species_id`。
3. **後端推導 breed**：帶 `species_id` 時由後端推導 `breed`（豬子物種→對應 enum；其餘→`other`），**前端不再送 enum**。通用規則，新物種零 code 改動。
4. **顯示改讀 `species.name`**（清單／明細／匯出／print-pdf payload），`species_id` NULL 時 fallback 舊 breed。
5. **Backfill migration**：補 44 筆 `species_id`；**補建 `LYD` 物種列**。
- ✅ 產出：admin 加「山羊」→ 立即可建羊。**4 隻山羊在此階段建立**。

### P2 — 全面轉 species（清硬編）
- 匯入改為 species 查表（code/name/name_en/別名）＋未知字串政策（見 §5 決策 2）；範本同步。
- `by_breed` 改 `GROUP BY species_id JOIN species`；API 形狀改動；前端篩選改吃動態物種清單（順帶修 `lyd` 缺項 bug）。
- `ai.rs` 查詢與 LLM 欄位描述改 species。
- **GLP 更正**：品種可更正欄改為 `species_id`；歷史字串**保留不改寫**，畫面加翻譯層。
- **print-pdf 與後端 lockstep 部署**。

### P3 — 真正移除（contract）
- `breed` 改 nullable → 移除欄位 + `DROP TYPE animal_breed` + 移除 `breed_other`（含 `seed.rs` 那段 DDL）。
- 更新 27 個測試（18 後端整合＋in-src＋4 Python＋1 E2E）與 guest-demo fixtures。
- 更新 `.claude/skills/legacy-sync/SKILL.md:51`、`protocol-import-backfill`（目前硬編 `breed:"white"`）。

## 5. 需使用者拍板的決策
1. **節奏**：分三階段（建議）vs 一次到底。
2. **匯入遇未知品種字串**：拒絕該列並報錯（建議，資料最乾淨）／自動建立新物種（最自助但易長垃圾主檔）／歸「其他」（現行行為）。
3. **`breed_other`**：一併移除（建議，0 筆資料）／保留作自由文字。
4. **GLP 品種更正**：改為可更正 `species_id`（建議）／取消品種可更正／維持現狀。
   （無論何者，**歷史稽核字串一律不改寫**。）

## 6. 驗收標準
1. admin 於物種管理新增「山羊」→ 新增動物表單**立即**出現、可建立（**不需部署**）。
2. 該動物顯示「山羊」於清單／明細／匯出／病歷 PDF。
3. 既有豬資料顯示與篩選不變（回歸）。
4. 停用/刪除使用中物種被正確擋下。
5. `cargo test` / `tsc` / `eslint` / E2E 綠；CI 綠。
6. P3 後：DB 無 `breed`/`breed_other` 欄與 `animal_breed` type。

## 7. 與「4 隻山羊 + 羊舍」的銜接
- 羊隻**於 P1 完成後建立**（使用者已裁定：等自助功能好再建）。
- 羊舍前置（資料整理）：building `S=羊舍` 下 3 個亂 zone → 收成「zone 羊(b370b0ad) 啟用 + pen S(容量4)」，
  刪 羊１(S01) 與重複 羊(pen 容量1)。4 隻同欄群養進 pen S。
- 建羊資料：公、出生 2025-01-30、進場 2026-07-13、體重 825=59 / 826=64 / 827=56.5 / 828=68 kg。
  紙本每日觀察（D-0 起）依使用者裁定**先不數位化**。

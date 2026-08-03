# 計劃書 HTML 檢視「顯示未選選項」規格

> 狀態：**已定稿（2026-06-30，使用者確認 Q1/Q2/Q3）**。本輪先實作 **Design (§4) 示範**，驗證 pattern 後再決定是否鋪到其他 section。
> 對應 PR：見「計劃書 unselected options」分支（stacked on #813）。

## 1. 目標與原則

- 線上 **HTML 檢視**：每個「選擇欄位」除了申請者**已選**的項目，也呈現**未選的其他選項**（淡化標示），讓審查員看見「原本有哪些可能性、申請者選了哪個、沒選哪些」，自行判斷其合理性。
- **不在計劃書上寫任何理由文字** —— 「為什麼選 A 不選 B」是審查員自行思考的事，不是要顯示的資料。
- **列印 / 匯出 PDF 維持現狀**（完稿只顯示已選），本功能僅影響螢幕 HTML 檢視。

## 2. 使用者確認的決策

| # | 決策 | 選定 |
|---|---|---|
| Q1 | 範圍 | **先做 Design (§4) 一個當示範**，確認後再鋪其他 section |
| Q2 | 未作答（null）欄位 | **仍顯示全部選項**（全部標未選），讓審查員知道有此欄位且未填 |
| Q3 | 視覺樣式 | **勾選框 ☑/☐ + 已選實色、未選淡灰**（依 DESIGN.md token，不硬編色） |

## 3. 顯示規則（三型別）

| 型別 | 範例欄位 | 顯示方式 |
|---|---|---|
| Boolean（是/否） | `is_under_anesthesia`、`restrictions.is_restricted`、`non_pharma_grade.used`、`hazards.used`、`controlled_substances.used` | 列出「是 / 否」兩項，已選實色、另一項淡灰；null 時兩項皆淡灰 |
| Enum（多選一） | `pain.category`、`final_handling.method`、`anesthesia_type`、`euthanasia_type`、`restriction_type` | 列出完整選項，已選實色、其餘淡灰 |
| 複選（multi-select） | `pain.relief_measures` | 已勾選實色、未勾選**不再隱藏**，改淡灰列出 |

**巢狀依賴欄位**：依賴父選項才有意義的子 enum（`anesthesia_type` 需麻醉=是、`euthanasia_type` 需處置=安樂死、`restriction_type` 需限制=是）只在父分支被選時顯示其選項；不在父分支未選時硬列出。

## 4. Design (§4) 選擇欄位 + 選項（含 stored value ↔ i18n label key 對照）

| 欄位路徑 | 型別 | stored values → i18n label key（前綴 `aup.design.`） |
|---|---|---|
| `anesthesia.is_under_anesthesia` | bool | 是/否（`common.yes`/`common.no`） |
| `anesthesia.anesthesia_type`（依賴麻醉=是） | enum | `survival_surgery`→`anesthesiaTypes.survival`、`non_survival_surgery`→`anesthesiaTypes.non_survival`、`gas_only`→`anesthesiaTypes.gas_only`、`azaperonum_atropine`→`anesthesiaTypes.azaperonum_atropine` |
| `pain.category` | enum | `B/C/D/E`→`painCategories.{B/C/D/E}` |
| `pain.relief_measures` | 複選 | `alternative_painless_procedure`/`anesthesia_analgesia`/`humane_euthanasia`/`no_relief_with_justification`→`reliefMeasures.*`（key 同值） |
| `restrictions.is_restricted` | bool | 是/否 |
| `restrictions.restriction_type`（依賴限制=是） | enum | `fasting_before_anesthesia`→`restrictionTypes.fasting`、`other`→`restrictionTypes.other` |
| `final_handling.method` | enum | `euthanasia`/`transfer`/`other`→`handlingMethods.*`（key 同值） |
| `final_handling.euthanasia_type`（依賴處置=安樂死） | enum | `kcl`/`electrocution`/`other`→`euthanasiaTypes.*`（key 同值） |
| `non_pharma_grade.used` | bool | 是/否 |
| `hazards.used` | bool | 是/否（已選明細沿用現有 materials 清單） |
| `controlled_substances.used` | bool | 是/否（已選明細沿用現有表格） |

> 注意 `anesthesia_type` 與 `restriction_type` 的 **stored value ≠ i18n key**，須以 value→labelKey 對照表處理（已編入 `protocolDesignOptions.ts`）。

## 5. 實作元件

- `frontend/src/lib/constants/protocolDesignOptions.ts`：各 Design enum 的 `{ value, labelKey }[]` 正規清單（顯示端 single source）。
- `frontend/src/components/protocol/content-sections/ChoiceList.tsx`：共用呈現元件，input = `options: {value,labelKey?,label?}[]` + `selectedValues: string[]`，輸出 ☑/☐ + 已選/未選樣式（boolean/single/multi 共用，single/bool 即 selectedValues 長度 0~1）。
- 改寫 `frontend/src/components/protocol/content-sections/DesignSection.tsx` 的選擇欄位區塊改用 `ChoiceList`；自由文字欄位（程序敘述、終點、各 description）維持原樣。

## 6. 尚未處理（待 Design 示範確認後）

- ✅ **已完成**：Design（§4，PR #816）、Surgery（§6：無菌措施 / 多次手術 / 術後護理類型）、Items（§3：是否使用試驗物質）、Guidelines（§5：A–L 12 資料庫顯示已勾選/未勾選）。共用 `ChoiceList` + `CheckIndicator` + `protocolChoiceOptions.ts`（通用 helper + Surgery/Guidelines 選項）。
- ⏳ **待做：Purpose（§2）**。巢狀條件最複雜（重複性 status、3R 縮減 special_care / single_housing[+reasons] / animal_reuse[+plan]、替代搜尋平台 8 項），需謹慎保留現有條件明細欄位，另開一輪處理。
- ⏳ **DRY 收斂**：選項清單目前同時存在於「編輯表單元件」與顯示端常數；應讓編輯表單也改用 `protocolDesignOptions.ts` / `protocolChoiceOptions.ts`，單一來源。為降風險尚未改動編輯表單。
- **未納入**：Items 的逐項 `is_sterile`（是/否屬性，非「替代方案」選擇）、Design 的 `distress_signs`（17 項觀察症狀）維持原樣。

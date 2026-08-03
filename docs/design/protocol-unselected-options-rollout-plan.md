# 計劃書「顯示未選選項」rollout — 剩餘工作計畫

> 配套規格：`docs/design/protocol-unselected-options-spec.md`（目標/決策 Q1–Q3/三型別顯示規則）。
> 本檔為**剩餘工作的追蹤計畫**，讓後續可直接執行（含 Purpose 詳細欄位盤點、DRY 收斂目標）。
> 更新日：2026-06-30。

## 進度總覽

| Section | 狀態 | 對應 PR | 備註 |
|---|---|---|---|
| **Design (§4)** | ✅ 已合併 main | #816 | 麻醉/疼痛/緩解/限制/最終處置/安樂死/非藥用級/危害/管制藥 |
| **Surgery (§6)** | 🔵 PR 審查中（**未合併**） | #819 | 無菌措施/多次手術/術後護理類型；待 local 驗證後合併 |
| **Items (§3)** | 🔵 PR 審查中（**未合併**） | #819 | 是否使用試驗物質 |
| **Guidelines (§5)** | 🔵 PR 審查中（**未合併**） | #819 | A–L 12 資料庫已勾選/未勾選 |
| **Purpose (§2)** | ⏳ 待做 | — | 巢狀最複雜，見下方盤點 |
| **DRY 收斂（編輯表單）** | ⏳ 待做 | — | 編輯表單改用顯示端選項常數 |
| **部署 prod** | ⏳ 待做 | — | 合併後需 rebuild web 才會在 ipigsystem.asia 出現 |

## 共用基礎（已存在，後續沿用）

- `frontend/src/components/protocol/content-sections/ChoiceList.tsx`：`ChoiceList`（☑/☐ + 已選/未選 + sr-only）、`CheckIndicator`（自訂列共用勾選方塊）。
- `frontend/src/lib/constants/protocolDesignOptions.ts`：Design enum 選項 + `ProtocolChoiceOption` 型別。
- `frontend/src/lib/constants/protocolChoiceOptions.ts`：通用 `YES_NO_OPTIONS` / `boolSelected` / `oneOf` + Surgery / Guidelines 選項。

## Purpose (§2) 待做盤點

> 檢視元件：`content-sections/PurposeSection.tsx`；編輯表單：`pages/protocols/protocol-edit/SectionPurpose.tsx`（常數 L13–33）。i18n：`zh-TW.json > aup.purpose.*`（群組已存在，已核對）。
> **巢狀依賴多**，改寫時務必保留現有條件明細欄位（justification / previous_iacuc_no / regulation_basis / description / metabolic_cage_duration / plan_other 等）。

| 欄位路徑 | 型別 | stored values → i18n labelKey | 巢狀依賴 |
|---|---|---|---|
| `purpose.duplicate.status` | enum | `no`/`not_applicable`/`yes_continuation`/`yes_duplicate` → `aup.purpose.duplicateStatusOptions.*`（key 同值） | not_applicable→regulation_basis；yes_continuation→previous_iacuc_no；yes_duplicate→justification |
| `purpose.reduction.special_care.needed` | bool | 是/否（`common.yes`/`common.no`） | true→description |
| `purpose.reduction.single_housing.required` | bool | 是/否 | true→reasons + 監控欄位 |
| `purpose.reduction.single_housing.reasons` | 複選 | `b1_pregnant_female`/`b1_breeding_male`/`b1_post_wean`/`b2_post_surgery`/`b2_single_in_group`/`b2_metabolic_cage`/`b3_aggressive`/`b3_temporary`/`b4_other` → `aup.purpose.singleHousingReasonOptions.*`（key 同值） | 僅 required=true 時顯示；b2_metabolic_cage→metabolic_cage_duration |
| `purpose.reduction.animal_reuse.considered` | bool | 是/否 | true→plan |
| `purpose.reduction.animal_reuse.plan` | enum | `no_further_procedure`/`partial_procedure_euthanasia`/`teaching_purpose`/`deferred`/`other` → `aup.purpose.animalReusePlanOptions.*`（key 同值） | 僅 considered=true 時顯示；other→plan_other |
| `purpose.replacement.alt_search.platforms` | 複選 | `altbib`→`aup.purpose.altbibLabel`、`db_alm`→`dbAlmLabel`、`re_place`→`rePlaceLabel`、`johns_hopkins`→`johnsHopkinsLabel`、`taat`→`taatLabel`、`nc3rs_eda`→`nc3rsEdaLabel`、`nc3rs_refinement`→`nc3rsRefinementLabel`、`other`→`otherPlatformLabel`（**個別 key，非群組**） | other→alt_search.other_name |

> 平台選項建議在 `protocolChoiceOptions.ts` 新增 `ALT_SEARCH_PLATFORM_OPTIONS`（value→上述個別 labelKey）。

## DRY 收斂（編輯表單改用顯示端選項常數）

目標：消除「編輯表單各自定義選項」與「顯示端常數」的重複，單一來源。

| 編輯表單檔 | 目前各自定義 | 收斂到 |
|---|---|---|
| `protocol-edit/components/AnesthesiaSection.tsx` | 麻醉類型 4 項 | `protocolDesignOptions.ANESTHESIA_TYPE_OPTIONS` |
| `protocol-edit/components/PainCategorySection.tsx` | 疼痛分級 / 緩解措施 | `PAIN_CATEGORY_OPTIONS` / `RELIEF_MEASURE_OPTIONS` |
| `protocol-edit/components/RestrictionsSection.tsx` | 限制類型 | `RESTRICTION_TYPE_OPTIONS` |
| `protocol-edit/components/FinalHandlingSection.tsx` | 最終處置 / 安樂死方式 | `HANDLING_METHOD_OPTIONS` / `EUTHANASIA_TYPE_OPTIONS` |
| `protocol-edit/SectionSurgery.tsx` | 無菌措施 / 術後護理類型 | `protocolChoiceOptions.SURGERY_*` |
| `protocol-edit/SectionPurpose.tsx` | duplicate / single_housing reasons / animal_reuse / platforms | 上述 Purpose 常數 |

> 注意：編輯表單為 SelectItem / checkbox，value 須與顯示端常數的 `value` 完全一致（已在常數內對齊 stored value）。

## 刻意排除（非「替代選擇」性質，維持原樣）

- Items 逐項 `is_sterile`（是/否屬性）。
- Design `pain.distress_signs`（17 項觀察症狀，屬「觀察到的徵候」而非備選方案）。

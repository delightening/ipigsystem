# 計畫書（AUP Protocol）填寫表單 — 完整欄位規格

> **用途**：交給 cowork（或任何工具）作為「互動式計畫書填寫 skill」的欄位真相來源。
> **產生日期**：2026-06-09
> **真相來源**：`frontend/src/pages/protocols/protocol-edit/` 下的 `ProtocolEditPage.tsx` + 各 `Section*.tsx` + `validation.ts` + `types/protocol.ts` + `locales/zh-TW.json`。
> **viewer 提示**：本檔為 Markdown，可用瀏覽器/GitHub/任何 Markdown 檢視器直接渲染成網頁閱讀。

---

## 0. 閱讀本文件的方式

計畫書填寫表單共 **10 個 Section**，主容器是 `ProtocolEditPage.tsx`，每個 Section 對應一個 `Section*.tsx` 元件。所有填寫資料存在一個巢狀物件 `working_content`（型別 `ProtocolWorkingContent`），少數欄位（研究名稱、起訖日期）存在 `formData` 根層級。

每個欄位記錄以下屬性：

| 屬性 | 意義 |
|---|---|
| **path** | 資料路徑（例：`basic.project_type`、`working_content.animals.animals[]`） |
| **標籤** | UI 顯示的中文（來自 i18n `aup.*`） |
| **型別** | `text` / `textarea` / `number` / `date` / `radio`(單選) / `checkbox`(複選) / `repeater`(可新增多筆) / `file` / `signature` |
| **必填** | 是 / 否 / 條件（並註明 UI 標 `*` 但實際 validation 是否擋送出） |
| **選項** | radio/checkbox 的可選值 → 中文標籤 |
| **條件顯示** | 此欄位在什麼前置條件下才出現 |
| **驗證** | `validation.ts` 的送出檢查規則 |

### 三態欄位慣例（重要）
多個「是/否」問題用 `boolean | null` 三態：`null`=未選、`true`=是、`false`=否。UI 用下拉選單（值 `''` / `yes` / `no`）。**選「否」時程式會主動清空其下展開欄位。**

### 「UI 標 `*` 但 validation 不擋」
部分欄位畫面有紅星 `*`，但 `validation.ts` 並未在送出時阻擋。本文件會逐一註明，cowork 若要做「真正必填」清單，請以 validation 規則為準（每個 Section 末尾有彙整）。

---

## Section 1 — 研究資料（基本資料）

> i18n：`aup.section1` =「1. 研究資料」。元件 `SectionBasic.tsx` + 共用子元件 `ResearchBasicFields.tsx`。
> 注意：**研究名稱、起訖日期寫在 `formData` 根層級**，其餘在 `working_content.basic`。

| # | path | 標籤 | 型別 | 必填 | 條件顯示 | 選項 / 驗證 |
|---|---|---|---|---|---|---|
| 1 | `title`（頂層） | 研究名稱 | text | **是** | 恆顯示 | 非空白，否則「請填寫研究名稱」 |
| 2 | `basic.apply_study_number` | 試驗編號 | text | 否 | **僅非新建 + IACUC 執行秘書**可見 | 由執行秘書填寫，無驗證 |
| 3 | `start_date`（頂層） | 預計試驗時程—開始 | date | **是** | 恆顯示 | 起訖皆需有值 |
| 4 | `end_date`（頂層） | 預計試驗時程—結束 | date | **是** | 恆顯示 | 需有值；且**結束日須晚於開始日**，否則「預計試驗完成日期必須大於起始日期」 |
| 5 | `basic.pi.name` | 計畫主持人—姓名 | text | **是** | PI 段（編輯頁顯示；匯入頁隱藏） | 非空白 |
| 6 | `basic.pi.email` | PI—Email | text | **是** | 同上 | 單一 email 格式 `xxx@xxx.xxx` |
| 7 | `basic.pi.phone` | PI—電話 | text | **是** | 同上 | 去 `-` 後須 9 或 10 碼數字 |
| 8 | `basic.pi.phone_ext` | PI—分機 | text | 否 | 同上 | — |
| 9 | `basic.pi.address` | PI—地址 | text | **是** | 同上 | 非空白 |
| 10 | `basic.is_glp` | GLP 符合性 | radio | UI標*，**validation 不擋** | 恆顯示 | `true`→「GLP」/ `false`→「非GLP」 |
| 11 | `basic.registration_authorities` | 預定申請註冊之權責機關 | checkbox | UI標*，**validation 不擋** | **僅 `is_glp===true`** | FDA(美國)/CE(歐盟)/TFDA(台灣)/CFDA(中國)/other |
| 12 | `basic.registration_authority_other` | 權責機關—其他說明 | text | 否 | `is_glp===true` 且含 `other` | — |
| 13 | `basic.project_type` | **計畫類型**（複選） | checkbox | **是** | 恆顯示 | 見下方選項表；至少選 1 |
| 14 | `basic.project_type_other` | 計畫類型—其他說明 | text | 否 | 含 `6_other` 時顯示 | — |
| 15 | `basic.project_category` | **計畫種類**（複選） | checkbox | **是** | 恆顯示 | 見下方選項表；至少選 1 |
| 16 | `basic.project_category_other` | 計畫種類—其他說明 | text | **條件**（含 `12_other` 時必填） | 含 `12_other` 時顯示 | 含 12_other 但空→「請填寫其他計畫種類說明」 |
| 17 | `basic.funding_sources` | 資金來源（複選） | checkbox | 否 | 恆顯示 | moa農業部/mohw衛福部/nstc國科會/moe教育部/env環境部/other |
| 18 | `basic.funding_other` | 資金來源—其他說明 | text | 否 | 含 `other` 時顯示 | — |
| 19 | `basic.sponsor.contact_same_as_pi` | 同計畫主持人 | checkbox(單一旗標) | 否 | 恆顯示 | 勾選後聯絡人三欄繼承 PI 且唯讀並 live-sync |
| 20 | `basic.sponsor.name` | 委託單位—單位名稱 | text | **是** | 恆顯示 | 非空白 |
| 21 | `basic.sponsor.contact_person` | 委託單位—聯絡人 | text | **是** | 恆顯示（可被旗標 disabled） | 非空白 |
| 22 | `basic.sponsor.contact_phone` | 委託單位—聯絡電話 | text | **是** | 同上 | 去 `-` 後 9 或 10 碼數字 |
| 23 | `basic.sponsor.contact_email` | 委託單位—聯絡信箱 | text(支援多筆) | **是** | 同上 | 多筆以 `;` `/` `,` 或換行分隔，每筆須合法 email |
| 24 | `basic.facility.title` | 機構名稱 | text | **是** | 恆顯示；**僅 admin/SYSTEM_ADMIN/IACUC_STAFF 可編輯** | 非空白 |
| 25 | `basic.housing_location` | 位置 / 動物飼養地點 | text | **是** | 同上（角色鎖定） | 非空白 |

### 計畫類型選項（`basic.project_type`，i18n `aup.projectTypes.*`）
| key | 標籤 |
|---|---|
| `1_basic_research` | 1. 基礎研究 |
| `2_applied_research` | 2. 應用研究 |
| `3_pre_market_testing` | 3. 產品上市前測試 |
| `4_educational` | 4. 教學訓練 |
| `5_biologics_manufacturing` | 5. 製造生物製劑 |
| `6_other` | 6. 其他（選此顯示補充說明框） |

### 計畫種類選項（`basic.project_category`，i18n `aup.projectCategories.*`）
| key | 標籤 | | key | 標籤 |
|---|---|---|---|---|
| `1_medical` | 1. 醫學研究 | | `7_medical_materials` | 7. 醫療器材 |
| `2_agricultural` | 2. 農業研究 | | `8_pesticide` | 8. 農藥 |
| `3_drugs_vaccines` | 3. 藥物及疫苗 | | `9_animal_drugs_vaccines` | 9. 動物用藥及疫苗 |
| `4_supplements` | 4. 健康食品 | | `10_animal_supplements_feed` | 10. 動物保健品、飼料添加物 |
| `5_food` | 5. 食品 | | `11_cosmetics` | 11. (含藥)化妝品 |
| `6_toxics_chemicals` | 6. 毒、化學品 | | `12_other` | 12. 其他（選此須填補充說明） |

> **Section 1 真正擋送出的必填**：研究名稱、起訖日期(+結束晚於開始)、PI 姓名/email/電話/地址、計畫類型(≥1)、計畫種類(≥1)、計畫種類其他說明(條件)、委託單位名稱/聯絡人/電話/信箱、機構名稱、位置。
> **型別存在但 UI 未渲染**（不算欄位，僅備註）：`basic.study_title`、`test_item_type*`、`tech_categories`、`sd.{name,email}`、`facility.address`。

---

## Section 2 — 研究目的

> i18n：`aup.section2` =「2. 研究目的」。元件 `SectionPurpose.tsx`。全段 path 屬 `purpose.*`。

### 2.1 研究目的及重要性
| path | 標籤 | 型別 | 必填 | 驗證 |
|---|---|---|---|---|
| `purpose.significance` | 2.1 研究之目的及重要性 | textarea(8列) | **是** | 非空白（建議 500–1000 中文字 / 250–500 英文字，勿超過 1 個 A4 頁） |

### 2.2 替代原則（Replacement）
| path | 標籤 | 型別 | 必填 | 條件顯示 | 選項 / 驗證 |
|---|---|---|---|---|---|
| `purpose.replacement.rationale` | 2.2.1 活體動物試驗之必要性及選擇此動物種別的原因 | textarea(4列) | **是** | 恆顯示 | 非空白 |
| `purpose.replacement.alt_search.platforms` | 2.2.2 非動物替代方案搜尋—資料庫平台（複選） | checkbox | **是** | 恆顯示 | 見下方平台清單；至少選 1 |
| `purpose.replacement.alt_search.other_name` | 其他資料庫名稱 | text | 否 | 含 `other` 時 | — |
| `purpose.replacement.alt_search.keywords` | 搜尋關鍵字 | text | **是** | 恆顯示 | 非空白 |
| `purpose.replacement.alt_search.conclusion` | 搜尋結果與結論 | textarea(3列) | **是** | 恆顯示 | 非空白 |
| `purpose.duplicate.status` | 2.2.3 是否為重複本人或他人試驗 | radio(下拉) | **是** | 恆顯示 | `no`否 / `not_applicable`不適用(委託試驗) / `yes_continuation`是,延續性實驗 / `yes_duplicate`是 |
| `purpose.duplicate.regulation_basis` | 法規依據 | text | **條件**(status=not_applicable) | status=not_applicable | 條件必填 |
| `purpose.duplicate.previous_iacuc_no` | 前次核准 IACUC 編號 | text | **條件**(status=yes_continuation) | status=yes_continuation | 條件必填 |
| `purpose.duplicate.justification` | 重複的必要性說明 | textarea(3列) | **條件**(status=yes_duplicate) | status=yes_duplicate | 條件必填 |

**2.2.2 替代方案搜尋平台選項**（`ALT_PLATFORMS`，部分附外部連結）：
`altbib` ALTBIB / `db_alm` DB-ALM / `re_place` 歐洲動物替代試驗資源平台 / `johns_hopkins` Johns Hopkins 替代中心 / `taat` 臺灣 TAAT / `nc3rs_eda` NC3Rs EDA / `nc3rs_refinement` NC3Rs 精緻化資料庫 / `other` 其他

### 2.3 減量原則（Reduction）
| path | 標籤 | 型別 | 必填 | 條件顯示 | 選項 / 說明 |
|---|---|---|---|---|---|
| `purpose.reduction.design` | 2.3 實驗設計說明 | textarea(6列) | **是** | 恆顯示 | 非空白 |
| `purpose.reduction.special_care.needed` | 2.3.1 動物是否需要特殊照護 | radio(是/否) | 否 | 恆顯示 | 選否清空描述 |
| `purpose.reduction.special_care.description` | 特殊照護內容 | textarea(3列) | 否 | needed=true | — |
| `purpose.reduction.single_housing.required` | 2.3.2 是否需要單獨飼養 | radio(是/否) | 否 | 恆顯示 | 選否清空相關欄 |
| `purpose.reduction.single_housing.reasons` | 單獨飼養原因（複選） | checkbox | 否 | required=true | 見下 9 項 |
| `purpose.reduction.single_housing.metabolic_cage_duration` | 代謝籠使用期間 | text | 否 | required=true 且含 `b2_metabolic_cage` | — |
| `purpose.reduction.single_housing.monitoring_method` | 結束單獨飼養評估的監控方式 | text | 否 | required=true | — |
| `purpose.reduction.single_housing.estimated_duration` | 預計單獨飼養時間 | text | 否 | required=true | — |
| `purpose.reduction.animal_reuse.considered` | 2.3.3 試驗結束後是否考量動物再應用 | radio(是/否) | 否 | 恆顯示 | 選否清空計畫 |
| `purpose.reduction.animal_reuse.plan` | 再應用計畫 | radio(下拉) | 否 | considered=true | 見下 5 項 |
| `purpose.reduction.animal_reuse.plan_other` | 再應用計畫—其他說明 | textarea(2列) | 否 | considered=true 且 plan=other | — |

**單獨飼養原因選項**：`b1_pregnant_female`懷孕雌性 / `b1_breeding_male`繁殖雄性 / `b1_post_wean`斷奶後單獨 / `b2_post_surgery`術後護理 / `b2_single_in_group`測試組單隻 / `b2_metabolic_cage`代謝籠(≤7天) / `b3_aggressive`攻擊性行為 / `b3_temporary`暫時使用 / `b4_other`其他
**再應用計畫選項**：`no_further_procedure`回歸群養/觀察 / `partial_procedure_euthanasia`部分操作後安樂死 / `teaching_purpose`教學訓練用途 / `deferred`暫未確定/補件審查 / `other`其他

### 2.4 精緻化原則（Refinement）
| path | 標籤 | 型別 | 必填 | 說明 |
|---|---|---|---|---|
| `purpose.refinement_description` | 2.4 精緻化原則說明 | textarea(8列) | **是** | 欄位空白時提供「插入標準預設文字」按鈕（麻醉止痛、環境豐富化、健康觀察等標準段落） |

> **型別存在但 UI 未渲染**：`purpose.abstract`(2.0摘要)、`reduction.sample_size_method/details`、`reduction.grouping_plan`。

---

## Section 3 — 試驗物質與對照物質

> i18n：`aup.section3` =「3. 試驗物質與對照物質」。元件 `SectionItems.tsx`。path 屬 `items.*`。

### 3.0 入口開關
| path | 標籤 | 型別 | 必填 | 條件顯示 | 選項 / 驗證 |
|---|---|---|---|---|---|
| `items.use_test_item` | 本計畫是否投予「試驗物質」於動物 | radio(三態) | **是** | 恆顯示 | yes/no；選 yes 展開下方兩個 repeater，選 no 顯示「略」 |

### 3.1 試驗物質 `items.test_items[]`（repeater，僅 `use_test_item===true` 顯示）
| 子欄位 | 標籤 | 型別 | 必填 | 條件 |
|---|---|---|---|---|
| `name` | 物質名稱 | text | **是** | — |
| `form` | 劑型 | text | **是** | （如：液體、粉末） |
| `purpose` | 用途 | text | **是** | — |
| `storage_conditions` | 保存環境 | text | **是** | — |
| `is_sterile` | 本物質是否為無菌製備 | radio(預設是) | **是** | — |
| `non_sterile_justification` | 非無菌製備說明 | textarea(3列) | **條件** | 僅 `is_sterile===false` 顯示且必填 |
| `photos` | 佐證資料 | file(image,≤10MB,≤10張) | 否 | — |

### 3.2 對照物質 `items.control_items[]`（repeater，僅 `use_test_item===true` 顯示）
欄位同試驗物質，但**無「劑型 form」欄位**；`name` 標籤為「對照名稱」（若無對照填 N/A）。其餘 `purpose`/`storage_conditions`/`is_sterile`/`non_sterile_justification`/`photos` 同上。

> **型別存在但 UI 未渲染**：`lot_no`/`expiry_date`/`concentration`/`hazard_classification`、control 的 `is_sham`/`is_vehicle`。

---

## Section 4 — 研究設計與方法

> i18n：`aup.section4` =「4. 研究設計與方法」。元件 `SectionDesign.tsx` + 子元件。path 屬 `design.*`。

### 4.1.1 麻醉 `design.anesthesia`
| path | 標籤 | 型別 | 必填 | 條件顯示 | 選項 |
|---|---|---|---|---|---|
| `anesthesia.is_under_anesthesia` | 4.1.1 是否於麻醉下進行試驗 | radio(三態) | **是** | 恆顯示 | yes/no |
| `anesthesia.anesthesia_type` | 麻醉類型 | radio(下拉) | **條件**(is_under_anesthesia=true) | is_under_anesthesia=true | 見下 5 項 |
| `anesthesia.other_description` | 其他麻醉方式說明 | textarea(3列) | **條件** | anesthesia_type=other | — |

**麻醉類型選項**：`survival_surgery`存活手術 / `non_survival_surgery`非存活手術 / `gas_only`僅氣體麻醉(Isoflurane) / `azeperonum_atropine`畜舒坦肌注鎮靜+氣麻 / `other`其他
> ⚠️ **跨 Section 連動**：選 `survival_surgery` 或 `non_survival_surgery` → **Section 6 手術計畫書整組變必填**。

### 4.1.2 試驗內容及流程
| path | 標籤 | 型別 | 必填 |
|---|---|---|---|
| `design.procedures` | 4.1.2 詳述動物試驗內容及流程、投予物質/途徑/理由、採血、影像觀察、保定、頻率 | textarea(8列) | **是** |

### 4.1.3–4.1.5 疼痛 `design.pain`
| path | 標籤 | 型別 | 必填 | 條件顯示 |
|---|---|---|---|---|
| `pain.category` | 4.1.3 實驗動物疼痛等級評估 | radio(下拉) | **是** | 恆顯示；切換清空細項 |
| `pain.category_items` | 疼痛等級對應操作項目（複選） | checkbox | **是**(≥1) | category∈{B,C,D,E} 時依等級展開不同清單 |
| `pain.category_item_other_text` | 其他操作項目說明 | text | 否 | category_items 含任一 `*_other` |
| `pain.distress_signs` | 4.1.4 可能造成的疼痛或痛苦症狀（複選 17 項） | checkbox | **是**(≥1) | 恆顯示 |
| `pain.distress_signs_other_text` | 其他症狀說明 | text | 否 | distress_signs 含 `other` |
| `pain.relief_measures` | 4.1.5 緩解措施（複選 4 項） | checkbox | **是**(≥1) | 恆顯示 |
| `pain.relief_drug_name` | 止痛/麻醉藥品名稱 | checkbox群+input(join成字串) | **條件** | relief_measures 含 `anesthesia_analgesia` |
| `pain.no_relief_justification` | 不緩解的科學依據 | textarea(3列) | **條件** | relief_measures 含 `no_relief_with_justification` |

**疼痛等級**：`B`不引起疼痛不適 / `C`極小不適不需用藥 / `D`有疼痛須給藥緩解 / `E`對清醒未麻醉動物造成劇烈疼痛。各等級展開的操作項目清單（B 2項 / C 7項 / D 13項 / E 12項）詳見 i18n `aup.design.painCategoryItems.*`，每組末項 `*_other`。
**緩解措施選項**：`alternative_painless_procedure`改用無痛替代 / `anesthesia_analgesia`投予麻醉或止痛藥 / `humane_euthanasia`人道安樂死 / `no_relief_with_justification`不緩解但有科學依據
**藥品名稱可選**：麻醉藥(Atropine/Azeperonum/Zoletil-50/Isoflurane)、止痛藥(Ketorolac/meloxicam/ketoprofen) + 其他自由輸入

### 4.1.6 飲食/飲水限制 `design.restrictions`
| path | 標籤 | 型別 | 必填 | 條件顯示 | 選項 |
|---|---|---|---|---|---|
| `restrictions.is_restricted` | 4.1.6 是否限制飲食或飲水 | radio(三態) | UI標*(validation 僅 true 才往下查) | 恆顯示 | yes/no |
| `restrictions.restriction_type` | 限制類型 | radio(下拉) | **條件** | is_restricted=true | `fasting_before_anesthesia`麻醉前禁食 / `other`其他 |
| `restrictions.other_description` | 其他限制說明 | textarea(3列) | **條件** | restriction_type=other | — |

### 4.1.7 實驗終點 `design.endpoints`
| path | 標籤 | 型別 | 必填 |
|---|---|---|---|
| `endpoints.experimental_endpoint` | 實驗終點（預期結束時機） | textarea(3列) | **是** |
| `endpoints.humane_endpoint` | 人道終點（達何狀態提前安樂死） | textarea(4列) | **是**（空白時有「插入標準預設文字」按鈕） |

### 4.1.8 最終處置方式 `design.final_handling`
| path | 標籤 | 型別 | 必填 | 條件顯示 | 選項 |
|---|---|---|---|---|---|
| `final_handling.method` | 4.1.8 安樂死或最終處置方式 | radio(下拉) | UI標*，**validation 不擋** | 恆顯示 | `euthanasia`安樂死 / `transfer`轉讓 / `other`其他 |
| `final_handling.euthanasia_type` | 安樂死方式 | radio(下拉) | 否 | method=euthanasia | `kcl`KCl注射 / `electrocution`電擊 / `other`其他 |
| `final_handling.euthanasia_other_description` | 其他安樂死說明 | textarea(3列) | 否 | euthanasia_type=other | — |
| `final_handling.transfer.recipient_name` | 接受者姓名 | text | 否 | method=transfer | — |
| `final_handling.transfer.recipient_org` | 接受者單位 | text | 否 | method=transfer | — |
| `final_handling.transfer.project_name` | 計畫名稱 | text | 否 | method=transfer | — |
| `final_handling.other_description` | 其他處置說明 | textarea(3列) | 否 | method=other | — |

### 4.2 屍體處理
| path | 標籤 | 型別 | 必填 |
|---|---|---|---|
| `carcass_disposal.method` | 4.2 動物屍體處理方法 | textarea(4列) | UI標*，**validation 不擋** |

### 4.3 非藥用等級物質 `design.non_pharma_grade`
| path | 標籤 | 型別 | 必填 | 條件顯示 |
|---|---|---|---|---|
| `non_pharma_grade.used` | 4.3 是否使用學術研究用化學藥品或非醫藥級物質 | radio(三態) | 是(UI標*) | 恆顯示 |
| `non_pharma_grade.description` | 物質性質、安全性及科學理由 | textarea(4列) | **條件** | used=true |

### 4.4 危害性物質 `design.hazards`（多選互斥分組）
| path | 標籤 | 型別 | 必填 | 條件顯示 |
|---|---|---|---|---|
| `hazards.used` | 4.4 是否使用危害性物質材料 | radio(三態) | 是 | 恆顯示 |
| （類型開關） | 危害性物質類型（可複選 3 種） | checkbox | ≥1 種 | used=true |
| `hazards.materials[]` | 危害物清單（repeater，依類型分組） | repeater | ≥1 筆有效 | used=true |
| `hazards.operation_location_method` | 4.5.1 施用方法、途徑與使用場所 | textarea(4列) | **條件** | used=true |
| `hazards.protection_measures` | 4.5.2 保護措施 | textarea(4列) | **條件** | used=true |
| `hazards.waste_and_carcass_disposal` | 4.5.3 實驗廢棄物與屍體處理方式 | textarea(4列) | **條件** | used=true |

**類型選項**：`biological`生物性材料 / `radioactive`放射性 / `chemical`危險性化學藥品
**materials[] 子欄位**：`type`(由分組決定) / `agent_name`名稱(必填) / `amount`所需用量(必填) / `photos`佐證資料(file)。整體驗證：used=true 時至少 1 筆 type 合法+agent_name 有值。
> ⚠️ 型別內 `hazards.selected_type`(註解標互斥) 與 `waste_disposal_method` 兩欄位**已被現行 multi-select 實作取代，UI 不讀寫**。實際可同時勾三類。

### 4.5/4.6 管制藥品 `design.controlled_substances`（編號隨 hazards.used 動態：used=true→4.6 / false→4.5）
| path | 標籤 | 型別 | 必填 | 條件顯示 |
|---|---|---|---|---|
| `controlled_substances.used` | 是否使用管制藥品 | radio(三態) | 是 | hazards.used 非 null 時才整段渲染 |
| `controlled_substances.items[]` | 管制藥品清單（repeater） | repeater | ≥1 筆 | used=true |

**items[] 子欄位**（皆必填，photos 除外）：`drug_name`藥品名稱 / `approval_no`核准編號 / `amount`所需用量 / `authorized_person`管制藥品管理人 / `photos`佐證資料(file)。

> **Section 4 三態欄位**：`anesthesia.is_under_anesthesia`、`restrictions.is_restricted`、`non_pharma_grade.used`、`hazards.used`、`controlled_substances.used`。
> **UI 標 `*` 但 validation 不擋**：`final_handling.method`、`carcass_disposal.method`。
> **型別存在但 UI 未渲染**：`anesthesia.plan_type/premed_option/custom_text`、`route_justifications/blood_withdrawals/imaging/restraint`、`restrictions.types/other_text`、`final_handling.other_text`、`carcass_disposal.vendor_name/vendor_id`。

---

## Section 5 — 相關規範及參考文獻

> i18n：`aup.section5` =「5. 相關規範及參考文獻」。元件 `SectionGuidelines.tsx`。path 屬 `guidelines.*`。
> ⚠️ **整個 Section 5 無送出驗證**（即使 5.1 畫面標 `*`，送出不擋）。

### 5.1 法源依據
| path | 標籤 | 型別 | 必填 |
|---|---|---|---|
| `guidelines.content` | 5.1 法源依據(指南/標準)及參考文獻 | textarea(5列) | UI標*，**不擋** |

### 5.2 資料庫搜尋紀錄 `guidelines.databases`（固定 A~L 勾選清單，非可新增 repeater）
每筆：`code`(A~L) / `checked` / `keywords?`(A~E 用) / `note?`(K,L 用)。

| code | 名稱 | code | 名稱 |
|---|---|---|---|
| A | AGRICOLA 資料庫 | G | 動物福利資訊中心 |
| B | MEDLINE 資料庫 | H | 實驗動物福利文獻索編 |
| C | CAB Abstracts 資料庫 | I | 替代毒理方法基準資料 |
| D | TOXNET 資料庫 | J | 國際替代與動物使用會議資料 |
| E | BIOSIS 資料庫 | K | 與同儕直接聯繫（需記錄來源） |
| F | 實驗動物科學期刊/雜誌 | L | 其他 |

**條件子欄位**：A~E 勾選後出現「使用的關鍵字」(text)；K/L 勾選後出現「備註說明」(textarea 2列)。F~J 只有勾選框。

### 5.3 引用文獻 `guidelines.references[]`（repeater，可新增/刪除）
每筆：`citation`引用方式(text，作者(年份).標題.期刊…) / `url?`網址(選填)。無必填驗證。

---

## Section 6 — 手術計畫書

> i18n：`aup.section6` =「6. 手術計畫書」。元件 `SectionSurgery.tsx`。path 屬 `surgery.*`。

### ⚠️ 整段條件顯示（gating）
**只有當 Section 4 麻醉設定為手術時，整個 Section 6 才可編輯**，否則全欄位顯示 disabled「N/A」且所有 surgery 驗證 skip：
```
needsSurgeryPlan = anesthesia.is_under_anesthesia === true
  && (anesthesia_type === 'survival_surgery' || anesthesia_type === 'non_survival_surgery')
```
標頭有「載入預設值」按鈕（一鍵填入各段標準範本）。

| path | 標籤 | 型別 | 必填(needsSurgeryPlan 時) | 說明 |
|---|---|---|---|---|
| `surgery.surgery_type` | 6.1 手術種類 | text(**唯讀**) | 條件 | 值由 Section 4 推導：`survival`存活手術 / `non_survival`非存活手術 |
| `surgery.preop_preparation` | 6.2 術前準備 | textarea(8列) | **是** | 空或「略」擋送出 |
| `surgery.aseptic_techniques` | 6.3 無菌措施（複選 5 項） | checkbox | UI標*，**不擋** | 見下 |
| `surgery.surgery_description` | 6.4 手術內容說明 | textarea(5列) | **是** | 空或「略」擋 |
| `surgery.monitoring` | 6.5 術中監控 | textarea(5列) | **是** | 空擋（不檢查「略」） |
| `surgery.postop_expected_impact` | 6.6 存活手術預期術後影響 | textarea(4列) | **條件** | 僅 surgery_type=survival 時必填 |
| `surgery.multiple_surgeries.used` | 6.7 是否多次手術 | radio(是/否) | — | 選否自動 number=0,reason='' |
| `surgery.multiple_surgeries.reason` | 6.7 次數與原因 | textarea(3列) | **條件** | used=true 時顯示且必填 |
| `surgery.postop_care_type` | 6.8 手術類型 | radio(下拉) | **是** | `orthopedic`骨科 / `non_orthopedic`非骨科（選後自動帶入術後照護範本） |
| `surgery.postop_care` | 6.8 術後照護詳細內容 | textarea(15列) | **是** | 空擋 |
| `surgery.expected_end_point` | 6.9 實驗預期結束時機 | textarea(4列) | **是** | 空擋 |
| `surgery.drugs[]` | 6.10 手術用藥資訊（repeater 表格） | repeater | **是**(≥1筆) | 子欄位見下 |

**6.3 無菌措施選項**：`surgical_site_disinfection`動物術部消毒 / `instrument_disinfection`器械消毒 / `sterilized_gowns_gloves`無菌手術衣及手套 / `sterilized_drapes`無菌手術覆布 / `surgical_hand_disinfection`術者刷手
**6.10 drugs[] 子欄位**（每筆每欄皆必填）：`drug_name`藥品名稱 / `dose`劑量 / `route`投與途徑 / `frequency`頻率 / `purpose`給藥目的

> **型別存在但 UI 未實作**：`surgery.surgery_steps[]`（step_no/description/estimated_duration_min/key_risks）—完全未渲染、未驗證。

---

## Section 7 — 實驗動物資料

> i18n：`aup.section7` =「7. 實驗動物資料」。元件 `SectionAnimals.tsx`。path `working_content.animals.animals[]`。

### 容器
| path | 型別 | 必填 |
|---|---|---|
| `animals.animals[]` | repeater（清單，可新增「新增動物」） | **是**（至少 1 筆） |
| `animals.total_animals` | number | ⚠️ 型別存在但 **UI/validation 皆不讀寫**，無加總邏輯 |

### animals[] 單筆子欄位（型別 `ProtocolAnimalItem`）
| 子欄位 | 標籤 | 型別 | 必填 | 條件顯示 | 選項 / 驗證 |
|---|---|---|---|---|---|
| `species` | 物種 | radio/select | **是** | — | `pig`豬 / `other`其他 |
| `species_other` | 物種(其他) | text | **條件** | species=other | other 時必填 |
| `strain` | 品系 | select | **條件**(pig 時) | species=pig | `white_pig`白豬 / `mini_pig`迷你豬 |
| `strain_other` | 品系(其他) | text | **條件** | species=other | other 時必填 |
| `sex` | 性別 | radio/select | **是** | — | `male`公 / `female`母 / `unlimited`不限 |
| `number` | 數量 | number(≥1) | **是** | — | 須 >0；<0 自動歸 0 |
| `age_unlimited` | 年齡不限 | checkbox | 否 | — | 勾選後隱藏年齡輸入 |
| `age_min` | 最小年齡(月) | number(≥3) | **條件** | !age_unlimited | 須 ≥3，否則錯誤 |
| `age_max` | 最大年齡(月) | number | **條件** | !age_unlimited | 須 > age_min |
| `weight_unlimited` | 體重不限 | checkbox | 否 | — | 勾選後隱藏體重輸入 |
| `weight_min` | 最小體重(kg) | number(允許小數) | **條件** | !weight_unlimited | 豬<20kg 軟提醒(不擋)，送出前二次確認 |
| `weight_max` | 最大體重(kg) | number(允許小數) | **條件** | !weight_unlimited | 須 > weight_min |
| `housing_location` | 動物飼養場所 | text | 否 | — | 預設「豬博士畜牧場（可改）」 |

> **型別存在但 UI 未渲染**：`source_id`、`source_name`。

---

## Section 8 — 試驗人員資料

> i18n：`aup.section8` =「8. 試驗人員資料」。元件 `SectionPersonnel.tsx`(表格) + `AddPersonnelDialog.tsx`(新增) + `TrainingCertificates.tsx`(巢狀證書)。path `working_content.personnel[]`。
> ⚠️ **頁面層無必填驗證**；必填只在新增對話框 `validateNewPersonnel`（新增當下擋）。人員透過 Dialog 整筆新增，表格只顯示+刪除。

### personnel[] 單筆子欄位（型別 `ProtocolPerson`）
| 子欄位 | 標籤 | 型別 | 必填 | 條件顯示 | 選項 |
|---|---|---|---|---|---|
| `name` | 姓名 | text(IACUC staff 模式有下拉帶入) | **是** | — | — |
| `position` | 職稱 | text | 否 | — | 表格顯示固定「研究人員」 |
| `roles` | 工作內容（複選） | checkbox | **是**(≥1) | — | a~i 見下 |
| `roles_other_text` | 其他工作內容 | text | **條件** | roles 含 `i` | — |
| `years_experience` | 參與動物試驗年數 | number(≥1) | **是**(>0) | — | — |
| `trainings` | 訓練/資格（複選） | checkbox | **是**(≥1) | — | A~F 見下 |
| `trainings_other_text` | 其他訓練/資格 | text | **條件** | trainings 含 `F` | — |
| `training_certificates[]` | 訓練證書（巢狀 repeater） | repeater | 否 | 每個勾選且≠F 的訓練各一組 | 見下 |

**工作內容 roles 選項(a~i)**：a 計畫督導 / b 飼養照顧 / c 保定 / d 麻醉止痛 / e 手術 / f 手術支援 / g 觀察監測 / h 安樂死 / i 其他
**訓練/資格 trainings 選項(A~F)**：A 實驗動物照護及使用委員會/小組成員訓練班 / B IACUC教育訓練研討會 / C 輻射安全訓練班 / D 生醫產業用畜禽應用研習會 / E 實驗動物法規及照護管理班 / F 其他
**training_certificates[] 子欄位**：`training_code`(由所屬訓練決定) / `certificate_no`證書編號(text，可新增多筆，例「(112)動訓字第 001 號」)

> IACUC staff 模式：選 staff 自動帶入 name/position/years/roles=`[b,c,d,f,g,h]`/trainings/certs。

---

## Section 9 — 附件

> i18n：`aup.section9` =「9. 附件」。元件 `SectionAttachments.tsx`。path `working_content.attachments`。

| path | 標籤 | 型別 | 必填 | 規則 |
|---|---|---|---|---|
| `attachments` | 附件（PDF） | file(多檔) | 否(無驗證) | 僅 PDF；單檔 ≤20MB；最多 10 檔 |

---

## Section 10 — 電子簽名

> i18n：`aup.section10` =「10. 電子簽名」。元件 `SectionSignature.tsx`。
> ⚠️ **整段無必填驗證**。兩種模式切換（local state，不互斥儲存）：

### 模式 A — 上傳簽名檔
| path | 標籤 | 型別 | 規則 |
|---|---|---|---|
| `working_content.signature` | 簽名檔 | file/signature(多檔) | 圖片格式；單檔 ≤5MB；最多 5 檔 |

### 模式 B — 手寫簽名
| path | 標籤 | 型別 | 說明 |
|---|---|---|---|
| `working_content.handwriting_svg` | 手寫簽名 | signature(SVG string) | 簽名板寫入；有值顯示「已簽署 ✓」 |
| `working_content.stroke_data` | （隨手寫板） | object[] | 與 handwriting_svg 成對寫入/清除 |

---

## 附錄 A — 全表單真正擋送出的必填欄位彙整

> cowork 若要做「必填檢核」，以下是 `validation.ts` 實際阻擋送出的清單（Section 5/8/9/10 頁面層不擋；8 在新增對話框擋）。

- **S1**：研究名稱、起訖日期(結束>開始)、PI 姓名/email/電話/地址、計畫類型(≥1)、計畫種類(≥1)、計畫種類其他(條件)、委託單位名稱/聯絡人/電話/信箱、機構名稱、位置
- **S2**：2.1 重要性、2.2.1 必要性、2.2.2 平台(≥1)/關鍵字/結論、2.2.3 狀態(+條件子欄)、2.3 設計、2.4 精緻化
- **S3**：use_test_item(必選)、若 true 則各 test_item 的 name/form/purpose/storage/(非無菌說明)、各 control_item 的 name/purpose/storage/(非無菌說明)
- **S4**：is_under_anesthesia、(條件)麻醉類型/其他、procedures、pain.category/category_items/distress_signs/relief_measures(+條件藥名/依據)、(條件)限制類型/其他、experimental_endpoint、humane_endpoint、(條件)non_pharma 說明、(條件)hazards materials/4.5 三欄、(條件)管制藥品 items
- **S6**（僅 needsSurgeryPlan 時）：surgery_type、preop_preparation、surgery_description、monitoring、(條件)postop_expected_impact、(條件)multiple reason、postop_care_type、postop_care、expected_end_point、drugs(≥1 筆且每欄)
- **S7**：至少 1 隻動物，每隻 species/(species_other)/(strain pig時)/(strain_other other時)/sex/number(>0)/(年齡 min≥3,max>min)/(體重 min,max>min)
- **S8**（新增對話框）：name、roles(≥1,+i其他)、years(>0)、trainings(≥1,+F其他)

## 附錄 B — 給 cowork 的實作提示

1. **依序引導**：建議照 Section 1→10 順序逐段引導填寫；Section 6 是否啟用取決於 S4 麻醉類型。
2. **三態欄位**：是/否/未選三態，選「否」要清空其下展開欄位。
3. **條件顯示是核心**：很多欄位（其他說明、品系、年齡/體重區間）只在特定前置選擇後出現，務必照「條件顯示」欄實作分支。
4. **repeater 欄位**：S3 試驗/對照物質、S4 危害物/管制藥品、S5 文獻、S6 用藥、S7 動物、S8 人員(+巢狀證書) 都是可新增多筆。
5. **跨段連動**：S4 麻醉類型 → S6 必填；hazards.used → 管制藥品段編號 4.5/4.6。
6. **必填以附錄 A 為準**，畫面 `*` 不等於真正擋送出。

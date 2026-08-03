# AUP 計畫書「表單 ↔ 列印 PDF」全表歧異稽核

> 日期：2026-06-09　範圍：`aup_protocol`（動物試驗研究計畫書 R32 / GLP AD-04-01-01F）
> 方法：4 路平行稽核，雙向比對前端表單 / 列印 adapter / 列印 template / schema 四層。
> 用途：使用者逐項裁決「保留表單版 or 列印版」。內容遺失類預設以**表單為準**修正；標籤/序號類需裁定。

涉及檔案：
- 前端表單 `frontend/src/pages/protocols/protocol-edit/`、型別 `frontend/src/types/{aup,protocol}.ts`、標籤 `frontend/src/locales/zh-TW.json`
- 列印 `services/print-pdf/templates/aup_protocol.html`、`adapters/aup_protocol.py`、`schemas/aup_protocol.py`

---

## 已預先修正（本 session，待併入此批；尚未 rebuild 部署）

| 項次 | 修正 | 檔:行 |
|---|---|---|
| 4.1.2 | 列印改印使用者填的 `design.procedures`（原本誤印 §3.1 試驗物質清單） | template:680 / adapter:543 / schema:95 |
| 4.1.3 D | 標籤「亞致死劑量化學品」→「投予非致死劑量之藥物或化學品」 | template:720 |
| §3 | 試驗/對照物質明細表「未輸入即不顯示」（依 `test_article.name`/`control_article.name` 各自判斷） | template:639,653 |

---

## A 類｜內容遺失或接錯（使用者填了，PDF 印錯/空白）— 建議全修，以表單為準

| # | 章節 | 欄位 | 表單(計劃書) | 列印(PDF) | 類型 | 證據 |
|---|---|---|---|---|---|---|
| A1 | §1 | 經費來源 6 項 | 存 `moa/mohw/nstc/moe/env/other` | adapter 比對 `1_moa/...5_environment/6_other` → **全不 match，財源欄全空白** | 來源接錯 | adapter:301-307；#608 parity 漏鎖 funding |
| A2 | §4.1.1 | 麻醉「5.其他」+ 說明 | 可選「其他」並填麻醉方式 | template 無「其他」列、adapter 未 map → 選其他時**五框全空、說明消失** | 漏印 | template:674-678；adapter:336-342 |
| A3 | §3.1.2/3 | 多筆試驗/對照物質 | 可新增多筆 | 只印第一筆，第 2 筆起全漏 | 多筆漏印 | adapter:313-314；template:639-665 |
| A4 | §3.1.2 | 劑型 `form`（必填） | 有劑型輸入 | 明細表不印劑型 | 漏印 | template:641-650 |
| A5 | §3.1.2/3 | 非無菌說明 | 選「否」必填說明 | 只印是/否，不印說明 | 漏印 | template:644-661 |
| A6 | §4.1.3 E | `e_non_avma_euthanasia` 未經 AVMA 安樂死 | 可勾選 | schema/map/template 三層全缺 → **勾了靜默消失** | 漏印 | PainCategorySection.tsx:31 |
| A7 | §6.1 | 手術種類（存活/非存活） | 存 `surgery.surgery_type` | adapter 從不建構 `surgery_type` → 兩框恆空 | 恆空 | template:907-910 |
| A8 | §6.3 | 無菌措施 5 項 | 存 `aseptic_techniques[]` | adapter 從不建構 `aseptic` → 5 框恆空；另 key 拼錯 `sterile_*` vs `sterilized_*` | 恆空+代碼錯 | template:915-922；schema:364-365 |
| A9 | §6.10 | 手術用藥「藥品名稱」 | 存 `drug_name` | adapter 讀 `name`（key 不符）→ 藥名空白、劑量途徑卻有值 | 來源接錯 | adapter:474（controlled 路徑:403 已修，獨漏此處） |
| A10 | §6.7 | 多次手術次數 | 存 `multiple_surgeries.number` | 只印 yes/no+reason，次數漏 | 漏印 | template:933-939 |
| A11 | §6.8 | 術後照護分類（骨科/非骨科） | 存 `postop_care_type` | 只印自由文字，分類漏 | 漏印 | template:941-942 |
| A12 | §5.2 | 資料庫搜尋清單+關鍵字 | A–L 平台勾選+關鍵字 | PDF §5 只印 `references` 自由文字，整段漏 | 漏印 | adapter:553；template:899-901 |
| A13 | §5.3 | 引用文獻列表（citation+URL，多筆） | 可新增多筆文獻 | 完全未印 | 多筆漏印 | SectionGuidelines.tsx:113-166 |
| A14 | §2.2.2 | 已檢索資料庫 | 中文平台名 | 印成代碼 `altbib、taat` | 來源接錯 | template:592 |
| A15 | §2.2.2 | 其他資料庫說明 `other_name` | 勾其他後填名稱 | adapter 完全沒讀 | 漏印 | adapter:484-505 |
| A16 | §2.3.2 | 單獨飼養原因 `reasons[]` | 複選 9 項原因 | 整批丟棄 | 漏印 | adapter:520-527 |
| A17 | §7 | 動物別/品系 | species=other+`species_other`+`strain` | 硬寫「☑豬/{strain}」；other 印成「☑豬/」空品系，other 文字丟 | 來源接錯 | adapter:421-435 |
| A18 | §1 | PI 分機 `phone_ext` | 有分機輸入 | 只送 phone，分機丟 | 漏印 | adapter:582 |
| A19 | §1 | 委託單位聯絡人分機 | 型別有 ext | 只送 contact_phone | 漏印 | adapter:587 |
| A20 | §1 | 試驗起始日 `start_date` | 收起迄兩日期 | 只印「自核准日至 valid_to」，start_date 不印 | 漏印 | template:489-491 |
| A21 | §10 | 簽名（上傳/手寫） | 收 signature 圖片+手寫 SVG | PDF 無 §10；封面只印空白簽名線，簽名從未嵌入 | 漏印 | SectionSignature.tsx:69-108 |

---

## B 類｜表單沒收集、但 PDF 有此欄 → 恆空（裁定：PDF 移除該欄 or 表單補輸入欄）

| # | 章節 | 欄位 | 現況 | 證據 |
|---|---|---|---|---|
| B1 | §1 | SD 專案主持人 name/email | 表單無此輸入欄，PDF 印整列恆空 | template:510-519 |
| B2 | §1 | PI 職稱 position | 表單 PI 段無職稱欄，PDF 印「職稱」格恆空 | template:502 |
| B3 | §3.1.2/3 | 效期 expiry | 表單無效期輸入，PDF 印「效期」列恆空（—） | template:643,657 |
| B4 | §7 | 動物來源 source_name | 表單無來源欄，PDF 印「來源」恆空 | template:985 |

---

## C 類｜標籤措辭：PDF 縮寫 vs 表單完整法規措辭（裁定政策）

> 4.1.3 疼痛等級與 4.1.5 痛苦徵象的子項，PDF 普遍把表單的完整法規措辭壓成 2–6 字簡稱。
> 對 IACUC 送審：列印版與委員在系統看到的逐字措辭不一致 = 稽核瑕疵。但完整措辭較長、影響 PDF 排版。

代表性對照（完整清單見各 agent 報告，4.1.3 約 20 筆、4.1.5 約 11 筆）：

| 章節 | 表單完整措辭 | PDF 縮寫 |
|---|---|---|
| 4.1.3 D | 任何流程導致明顯的疼痛或不適，但可施以止痛藥…（減少食慾/活動、開放性皮膚病變、膿腫、跛行、結膜炎…） | 疼痛施以止痛 |
| 4.1.3 D | 誘導解剖學或生理學異常造成的疼痛或緊迫輻射性病痛 | 誘發病理變化 |
| 4.1.3 D | 藥物或化學物損害動物體的生理系統 | 化學損傷 |
| 4.1.3 E | 使用藥物或化學物嚴重損害動物生理系統而造成死亡、劇烈疼痛或極度緊迫 | 化學物質嚴重損傷 |
| 4.1.3 E | 實驗操作可能會導致動物死亡 | 致死性處置 |
| 4.1.5 | 脫水／皮膚無彈性／眼眶下陷 | 脫水 |
| 4.1.5 | 毛髮蓬亂、打結或失去光澤 | 毛髮凌亂 |
| §1 | 資金來源 | 經費來源 |
| §3.1.2 | 無菌（製備） | 滅菌（產品） |
| §5.1 | 法源依據 / 資料庫搜尋 / 引用文獻（三塊） | 全塞進「請說明法源依據…及參考文獻」一格 |
| §8 訓練 | A=實驗動物照護及使用委員會…訓練班；缺 F=其他 | A=IACUC 訓練班；無 F |

---

## D 類｜章節序號錯置（裁定：以官方 AD-04-01-01F 為準）

| 項目 | 表單編號 | PDF 編號 |
|---|---|---|
| 限食限水 | 4.1.6 | 4.1.4 |
| 痛苦徵象 | 4.1.4 | 4.1.5 |
| 緩解措施 | 4.1.5 | 4.1.6 |

---

## E 類｜設計缺漏（填了但 template 完全無對應欄位）

| 項目 | 說明 |
|---|---|
| §1 GLP 註冊權責機關 registration_authorities | 表單可填，adapter/template 無輸出（GLP 模式才顯示） |

---

## 統計

- A 類（內容遺失/接錯）：**21 筆** — 建議全修，以表單為準
- B 類（恆空欄）：**4 筆** — 裁定 PDF 移除 or 表單補欄
- C 類（標籤措辭）：**~33 筆** — 政策決定（全改完整/逐項指定/維持縮寫）
- D 類（序號錯置）：**3 項** — 需官方表單裁定
- E 類（設計缺漏）：**1 筆**

**最高風險**：A1 經費來源全空、A2 麻醉「其他」整題消失、A6 未經 AVMA 安樂死勾選消失、A12/A13 §5 參考文獻整段漏印、A21 簽名從未嵌入 —— 皆為 IACUC 送審文件的實質內容遺失。

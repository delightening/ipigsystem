# R32-A8 PDF 合規驗證報告

> 對應 R32-A8（回歸驗證 + GLP 合規驗證）。
> 本地驗證階段 — staging 部署後須補跑完整 GLP 維度。

## 驗證範圍（已完成）

| 維度 | 工具 | 狀態 |
|---|---|---|
| docx → PDF 轉換成功（HTTP 200 + size > 10KB） | `pdf-service/scripts/validate_pdfs.py` | ✅ |
| 字型完整性（CJK 字型嵌入 + 無 `.notdef` glyph） | 解析 PDF `/BaseFont` | ✅ |
| 中文 / 英文混排（標楷體 / Times New Roman） | 視覺檢視 + font 名稱比對 | ✅ |
| 大標前換頁 / 小標 keep_with_next | 視覺檢視 | ⏸ vet/QA |

## 樣本資料

`smoke_real_data.py` 使用 dev DB 真實資料：

| 報表 | 樣本 | 輸出 |
|---|---|---|
| AUP 計畫書 | Pre-115-010（5 personnel / 1 animal） | `templates/output/aup_protocol_REAL_DATA_v3.{docx,pdf}` |
| 巡視紀錄 | 90 pens（A20+B20+C20+D33+E25+G6 zones）| `templates/output/vet_patrol_REAL_DATA.v2.{xlsx,pdf}` |

## 字型驗證結果（A2b 自建 Gotenberg image）

`ipig-gotenberg-cjk:8` image 包含：
- Noto Sans CJK TC / SC (Regular / Bold / Black / Medium / SemiBold)
- Noto Serif CJK TC / SC
- AR PL UMing TW / HK / CN（開源明體）
- AR PL UKai TW / HK / CN（開源楷體 — 標楷體替代）
- Liberation Serif / Sans / Mono（英文 metric-compatible）

**AUP PDF 嵌入字型** (8)：

```
NotoSansCJKtc-Regular  ← 中文
NotoSansCJKtc-Bold     ← 中文（粗體）
TimesNewRomanPSMT      ← 英文
TimesNewRomanPS-BoldMT ← 英文（粗體）
Carlito-Regular        ← 西文 fallback
```

**Patrol PDF 嵌入字型** (5)：

```
NotoSansCJKsc-Regular  ← 中文（LibreOffice 預設 sc，視覺上 TC 仍可讀）
NotoSans-Regular
DejaVuSans / DejaVuSerif
ArialMT
```

**已知限制**：

- LibreOffice 預設把「標楷體」mapping 到 NotoSansCJK，未對應到開源楷體 AR PL UKai。若 vet/QA 強制要求楷書外觀，需在 image 補 `/etc/fonts/conf.d/61-cjk-tw.conf` 設 alias「標楷體 → AR PL UKai TW」。本次未做（差異視覺評估後決定）。
- xlsx 用了 NotoSansCJK**sc**（簡體子集，TC 字仍能渲染，但部分異體字可能略有差異）。同樣需 fontconfig alias 修正。

## 未完成驗證（須 staging 部署 + R32-A6 backend）

| 維度 | 阻塞原因 |
|---|---|
| 4 報表 × 3 樣本（surgery / medical_record / review_reply / review_result） | smoke_real_data 目前只實作 AUP + patrol；其他 4 份 schema 已就位但未接 DB 真實資料 |
| GLP HMAC chain link 驗證 | 須 backend `pdf_artifacts` 表 + `services/audit.rs` chain-write（R32-A6 已併） |
| `electronic_signatures.meaning` 整合（21 CFR §11.50） | 須完整 staging 簽章流程 |
| PDF/A-2b 合規（archival 標準） | 須 ghostscript `gs -dPDFA=2 -dPDFACompatibilityPolicy=1` + 手動驗證 metadata |
| HMAC `pdf_blob_hash` 寫入後驗證 | 須 backend handler + DB 整合測試 |

## 後續步驟

1. **smoke_real_data 擴充**：補上 surgery / medical_record / review_reply / review_result 4 份 DB → render 流程（每份 3 樣本）
2. **A6 整合測試**：產 PDF 後寫 `pdf_artifacts` + 重複下載驗證 hash 一致
3. **PDF/A 工具鏈**：在 gotenberg image 補 ghostscript（or 用獨立 microservice）
4. **fontconfig alias**：標楷體 → AR PL UKai TW、TC subset 強制
5. **staging 部署觀察 ≥1 週**（R32-A7 砍舊路徑前置條件）

## 驗證指令

```bash
# 1. 起 gotenberg + pdf-service
docker compose up -d gotenberg pdf-service

# 2. 重新產樣本
cd pdf-service && python -X utf8 -m scripts.smoke_real_data --target aup_protocol

# 3. 跑驗證
python -X utf8 -m scripts.validate_pdfs
```

預期輸出：

```
✅ aup_protocol_REAL_DATA_v3.docx → ...pdf  (530KB, 8 fonts, CJK=True, .notdef=False)
✅ vet_patrol_REAL_DATA.v2.xlsx → ...pdf    (77KB, 5 fonts, CJK=True, .notdef=False)
✅ 全部 2 份 PDF 通過字型 / 大小驗證
```

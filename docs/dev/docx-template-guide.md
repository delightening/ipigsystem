# docx 模板開發指南（R32 v3 後）

> 本文件給需要**新增 / 修改 PDF 報表模板**的工程師 / vet / QA。對應 R32-A1~A2 實作（已 merge）。

---

## TL;DR

PDF 報表來源 = `templates/*.docx`（Word 檔含變數）+ `pdf-service/app/schemas/*.py`（Pydantic）。流程：

```text
React detail page                Backend Rust          pdf-service (Python)        Gotenberg (LibreOffice)
   "下載 PDF"  →  資料蒐集  →  POST /render-docx →  docxtpl fill .docx       →  /forms/libreoffice/convert
                                  ?format=pdf      →  返回 docx bytes        →  返回 pdf bytes
                                                                                       │
                                  ←─────────── PDF binary ────────────────────────────┘
```

要新增一份報表 = 4 個動作：
1. 在 `templates/<name>.docx` 放 Word 範本（內含 docxtpl 變數）
2. 在 `pdf-service/app/schemas/<name>.py` 寫 Pydantic schema
3. 在 `pdf-service/app/doc_types.py::DOCX_REGISTRY` 註冊
4. 在 `backend/src/services/pdf_v3/` 寫 endpoint handler 蒐集資料 + call `PdfServiceClient::render_docx`

---

## docxtpl 變數語法（給 vet / QA）

模板用 [docxtpl](https://docxtpl.readthedocs.io/) 提供的 Jinja-like 語法。在 Word 裡直接打字即可（**不是** Word field code）。

### 簡單變數

```jinja2
動物編號：{{ animal.iacuc_no }}
耳號：{{ animal.ear_tag }}
日期：{{ report_date }}
```

⚠️ **重要**：在 Word 裡輸入 `{{ x }}` 時，**整個 placeholder 必須在同一個 character run 內**（同字型、同顏色、同粗體狀態）。Word 會偷偷把 `{{` 和 `}}` 拆成不同 run，docxtpl 就找不到。**訣竅：先打 `xx`，全選改字型/顏色，再把 `xx` 改成 `{{ var }}`** — 這樣整段在同一個 run。

### 表格 Loop（疫苗紀錄、體重觀察等動態行數）

在 Word 表格裡，把要重複的整列複製，加上 `{%tr ... %}` 起訖標記：

```jinja2
| 日期            | 體重 (kg) | 備註           |
|----------------|-----------|----------------|
| {%tr for w in weights %} |||
| {{ w.date }}   | {{ w.kg }}| {{ w.note }}   |
| {%tr endfor %} |||
```

### 條件區段

```jinja2
{%p if animal.is_pregnant %}
  ⚠️ 此動物懷孕中，操作前請與獸醫確認
{%p endif %}
```

### 完整範例

見 [docxtpl 官方文件](https://docxtpl.readthedocs.io/en/latest/#) 或既有 `templates/` 範本。

---

## Pydantic Schema 對應規則

每份 `.docx` 對應一個 Pydantic schema，定義變數的型別 + 驗證規則：

```python
# pdf-service/app/schemas/medical_record.py
from datetime import date
from pydantic import BaseModel, Field

class WeightEntry(BaseModel):
    date: date
    kg: float = Field(..., ge=0.1, le=500.0)
    note: str = Field("", max_length=200)

class MedicalRecordPayload(BaseModel):
    animal: AnimalInfo
    weights: list[WeightEntry] = Field(..., min_length=1)
    report_date: date
```

**命名規則**：
- 檔名 `snake_case.py`（與 doc_type 對齊）
- Class 名 `PascalCase` + `Payload` / `Entry` 後綴
- 欄位 `snake_case`，與模板 `{{ var }}` 對齊

**驗證規則**（per CodeRabbit PR #315 review）：
- 別只寫 description，要實際 `Field(..., pattern=..., min_length=..., ge=..., le=...)`
- 必填欄位用 `Field(...)`，可選用 `Field(None)` 或 `Field("")`
- 數字範圍要寫 `ge` / `le`（避免無效資料進模板）

---

## 註冊到 DOCX_REGISTRY

```python
# pdf-service/app/doc_types.py
from .schemas.medical_record import MedicalRecordPayload

def _medical_record_filename(payload: BaseModel, ext: str) -> str:
    if not isinstance(payload, MedicalRecordPayload):
        raise TypeError(f"Expected MedicalRecordPayload, got {type(payload).__name__}")
    return f"medical_record_{payload.animal.iacuc_no}_{payload.animal.ear_tag}.{ext}"

DOCX_REGISTRY = {
    # ... 既有
    "medical_record": DocxDocType(
        template="medical_record.docx",
        schema_cls=MedicalRecordPayload,
        filename_fn=_medical_record_filename,
    ),
}
```

---

## Backend Rust handler

```rust
// backend/src/handlers/pdf_v3/medical_record.rs
pub async fn export_medical_record_pdf(
    State(state): State<AppState>,
    Extension(current_user): Extension<CurrentUser>,
    Path(animal_id): Path<Uuid>,
) -> Result<impl IntoResponse> {
    require_permission!(current_user, "animal.medical.view");
    SignatureService::check_animal_record_access_uuid(
        &state.db, "animal_medical", animal_id, &current_user,
    ).await?;

    // 蒐集資料 — 從各 service 拉
    let payload = MedicalRecordPayload {
        animal: animal_service::get_info(&state.db, animal_id).await?,
        weights: animal_weight_service::list(&state.db, animal_id).await?,
        report_date: chrono::Utc::now().date_naive(),
    };

    // call pdf-service
    let pdf_bytes = state.pdf_service_client
        .render_docx("medical_record", &payload, DocxRenderFormat::Pdf)
        .await?;

    // R32-A6 寫存證
    let mut tx = state.db.begin().await?;
    let hash = pdf_artifact::compute_pdf_hash(&pdf_bytes);
    pdf_artifact::insert_artifact_tx(&mut tx, CreatePdfArtifact {
        resource_type: "animal_medical",
        resource_id: &animal_id.to_string(),
        pdf_blob_hash: &hash,
        pdf_size_bytes: pdf_bytes.len() as i64,
        doc_type: "medical_record",
        generated_by: current_user.id,
        // ... 其他
    }).await?;
    tx.commit().await?;

    Ok((
        StatusCode::OK,
        [(header::CONTENT_TYPE, "application/pdf")],
        pdf_bytes,
    ))
}
```

---

## 中文字型問題（R32-A2b，已過時）

> ⚠️ **過時（2026-05-30）**：本節原描述 Gotenberg image 的中日韓字型設定（`services/gotenberg-zh/`）。
> Gotenberg 與 word-convert daemon 均已下線，現行唯一 PDF 服務為 `services/print-pdf/`
> （FastAPI + WeasyPrint）。CJK 字型由 print-pdf 自帶處理，沿用 **Noto Sans CJK TC**。
> 字型設定請見 `services/print-pdf/`。

---

## 開發測試

```bash
# 本地開 pdf-service
cd pdf-service
pip install -r requirements.txt
PDF_SERVICE_TOKEN=dev-token uvicorn app.main:app --reload --port 3200

# 測試 docx 路徑
curl -X POST 'http://localhost:3200/render-docx/medical_record?format=docx' \
  -H "X-Internal-Token: dev-token" \
  -H "Content-Type: application/json" \
  -d @test_payload.json --output out.docx

# 測試 PDF 路徑（需 Gotenberg 在跑）
docker compose up -d gotenberg
curl -X POST 'http://localhost:3200/render-docx/medical_record?format=pdf' \
  -H "X-Internal-Token: dev-token" \
  -H "Content-Type: application/json" \
  -d @test_payload.json --output out.pdf
```

---

## 相關文件

- 使用者操作：[`docs/USER_GUIDE.md`](../USER_GUIDE.md) PDF 匯出章節
- v3 架構決策：[`qa/r32-pdf-baseline.md` §9](../qa/r32-pdf-baseline.md)
- pdf-service README：[`pdf-service/README.md`](../../pdf-service/README.md)
- docxtpl 官方：<https://docxtpl.readthedocs.io/>
- GLP §11.50 (signature meanings) + §11.10(c) (record integrity) 對齊：[`docs/security/HMAC_VERSIONING.md`](security/HMAC_VERSIONING.md)

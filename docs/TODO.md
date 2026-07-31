# 豬博士 iPig 系統 - 待辦功能清單

> **最後更新：** 2026-07-10 (文件封存重整：全完成輪次移至 `docs/archive/TODO_done.md`)
> **維護慣例：** 完成項目標 [x] + 更新待辦統計 + 在 `docs/PROGRESS.md` §9 新增變更紀錄。詳見 `CLAUDE.md`「文件記錄規則」。
> **封存規則：** 整輪全部 [x]（0 未完成）的輪次移至 `docs/archive/TODO_done.md`；本檔只保留「含未完成項的輪次」+ 待辦統計。詳見 `docs/agents/DOCS_PROTOCOL.md`。
> **章節排列：** 禁止事項 → 含未完成項的輪次（R 編號不連續，已封存者見 archive）→ 待辦統計
> ⚠️ **PR 編號（2026-08-03 起）：** 本檔既有的 `#N` 引用（393 個相異編號、897 次提及）一律指**舊 repo** `delightening/ipig_system`——該 repo 已於 2026-08-03 轉為 private 封存（原因：git 歷史含 prod DB 匯出檔，見 R83-6）。本 repo `delightening/ipigsystem` 的 PR 編號自 #1 重新起算，兩者**不通用且會撞號**。引用新 PR 時請寫成 `#N`，引用舊 repo 請寫成 `ipig_system#N`。

---

## ⛔ 禁止事項

1. 密碼過期策略
2. 密碼歷史紀錄（SEC-38：密碼歷史紀錄）

---

## 🤖 R20 — AI 預審與執行秘書標註（2026-03-29）

> 來源：`docs/AIReview.md` + `docs/clientsAccess.md` §4。雙角色 AI 審查：客戶端預審 + 執行秘書標註。

### Phase 1：規則式檢查

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R20-1 | **Backend 驗證規則擴展** | `services/protocol/validation.rs` — 字數門檻、日期邏輯、3Rs 完整性、疼痛分類 vs 麻醉一致性 | [x] |
| R20-2 | **驗證 API endpoint** | `POST /api/protocols/{id}/validate` — Level 1 規則檢查 | [x] |
| R20-3 | **前端提交前驗證 UI** | 提交時觸發驗證 + 報告面板（必須修正/建議改善） | [x] |

### Phase 2：Claude API 整合

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R20-4 | **protocol_ai_reviews migration** | 儲存 AI 預審結果，含 `review_type`（client_pre_submit / staff_pre_review） | [x] |
| R20-5 | **AI 預審 service** | 擴展 `services/ai/` — system prompt、計劃書序列化、回應解析、快取、成本控制 | [x] |
| R20-6 | **客戶端 AI 預審** | `POST /api/protocols/{id}/ai-review` + 前端 AI 預審按鈕 + 結果面板 | [x] |
| R20-7 | **執行秘書 AI 標註** | `POST /api/protocols/{id}/staff-review-assist` + Pre-Review 頁面頂部標註面板（🚩⚠️ℹ️ 三類） | [x] |
| R20-8 | **Pre-Review 自動觸發** | Status 變更為 Pre_Review 時自動呼叫 AI 標註 | [x] |

### Phase 3：調校與優化

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R20-9 | **System prompt 調校** | 收集真實審查意見，對比 AI 預審結果，調整 prompt 提高準確率。**2026-04-12 階段一已完成**：基於 45 封真實 IACUC 信件分析，CLIENT/STAFF 兩個 system prompt 已套用 5 類補丁（交叉引用稽核、人道終點量化、對照組處置、3R 教學挑戰、文書 pre-filter）。完整報告見 `docs/R20_real_review_patterns.md`。**剩餘**：Gmail Takeout data pipeline、Evonne 標 50 筆 ground truth、`backend/tests/ai_review_eval.rs` eval harness、Recall ≥ 0.7 / Precision ≥ 0.6 baseline | 🔶 |
| R20-10 | **退回率追蹤** | 追蹤 Pre-Review 退回次數是否下降 | [ ] |

### R20 詳細實作計畫

<details>
<summary>R20-1：Backend 驗證規則擴展（Level 1 規則引擎）</summary>

**新增檔案**：`backend/src/services/protocol/validation.rs`

**規則引擎設計**：

```rust
pub struct ValidationResult {
    pub passed: Vec<ValidationCheck>,
    pub errors: Vec<ValidationIssue>,    // 必須修正
    pub warnings: Vec<ValidationIssue>,  // 建議改善
}

pub struct ValidationIssue {
    pub code: String,           // e.g. "3RS_REDUCTION_MISSING"
    pub category: String,       // e.g. "3Rs", "animals", "design"
    pub section: String,        // e.g. "purpose", "animals", "design"
    pub message: String,        // 人類可讀訊息
    pub suggestion: String,     // 建議修正方式
}

pub fn validate_protocol(working_content: &serde_json::Value) -> ValidationResult
```

**驗證規則清單**（從 `working_content` JSON 解析）：

| 規則 | 類型 | 欄位 | 條件 |
|------|------|------|------|
| 研究目的字數 | error | `purpose.significance` | ≥ 100 字，「略」「同上」視為無效 |
| Replacement 說明 | error | `purpose.replacement` | ≥ 50 字，必須說明為何不能用替代方法 |
| Reduction 說明 | error | `purpose.reduction` | ≥ 50 字，必須提及統計方法或文獻支持 |
| Refinement 說明 | error | `purpose.refinement` | ≥ 50 字，必須提及痛苦最小化措施 |
| 日期邏輯 | error | `basic.start_date`, `end_date` | end > start，期限 ≤ 3 年 |
| 動物數量 | error | `animals.total_count` | > 0 且與分組合計一致 |
| 疼痛分類 vs 麻醉 | warning | `design.pain_category`, `design.anesthesia` | C/D/E 類必須有麻醉方案 |
| 人員訓練證照 | warning | `personnel[].training` | 所有人員應有證照編號 |
| 替代方案搜尋平台 | warning | `purpose.alternative_databases` | ≥ 2 個平台 |
| 人道終點具體性 | warning | `design.humane_endpoint` | 不含「明顯」「嚴重」等模糊詞，應有量化指標 |
| 術後觀察頻率 | warning | `design.post_op_care` | 如有手術，必須提及觀察時間點 |
| 實驗期程合理性 | warning | `basic.start_date`, `end_date` | > 2 年標記提醒 |
| 安樂死方法 | warning | `design.euthanasia_method` | 對照 AVMA 推薦方法清單 |
| 附件完整性 | warning | `attachments[]` | 至少 1 份附件 |

**實作要點**：
- 從 `working_content` JSONB 解析各欄位，容忍欄位缺失（Option）
- 每條規則獨立函式，方便擴展
- 回傳結構化結果，前端可直接對應到表單 section
</details>

<details>
<summary>R20-2：驗證 API endpoint</summary>

**新增 handler**：`backend/src/handlers/protocol/validation.rs`

```rust
/// POST /api/protocols/{id}/validate
/// 權限：protocol owner (PI/Co-editor) 或 IACUC_STAFF
pub async fn validate_protocol(
    State(state): State<AppState>,
    Extension(user): Extension<CurrentUser>,
    Path(protocol_id): Path<Uuid>,
) -> Result<Json<ValidationResult>, AppError> {
    // 1. 權限檢查：require_protocol_view_access
    // 2. 讀取 protocol.working_content
    // 3. 呼叫 validation::validate_protocol(working_content)
    // 4. 回傳 ValidationResult
}
```

**路由**：在 `routes/protocol.rs` 加入：
```rust
.route("/protocols/:id/validate", post(validate_protocol))
```

**回應格式**：
```json
{
    "errors": [
        { "code": "3RS_REDUCTION_MISSING", "category": "3Rs", "section": "purpose", "message": "...", "suggestion": "..." }
    ],
    "warnings": [...],
    "passed": ["research_purpose", "personnel_qualifications", ...]
}
```
</details>

<details>
<summary>R20-3：前端提交前驗證 UI</summary>

**新增元件**：`frontend/src/components/protocol/ValidationPanel.tsx`

**觸發時機**：
1. 使用者點擊「提交」按鈕時，先呼叫 `POST /api/protocols/{id}/validate`
2. 如有 errors → 阻擋提交，顯示 ValidationPanel
3. 如只有 warnings → 顯示 ValidationPanel，使用者可選擇「修正」或「忽略並提交」
4. 全部通過 → 直接提交

**元件結構**：
```tsx
<ValidationPanel result={validationResult}>
  {/* errors 區塊 — 紅色，必須修正 */}
  <ValidationSection severity="error" issues={result.errors} />

  {/* warnings 區塊 — 黃色，建議改善 */}
  <ValidationSection severity="warning" issues={result.warnings} />

  {/* passed 區塊 — 綠色，可摺疊 */}
  <ValidationSection severity="passed" items={result.passed} />

  {/* 操作按鈕 */}
  <Button onClick={fix}>修正</Button>
  {onlyWarnings && <Button onClick={submitAnyway}>忽略建議，直接提交</Button>}
</ValidationPanel>
```

**每個 issue 可點擊**：跳轉到對應的表單 section（利用既有的 section tab 導航）。

**修改檔案**：
- `frontend/src/pages/protocols/ProtocolEditPage.tsx`：提交流程插入 validate 步驟
- `frontend/src/lib/api/protocol.ts`：新增 `validate(protocolId)` API 函式
</details>

<details>
<summary>R20-4：protocol_ai_reviews migration</summary>

**檔案**：`backend/migrations/0XX_protocol_ai_reviews.sql`

```sql
CREATE TABLE protocol_ai_reviews (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    protocol_id UUID NOT NULL REFERENCES protocols(id) ON DELETE CASCADE,
    protocol_version_id UUID REFERENCES protocol_versions(id),
    review_type VARCHAR(30) NOT NULL
        CHECK (review_type IN ('client_pre_submit', 'staff_pre_review')),
    -- Level 1 結果
    rule_result JSONB,
    -- Level 2 AI 結果
    ai_result JSONB,
    ai_model VARCHAR(50),          -- 'claude-haiku-4-5' | 'claude-sonnet-4-6'
    ai_input_tokens INTEGER,
    ai_output_tokens INTEGER,
    -- 合併結果
    total_errors INTEGER NOT NULL DEFAULT 0,
    total_warnings INTEGER NOT NULL DEFAULT 0,
    score INTEGER,                  -- 0-100 整體評分
    -- 元資訊
    triggered_by UUID REFERENCES users(id),  -- NULL = 自動觸發
    duration_ms INTEGER,
    created_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 查詢最新一筆 AI review
CREATE INDEX idx_ai_reviews_protocol_latest
    ON protocol_ai_reviews (protocol_id, created_at DESC);

-- 避免同一 version 重複呼叫
CREATE UNIQUE INDEX idx_ai_reviews_version_type
    ON protocol_ai_reviews (protocol_version_id, review_type)
    WHERE protocol_version_id IS NOT NULL;
```

**設計考量**：
- `rule_result` 和 `ai_result` 分開存，Level 1 不花錢可頻繁呼叫
- `ai_input_tokens` / `ai_output_tokens` 追蹤成本
- `protocol_version_id` + `review_type` UNIQUE index 防重複呼叫
- 不分區（量少，每筆計劃書最多幾十筆 review）
</details>

<details>
<summary>R20-5：AI 預審 service（Claude API 整合）</summary>

**新增檔案**：`backend/src/services/protocol/ai_review.rs`

**Config 擴展**（`config.rs`）：
```rust
pub struct Config {
    // ... 現有欄位 ...
    pub anthropic_api_key: Option<String>,       // ANTHROPIC_API_KEY
    pub ai_review_model: String,                 // AI_REVIEW_MODEL, 預設 "claude-haiku-4-5"
    pub ai_review_enabled: bool,                 // AI_REVIEW_ENABLED, 預設 true
    pub ai_review_timeout_secs: u64,             // AI_REVIEW_TIMEOUT_SECS, 預設 30
}
```

**Service 結構**：
```rust
pub struct AiReviewService;

impl AiReviewService {
    /// 完整預審（Level 1 + Level 2）
    pub async fn review_protocol(
        db: &PgPool,
        config: &Config,
        protocol_id: Uuid,
        review_type: &str,        // "client_pre_submit" | "staff_pre_review"
        triggered_by: Option<Uuid>,
    ) -> Result<AiReviewResult, AppError> {
        let start = Instant::now();

        // 1. 讀取 protocol.working_content
        let protocol = find_protocol_by_id(db, protocol_id).await?;
        let content = &protocol.working_content;

        // 2. Level 1：規則引擎
        let rule_result = validation::validate_protocol(content);

        // 3. 快取檢查：同一 version + type 已有結果 → 直接回傳
        if let Some(cached) = find_cached_review(db, protocol.current_version_id, review_type).await? {
            return Ok(cached);
        }

        // 4. Level 2：Claude API（僅在 Level 1 基本通過 + API key 存在時呼叫）
        let ai_result = if config.anthropic_api_key.is_some() && config.ai_review_enabled {
            Some(call_claude_api(config, content, review_type).await?)
        } else {
            None
        };

        // 5. 合併結果
        let combined = merge_results(rule_result, ai_result);

        // 6. 儲存至 DB
        insert_ai_review(db, protocol_id, protocol.current_version_id, review_type, &combined, triggered_by, start.elapsed()).await?;

        Ok(combined)
    }

    /// 呼叫 Claude API
    async fn call_claude_api(
        config: &Config,
        content: &serde_json::Value,
        review_type: &str,
    ) -> Result<AiResult, AppError> {
        let client = reqwest::Client::new();  // 複用現有 reqwest 依賴

        // 序列化計劃書內容為結構化文本
        let protocol_text = serialize_protocol_for_ai(content);

        // 選擇 system prompt
        let system_prompt = match review_type {
            "client_pre_submit" => CLIENT_REVIEW_PROMPT,
            "staff_pre_review" => STAFF_REVIEW_PROMPT,
            _ => return Err(AppError::BadRequest("Invalid review type")),
        };

        let response = client
            .post("https://api.anthropic.com/v1/messages")
            .header("x-api-key", config.anthropic_api_key.as_ref().unwrap())
            .header("anthropic-version", "2023-06-01")
            .header("content-type", "application/json")
            .timeout(Duration::from_secs(config.ai_review_timeout_secs))
            .json(&serde_json::json!({
                "model": config.ai_review_model,
                "max_tokens": 2048,
                "system": system_prompt,
                "messages": [{ "role": "user", "content": protocol_text }]
            }))
            .send()
            .await
            .map_err(|e| AppError::ExternalService(format!("Claude API: {}", e)))?;

        // 解析回應
        let body: serde_json::Value = response.json().await?;
        let text = body["content"][0]["text"].as_str().unwrap_or("");

        // 解析 JSON（Claude 回傳結構化 JSON）
        parse_ai_response(text)
    }
}
```

**System Prompt 常數**：
```rust
const CLIENT_REVIEW_PROMPT: &str = r#"
你是一位資深的 IACUC 審查委員，擁有實驗動物科學與獸醫學背景。
你的任務是預審動物實驗計劃書（AUP），幫助計畫主持人在提交前改善內容。
...（完整 prompt 見 docs/AIReview.md）
回覆格式為 JSON: { "summary": "...", "score": 72, "issues": [...], "passed": [...] }
"#;

const STAFF_REVIEW_PROMPT: &str = r#"
你是一位資深的 IACUC 審查輔助系統，協助執行秘書進行 Pre-Review。
你的任務是標註計劃書中值得注意的地方，幫助審查人員聚焦重點。
產出三類標註：
- 🚩 needs_attention（格式/完整性問題）
- ⚠️ concern（內容疑慮）
- ℹ️ suggestion（審查建議）
回覆格式為 JSON: { "summary": "...", "flags": [...] }
"#;
```

**成本控制**：
- 快取：同一 `protocol_version_id` + `review_type` 不重複呼叫
- 模型選擇：預設 Haiku（快速便宜），`ai_review_model` 可設為 Sonnet
- Token 限制：`serialize_protocol_for_ai` 截斷至 ≤ 8K tokens
- Rate limit：每用戶每日 10 次（在 handler 層檢查 `protocol_ai_reviews` 表 count）
</details>

<details>
<summary>R20-6：客戶端 AI 預審</summary>

**Backend handler**：`backend/src/handlers/protocol/ai_review.rs`

```rust
/// POST /api/protocols/{id}/ai-review
/// 權限：protocol owner (PI/Co-editor)
/// Rate limit：10 次/天/用戶
pub async fn ai_review_protocol(
    State(state): State<AppState>,
    Extension(user): Extension<CurrentUser>,
    Path(protocol_id): Path<Uuid>,
) -> Result<Json<AiReviewResult>, AppError> {
    // 1. 權限：require_protocol_edit_access
    // 2. Rate limit 檢查：今天已用次數
    // 3. AiReviewService::review_protocol(db, config, id, "client_pre_submit", Some(user.id))
    // 4. 回傳結果
}

/// GET /api/protocols/{id}/ai-review/latest
/// 取得最新一筆 AI review 結果（快取用）
pub async fn get_latest_ai_review(...)
```

**Frontend**：

1. **`frontend/src/components/protocol/AIReviewButton.tsx`**
   ```tsx
   // 放在 ProtocolEditPage 工具列
   <Button onClick={triggerAiReview} disabled={isLoading}>
     {isLoading ? <Spinner /> : '🔍 AI 預審'}
   </Button>
   // 剩餘次數顯示：「今日剩餘 8/10 次」
   ```

2. **`frontend/src/components/protocol/AIReviewPanel.tsx`**
   ```tsx
   // 顯示 AI 預審結果
   <Card>
     <CardHeader>AI 預審報告 — 評分 {score}/100</CardHeader>
     <CardContent>
       {errors.map(issue => <IssueItem severity="error" issue={issue} />)}
       {warnings.map(issue => <IssueItem severity="warning" issue={issue} />)}
       <Collapsible><PassedItems items={passed} /></Collapsible>
     </CardContent>
     <CardFooter>
       <Button onClick={rerun}>重新檢查</Button>
       {onlyWarnings && <Button onClick={submitAnyway}>忽略建議，直接提交</Button>}
     </CardFooter>
   </Card>
   ```

3. **`frontend/src/lib/api/aiReview.ts`**
   ```typescript
   export const aiReviewApi = {
     trigger: (protocolId: string) => client.post(`/protocols/${protocolId}/ai-review`),
     getLatest: (protocolId: string) => client.get(`/protocols/${protocolId}/ai-review/latest`),
   }
   ```

**修改檔案**：
- `ProtocolEditPage.tsx`：加入 AIReviewButton + AIReviewPanel
- `routes/protocol.rs`：加入新路由
</details>

<details>
<summary>R20-7：執行秘書 AI 標註</summary>

**Backend handler**：

```rust
/// POST /api/protocols/{id}/staff-review-assist
/// 權限：IACUC_STAFF, IACUC_CHAIR
pub async fn staff_review_assist(
    State(state): State<AppState>,
    Extension(user): Extension<CurrentUser>,
    Path(protocol_id): Path<Uuid>,
) -> Result<Json<StaffReviewResult>, AppError> {
    // 1. 權限：require permission "aup.review.comment" 或 IACUC_STAFF
    // 2. AiReviewService::review_protocol(db, config, id, "staff_pre_review", Some(user.id))
    // 3. 回傳結果
}

/// GET /api/protocols/{id}/staff-review-assist/latest
pub async fn get_latest_staff_review(...)
```

**Frontend 元件**：`frontend/src/components/protocol/StaffReviewAssistPanel.tsx`

```tsx
// 顯示在 ProtocolDetailPage 的 Pre-Review 階段頂部
// 只有 IACUC_STAFF / IACUC_CHAIR 可見

<Alert variant="info">
  <AlertTitle>📋 Pre-Review 審查輔助</AlertTitle>

  {/* 🚩 需要注意 */}
  <Section title="🚩 需要注意" items={flags.filter(f => f.type === 'needs_attention')} color="red" />

  {/* ⚠️ 留意事項 */}
  <Section title="⚠️ 留意事項" items={flags.filter(f => f.type === 'concern')} color="yellow" />

  {/* ℹ️ 審查建議 */}
  <Section title="ℹ️ 審查建議" items={flags.filter(f => f.type === 'suggestion')} color="blue" />

  <footer>
    AI 標註僅供參考，請依專業判斷審查
    <Button onClick={reanalyze}>重新分析</Button>
  </footer>
</Alert>
```

**修改檔案**：
- `ProtocolDetailPage.tsx`：在 Pre-Review 狀態時顯示 StaffReviewAssistPanel
- `CommentsTab.tsx`：可選 — 在審查意見區旁邊顯示 AI 建議
</details>

<details>
<summary>R20-8：Pre-Review 自動觸發</summary>

**修改檔案**：`backend/src/services/protocol/status.rs`

在 `change_status()` 函式中，當狀態變更為 `Pre_Review` 時：

```rust
ProtocolStatus::PreReview => {
    // ... 現有邏輯（assign co-editor 等）...

    // 自動觸發 AI 標註（非同步，不阻塞狀態變更）
    if state.config.ai_review_enabled && state.config.anthropic_api_key.is_some() {
        let db = state.db.clone();
        let config = state.config.clone();
        let pid = protocol_id;
        tokio::spawn(async move {
            if let Err(e) = AiReviewService::review_protocol(
                &db, &config, pid, "staff_pre_review", None  // None = 自動觸發
            ).await {
                tracing::warn!("Auto AI review failed for protocol {}: {}", pid, e);
            }
        });
    }
}
```

**設計要點**：
- `tokio::spawn` 非同步執行，狀態變更不等 AI 結果
- 失敗只 log warning，不影響正常流程
- 執行秘書打開頁面時，如果 AI 結果已就緒則直接顯示，否則顯示「分析中...」
- 可手動點「重新分析」強制重跑
</details>

<details>
<summary>R20-9：System prompt 調校</summary>

**持續性工作，非一次性開發**。

**方法**：
1. 上線後收集前 20 筆真實計劃書的 AI 預審結果
2. 與實際 Pre-Review / Committee 審查意見對比
3. 分析 False Positive（AI 標記但人工未標記）和 False Negative（人工標記但 AI 遺漏）
4. 調整 system prompt：
   - 如 FP 過多 → 提高判斷門檻，減少 warning
   - 如 FN 過多 → 增加特定領域的檢查指引
5. 記錄每次 prompt 版本和對應的準確率
6. 保存在 `docs/ai-review-prompt-history.md`

**目標**：AI 標記問題 vs 人工審查問題的重疊率 ≥ 80%。
</details>

<details>
<summary>R20-10：退回率追蹤</summary>

**新增查詢**：在 QAU Dashboard 或新增報表頁面

**SQL**：
```sql
-- 月度退回率（狀態時間軸來源：protocol_activities，狀態轉移列 to_value IS NOT NULL）
SELECT
    DATE_TRUNC('month', h.created_at) AS month,
    COUNT(*) FILTER (WHERE h.to_value IN ('PRE_REVIEW_REVISION_REQUIRED', 'VET_REVISION_REQUIRED', 'REVISION_REQUIRED')) AS revision_count,
    COUNT(*) FILTER (WHERE h.to_value IN ('SUBMITTED', 'RESUBMITTED')) AS submission_count,
    ROUND(
        COUNT(*) FILTER (WHERE h.to_value IN ('PRE_REVIEW_REVISION_REQUIRED', 'VET_REVISION_REQUIRED', 'REVISION_REQUIRED'))::NUMERIC /
        NULLIF(COUNT(*) FILTER (WHERE h.to_value IN ('SUBMITTED', 'RESUBMITTED')), 0) * 100, 1
    ) AS revision_rate_pct
FROM protocol_activities h
WHERE h.to_value IS NOT NULL
GROUP BY 1
ORDER BY 1 DESC;
```

**前端**：在 QAU Dashboard 新增「退回率趨勢」圖表（Recharts line chart），月度追蹤。

**衡量基準**：上線 AI 預審前的退回率 vs 上線後，目標降低 50%。
</details>

---

## 🌡️ R21 — 環境監控子系統（MES-Lite）（2026-04）

> 冰箱溫度 + 動物房溫濕度感測器資料收集、即時監控、超限告警。整合進現有 ERP 作為新子系統，不建立獨立 MES。
> 技術棧：TimescaleDB（PostgreSQL extension）+ HTTP/MQTT + Recharts。

### 21-A 後端基礎建設（P1）

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R21-1 | **DB Migration：感測器設備表** | `sensor_devices`（id, name, location, type enum: temperature/humidity/combo, calibration_due_at）+ `sensor_readings`（device_id, metric_type, value, unit, recorded_at）；TimescaleDB hypertable on `sensor_readings` | [ ] |
| R21-2 | **DB Migration：告警規則表** | `alert_rules`（device_id, metric_type, min_value, max_value, notify_emails, is_active）+ `alert_events`（rule_id, value, triggered_at, resolved_at, acknowledged_by）| [ ] |
| R21-3 | **感測器資料接收 API** | `POST /api/v1/sensors/readings`（API key 認證，Bearer token，複用 `config.rs` 模式）；handler → service → repository 分層 | [ ] |
| R21-4 | **歷史查詢 API** | `GET /api/v1/sensors/readings?device_id&from&to&interval=5m`（TimescaleDB `time_bucket` 降採樣）；`GET /api/v1/sensors/devices`（設備列表）| [ ] |
| R21-5 | **告警規則 CRUD API** | `GET/POST/PUT/DELETE /api/v1/sensors/alert-rules`（需 `sensor.config` 權限）| [ ] |
| R21-6 | **告警觸發邏輯** | `services/sensor/alert.rs`：每次寫入後檢查規則；超限時呼叫 `services/notification/` + email；自動 resolve（恢復正常後更新 `resolved_at`）| [ ] |

### 21-B 前端（P2）

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R21-7 | **Dashboard 即時面板** | `DashboardPage` 新增「環境監控」區塊；各設備目前溫濕度數值卡片；超限高亮紅色 CSS variable token | [ ] |
| R21-8 | **歷史趨勢圖頁面** | `pages/sensors/SensorHistoryPage.tsx`；Recharts LineChart；時間範圍選擇（1h/6h/24h/7d）；設備切換 | [ ] |
| R21-9 | **告警管理頁面** | `pages/sensors/AlertRulesPage.tsx`；規則 CRUD（RHF + Zod）；告警事件列表（已觸發/已解除/待確認）| [ ] |
| R21-10 | **Subsystem 導覽整合** | Sidebar 新增「環境監控」子系統入口；色相：`--subsystem-sensor: cyan`（DESIGN.md 登記）| [ ] |

### 21-C 硬體整合文件（P3）

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R21-11 | **感測器端設定文件** | `docs/sensor-setup/SETUP.md`：ESP32/Raspberry Pi 範例程式碼（Python/Arduino）；HTTP POST payload 格式；API key 申請流程 | [ ] |
| R21-12 | **MQTT Broker 評估** | 評估 Mosquitto 整合（替代 HTTP polling）；適合感測器數量 > 20 個時啟用；短期不需要 | ⏸️ |

---

## 🔧 R28 — bot review + R26/R27 code review 發現（2026-04-27）

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R28-1 | **observation 服務層仍重複查 animal** | `AnimalObservationService::create` 內部 audit log 邏輯也呼叫 `AnimalService::get_by_id`（observation.rs L113），handler + service 全程仍有 2 次重複查詢。R27-10 (PR #221) 只解了 handler 內的 2→1，service 層的 1 次仍在。深層修法需動 service 簽名（回傳 `(Observation, Animal)` 或讓 handler pre-fetch 傳入）— breaking change 跨多 callers，獨立 PR 處理。來源：Gemini PR #221 Medium。LOW | [ ] |
| R28-2 | **concurrent audit write 整合測試提升至 10 並行** | `backend/tests/api_audit_r26.rs` L259 並行度為 3（pool max=5 限制保守值），規劃中為 10。需先擴 TestApp pool max_connections ≥12 再補測試。來源：R26 review。MEDIUM。**已完成（PR #236 `f46f762e`）** | [x] |
| R28-3 | **掃描 upsert pattern 是否還有 SELECT FOR UPDATE 遺漏** | PR #197 R26-13 修了 `storage_location.rs`，但其他 module（product / equipment / partner）的 upsert (`ON CONFLICT DO UPDATE`) 樣式可能仍有遺漏。grep `INSERT.*ON CONFLICT DO UPDATE` 全 backend，逐一驗證是否需改為顯式 SELECT FOR UPDATE + 分支以保證 audit before snapshot 正確 + 並發安全。來源：R26 review。MEDIUM (security-adjacent)。**已完成（PR #234 `255bdd4e`，含 system_settings audit 補全）** | [x] |
| R28-4 | **ActorContext::Anonymous 適用情境文檔化** | `middleware/actor.rs` Anonymous 變體用於 login attempt + CSP report；HMAC fallback 用 SYSTEM_USER_ID。新增 anonymous 事件（rate limit block 等）易遺漏一致性。**已完成**：CLAUDE.md §4 Backend 加 ActorContext::Anonymous subsection — 列 5 個已知場景（LOGIN_FAILED / CSP_VIOLATION / HONEYPOT_HIT / RATE_LIMIT_EXCEEDED / IDOR_PROBE）+ 3 條規範（HMAC chain 用 SYSTEM_USER_ID / service 層拒絕 Anonymous mutation / 新增事件 checklist）。LOW | [x] |
| R28-5 | **HMAC versioning backfill 完成度監控** | (1) `log_security_event_tx` 改走 `log_activity_tx`（HMAC chain），刪除舊版直接 INSERT 路徑 (2) `bin/backfill_hmac_version.rs` 工具：逐 row 重算 v2/v1 HMAC 並 UPDATE hmac_version（`--dry-run` 預覽） (3) `HmacInput` / `compute_hmac_for_fields_versioned` 改 `pub` 供 bin 使用。Prod 執行：deploy 後跑 `cargo run --bin backfill_hmac_version` | [x] |
| R28-6 | **Shell script + Docker 邊界 case 自動化測試** | `frontend/docker-entrypoint.sh` 邏輯（trim、fail-fast、唯讀路徑判斷）只手動驗證，無 CI 自動測試。建議：(1) `sh -n` 語法檢查 (2) docker run with `API_BACKEND_URL=""` / `"  "` / valid 三組驗證；放 `frontend/test-entrypoint.sh` + CI step。來源：R27 review (PR #217)。MEDIUM。**已完成（PR #236 `f46f762e`）** | [x] |
| R28-7 | **Admin permission cache 效能基準** | 2026-05-26 prod metrics 確認：admin 39 hits / 2 misses = 95% hit rate；non-admin 3/1；1 次 expired eviction。5min TTL 完全合理，admin 路徑成本極低。`is_admin` label 已加（auth.rs L174-177），Grafana 可直接 filter | [x] |
| R28-8 | **Observation notification failure handling** | 2026-05-26 完成：`.ok()` 改為 `match` + `tracing::warn`，fetch 失敗時明確 log emergency/abnormal 標記 + error 內容。通知仍 silent skip（不阻擋主流程），但 ops 可從 log 發現遺漏 | [x] |
| R28-9 | **permission_cache metrics 計數精度** | 2026-05-26 accepted：prod 數據 admin 39+2=41、non-admin 3+1=4，hit+miss 總和符合預期。Race <1% 微誤差已在 auth.rs L170-171 code comment 文檔化，可接受 | [x] |
| R28-10 | **Auth spinner 永久卡 loading — 真正 root cause 調查** | 2026-05-13 prod 現象：未登入訪客打開 `https://ipigsystem.asia/` 卡在 `ProtectedRoute` spinner 6+ 秒不 redirect 到 `/login`。playwright 4 次黑盒 probe 證據：(1) `/api/v1/me` → 401 → `/api/v1/auth/refresh` → 401（皆符合預期）(2) React 已掛載、`#root` 有 spinner 子節點 (3) `setTimeout(1000ms)` 從未被排程 → 代表 `lib/api/client.ts` interceptor 的 `logoutPromise` block 沒走到 (4) `auth-storage` localStorage 永遠 null、無 pageerror、無 console.error。**已落地（同 PR）防禦性 kill-switch**：`App.tsx` checkAuth 加 `.finally()` 保證 `isInitialized: true`，spinner 不再卡死。**待追**：interceptor `await refreshPromise` → `clearAuth()` → `setTimeout(1000ms, → /login)` 為何整段沒執行（hypothesis：`refreshPromise` 競態 / `useAuthStore.getState().isGuest()` 在初始狀態抛 / interceptor 内 unhandled rejection 被吞）。需在 prod build 加 `console.debug` 標記 + 重現後拔掉，或本地用相同建構 mode 重現。LOW（kill-switch 已遮蓋症狀，但 root cause 暴露 axios interceptor 維護性問題） | [ ] |

### R28 second-pass review — Medium findings (2026-04-27)

> 來源：`docs/reviews/2026-04-27-r26-r27-second-pass-review.md`（6 parallel sub-agent + 主審 verify，13 findings 中 6 條 Medium）。

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R28-M1 | **Migration 037 註解 vs verifier try-both 矛盾** | 註解誤導 backfill 腳本撰寫者（驗證端非「視為 v=1」而是 try-both）。修正後補 `docs/security/HMAC_VERSIONING.md` 三階段計畫。**已完成（PR #240 `ace7c379`）** | [x] |
| R28-M2 | **Anonymous→SYSTEM HMAC residual risk** | actor 類別 SYSTEM 替代讓鏈中無法區分 Anonymous，理論可被竄改。採 design doc 路線（HMAC_VERSIONING.md §4）說明 accepted residual risk + v3 編碼擴充計畫。**已完成（PR #240 `ace7c379`）** | [x] |
| R28-M3 | **Advisory lock key 中央註冊** | i64 常數 vs hashtext() 派生兩種命名空間共存無集中表。集中於 `backend/src/constants.rs::§Advisory Lock Key`，加 i32 範圍外驗證 unit test。**已完成（PR #239 `d3c6feda`）** | [x] |
| R28-M4 | **middleware AppError::Database variant 透傳** | `check_user_active_status` 把 `AppError::Database` 包成 `AppError::Internal`，error variant 流失。改為 `.inspect_err` 保留 log + `?` 透傳；`map_cache_loader_error` 補 sqlx::Error not Clone 限制註解。**已完成（PR #239 `d3c6feda`）** | [x] |
| R28-M5 | **Prometheus init failure → /api/health degraded** | init 失敗時 metrics 靜默掉（NoopRecorder），無 ops 可觀測。改為失敗時 `/api/health` 回 503 degraded + `tracing::error`；TestApp 加 `OnceLock<PrometheusHandle>` 避免 install_recorder 多次。**已完成（PR #238 `6d5ebbe6`）** | [x] |
| R28-M6 | **`create_animal_observation` 缺 IDOR `require_animal_access`** | pre-existing IDOR（非 PR #221 引入），handler + service 兩層皆未檢查。handler 加 `require_animal_access`（與其他 observation handler 一致）。**已完成（PR #237 `aedc1af5`）** | [x] |

---

## 🔧 R29 — ClawSweeper review follow-up backlog（2026-04-27 起）

> 來源：合規類 PR ClawSweeper review 中 DEFER 的條目；嚴重度 MEDIUM 以上者進此 backlog，獨立 PR 統一處理（避免合規 hotfix PR scope creep）。

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R29-1 | **Maintenance + Disposal signature handler→service + tx-aware sign_record + audit log** | 來源：PR #241 ClawSweeper review (CR-1 + CR-2 + G-1)。原 spec 列 6 個 sign handler，實際調查後 scope 縮窄至有「sign + UPDATE 非原子」破洞的兩個入口：maintenance + disposal。**已完成**：1a maintenance（PR #249 `70030c63`）建立 `SignatureService::sign_record_tx` + `EquipmentService::sign_maintenance_review_tx` + `access::require_equipment_review`；1b disposal applicant/approver（PR #251 in-flight）增 `sign_disposal_applicant_tx` / `sign_disposal_approver_tx`，含「申請人不得代簽」+ 「申請人不得自核（職權分離）」雙守衛。其他 5 sign handler（transfer / sacrifice / observation / euthanasia / protocol_review）只 INSERT signature 一個 statement 不需 atomicity 包裝，已記錄於 R29-1b commit message。 | [x] |
| R29-2 | **Frontend deps major bump — react-router-dom 6.30.3 → 7.14.2 升級適配** | **已完成（PR #247 `5b49ba4c`）**：升級走 R29-4 dev-deps group 拆解路線，獨立 PR 完成。CI `tsc check` 一次綠（v7 type-level breaking 在本系統實際無衝擊；無 v6 future flags 殘留）；dependabot PR #229 merge 後自動 close。 | [x] |
| R29-3 | **Frontend deps major bump — i18next 25.10.10 → 26.0.8 升級適配（含 CWE-117 / ReDoS 安全強化）** | 來源：PR #233 ClawSweeper review。實際只受單一 breaking 影響：v26 移除 `showSupportNotice` 選項。其他 v26 breaking（`initImmediate` / 舊 `interpolation.format` 函式式 / `simplifyPluralSuffix` / `@babel/polyfill`）本系統皆未使用。94 檔 i18n 使用點全部 forward-compatible。採納 v26.0.6 三條 security fixes（CWE-117 log forging / ReDoS / nesting injection 警告）。**已完成（PR #242 `8b2e68d0`）**，實際工時 ~30 min 遠低於原估 2-4h。 | [x] |
| R29-4 | **Frontend dev-deps group bump 拆解（PR #227 14 個套件）** | 來源：dependabot PR #227 group bump CI `tsc check` + Trivy FAIL。**已完成**：拆 5 個獨立 PR 順序 land — #243 vitest patch / postcss / jsdom (`a5d74b98`) → #247 react-router 7 (`5b49ba4c`) → #244 eslint 10 (`66c457c4`) → #245 vite 8 + plugin-react 6 + manualChunks fix (`842b3543`) → #246 TS 6 + @types/node 25 + @typescript-eslint 8.59 + tsconfig baseUrl 移除 (`91402950`)。原估 1-2h 實際 ~3h（含 4 次 lockfile rebase）。**Tailwind v4 不在本批次**（見 R29-5）。 | [x] |
| R29-5 | **Frontend deps major bump — Tailwind CSS 3.4 → 4.2 升級適配（CSS-first 配置重寫）** | **DEFER 至 2026-07-28（v4 ecosystem 穩定化窗口）**。決策（2026-04-28）：D1=defer 1-3 個月（Tailwind v3 仍 LTS、無安全壓力、v4 plugin 生態尚在補齊）；D2=auto-convert `tailwind.config.js` → CSS `@theme`（surgical change，不擴大 scope）；**D3=自動 screenshot diff（gstack browse）做 visual smoke**（不仰賴 E2E / DesignReview 人工）；D4=grep + 全自動取代 deprecated utility（tsc/build 守護）；D5=本專案無 Storybook，不需同步。修法（屆時）：開新 branch `chore/deps-tailwind-4-upgrade`，遷 config → CSS → 改 PostCSS plugin → grep utility 取代 → DESIGN.md token sync → 升級前後各跑一次 gstack browse 對 critical path 截圖（DataTable / Dialog / Sidebar / Login / FormPage 5 處）做 pixel diff。預估 4-8 小時。MEDIUM (visual regression risk) | [ ] |
| R29-6 | **Dependabot PR group 拆分策略 + CI fail-fast 短路** | **已完成（PR #250 `bbf7b820`）**：`.github/dependabot.yml` 9 種高風險 major 套件單獨成 PR（typescript / tailwind / react-router / eslint / vite / i18next / @types/node / @typescript-eslint）；`.github/workflows/ci.yml` 為 `frontend-entrypoint-test` + `trivy-scan` 加 `needs:` short-circuit。 | [x] |

---

## 🔒 R31 — CSP 強化（2026-04-29）

> **背景**：當前 CSP（`frontend/security-headers.conf:12`）為了 Vite/React 與 Tailwind 開了 `script-src 'unsafe-inline' 'unsafe-eval'` 與 `style-src 'unsafe-inline'`，相當於 XSS 防線被大幅削弱。本輪目標：在不破壞 dev/prod build 的前提下，**逐步收緊 CSP 至 `'strict-dynamic' + nonce`**，並移除 prod `'unsafe-eval'`。
>
> **不要一次全收**：每收一個 directive 都要 staging 驗證 + CSP report 觀察一週確認無 violation 再上 prod。

### A. 偵察階段（執行收緊前必做）

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R31-1 | **CSP report 基準掃描** | 開啟 `Content-Security-Policy-Report-Only` header（與當前 enforce header 並存），收一週 `csp_report` 表，分類目前實際違規來源（inline script / inline style / eval / 第三方 domain）。產出基準報告 `docs/security/csp-baseline-2026-04.md`。**這是後續所有收緊 PR 的依據** | [x] |
| R31-2 | **Audit `index.html` inline 內容** | 檢查 `frontend/index.html` 是否有 inline `<script>`、`<style>`、`onclick=` 等。若有，盤點是否可挪到外部檔案（最理想），或標記必須保留 → 之後改 nonce / hash | [x] |
| R31-2b | **Audit React `dangerouslySetInnerHTML` 用量** | `rg "dangerouslySetInnerHTML" frontend/src` 全 codebase，檢查是否有注入帶 inline event handler / `<script>` / `<style>` 的 HTML。每處分類為：(a) 可改 React 事件綁定 → 改寫；(b) 必須保留 → 標記為需 nonce / hash；(c) 可移除 → 移除。產出清單併入 `csp-baseline-2026-04.md`。**避免 R31-10 enforce 後白屏** | [x] |
| R31-3 | **Audit React inline style 用量** | grep `style={{` 全 codebase，量級評估。若 >50 處，`style-src 'unsafe-inline'` 短期不收（標記 R31-Z 長期項目） | [x] |

### B. Prod 移除 `'unsafe-eval'`（❌ 廢案 — 2026-04-30 R31-15 baseline 結果打臉）

> R31-1 baseline 24h 收到 62 個 eval 違規（33 wasm-eval + 29 eval），來自 transitive deps + Cloudflare Insights beacon 內部使用。frontend src 雖 0 處呼叫，但無法控制依賴內部行為。**改用 R31-13b 接受 `'unsafe-eval'` 為長期風險**（同 R31-13 inline style 模式）。詳見 csp-baseline-2026-04.md §5。

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| ~~R31-4~~ | ~~拆分 dev / prod nginx CSP~~ | **廢案**（見上） | [~] |
| ~~R31-5~~ | ~~Staging 驗證 prod build 無 eval 依賴~~ | **廢案**（見上） | [~] |
| ~~R31-6~~ | ~~Prod 切換~~ | **廢案**（見上） | [~] |

### C. Script nonce 化（中風險高 ROI）

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R31-7 | **nginx 注入 nonce** | **完成**（nginx.conf `set $cspNonce $request_id` + `sub_filter '__CSP_NONCE__' $cspNonce`；security-headers.conf Report-Only header `script-src 'nonce-$cspNonce' 'strict-dynamic' 'wasm-unsafe-eval'`，與舊 enforce header 並存待 R31-9/10 驗證後切換） | [x] |
| R31-8 | **Vite build 配合（含動態 chunk + modulepreload）** | **完成**（自寫 `frontend/src/vitePlugins/cspNoncePlugin.ts` + `vite.config.ts` 已 enabled；plugin transformIndexHtml 把 `<script>` 與 `<link rel="modulepreload">` 注入 `nonce="__CSP_NONCE__"` placeholder；nginx sub_filter 替換為實際 nonce。Unit tests 覆蓋 plugin shape） | [x] |
| R31-9 | **Report-Only 並存觀察期** | dual-header 上 prod 12 天（R31-7 nonce 自 2026-05-03）。SOP `docs/runbooks/csp-enforce-cutover.md`（2026-05-13）。觀察期數據：DB `CSP_VIOLATION_REPORT_ONLY` 連續 9 天 0 非雜訊違規（2026-05-06 起）；Playwright 3 engines (Chromium/Firefox/WebKit) `SIMULATE_CUTOVER=1` dry-run 全 0 violation。`scripts/csp-smoke.mjs` 自動化驗證腳本落地。 | [x] PR #410 |
| R31-10 | **切換 enforce + 移除 CF Insights**（R31-C 同步決策）| 觀察期通過後 cutover：刪舊 enforce header、新 enforce 移除 `'unsafe-inline'` + `'unsafe-eval'` + `https://static.cloudflareinsights.com` + `https://cloudflareinsights.com`。**選項 C**（移除 CF Insights）：solo + prod-on-laptop telemetry 由 self-hosted Prometheus/Grafana/Loki 提供，CF Insights RUM 無實際用途；script-src 不需第三方 CDN 例外 = R31 最乾淨終局。**Cutover 落地 2026-05-15**：Playwright 真實 enforce prod 3 engines (Chromium/Firefox/WebKit) **0 violations**。Rollback：revert + `docker compose exec web nginx -s reload`，runbook §「切換失敗」。 | [x] PR #410 |

### D. report-uri → report-to 過渡

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R31-11 | **加 `report-to` directive + Reporting-Endpoints header** | Backend handler refactor + dual payload (CSP1/2 legacy + CSP3 Reporting API) + service 層拆出 `services/csp_report.rs::insert_csp_violation` 全部完成（PR #312）。Nginx side：security-headers.conf 兩個 CSP header 都加 `report-to csp-endpoint` directive + 新增 `Reporting-Endpoints: csp-endpoint="$scheme://$host/api/v1/csp-report"` header（PR `feat/r31-11-reporting-endpoints`） | [x] |
| R31-12 | **觀察新版 report 進來後移除 `report-uri`** | 三個月過渡期後，若所有主流瀏覽器都已切到 `report-to`，移除 `report-uri` directive 與 handler 舊版分支。**🕒 觀察期起算：2026-05-07 PR #345（Reporting-Endpoints 上線），最早可動：~2026-08-07** | [ ] |

### E. 長期項目（觀察用，不主動推）

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R31-13 | **`style-src 'unsafe-inline'` 收緊評估** | 取決於 R31-3 結果。若 inline style 量小可改 nonce / hash；若量大（CSS-in-JS / Tailwind arbitrary values）則放棄收緊，文件標記為已接受風險 | [ ] |
| R31-13b | **~~`script-src 'unsafe-eval'` 接受風險~~ → R31-C 解決：移除 CF Insights** | 原本 R31-15 把 eval 違規（CF Insights beacon 內部 eval）標記為「接受風險」；2026-05-15 R31-10 cutover 同步決策（PR #410）改採選項 C：直接移除 CF Insights 白名單。理由：solo + prod-on-laptop telemetry 已由 self-hosted stack 提供，CF Insights RUM 無實際用途。結果：script-src 不需 `'unsafe-eval'`、不需第三方 CDN 例外，原本永久接受的 risk **被消除** | [x] |
| R31-14 | **`connect-src` 第三方白名單清理** | ✅ GA4（`google-analytics.com` / `analytics.google.com`）已移除（前端未使用，PR #284）；Cloudflare Insights 保留；後續 quarterly review | [x] |
| R31-15 | **R31-1 baseline 24h findings 處理** | (a) RO header 加 `'wasm-unsafe-eval'`（CSP3 窄化）→ 33 wasm-eval 噪音降至 0；(b) **R31-4~6 廢案** + 新增 R31-13b 接受風險；(c) ✅ 確認 `G-4DRSC0MFNJ` 非我方 GA4 ID（使用者已確認無 GA4 帳號，FB inapp browser / extension 注入第三方追蹤）；(d) 文件化於 csp-baseline-2026-04.md §5 | [x] |

### R31 風險與停機規則

- **R31-1 偵察報告產出後必停**：使用者裁定先收哪個 directive（順序可能不同於 B → C）
- ~~**R31-6（prod 切換 unsafe-eval 移除）必停**~~：B 段廢案（R31-15）
- **R31-10（script-src enforce 切換）必停**：若有遺漏的 inline script，prod 立即白屏
- **R31-9 / R31-11 dual-header 期間 prod 推送 OK**：Report-Only 不會擋資源，安全可逆

### R31 預估

- 17 項（15 + R31-13b + R31-15），扣除廢案 R31-4~6 後實際推進 14 項。總預估 30-45 小時（約 1 週全職），跨 4-6 週日曆時間（含 staging 觀察等待）。

---

## 🚀 R35 — 系統改進 backlog（2026-05-08，5 wave / 24 PR）

> 來源：2026-05-08 全系統掃描（基於 R34 完成後的 codebase 狀態），結合使用者「對倉庫平面圖 / PDF 列印 / 下載」連續實戰回饋。
> 採 **wave-based 平行化計畫**：同 wave 內 PR 互不衝突可並行；跨 wave 依序推進，hot files (`docs/TODO.md` / `docs/PROGRESS.md` / `services/mod.rs`) 集中在 wave 末尾收。
>
> **執行門檻**：每個 PR ≤ 1 邏輯單元，每 wave 結束「停 + 合 + 等使用者裁定下一 wave」。
> **不做（parked）**：8 項已盤點為「現階段價值低 / 影響面大 / 等真實用戶反饋再啟動」，列在最末尾備忘。

### Wave 1 — UX 改進（並行 4-5 PR / 1-2 天）

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R35-1 | 倉庫列印 UX：列印按鈕加 loading spinner + 失敗 retry | `WarehouseReportPage.tsx` printPdfMutation 加進度指示。Touch: frontend only。code-only。 | [x] |
| R35-2 | 倉庫平面圖 hover tooltip 顯示完整品項清單 | 滑過儲位顯示前 5 個產品 + 總數量。Touch: `LayoutDiagram` component。code-only。 | [x] |
| R35-3 | 倉庫報表新增「庫存價值」摘要卡片（ASP × qty） | R35-16 加 `selling_price` 後已重做：backend `SUM(qty × selling_price)` + frontend `SummaryCard` + `formatInventoryValue()` 千分位 NTD$ 格式化 | [x] |
| R35-4 | PDF 預覽分頁標題從 `blob:` → 倉庫名稱 | Frontend `fetchPdfBlob(inline)` 加 `?inline=1` + `win.addEventListener('load', → document.title)`；download 路徑不受影響 | [x] |
| R35-5 | 動物列表 server-side sort（取代 client-side `useTableSort`） | 大農場 > 1k 筆動物時 client sort 卡頓。Touch: backend `find_animals_*` 加 sort param。 | [x] |
| R35-6 | 共通 `useDebouncedSearch` hook 抽出 | `useDebounce` baseline 已存在 + 8 個檔案在用，重複 ≥ 5 處假設過時 → SKIP（feat/r35-wave1） | [x] |

### Wave 2 — Observability / DevEx（並行 3-4 PR / 1-2 天）

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R35-7 | pdf-service 加 Prometheus `/metrics` endpoint | render duration / template miss / convert failure 計數。Touch: pdf-service only。code-only。**PR #352 已開（2026-05-08）**。 | [~] |
| R35-8 | ~~backend audit log 查詢加 covering index~~ | **Parked（前提錯誤，2026-05-08 wave2 查證）**：`(actor_user_id, created_at DESC)` 等價 index 已存在於 `004_security_audit.sql:63 idx_activity_actor_created`。若日後有實證的慢 query 再回頭設計 covering（INCLUDE 子句）。 | [-] |
| R35-9 | docker compose dev 加 `--watch` profile（hot reload Rust） | cargo-watch + bind mount。dev 體驗，不影響 prod。code-only。**PR #353 已開（2026-05-08）**。 | [~] |
| R35-10 | E2E test 補：warehouse PDF print path | playwright 點列印按鈕 → 期待新分頁含 PDF。Touch: e2e/tests only。code-only。**PR #354 已開（2026-05-08）**。 | [~] |
| R35-11 | Frontend bundle 分析 + lazy load 大頁面 | **TODO 描述部分過時（2026-05-08）**：lazy load 早已完成（App.tsx 全部 page 都 `lazy()` + 三層 idle prefetch）。本項只剩「bundle 分析工具」面，**PR #355 已開**加 `rollup-plugin-visualizer` + `pnpm build:analyze`。 | [~] |

### Wave 3 — Security cross-cutting（依序 4 PR / 2-3 天）

> 此 wave 動 middleware / handlers，互相 conflict 風險高，依序做。

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R35-12 | CSP `enforce` 切換（R31-10 兌現） | Report-Only 觀察期過 → 切 `Content-Security-Policy`。需先確認 R31-9 觀察期報告 0 嚴重 violation。 | [ ] |
| R35-13 | 移除 CSP `report-uri` legacy directive（R31-12） | Reporting-Endpoints 已上線（PR #345 / 2026-05-07）。**⚠️ 延辭至 ~2026-08-07** — R31-12 原規範三個月過渡期，提前移除會盲掉 Safari 16- / Firefox 131- 用戶的 violation 報告，並影響 R31-9 觀察期樣本。Touch: nginx conf only。 | [ ] |
| R35-14 | Rate limit 每 IP × endpoint 細分（取代全域） | 5-tier 之中 write/upload tier 改 per IP × `MatchedPath` keying（同 IP 不同 endpoint 獨立配額）；auth/forgot-pw/api tier 維持 IP-only（auth 為了 escalation 邏輯、api 為了反 pattern rotation backstop）。Touch: `middleware/rate_limiter.rs`。 | [x] |
| R35-15 | JWT refresh token rotation + reuse detection | 既有 rotation 已實作（撤銷舊 + 發新），補上 reuse detection：migration 054 加 `family_id` + `revoked_reason`；rotation 沿用 family，已撤銷 token 再次提交 → 整 family revoke + 寫 critical security_alert (`REFRESH_TOKEN_REUSE`)。Touch: `services/auth/session.rs` + migration 054 + `models/user.rs::RefreshToken`。 | [x] |

### Wave 4 — Schema 變更（依序 5-6 PR / 5-7 天）

> Migration 需 staging 驗證，每 PR 一個獨立 migration。

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R35-16 | `products.unit_price` numeric → 拆 `cost_price` + `selling_price` | Plan 假設錯誤（products 從沒 unit_price 欄位）→ 改「從零加 cost/selling 兩欄」+ 部分索引；無 backfill source。Migration 054 + Product model（PR #356）。 | [x] |
| R35-17 | `storage_location_inventory_items.expiry_date` 加 not-null 約束 + 過期警示 | NOT NULL SKIP（products.track_expiry=false 時 NULL 合法）；底層 `v_expiry_alerts` view + API 已存在；補 within_days filter + Dashboard ExpiryAlertWidget（PR #356）。 | [x] |
| R35-18 | `users.last_login_at` 欄位（auth 補 update） | Schema + login UPDATE 全部已存在於 main（migration 002 + login.rs / two_factor.rs）；補 admin UsersPage「最後登入」欄 + ≥90 天 dormant 紅標（PR #356）。 | [x] |
| R35-19 | `animals.weight_history` JSONB 改 `animal_weights` 子表 | 既有 JSONB 不易查詢趨勢。需 backfill。 | [ ] |
| R35-20 | `audit_log` partition by month（PG 13+ declarative） | 表已 > 100k row。Migration + repository 改寫。 | [ ] |
| R35-21 | audit JSONB 欄位加 GIN index for path query | Migration 076：`user_activity_logs` + `audit_logs` 的 `before_data` / `after_data` 加 `jsonb_path_ops` GIN index（4 個 index） | [x] |

### Wave 5 — 業務 quick wins（並行 2-3 PR / 2-3 天）

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R35-22 | ~~動物轉場（move） 批次操作 UI~~ | **Parked（前提錯誤，2026-05-08 wave5 查證）**：TODO 寫「API 已支援 batch」不成立 — 後端只有 `/animals/batch/assign`（耳標批次指派），**沒有 batch transfer endpoint**。Animal transfer 是 5 步重型 workflow（initiate→vet→assign→approve→complete），單次批次操作不適合。要做的話需先設計 backend 新 endpoint。 | [-] |
| R35-23 | ~~庫存低於 reorder_point 通知（每日 scheduler）~~ | **Parked（前提錯誤，2026-05-08 wave5 查證）**：TODO 寫「reorder_point 欄位閒置」不成立 — `scheduler.rs:80 register_low_stock_job` 早已每小時觸發、SQL view `v_low_stock_alerts`（`migrations/009_erp_stock.sql:514`）用 `reorder_point < on_hand_qty` 比較、in-app 通知 + email + dashboard widget + 前端列表全已上線（`/notifications/alerts/low-stock`）。 | [-] |
| R35-24 | 報表中心：跨子系統 `/reports` hub | **TODO 描述部分過時**：ERP 9 項早已有 hub `/erp/reports`（ErpReportsPage）。**PR #358 已開**：把 hub 升級為跨子系統（加 audit / warehouse / AUP 入口）並改路由 `/erp/reports` → `/reports`，per-item permission gate。code-only。 | [~] |

### R35「不做 / parked」備忘

| # | 項目 | 不做原因 |
|---|------|---------|
| P1 | i18n 多語言（en/zh/ja） | 場域單語言（zh-TW），無真實需求 |
| P2 | 圖表 dashboard refactor（Recharts → ECharts） | 目前可用，換引擎成本 > 收益 |
| P3 | GraphQL API 平行於 REST | 內部單 client，REST 足夠 |
| P4 | Service Worker offline mode | 場域必網路（IoT 感測），無 offline 需求 |
| P5 | Storybook 元件文件化 | 元件數 < 80，README 即可 |
| P6 | 自架 SSO（OIDC provider） | 規模太小，現有 JWT + admin 已涵蓋 |
| P7 | Multi-tenant SaaS 化 | 單客戶部署，無 multi-tenant 需求 |
| P8 | Mobile native app（React Native） | RWD web 已涵蓋現場 iPad 場景 |

### R35 平行化分析（總和：24 PR / 11-17 工作日）

- **Wave 1+2 互不衝突** → 可同時進場（5+4 = 9 PR 並行 1-2 工作日）
- **Wave 3 必依序**（middleware 同檔）
- **Wave 4 必依序**（migration version 衝突）
- **Wave 5 與 Wave 3/4 部分並行**（不同檔）
- **Hot files** (`services/mod.rs` / `docs/TODO.md` / `docs/PROGRESS.md`) → 每 wave 末尾統一 touch

### R35 對應 memory

- `feedback_integration_branch_strategy.md` → 是否走 `integration/r35` 長期分支待使用者裁定
- `feedback_no_prod_build.md` → 前端驗證一律 vite dev，禁 `npm run build`
- `feedback_docs_only_prs_skip_ci.md` → migration 結構文件變更可直接 main

---

## 🚨 R36 — Backup & DR 緊急修復 + 異地備份（2026-05-08）

> 來源：2026-05-08 與使用者討論 Docker CPU 優化時，發現 prod 跑在筆電上、且**現場沒有異地備份**；進一步 inspect `ipig-db-backup` 容器發現 `/backups/` 目錄空無一物。
>
> **背景情境** ⚠️：ipig_system 為 prod 環境跑在 ASUS ExpertBook B1500 筆電上，使用者一人 solo 開發+維運，無團隊 / 無備援。一旦 SSD 壞掉或筆電損毀，**目前無任何 backup 可還原**。
>
> **執行門檻**：R36-1~4 為 **P0 緊急修復**，必須在數天內完成，不可進其他 backlog；R36-5~10 為 **異地備份建置**，1-2 週內收斂；R36-11+ 為 **自建伺服器遷移規劃**（2026-07-24 改方向，見 R36-D），預算未定（使用者裁定「價格不是問題」）。

### R36-A. 緊急修復（P0，數天內）

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R36-1 | **`pg_backup.sh` DB_NAME 預設值錯誤** | `scripts/backup/pg_backup.sh:9` 預設 `DB_NAME=erp_db`，但實際 DB 為 `ipig_db`。compose 傳的是 `POSTGRES_DB` env 而非 `DB_NAME` → script 用預設 `erp_db` → pg_dump 失敗 → **每天 02:00 cron job 都失敗，無人察覺**（log 只噴錯，沒上 alert）。修：script 改讀 `POSTGRES_DB`（fallback `DB_NAME`），預設值改 `ipig_db`。**完成於 commit `6ade6c24`（2026-05-08）**。 | [x] |
| R36-2 | **`pg_backup.sh` pipefail + SIGPIPE bug** | 第 40 行 `gunzip -c "$BACKUP_FILE" \| pg_restore --list > /dev/null 2>&1` — pg_restore 讀完 header 即關 stdin，gunzip 收 SIGPIPE 退 141；`set -euo pipefail` 把這當失敗 → script 最終 exit 1，雖然 backup 檔已產生且有效。修：把驗證改成先解壓到 temp 檔再 `pg_restore --list`。**完成於 commit `6ade6c24`（2026-05-08）**。 | [x] |
| R36-3 | **驗證 cron 真的在跑 + 失敗會通知** | heartbeat metric `backup_last_success_timestamp_seconds` 由 `pg_backup.sh` 寫入 `/backup-metrics/ipig_backup.prom`，node-exporter textfile collector 暴露至 prometheus。3 條 alerts：BackupStale (>25h)、BackupMetricMissing (30m)、BackupSizeAnomaly (>50% 7d 平均)。**完成於 commit `eab076d4`（2026-05-08）**。 | [x] |
| R36-4 | **GPG 加密啟用 + 金鑰管理** | dedicated keypair (RSA 4096，fingerprint `E1301...A32367`，email `backup@ipigsystem.asia`) 已產生；公鑰已 import 到 `secrets/backup_gpg_pubkey.asc`，entrypoint 自動 import 到容器 keyring 並設 ownertrust=ultimate；私鑰**僅存兩支 USB**（BLACKSLIVER + King，bytes-identical），keyring 已清空。**完成於 commit `eab076d4` + `b9cae5cd` + GPG keypair gen on 2026-05-09**。 | [x] |

### R36-B. 異地備份建置（P1，1-2 週內）

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R36-5 | **開 Cloudflare R2 帳號 + bucket** | bucket `ipig-backups-prod`（APAC 區）+ Object R/W token（限定該 bucket）+ 30 天 lifecycle rule 已開好。**Bonus：另外加 DS918 SMB 為第二異地（rclone smb backend），三點異地組合：本機 + R2 + DS918**。**完成於 2026-05-09**。 | [x] |
| R36-6 | **db-backup container 加 rclone** | Dockerfile 加 `rclone ca-certificates`，entrypoint 自動 link `secrets/rclone.conf` 到 `~/.config/rclone/rclone.conf` + 預先驗證每個 remote 設定存在。**完成於 commit `eab076d4`**。 | [x] |
| R36-7 | **`pg_backup.sh` 加 rclone 雙 remote 上傳步驟** | 加密完成後 `rclone copy` 到 `BACKUP_RCLONE_REMOTES` 內所有 remote（年/月 prefix），任何失敗 → script exit 1 → R36-3 alert 觸發。**完成於 commit `eab076d4`**。 | [x] |
| R36-8 | **R2 lifecycle rule：30 天自動刪舊** | R2 console → bucket settings → lifecycle rules → `delete-after-30d`，全 bucket prefix。**完成於 2026-05-09 Step 2**。 | [x] |

### R36-C. 災難復原演練（P1，建置完隔週）

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R36-9 | **首次 restore drill** | 2026-05-09 完整跑通：R2 下載 → SHA256 verify ✅ → GPG 解密（USB G: 私鑰）→ pg_restore 到隔離 postgres 容器 → row-count 比對 5 表全相符（animals=147 / users=18 / electronic_signatures=12 / protocols=11 / user_activity_logs=397）。RTO ~10 分鐘（首次手動，自動化後估 < 30 分）。紀錄於 `docs/runbooks/dr-drill-records.md` §5。 | [x] |
| R36-10 | **DR runbook 文件化** | `docs/runbooks/backup-setup.md` + `dr-drill-records.md` §5 已有；**2026-05-13 補完 `docs/runbooks/cold-start.md`** — 筆電完全掛時的 9 step 恢復 SOP（NAS Docker setup + DB restore + uploads / cloudflare tunnel reroute / DNS 切換 / Word daemon 替代方案）。 | [x] 2026-05-13 |

### R36-D. 自建伺服器遷移規劃（P2，2026-07-24 改方向：獨立主機而非 NAS）

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R36-11 | **採購全新 Tower 企業伺服器**（原「採購 Synology DS925+」，2026-07-24 改方向） | **2026-07-24 使用者裁定**：不買 NAS 跑 prod，改買獨立 Linux 伺服器；NAS（DS918 + DS923+）純備份鏈。規格：全新 Tower（Dell PowerEdge T150 / HPE ProLiant MicroServer Gen11 同級）+ iDRAC/iLO 遠端管理 + 原廠到府保固 + 32GB ECC + 2 顆 SSD 硬體 RAID1。使用者裁定「價格不是問題，問題是怎麼維護」→ 選新機+保固而非二手。OS：Ubuntu Server 24.04 LTS。舊版 DS925+ 規格決策（2026-05-08）與 deferred 裁定（2026-05-09）作廢，詳見 `project_local_server_migration` 記憶條目。 | [ ] |
| R36-12 | **伺服器遷移 SOP 與切換窗口** | 已改寫為 `docs/deploy/server-migration/migration-sop.md`（原 nas-migration/ 已 rename + 內容重寫，移除 DSM/Container Manager/Watchtower 假設）。切換流程：(1) 新伺服器起 stack 並監控 24h (2) 同步 prod DB pg_dump → restore (3) Cloudflare Tunnel 改指向新伺服器 (4) 觀察 1-2 週 (5) 筆電 stack 改 dev/cold spare。**切換窗口必選週末凌晨**（使用者最少）。備份路由不變：新伺服器 rclone 只推 DS918，DS918→DS923+ 是 NAS 端另設 DSM 排程同步（跟本 SOP 無關）。Watchtower 不帶到新機，改手動 `docker compose build+up -d`。 | [ ] |
| R36-13 | **筆電轉純 dev 角色** | 新伺服器切換完成後筆電不再跑 prod。**2026-07-24 使用者裁定**：先當 cold spare 留著，新機穩定跑 1-2 週 + 備份循環驗證過一輪後再處理，不急著清空或拆機。docker-compose 屆時可改用 `docker-compose.dev.yml` profile 跑簡化 stack。風險解除：Windows update / 出門帶筆電 / 散熱降頻 / 電池膨脹 / 誤操作影響 prod 全消失。 | [ ] |

### R36 對應 memory

- `project_prod_on_laptop.md`（2026-05-08 新增）→ prod 跑在筆電上、observability 不可停的根本背景
- `feedback_no_plaintext_passwords.md` → R2 credentials 必走 secrets/ + docker secrets
- `feedback_integration_branch_strategy.md` → 本輪因屬基建單元，不走 integration branch；每個 R36-x 獨立 PR
- `project_local_server_migration.md`（2026-07-24 新增）→ 自建伺服器規格/OS/RAID1/Watchtower 取捨/雙 NAS 備份路由的完整討論記錄

### R36 風險與停機規則

- **R36-1~4 完成才能繼續其他工作**：目前 prod 在裸奔，無 backup 可還原。
- **R36-9 restore drill 必須在 R36-7 上線後 1 週內做**：未驗證的備份等於沒備份。
- **R36-11 採購前必停**：實際下單伺服器型號/配置前，先讓使用者對過報價（Dell/HPE 台灣走報價制，未公開牌價）再下單。
- **R36-12 伺服器切換期間**：必須通知使用者 + 預估 downtime（建議 ≤30 分鐘），切換 SOP 走完才視為完成。

---

## 📄 R39 — 獸醫巡場報告完整重設計（2026-05-10 立案，2026-05-10 擴大範圍）

> **演進**：原本只是「HTML→docx wire-up」（~3-4h），與使用者討論後升級為**完整 UX 重設計**：
> 1. 照片掛 entry-level（每筆觀察直接搭配照片，臨床上更合理）
> 2. 一步流程（auto-save draft，使用者完全感受不到「先存後傳」兩步）
> 3. 手機 / 平板原生支援（巡場現場直接拍照上傳）
> 4. 順便完成原本的 HTML→docx 收斂
>
> **預估**：~8.5h（schema 30m + backend 1.5h + frontend 2h + docx 範本 2h + GC scheduler 0.5h + draft state 1.5h + 測試 1h）
>
> **影響面**：
> - 巡場報告是**獸醫日常使用最頻繁的功能**之一，UX 改動影響大但獲益也大
> - 完成後 Gotenberg 沒有專用 HTML caller（仍保留作 daemon failure fallback）
> - 既有 report-level photos 不遷移（保留共存，新功能加 entry-level）

### 設計決策（2026-05-10 與使用者敲定）

| # | 決策 |
|---|------|
| 1 | 照片**同時掛 report 和 entry 兩種** — entry-level 個別豬照、report-level 環境照 |
| 2 | **既有 report-level photos 不遷移** — 量小、共存即可 |
| 3 | **4 類 entry 都能掛照片** — 防疫類也可能要拍消毒前後 |
| 4 | **一步流程（auto-save draft）** — 使用者感受不到兩步；後端仍分階段 |
| 5 | **DOCX：每 entry 列下方接該 entry 照片**（非報表末尾統一一節） |
| 6 | **iPhone HEIC** 走 iOS Safari 自動轉 JPEG（不寫額外 backend logic） |
| 7 | **前端壓縮**：長邊 ≤ 2000px、JPEG q=0.85（≈1MB）|
| 8 | **EXIF**：rotate-then-strip（前端壓縮時處理）|

### R39-A. Schema migration（30m）

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R39-1 | **migration 059_vet_patrol_entry_photos.sql** | 新增 `vet_patrol_entry_photos` 表（mirror `vet_patrol_photos` schema 但 FK → `vet_patrol_entries.id`，ON DELETE CASCADE）；既有 `vet_patrol_reports.status` 已有 default 'draft'，**backfill UPDATE 全部既有報告 → 'submitted'**（之前未用 status）；加 `submitted_at TIMESTAMPTZ NULL` + CHECK constraint `status IN ('draft','submitted')` + partial index 給 GC scan | [x] |
| R39-2 | **down migration** | drop entry_photos table + drop submitted_at 欄位 | [x] |

### R39-B. Backend：entry photos + draft state（1.5h）

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R39-3 | **`VetPatrolEntryPhoto` 模型 + repository fns** | mirror `VetPatrolPhoto`，FK 改 `entry_id`。Service 層加 `list_entry_photos` / `insert_entry_photo` / `update_entry_photo_caption` / `delete_entry_photo` | [x] |
| R39-4 | **handlers**：`POST /vet-patrol-entries/{entry_id}/photos`（upload）、`GET /vet-patrol-entries/{entry_id}/photos`、`PUT /vet-patrol-entry-photos/{id}`（caption）、`DELETE /vet-patrol-entry-photos/{id}` | mirror 既有 photo handlers | [x] |
| R39-5 | **`POST /vet-patrol-reports/{id}/submit`** | 將 status 從 'draft' → 'submitted'，寫 `submitted_at = NOW()`、寫 audit `VET_PATROL_REPORT_SUBMITTED`；status 已是 submitted 則拒絕 | [x] |
| R39-6 | **`update` service 行為調整** | draft → draft 不寫 audit（避免 auto-save 噪音）；submitted → submitted 仍寫 audit；只在 status transition 時寫一次。**重點**：update 重寫為 diff-based（entries 帶 id → UPDATE in place、無 id → INSERT、缺 id → DELETE CASCADE photos），原 DELETE+re-INSERT pattern 會清掉 entry photos | [x] |
| R39-7 | **`list` 加 status filter** | query param `?status=draft\|submitted\|all`，default `submitted`（一般使用者不看自己的草稿） | [x] |

### R39-C. Backend：draft GC scheduler（0.5h）

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R39-8 | **scheduler.rs 新增 `cleanup_stale_drafts` job** | 每日 03:30 UTC 執行（避開 03:00 retention enforcer）；DELETE FROM vet_patrol_reports WHERE status='draft' AND updated_at < NOW() - INTERVAL '7 days' AND deleted_at IS NULL；ON DELETE CASCADE 連帶清掉 entries / entry_photos / report photos | [x] |

### R39-D. Frontend：dialog UX 重寫（2h）

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R39-9 | **auto-save 機制** | hasInteracted 旗標 + 800ms debounce → POST then PUT；server 回傳 entry id 回填 local state | [x] |
| R39-10 | **「儲存報告」按鈕語意改為「送出報告」** | submitMutation: flush 最新內容 + POST `/submit`；按鈕 disabled until 至少 1 筆有內容的 entry | [x] |
| R39-11 | **取消邏輯**：簡化為使用者按「關閉」直接收 dialog | onClose 時 draft 留待下次（GC 會清過期 draft，scheduler 已上線） | [x] |
| R39-12 | **每行 entry 下方加「上傳照片」+ 縮圖列** | entry-level upload 按鈕 + 縮圖卡 + caption inline 編輯 + 刪除 | [x] |
| R39-13 | **手機 / 平板**：`<input type="file" accept="image/*" capture="environment" multiple>` | 後鏡頭直拍 + 一次多張 | [x] |
| R39-14 | **前端壓縮**：自寫 canvas（無新 npm dep） | `lib/imageCompress.ts` 用 createImageBitmap({imageOrientation:'from-image'}) → canvas re-encode JPEG q=0.85 → strip EXIF；長邊 2000px | [x] |
| R39-15 | **保留 report-level photos 區塊** | 改名「整體環境照（選填）」+ 同樣支援 mobile + 壓縮 | [x] |

### R39-E. Frontend：草稿列表（0.5h，併入 R39-D 預估）

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R39-16 | ~~報告列表頁加 tab：「已送出」 / 「我的草稿」~~ | **2026-05-10 N/A**：前端目前沒有獨立的「巡場報告列表頁」（dialog 直接從動物管理頁開啟）。Backend `?status=...` filter 已就緒，待未來新增列表頁時即可用 | [→ N/A] |

### R39-F. pdf-service：schema + adapter + DOCX 範本（2h + 2h）

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R39-17 | **`pdf-service/app/schemas/vet_patrol_report.py`** | VetPatrolReportPayload + EntryRow + PhotoEntry；report-level photos 命名為 `photos`（非 report_photos）對齊現有範本根層 block | [x] |
| R39-18 | **adapter `vet_patrol_report.py`** | from_report_data + build_render_context（解 data URL → BytesIO → InlineImage Mm(70)）；接受 photos 與 report_photos 兩種輸入欄位名 | [x] |
| R39-19 | **註冊 `DOCX_REGISTRY['vet_patrol_report']`** | template `vet_patrol.docx`、filename `試驗豬場巡場報告_<YYYYMMDD>.<ext>`；key 與 XLSX_REGISTRY['vet_patrol'] 區分 | [x] |
| R39-20 | **DOCX 範本 nested loop** | **2026-05-10 deferred**：現有範本 16 placeholders 已涵蓋 text fields + 根層 `{%p for pair in photos \| batch(2) %}`（report-level 整體環境照）。entry-level photos 待範本擴充加入 `{%p for pair in cat.photos \| batch(2) %}` nested loop 後生效。本 commit 只做 wire-up — 照片資料已存 DB、API 已能傳 InlineImage、範本擴充由 vet/QA 後續手動加 block（或寫 python-docx 程式化方案）。待加 R39-D1 子項。 | [→ R39-D1] |
| R39-D1 | **vet/QA 在 Word 內加 entry photo nested block** | 對 4 個 categories 表格列各加 `{%p for pair in cat.photos \| batch(2) %}{{ pair[0].image }} {{ pair[0].caption }} {{ pair[1].image }} {{ pair[1].caption }}{%p endfor %}`。完成後 entry photos 即出現在 PDF。 | [ ] |
| R39-D2 | **巡場報告 PDF 格式整體完善**（2026-05-12 新增） | 2026-05-27 使用者驗收 PDF 輸出格式已足夠完整，不需進一步調整。系統走 HTML→WeasyPrint→PDF 路徑，不需 Word 版。 | [x] 2026-05-27 |
| R39-21 | ~~單元測試~~ | **deferred**：MVP 上線優先；vet/QA 加範本 block 後（R39-D1）一併寫測試 | [→ R39-D1] |

### R39-G. Backend handler 切換 + 收尾（1h）

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R39-22 | **`export_vet_patrol_report_pdf` 切到 pdf-service** | 切到 `state.pdf_service.render_vet_patrol_report_from_report_data`；payload 帶 categories[].photos + root photos | [x] |
| R39-23 | **加 `?inline=1` query** | 對齊 R35-4 / vet_patrol_v3 pattern | [x] |
| R39-24 | **視覺驗證**：產舊 HTML 版 + 新 docx 版各一份 PDF 對比 | **deferred 至 R39-D1**：須先讓 vet/QA 加範本 nested block，否則 entry photos 不會渲染，無法等價對比；ship 期間舊 HTML 路徑已砍，回 fallback 困難 — 接受短期視覺差異等 R39-D1 修復 | [→ R39-D1] |
| R39-25 | **砍 `vet_patrol_report.html`** + Tera ctx 構造 code | TemplateService 整類 + base.css + html 都砍乾淨（commit `2d34df41`） | [x] |
| R39-26 | **更新 `gotenberg.rs` 註解 fallback-only** | 加 R39 後 backend 已無專用 caller 註解 | [x] |
| R39-27 | **R38-D1 字體驗證**：本範本納入 batch（fixtures/vet_patrol_report.docx.json）| **deferred** 至範本 nested block 加好後再納入 | [→ R39-D1] |

### R39 對應 memory

- `vet_patrol-docx-locked` → **本次需要改範本**（加 nested loop），需 R39 開工後**更新此 memory** 改為 R39 完成後重新 lock
- `r26-service-driven-pattern` → entry photos service 沿用 pattern
- `feedback_no_modify_xlsx_template` → vet_patrol.xlsx 不動（這是欄位狀態表，不同範本）

### R39 與 R32-A8f 關係

R32-A8f 條目過時：原以為「等 vet/QA 加變數」blocked，2026-05-10 確認變數早已加好。但 R39 範圍擴大後，**16 個既有 placeholder 不夠用**（缺 entry-level photos nested loop），R39-20 會重新動範本一次。R32-A8f 標 `[→ R39]` 跳轉。

---

## 💬 R40 — 站內信系統 + R39 deferred refactors（2026-05-10 立案）

> **目標**：(A) 引入 user-to-user 站內信功能；(B) 收尾 R39 PR #363 review 中 6 項 deferred refactor。
>
> **驅動**：使用者要求新增站內信溝通功能。既有 `notifications` 表只支援系統 → user 單向通知（15 種預定義 type），不支援 user-to-user 對話。

### R40-A. 站內信系統（user-to-user messaging）

**決策已確認**（2026-05-10 使用者裁定，詳見 `docs/plans/messaging.md`）：

| # | 決策題 | 結論 |
|---|---|---|
| R40-1 | 誰能寫給誰 | **角色對矩陣**：admin↔ANY、vet↔staffs、vet↔vet、PI↔staffs、staffs↔staffs；vet↔PI / PI↔PI 禁止 |
| R40-2 | 對話結構 | 1-1 + 群組 thread |
| R40-3 | 附件 | 圖片（複用 R39 imageCompress + FileService） |
| R40-4 | 保留期 | 軟刪 30 天 → hard delete + 檔案清除 |
| R40-5 | Realtime | Polling 30s（不做 SSE / WebSocket） |
| R40-6 | 手機推播 | 不做 |
| R40-7 | 管理員 | 全可看 body |
| R40-8 | Email 同步 | 不寄 |

**Role category 對應**（messaging access matrix 內聚 16 個 role 為 4 + 1 external）：

| Category | 含 role codes |
|---|---|
| admin | `admin` |
| pi | `PI`, `STUDY_DIRECTOR` |
| vet | `VET` |
| staffs | `ADMIN_STAFF`, `EXPERIMENT_STAFF`, `INTERN`, `PURCHASING`, `WAREHOUSE_MANAGER`, `EQUIPMENT_MAINTENANCE`, `IACUC_STAFF`, `IACUC_CHAIR`, `QAU`, `REVIEWER` |
| external（無 messaging 權限） | `CLIENT`, `GUEST` |

**Schema design (待決策確定後)**：
- `messages` 表（id, thread_id, sender_id, body, created_at, edited_at?, deleted_at?）
- `message_threads` 表（id, subject, created_by, created_at, last_message_at, type=direct/group）
- `message_thread_participants`（thread_id, user_id, joined_at, last_read_at, role=participant/admin）
- `message_attachments`（message_id, file_path, file_name, mime_type, file_size）— 若 R40-3 選 B 或 C

**可重用既有資源**：
1. **`notifications` 表**（system → user 單向）→ 收訊時觸發 system_alert 通知 + UI badge
2. **`outbox` + `email_adapter`** → 未讀通知 email 推送
3. **`users` 表 + `/hr/staff` endpoint** → 收件人選擇直接複用（同 vet_patrol 陪同人員的 SearchableSelect pattern）
4. **`FileService`** → 附件上傳 / 下載
5. **`AuditService::log_activity_tx`** → 記錄訊息發送（內容部分依 R40-7 決定 redact 程度）
6. **權限系統 + role-based** → R40-1 限制可實作為 service 層 access check
7. **scheduler** → 訊息保留期 GC（同 R39 vet_patrol_draft_gc pattern）
8. **VetPatrolReportDialog auto-save pattern** → 訊息草稿 auto-save 可直接複用
9. **dialog UI patterns**（已有 14 個 dialog 元件可參考）

**估規模（取決於決策）**：
- 最小版（A-A-A-A-A-A-B-A）：~10-15h（schema + service + handlers + dialog UI + 列表 + GC）
- 完整版（A-B-C-D-D-B-B-B）：~30-40h（多 realtime SSE、WebSocket、PWA push、群組對話、附件等）

| # | 項目 | 說明 | 狀態 |
|---|---|---|---|
| R40-9 | **設計文件 `docs/plans/messaging.md`** | schema / API / role matrix / scheduler GC / 工時拆分 | [x] |
| R40-10 | **migration 060_messaging.sql** | message_threads + message_thread_participants + messages + message_attachments + last_message_at trigger | [x] |
| R40-11 | **backend services/messaging/**：mod / thread / message / attachment / access | 5 個檔案 + 4 unit tests for access matrix | [x] |
| R40-12 | **backend handlers + routes** | 9 endpoints（list / create / read / send / mark_read / delete / upload / download / unread_count）| [x] |
| R40-13 | **frontend MessagingPage**（self-contained，含 ThreadList / ThreadView / MessageBubble / NewThreadDialog） | TanStack Query 30s polling、Ctrl+Enter 送出、附件壓縮 | [x] |
| R40-14 | **frontend polling unread**（內建 refetchInterval=30s，無需獨立 hook） | TanStack refetchInterval 30s | [x] |
| R40-15a | **scheduler `messaging_gc` job**（每日 03:40 UTC） | 30 天前軟刪 messages → batch DELETE + unlink attachments 檔案 | [x] |
| R40-16a | **permission seed + EXPORT_TABLE_ORDER + nav** | `messaging.send` 給 admin/PI/STUDY_DIRECTOR/VET/staffs roles；`messaging.admin_view` 給 admin；4 表加進 IDXF backup；route `/messaging` 加 RequirePermission gate | [x] |
| R40-17a | **Sidebar 加「💬 站內信」連結** | 2026-05-10 完成（commit `d178cee5`）：sidebarNavConfig 加 messaging 條目，dashboard 之後；DEFAULT_NAV_ORDER 同步插入。Unread badge 暫未實作（low value，使用者進去就看到 thread 列表的 unread count）| [x] |
| R40-18a | **多輪 UX 修法**（2026-05-10 prod deploy 後使用者實測迭代）| commit `3295a4e8` URL `/v1` 前綴 + commit `d178cee5` NewThreadDialog 放大+附件支援 + commit `d9bf2f86`~`4f8dc651` 5 commits composer 釘底（最終 absolute bottom-0）+ commit `66b708da` 邊距對齊 + commit `4f8dc651` 高度 6rem | [x] |
| R40-19a | **收件人 picker 改用 access-matrix endpoint**（2026-05-29，PR #523）| 原 NewThreadDialog 借用 `/hr/staff`（只回 EXPERIMENT_STAFF）導致選不到 admin；新增 `GET /messages/recipients`（`access::list_allowed_recipients`，依 `messaging_pair_allowed` 過濾）+ 前端改用之。修正「無法寄站內信給 admin」| [x] |
| R40-20a | **follow-up：多 role per-role-pair access 判定** | 現行 `user_messaging_category` / `ensure_can_message_all` / `list_allowed_recipients` 將多 role 收斂為最高 rank category；access matrix 非單調，極少數多重身份（如 PI+Staffs 寄 PI）理論誤判。修法須同時改 picker + 守衛為「任一 sender role × 任一 recipient role 允許即可」的 Cartesian 判定並補測試（CodeRabbit PR #523 提出，2026-05-29 裁定另案）| [ ] |

### R40-B. R39 deferred refactors（PR #363 review 中 6 項）

| # | 項目 | 來源 | 狀態 |
|---|---|---|---|
| R40-15 | **`ListReportsQuery` magic strings → enum + serde** | CR #6 | [x] PR #407 |
| R40-16 | **handler post-commit unlink 邏輯下沉到 service**（upload_and_insert_photo / upload_and_insert_entry_photo 進 service；CodeRabbit follow-up：INSERT 用 `... SELECT FROM parent WHERE deleted_at IS NULL` atomic 收 race）| CR #7 | [x] PR #407 |
| R40-17 | **`upload_vet_patrol_*_photo` SQL in handler 抽掉 + dedupe**（`ensure_*_exists` 進 service + `parse_photo_multipart` 私有 helper） | CR #8 | [x] PR #407 |
| R40-18 | **`download_vet_patrol_*_photo` SQL in handler 抽掉**（`find_*_photo_for_download` 進 service + `build_photo_download_response` 共用） | CR #9 | [x] PR #407 |
| R40-19 | **`"draft"` / `"submitted"` magic strings → const/enum**（`pub mod status`，10 處 Rust callsites refactor） | CR #10 | [x] PR #407 |
| R40-20 | **`submit()` report-level access guard**（決策 A：created_by only + admin override，對齊本檔 5 處既有 is_admin pattern；未建 services/access.rs，solo 場景 < 2 instances 不夠 DRY） | CR #12 | [x] PR #407 |

---

## ⚡ R42 — Word COM daemon 效能改善（2026-05-11 立案）

> **背景**：R32 word-convert daemon 已就緒（pre-warm + instance reuse + COM mutex + auto-recovery），但實測 `/health` 5s、`export-pdf` >60s 撞 nginx 預設 60s timeout（已 hot-fix 拉到 180s，但治標不治本）。
> **觀察**：daemon socket 出現 `CLOSE_WAIT` / `FIN_WAIT_2` 殘留，暗示 Word.Application 雖被重用但內部狀態（add-in 載入 / file-format 引擎）每次 `Documents.Open` 仍重新初始化。
> **目標**：把第一次 PDF 匯出時間從 30-60s 降到 < 10s；後續同一範本重複匯出 < 3s。
> **不改方向**：保持 Word COM 為主路徑（fidelity 不可妥協）；不轉 LibreOffice。

| # | 項目 | 說明 | 影響 | 狀態 |
|---|------|------|------|------|
| R42-1 | **Daemon 健診 + log 擴充** | `services/word-convert/server.py` 啟動時記錄 pre-warm 耗時、Word version、載入的 COM add-ins 清單；`/health` response 加 `{startup_at, requests_served, last_convert_ms, word_pid}`；socket leak 監控（記 CLOSE_WAIT 數）。對齊「先量再改」原則 — 沒有 baseline 不做下面項目。 | 觀測 | [x] 2026-05-13 |
| R42-2 | **停用 Word COM add-ins** | Word 啟動時讀 OneDrive / Acrobat / Mendeley / Grammarly 等 add-in，每次 `Documents.Open` 也跑 add-in hooks。daemon 啟動腳本改用 `winword.exe /a /n /m` 或啟動後 `Application.COMAddIns(i).Connect = False` 關所有 add-in。預期 `Documents.Open` 從 20-40s → 5-10s。 | 速度 ★★★ | [x] 2026-05-13 |
| R42-3 | **背景 keep-warm 心跳** | 每 `WORD_CONVERT_KEEPWARM_INTERVAL_S`（預設 180）秒 daemon 內背景 thread 開 inline minimal docx → SaveAs2 PDF → 丟掉。讓 Word file-format 引擎、字型快取、PDF printer driver 不被釋放。走 HTTP loopback 觸發確保走 waitress worker thread（COM STA per-thread）。`/health` 暴露 `keepwarm_runs / keepwarm_last_ok_s_ago / keepwarm_last_error`。 | 速度 ★★ | [x] 2026-05-14 |
| R42-4 | **PDF render cache（content hash）** | `pdf-service/app/render_cache.py`：以 `sha256(input_bytes)` 為 key，daemon 成功路徑寫入 `PDF_RENDER_CACHE_DIR`（預設 `/var/cache/pdf-render`），TTL 24h（`PDF_RENDER_CACHE_TTL_S`），上限 500 MB（`PDF_RENDER_CACHE_MAX_BYTES`）每 100 寫入 best-effort LRU eviction。**只 cache daemon path** — fallback Gotenberg/HTML 不 cache（fidelity 不同）。Prometheus metric `pdf_render_cache_total{result, doc_format}`。 | 速度 ★★ | [x] 2026-05-14 |
| R42-5 | **Daemon 可靠性：watchdog scheduled task**（**TODO pivot** — 原 NSSM service 不可行） | 原計畫 `nssm install ipig-word-convert` 跑 LocalSystem 撞 Office COM Session 0 isolation（0x80080005），不可行。改用 `watchdog.ps1` + `install_watchdog.ps1`：另一個 scheduled task 每 5 分鐘 probe `/health`，task State≠Running 時 `Start-ScheduledTask` 拉回。保留 R44-9 hidden-launcher 架構不變。**需使用者在 Windows host 手動執行 `install_watchdog.ps1`**。 | 可靠性 ★★ | [x] 2026-05-14 |
| R42-6 | **Word/Excel.Application 定期回收** | 每 `WORD_CONVERT_RECYCLE_SECONDS`（預設 6h）或 `WORD_CONVERT_RECYCLE_REQUESTS`（預設 200）後 `_word_app.Quit() + None` 強制重啟 Word / Excel（避免 COM memory leak 累積）。下次 `_get_word_app/_get_excel_app` 觸發 lazy re-init + 重 disable add-ins。`/health` 暴露 `word_age_s / word_count_since_recycle / excel_age_s / excel_count_since_recycle`。 | 穩定性 ★ | [x] 2026-05-14 |
| R42-7 | **前端 UX：明示等待時間 + 防重複觸發** | `VetPatrolReportDialog::handleExportPdf` 已有 `isExporting` lock，但缺視覺等待提示。改顯示「PDF 產製中（首次可能需 30 秒）」+ progress spinner，並把 nginx 180s 寫進註解說明來源。對齊使用者重試 storm 防護。 | UX ★ | [x] 2026-05-14 |
| R42-8 | **Worker pool（多 Word instance）**（後續評估） | R42-2/3/4 落地後若仍不足，考慮 daemon 內 N 個 Word.Application worker（multi-process，避開 COM 單執行緒限制）。記憶體 × N，併發 × N。先量 R42-2~7 效果再決定是否做。 | 吞吐 | [ ] |

---

## 🤖 R43 — AUP AI 預審（OpenAI Codex / GPT-5.x，2026-05-12 立案）

> **目的**：Admin 在 AUP 詳情頁按一鍵「請 AI 看一下」，後端打 OpenAI API 對 AUP 全文做 5 面向體檢，產出意見供 IACUC reviewer 人審時參考（不取代人審）。
> **資料流向**：AUP 文字 + 附件文字內容送 OpenAI cloud（使用者已確認 IRB 能接受）；不送個資 / 病例 / 動物耳號（payload sanitization）。
> **不取代人審**：AI 意見定位為「reviewer 預讀提示」，最終核可仍以 reviewer 投票為準（合規 + 法律責任）。
> **延伸關聯**：R20 AI 預審與秘書標註已 park（R20-9/10 退回率追蹤）；R43 是 R20 的具體落地形式，限縮為 AUP 預審單一場景。

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R43-1 | **AI 服務抽象層 + OpenAI client** | `backend/src/services/ai/mod.rs` 新增 `AIClient` trait + `OpenAIClient` 實作；`Config` 加 `OPENAI_API_KEY`（Docker secret）+ `OPENAI_MODEL`（預設 `gpt-5.1`）+ `OPENAI_BASE_URL`。Trait 抽象讓未來換 local LLM / Anthropic 不動 caller。 | [ ] |
| R43-2 | **AUP payload 組裝 + sanitization** | `services/ai/aup_review.rs::build_prompt(aup_id)` 拉 protocol 主表 + 段落 + 附件文字內容（PDF/DOCX extract），**過濾掉動物耳號 / 個人 email / 內部 ID**（regex + 白名單欄位）。產出 system prompt + user prompt 結構。 | [ ] |
| R43-3 | **5 面向 prompt 設計（rubric-based）** | `prompts/aup_review.md` 定義 system instruction：(a) 3R 原則（Replacement / Reduction / Refinement 各別評分 + 文字依據）；(b) humane endpoint 明確性；(c) 統計設計合理性（樣本數、power analysis）；(d) 作業類別與麻醉/鎮痛方案一致性；(e) 參考文獻齊備度。每面向 1-5 分 + 缺漏指出 + 建議補充。 | [ ] |
| R43-4 | **AI 預審 service + handler** | `services/ai/aup_review.rs::review_aup(aup_id, actor)` 串完整流程：權限檢查（`aup.admin.ai_review` 新權限）→ rate-limit（同 AUP 30 分鐘內最多 3 次）→ build payload → call OpenAI → parse JSON 回應 → 寫 DB（新表 `aup_ai_reviews`）。Handler `POST /aup/:id/ai-review`，回傳 review_id。 | [ ] |
| R43-5 | **Migration 064：`aup_ai_reviews` 表** | 欄位：`id` UUID PK / `aup_id` FK / `model_used` / `prompt_version` / `result_json` JSONB / `tokens_used` / `cost_usd` / `created_by` FK / `created_at` / `error_message` nullable。FK ON DELETE CASCADE。Index on `aup_id, created_at DESC`。下檔 064 在 `migrations/down/` 對齊。 | [ ] |
| R43-6 | **AUP 詳情頁「AI 預審意見」Tab** | `frontend/src/pages/protocols/ProtocolDetailPage.tsx` 加 Tab，顯示歷次 AI 預審結果列表（時間 / 觸發者 / 模型 / 5 面向分數 + 詳細評語）。Admin 看到「請 AI 看一下」按鈕；非 admin 只能看歷史結果。`permission='aup.admin.ai_review'`。 | [ ] |
| R43-7 | **AI 預審 PDF 附錄** | `backend/src/handlers/animal/aup_pdf_export.rs` 既有 PDF 匯出加 `?include_ai_review=1` query；後端拉最新一筆 `aup_ai_reviews`，組裝 5 面向評分表 + 評語 → docxtpl 範本附錄段落 → 與 AUP 本體 PDF 同次輸出。範本 `templates/aup_ai_review.docx` 由 vet/QA 手動建。 | [ ] |
| R43-8 | **Audit log 整合** | `services/ai/aup_review.rs` 寫 audit event `AUP_AI_REVIEW_REQUESTED`（actor / aup_id / model / tokens / cost）。失敗時寫 `AUP_AI_REVIEW_FAILED`（含 error_message）。納入 HMAC chain。 | [ ] |
| R43-9 | **成本守門：rate limit + monthly budget** | `constants.rs::AUP_AI_REVIEW_COOLDOWN_MINUTES = 30`、`AUP_AI_REVIEW_MAX_PER_AUP_PER_DAY = 5`。`OPENAI_MONTHLY_BUDGET_USD` env var 預設 50；超過拒絕新 request + Prometheus alert。每筆 review 記 `tokens_used / cost_usd` 累計。 | [ ] |
| R43-10 | **Prompt 版本化 + 回放** | `prompts/aup_review.md` 加版本號（v1.0.0）。`aup_ai_reviews.prompt_version` 記錄當時版本。修改 rubric 後新版本不覆蓋舊結果，可在 UI 看「v1.0.0 的評語」「v1.1.0 的評語」差異 → 評估 prompt iteration 效果。 | [ ] |
| R43-11 | **退回率關聯（接 R20-9）** | AI 評分 < 3 分的 AUP 跟最終 reviewer 退回率做相關性分析（後續 dashboard）。立案時先把 schema 預留 `aup_ai_reviews.final_outcome` 欄位（nullable enum: `approved / rejected / withdrawn`），AUP 流程結束後回寫。 | [ ] |
| R43-12 | **文件**：`docs/ai/AUP_AI_REVIEW.md` | 涵蓋：政策（reviewer 看 AI 意見前後義務）、prompt 設計依據（3R / IACUC 文獻）、payload sanitization 規範、IRB 同意聲明、月度 cost / token 報告產出方式。 | [ ] |

---

## 🪟 R44 — Word / Excel COM daemon 拆分（2026-05-12 立案）

> **背景**：2026-05-12 vet patrol PDF 預覽失敗事故，根因是 Excel COM 在 host 上崩潰（53s 後回 500），但因 daemon 同 process 跑 Word + Excel，且 `/health` 只測 Word，pdf-service 無法及早偵測 Excel 半殘狀態。
> **現況 hot-fix**：pdf-service 加 5xx fallback → Gotenberg；`DOCX_CONVERTER_TIMEOUT` 從 120s 降到 30s；輸出 fidelity 暫降為 LibreOffice。
> **目標**：把 daemon 拆成兩個獨立 process（不同 port），Excel 崩不影響 Word 服務；各自 health probe；任一邊重啟不中斷另一邊。
> **不改方向**：daemon code 本身不重寫，只透過 env var 控制單 process 跑哪一個 Office app；pdf-service 路由依檔型分流。

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R44-1 | **Daemon `server.py` 加 `ENABLED_OFFICE_APP` env var** | 預設 `both`（向後相容單 daemon 模式）；值為 `word` 時只暴露 `/convert` + 不 init Excel；`excel` 時只暴露 `/convert-xlsx` + 不 init Word。`/health` 同步只測啟用的 app。對應 `services/word-convert/server.py`。 | [x] 2026-05-12 |
| R44-2 | **pdf-service 加 `EXCEL_CONVERT_URL` env var** | `_xlsx_to_pdf_excel_first` 改讀 `EXCEL_CONVERT_URL`；未設則 fallback 到 `WORD_CONVERT_URL`（向後相容）。`docker-compose.yml` pdf-service 區段加 env。 | [x] 2026-05-12 |
| R44-3 | **`install_service.ps1` 改成可參數化 port + app type** | 加 `-Port`、`-AppType (word\|excel)` 參數；scheduled task name 帶後綴（`ipig-word-convert-word` / `ipig-word-convert-excel`）。一次 install 跑兩條 command line 就能起兩個 task。 | [x] 2026-05-12 |
| R44-4 | **Windows host 部署：實際開兩個 task 跑 Word:9100 + Excel:9101** | 跑 `install_service.ps1 -AppType word -Port 9100` 與 `-AppType excel -Port 9101`；確認兩個 task 都 listen 上、`netstat -an \| findstr "9100 9101"` 兩 port 都 LISTENING。**需使用者在 Windows host 手動執行。** | [x] 2026-05-12 |
| R44-9 | **hidden window 啟動 + COM threading fix + /health 自動重連** | 部署過程實測發現三個問題並修：(1) Task Scheduler 跑 `.bat` 會冒 cmd 視窗，使用者誤關 → 整個 process tree 含 Word/Excel COM 被殺；改用 `hidden-launcher.vbs` (`WshShell.Run windowStyle=0`) 包 wrapper.bat。(2) `server.py` main thread `pre-warm` 與 waitress worker thread 跨 thread 用 COM ref → `CoInitialize 尚未被呼叫` 錯誤；移除 pre-warm 改 lazy init（`threads=1` 保證單一 worker thread）。(3) `/health` exception 沒清 cached COM ref，導致 Word/Excel 被外部關掉後永遠 503；對齊 `/convert` 邏輯加 reset。Commit `7aa4b865`。 | [x] 2026-05-12 |
| R44-5 | **驗證隔離**：殺 Excel daemon 不影響 Word | 手動 `Stop-ScheduledTask` Excel daemon → 觸發 vet patrol PDF（xlsx 路徑）→ 確認 pdf-service 503 fallback 到 Gotenberg；同時觸發 AUP PDF 匯出（docx 路徑）→ 應該完全不受影響。Depends on R44-4。 | [ ] |
| R44-6 | **回復 Excel fidelity + 拉長 timeout 回 120s** | R44-1~5 落地、雙 daemon 穩定後，把 `DOCX_CONVERTER_TIMEOUT` 改回 120s（或新增獨立 `EXCEL_CONVERTER_TIMEOUT`），讓 Excel 渲染複雜 xlsx 不被腰斬。 | [ ] |
| R44-7 | **Prometheus dashboard 分 Word / Excel** | `monitoring/grafana/dashboards/pdf-daemons.json` 含 8 個 panel（雙 daemon 路徑分布 / throughput / failure / R45 fallback chain）；`alert_rules.yml` 加 4 條 alert（WordDaemonFallbackHigh / ExcelDaemonFallbackHigh / DaemonFallbackToHtml / DaemonAndHtmlBothFailed）。 | [x] 2026-05-13 |
| R44-8 | **文件**：`services/word-convert/README.md` 補雙 daemon 部署說明 | 涵蓋：env var 對應、scheduled task 命名規則、`/health` 探測方法、Office license 注意事項、隔離驗證 SOP。 | [x] 2026-05-12 |

### R44 風險與停機規則

- **不可逆風險**：低 — env var + scheduled task 設定變更，可隨時還原成單 daemon 模式（`ENABLED_OFFICE_APP=both`、不設 `EXCEL_CONVERT_URL`）。
- **停機規則**：R44-4（host 上實際 install 雙 task）改變 prod 部署狀態，必須使用者明確同意；其餘 code 變更為純可逆，依一般 PR 流程。

### R44 對應 memory

- `word-daemon-already-implemented` — daemon 程式碼已成熟，本任務僅補強隔離；繼續維持「真正 gap 在 host 部署」的判斷。
- `prod-on-laptop` — prod 跑在筆電上，雙 process Office 對單機資源耗用要留意（Word ~150MB + Excel ~200MB idle）。

---

## 📄 R45 — PDF 渲染架構收斂（2026-05-12 立案，2026-05-13 落地）

> **背景**：2026-05-12 vet_patrol xlsx 出現 `_x000a_` 字面渲染 bug（LibreOffice 對 OOXML 換行 escape 處理不一致），暴露 Gotenberg LibreOffice 子路徑 fidelity 與 Word/Excel COM daemon 並行瓶頸兩個結構問題。
> **2026-05-13 R45 final 決策**：GLP 純走 daemon（fail-fast 無 fallback）；非 GLP 三階 fallback daemon → HTML → Gotenberg；daemon 失敗自動 email admin。詳見 [`docs/plans/pdf-r45-final-routing.md`](plans/pdf-r45-final-routing.md)。
> **實際工期**：2 天落地完成（5 phase）。

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R45-1 | **Phase 0 foundation** | `html_renderer.py` + `base.html` + warehouse 第一張落地 | [x] 2026-05-12 |
| R45-2 | **Phase 1 GLP daemon-only 收斂** | 5 GLP endpoint 移除 HTML branch + 4 GLP HTML park 至 `_parked/` + `_xx_to_pdf_xx_first(..., allow_fallback)` 參數 + `DaemonUnavailable` → HTTP 503 | [x] 2026-05-13 |
| R45-3 | **Phase 2 frontend GLP pre-check + email alert** | backend `/api/daemon-health` + outbox email (30 min rate-limit) + frontend `useDaemonHealth` hook + 4 GLP 按鈕 disable when down | [x] 2026-05-13 |
| R45-4 | **Phase 3 非 GLP HTML template + 三階 fallback** | 4 張 HTML template (audit_log/blood_test/medical_record/surgery) + 共用 `base.html`。Non-GLP 路徑：**daemon primary → HTML fallback 1 → Gotenberg fallback 2**。helper `_docx_to_pdf_with_html_fallback` 統一處理 + 後綴標籤 `_after_daemon_fail` / `_after_html_fail`。 | [x] 2026-05-13 |
| R45-5 | **Phase 4 project_medical 批次 zip 並行** | `asyncio.gather + Semaphore(4)` Chromium tab pool；per-animal 三階 fallback；8 隻測試 7.5s（vs daemon sequential ~50s，6.7× 加速）| [x] 2026-05-13 |
| R45-8 | **Backend daemon-fail email alert（非 GLP 路徑）** | backend handler 看 `X-PDF-Renderer` header 含 `_after_daemon_fail` / `_after_html_fail` → `alert_if_renderer_signals_daemon_failure()` → `maybe_alert_daemon_down()` 觸發 admin email（reuse 30 min rate-limit static）。6 個非 GLP export call site 都接 | [x] 2026-05-13 |
| R45-6 | **未來 GLP 升級準備**（park，無 deadline） | `blood_test` / `surgery` / `medical_record` 目前**非 GLP**，未來如升級走 3 步：(1) 指派 `AD-XX-XX-XXX` 編號 (2) HTML template 加 `@top-left { content: "文件編號 AD-..." }` (3) 從 `docs/glp-document-numbers.md` §B 移到 §A。觸發時機：vet/QA 提出受控需求時啟動。 | [ ] |
| R45-7 | **PagedJS TOC 自動頁碼**（park，PoC 計畫已寫）| Chromium 原生不支援 `target-counter()`。**2026-05-13 補完 `docs/plans/r45-7-pagedjs-weasyprint-poc.md`** — 兩條候選路徑（playwright + PagedJS 雙 pass vs 換 WeasyPrint engine）的 PoC 步驟、風險比較、驗收標準。實際 PoC 1-2 天，park 待 trigger（NAS 採購 / vet/QA 要求 GLP HTML / Office license 問題）。 | [ ] |

### R45 final 路由矩陣（revised 2026-05-13）

| 分類 | 文件 | Primary | Fallback 1 | Fallback 2 | daemon fail email |
|---|---|---|---|---|:-:|
| 🔒 GLP | aup_protocol / review_reply / review_result / vet_patrol_report (docx) | Word daemon | 無（503）| n/a | ✅（前端 pre-check）|
| 🔒 GLP | vet_patrol_template (xlsx) | Excel daemon | 無（503）| n/a | ✅（前端 pre-check）|
| 非 GLP | warehouse / audit_log / blood_test / medical_record / surgery | **Word daemon** | HTML/Chromium | Gotenberg LibreOffice | ✅（renderer header 後綴）|
| 非 GLP | project_medical（批次 zip）| **Word daemon**（per-animal）| HTML/Chromium 並行 | Gotenberg | ✅（任一 animal fallback 觸發）|

### X-PDF-Renderer label 體系

| Label | 意義 | 前端 toast | Backend email |
|---|---|:-:|:-:|
| `word_daemon` | docx daemon 成功 | ❌ | ❌ |
| `excel_daemon` | xlsx daemon 成功 | ❌ | ❌ |
| `chromium_after_daemon_fail` | daemon 掛了，HTML 接力 | ✅「HTML 備援」 | ✅ |
| `gotenberg_after_html_fail` | daemon + HTML 都掛，Gotenberg 兜底 | ✅「備援渲染器」 | ✅ |
| `gotenberg_fallback` | legacy 標籤（舊路徑兼容）| ✅ | ❌ |
| `gotenberg_only` | dev 環境，daemon 未配置 | ❌ | ❌ |

### R45 風險與停機規則

- **不可逆風險**：低 — HTML template 新增不動既有 docx 路徑；每個 phase 完成 user 簽收才進下個 phase。
- **停機規則**：
  - Phase 0 demo 完成 **必停**，由 user 確認視覺方向再進 Phase 1
  - Phase 1 結束 **必停**，user 簽收 4 張 🟢 報表 fidelity 後再進 Phase 2
  - Phase 3 AUP PoC 結束 **必停**，user 判定是否完整遷移
- **不主動推進 R45-6**：等使用者明確提出 GLP 升級需求，避免無謂的編號指派 + template 重做。

### R45 對應 memory

- `vet_patrol-template-locked` — xlsx 鎖檔規則，現已放寬允許 surgical header/footer 修補；HTML 遷移後該 template 角色弱化（只剩 .xlsx 下載用途）。
- `vet_patrol-docx-locked` — docx 定稿不程式化修改；HTML 版本為**新增 template** 不動原 docx。
- `prod-on-laptop` — Chromium 比 LibreOffice 輕量；HTML 路徑對筆電 prod 友善。
- `word-daemon-already-implemented` — daemon 保留作 .docx 下載 + AUP fidelity safety net，不退役。

---

## 🧪 R53 — 犧牲採樣「多採樣品」內部記錄 + 每週豬隻病歷彙整報表（2026-05-15 立案）

> **背景**：使用者提出兩個關聯需求：
> 1. **多採樣品的內部記錄**：豬隻在計畫案結案安樂死時，獸醫**將會被廢棄處理的組織/血液再利用**給其他研究需求方。這是**廢棄物再利用，不是奪取 PI 權利**。紀錄為內部稽核用，PI 看不到去向。
> 2. **每週豬隻病歷彙整報表**：所有豬隻醫療事件（治療、投藥、手術、觀察紀錄等）能彙整成週報表，可依耳號 / 計畫案 / 時間 AND 篩選 + 匯出 Excel + PDF。

### R53 規格決策（2026-05-15 與使用者敲定 + 同日 follow-up）

**核心框架**：廢棄物再利用（**byproduct reuse**），非 PI 資產轉移。豬隻計畫結案 → 安樂死 → 組織/血液本將焚化廢棄；多採只是把廢棄物拿去其他用途，PI 計畫案 deliverables 不受影響，故 PI 看不到去向 = 正常 lifecycle，不洩漏。

- **R53-A 多採樣品**：掛在既有 euthanasia 流程下，新建 `euthanasia_byproduct_samples` 子表（命名對齊「廢棄物再利用」框架）
- **可見性**：獸醫 / QAU / 系統管理員看得到；**PI audit log 範圍限縮為「研究內容相關事件」，廢棄物去向事件對 PI 隱形**（R53-A 加 audit entity_type 黑名單 to PI 視角）
- **欄位**：豬隻 id（FK to animals.id，耳號不變動所以用 id stable key）、採樣日期、來源計畫（FK to protocols.id）、採樣內容（自由文字）、需求方（自由文字 or FK to users.id）、採樣者（FK to users.id, ActorContext::User）
- **R53-B 週報表**：篩選 AND（耳號 ∩ 計畫案 ∩ 時間區間），匯出 Excel + PDF 兩種
- **病歷涵蓋範圍**：**R53-7 設計階段使用者會提供現有範本參考**，依範本盤點所有「醫療事件」表

### R53-A. 多採樣品內部記錄

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R53-1 | Migration：`euthanasia_byproduct_samples` 表 | 2026-05-17 落地：`066_euthanasia_byproduct_samples.sql` — euthanasia_id / animal_id / source_protocol_id 三個 FK NOT NULL；requester 二選一（`requester_user_id` UUID FK 或 `requester_text` 自由文字，CHECK constraint 強制至少一）；soft delete via `deleted_at`；3 個 partial index 過濾 deleted。data_export `EXPORT_TABLE_ORDER` 同步加入。 | [x] |
| R53-2 | Permission：`animal.byproduct_sample.view` + `animal.byproduct_sample.write` | 2026-05-17 落地：`startup/permissions.rs` 兩個權限 + grant VET (view+write) / QAU (view only, QAU 為唯讀單位) / admin (view+write)。PI / GUEST 無權限（配合 R53-6 audit blacklist）。 | [x] |
| R53-3 | Service：`ByproductSampleService` | 2026-05-17 落地：`services/animal/byproduct_sample.rs` — create / update / delete (soft) / get / list_by_euthanasia / list_by_animal / list_by_protocol；Service-driven audit pattern 對齊 R26 (single tx + DataDiff + log_activity_tx)；`actor.require_user()` 強制；validate_requester() 二選一檢查；ensure_fk_exists_tx() 給乾淨 NotFound 訊息；5 個 unit tests 通過。 | [x] |
| R53-4 | Handler：`/api/v1/euthanasia/{id}/byproduct-samples` 系列 | 2026-05-17 落地：`handlers/animal/byproduct_sample.rs` 7 個 handler（create / list_by_euthanasia / list_by_animal / list_by_protocol / get / update / delete）；`require_permission!(animal.byproduct_sample.{view,write})`；URL 設計 path-driven（euthanasia_id 走 path，body 不重複）；註冊在 `routes/animal.rs`（4 個 base path）；新增 `tests/api_byproduct_samples.rs` 9 條 integration test（401 / 403 RBAC / 200 / 404 / 400 全 cover，PASS）；service `create()` 拆 `insert_byproduct_sample_tx` + `audit_create_tx` private helpers（≤50 行門檻）。 | [x] |
| R53-5 | Frontend：euthanasia 詳情頁底部 collapsible「廢棄物再利用紀錄」區塊 | 2026-05-17 落地：`lib/api/byproductSample.ts`（TS 型別 + axios client）+ `components/animal/ByproductSamplesPanel.tsx`（collapsible，僅 `hasPermission('animal.byproduct_sample.view')` 渲染）+ `components/animal/ByproductSampleDialog.tsx`（4 欄表單 + requester internal/external radio）；掛在 `AnimalDetailPage.tsx` 底部。Follow-up：euthanasiaId / sourceProtocolId 自動 wire（目前 null → Add 按鈕 disabled，view-only 模式）。 | [x] |
| R53-6 | Audit entity_type 黑名單（PI 視角不顯示廢棄物去向事件） | 2026-05-17 落地：`services/audit.rs` 新增 `AUDIT_ENTITY_BLACKLIST = &["byproduct_sample"]` 常數；`list_activities` + `export_activities` SQL 加 `entity_type <> ALL(blacklist)` 過濾。採全 viewer 一致策略（admin / VET / QAU 也看不到），避免「忘記檢查 viewer role」bug — admin 稽核走 `/euthanasia/:id/byproduct-samples` API。Audit row 本身仍寫入 user_activity_logs（HMAC chain 不破），只是 list/export endpoint 過濾。新增 `tests/api_audit_blacklist.rs` 2 條 integration test PASS。 | [x] |

### R53-C. 財務性質補強（2026-05-17 立案）

> **背景**：使用者於 R53-A code review 過程明確指出 byproduct samples **不只是 GLP 紀錄、還是財務紀錄**（樣品給其他研究方時要算錢）。對應需求變更：

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R53-13 | **Update lock + admin 簽核 gate** | byproduct sample 原則上**不可修改**；要改需 (a) 完整 audit log（已 done in R53-3）(b) admin 電子簽章。對齊 R30-27 / GLP 21 CFR §11.10。實作：service `update()` 與 `delete()` 加 signature gate（同 amendment workflow），handler 接受 `signature_payload`；無簽章直接 403。**Defer**: 等簽章 dialog 套件規格定 + R30-27b prod cutover 後啟動 | [ ] |
| R53-14 | **Requester schema 分機構 / 聯絡人雙層 + billing 欄位** | 2026-05-17 落地：migration 067 — DROP `requester_text`，ADD `requester_org_name` / `requester_contact_name`（CHECK：FK 或兩欄都非空）+ billing 三欄 `special_equipment_used` / `work_started_at` / `work_ended_at`（CHECK：兩端都有值時 end >= start）。Service `validate_requester` 改三參數，新增 `validate_work_time`；INSERT / UPDATE SQL 全 cover 8 個新欄位；12 個 unit tests + 4 個新 integration test（only_org / only_contact / inverted_work_time 各回 400）PASS。R53-1 同日上線無 prod 資料需 backfill。**Frontend dialog 5 個欄位 follow-up 列為 R53-14b（defer，等 R53-15 報表規格敲定一起做）**。 | [x] |
| R53-15 | **byproduct samples 月結列表報表（交負責人算錢）** | 2026-05-17 使用者澄清：**不需要費用標準，只需要列出項目，交給公司負責人算錢**。欄位：`時間` (sampled_at) / `案子` (protocols.iacuc_no via source_protocol_id) / `需求客戶` (requester_org_name + requester_contact_name 雙層，per R53-14) / `實作項目` (sample_content) / `記錄者` (collector_id → display name)。Filter：時間區間 + （選）案子 / 機構。輸出 .xlsx（openpyxl 直接寫，不依賴 daemon）+ .pdf（print-pdf）。Permission：`animal.byproduct_sample.view`（PI 不見、admin / VET / QAU 可見）。**依賴**：R53-14（需 org / contact 兩層）。 | [ ] |

### R53-B. 每週豬隻病歷彙整報表

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R53-7 | **設計階段**：依使用者提供範本盤點所有「醫療事件」表 | 2026-05-17 MVP 落地：用 inline service / SQL comments 文字化設計決策。**MVP 範圍**只 UNION `animal_observations` 一表（最常見的日常醫療事件）。其他來源表（surgeries / vet_patrol_entries / care_medication_records / vaccinations / blood_test / sudden_deaths / euthanasia 流程事件）待使用者提供現有週報範本後依範本反推、再追加 UNION 子查詢。timeline event 統一 struct：`{ animal_id, ear_tag, iacuc_no, event_date, event_type, summary, details, actor_name, source_id, created_at }`。 | [x] |
| R53-8 | Service：`AnimalMedicalReportService::weekly_report(filter)` | 2026-05-17 落地：`services/animal_medical_report.rs` — filter = `{ animal_ear_tags?, protocol_ids?, start_date?, end_date? }` AND 邏輯；SQL JOIN protocols ON iacuc_no；LIMIT 5000；ORDER BY event_date DESC, created_at DESC；1 unit test PASS。 | [x] |
| R53-9 | Handler：`POST /api/v1/reports/animal-medical/weekly` | 2026-05-17 落地：`handlers/animal_medical_report.rs` — `require_permission!(animal.record.view)`（PI 角色擁有，GUEST 不帶）；route 註冊於 `routes/report.rs`；3 條 integration test PASS (401 / 200 empty / filter shape)。 | [x] |
| R53-10 | Excel 匯出 | 2026-05-26 落地：openpyxl 10 欄 xlsx，走 print-pdf daemon `/render-xlsx/weekly-medical-report`。 | [x] |
| R53-10b | 週報加手術/血檢/轉移 UNION | 2026-05-27 落地：SQL 四表 UNION ALL（observations + surgeries + blood_tests + transfers completed），前端加類別欄位顯示。 | [x] |
| R53-11 | PDF 匯出 | 2026-05-27 落地：橫式 A4 WeasyPrint HTML 模板，走 print-pdf daemon `/render-pdf/weekly-medical-report`。前端加 PDF 下載按鈕。 | [x] |
| R53-12 | Frontend：報表中心新增「豬隻病歷週報」入口 | 三維度 filter form + 預覽 + 匯出 Excel / PDF 按鈕；guest demo 唯讀。**Defer**：API 已上線可先用 curl / Postman 測 contract，UI 等使用者體驗 contract 後再做 | [ ] |

### R53 風險與停機規則（2026-05-15 follow-up 後 ✅ unblocked）

- **🟢 GLP 合規**：framework 為「廢棄物再利用」（byproduct reuse）而非「資產轉移」— 結案豬隻組織/血液本將焚化，多採只是廢棄物的另一去向。PI 計畫案 deliverables 不受影響。仍建議寫一份內部 SOP（廢棄物再利用作業辦法）讓 vet 簽核+ IACUC 知會，但非 blocker
- **🟢 Audit log 洩漏**：使用者明確表達「PI audit log 只關係到他的研究內容、不關係到廢棄物去向」→ entity_type 黑名單方案落實此 policy（R53-6）
- **🟢 耳號穩定**：使用者明確表達「豬隻耳號不太可能變動」→ 用 animal.id 主鍵即可，不需歷史 tooltip 設計
- **🟡 R53-7 涵蓋範圍**：使用者會提供現有範本參考；設計階段同步盤點 + 釐清，定案才往下走
- **🟢 整合測試**：R53-A 涉及 permission + service-driven audit + entity_type 黑名單，整合測試需 cover「PI 視角空、vet 視角有」兩條路徑

### R53 對應 memory

- 多採流程觸發路徑：`xenotransplantation-vet` 補強（一隻一隻照顧研究豬的 vet 工作流程的一部分）
- PDF 路由：R45 final 路由矩陣（daemon-only for GLP）
- Service-driven audit：R26 pattern（已定型）

### R53 預估

- R53-A：~8h（migration 1h + service 2h + handler 1h + frontend 2h + PDF redact 2h）
- R53-B：~12h（設計 2h + service 3h + handler 1h + Excel 範本 2h + PDF 範本 2h + frontend 2h）
- 合計 ~20h，**先做 R53-A**（範圍清楚），R53-B 等 R53-7 設計階段定案再啟動

---

## ☁️ R56 — AWS Migration（prod-on-laptop → AWS hybrid，2026-05-15 立案）

> **詳細計畫**：[`docs/plans/r56-aws-migration.md`](plans/r56-aws-migration.md)
> **目標**：將 prod 從筆電遷移至 AWS hybrid（Ubuntu EC2 docker + Windows EC2 Office daemon + RDS Postgres + S3 + ECR + GH Actions OIDC）
> **動機**：solo 玩具 → prod-grade reliability / 筆電要拿走 / Cloudflare Tunnel 依賴筆電不可靠 / 對外品牌化
> **月費**：~NT$5,000/mo（5 年 TCO ~NT$320,000）
> **工時**：142h 預估 + contingency × 1.3 = ~180-200h，日曆 ~3 個月

### Phase 0-10 概覽

| Phase | 主題 | 預估 h | 狀態 |
|---|---|---|---|
| R56-0 | AWS Account + Foundation（VPC / IAM / ACM）| 10 | [ ] |
| R56-1 | ECR + GH Actions OIDC（push pipeline）| 15 | [ ] |
| R56-2 | Windows EC2 + Office LTSC + Word/Excel daemon | 25 | [ ] |
| R56-3 | RDS Postgres（migration + multi-AZ）| 12 | [ ] |
| R56-4a | Backend-only Ubuntu EC2 docker stack（移除 web container；nginx 改為 reverse-proxy + security）| 15 | [ ] |
| R56-4b | **Frontend S3 + CloudFront**（vite build → S3 sync + CloudFront CDN，OAC origin protection）| 15 | [ ] |
| R56-4c | **CORS + Cookie pivot**（前後端跨子域名；SameSite=None + Secure；CSRF revalidate）| 10 | [ ] |
| R56-5 | S3（uploads / db-backups / audit-archive）| 10 | [ ] |
| R56-6 | DNS + Ingress（Cloudflare proxy → ALB）| 8 | [ ] |
| R56-7 | Observability migration（保留 self-hosted + CloudWatch infra alarm）| 12 | [ ] |
| R56-8 | GH Actions Deploy automation（SSM Run Command）| 10 | [ ] |
| R56-9 | Cutover（maintenance window + smoke + 48h watch）| 15 | [ ] |
| R56-10 | Decommission 筆電 prod | 5 | [ ] |

### R56 對應 memory

- [[prod-on-laptop]] → 完成後改為 `prod-on-aws`
- [[no-self-imposed-limits]] → docker exec 改 SSM
- [[nas-setup]] → DS923+ 從 hot backup target 變 cold backup
- [[word-daemon-already-implemented]] → daemon code 不動，host 從筆電變 Windows EC2
- R37 `secrets/*` → AWS Secrets Manager（R56-4-5）
- R51 watcher → 廢案（GH Actions SSM Run Command 取代）
- R45 GLP daemon-only 路由 → 維持，hostname 從 localhost 變 Windows EC2 IP
- R52 SHA-pin → 延伸到 ECR immutable tags（R56-1-7）

### R56 風險與停機規則

- **🔴 每 Phase 結束必停**確認下一 Phase 風險
- **🔴 Phase 2 結束**：Office IQ/PQ 沒過絕不進 Phase 4
- **🔴 Phase 4 結束**：staging Playwright 全綠才進 Phase 9
- **🔴 Phase 9 cutover 中**：每步有 rollback 路徑，5 分鐘決斷時間
- **🟡 Budget alarm**：CloudWatch billing $200/$300/$400 三級警報
- **🟡 OIDC trust policy**：限 `repo:delightening/ipig_system:ref:refs/heads/main` 防 PR branch 偷推

### R56 7 個 open decisions（待敲定）

| # | 決策 | 提案 |
|---|------|------|
| D1 | DNS 入口 | Cloudflare proxy（保 WAF / CDN）+ ALB origin |
| D2 | RDS Multi-AZ 啟用時機 | 先 single-AZ，跑穩 1 個月後切 multi |
| D3 | EC2 Reserved Instance | 跑穩 1-2 個月後 1-year all-upfront |
| D4 | Office LTSC 採購管道 | Microsoft Partner 台灣經銷商 |
| D5 | Migration 起跑日 | 待定 |
| D6 | 並行做（不擋現 prod）| 是 — Phase 0-7 不影響筆電 prod |
| D7 | 顧問 review AWS infra | 推薦 Phase 0-1 IAM 設計階段請 1 小時 |

---

## 📄 R60 — PDF 模板視覺對齊 11/11（2026-05-17 立案）

> **背景**：vet_patrol 視覺修正（字型 + zone label 字級）期間發現所有 11 個
> print-pdf 模板都需要對齊 reference PDF 的視覺規範：
> - **字型**：中文 標楷體（容器內 `AR PL UKai TW` FOSS 替代）+ 英數 Times New Roman（容器內 `Liberation Serif` metric-compat 替代）
> - **格子比例**：col widths / cell heights 對齊 reference
> - **字級層級**：dominant label（如 zone label A-G）vs 內文 vs status 圖示比例對齊
>
> **進度追蹤**：**0/11**。每個模板逐一視覺對比、調整、commit。預估每個 0.5-2h（含 vet/QA 確認），整批 8-16h。
>
> **Reference PDF 覆蓋**（5/11 有現成 reference，其餘待 vet/QA 補）：
>
> | 模板 | Reference PDF |
> |---|---|
> | aup_protocol | `templates/reference/AUP 動物試驗計畫書範例.pdf` |
> | vet_patrol | `templates/reference/動物欄位巡視報告範例.pdf` |
> | medical_record | `templates/reference/實驗豬隻病歷總表範例.pdf` |
> | review_reply | `templates/reference/審查意見回覆表範例.pdf` |
> | review_result | `templates/reference/審核結果範例.pdf` |
> | audit_log / blood_test / pig_approval / surgery / vet_patrol_report / warehouse | **待 vet/QA 補 reference** |
>
> **工作流**（per template）：(1) `python services/print-pdf/_tools/smoke_test.py` 重生 → (2) 用 Read PDF 對比 reference → (3) 改 `services/print-pdf/templates/<name>.html` extra_styles → (4) `docker compose up -d --build print-pdf` → (5) 重新 smoke → (6) 視覺確認後標 `[x]` + commit。

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R60-1 | audit_log | 字型 + cell 比例 + 字級對齊（reference 待補） — 已套用 R60-2 共通樣式（Noto 字型 + 標題去英文 + 移除產出日期 metadata） | [ ] |
| R60-2 | aup_protocol | 對齊 `AUP 動物試驗計畫書範例.pdf` — 2026-05-21 first pass；2026-05-23 second pass 完成（§2 計畫摘要 summary-style、§3-4 表格 conditional rendering、§4.3-4.6 是/否 inline checkbox + 子表格條件展開、§4.5 條件「不適用」、§6.3 3-col、§7-8 表頭中文化、§8 trainings 完整證號、全域 .free-text → .summary-text、page 3 表格 25/75 + 25/25/25/25、cover/h2 標題去英文、TOC 中文化、章節縮排規則 h4.subsub + * 套用全文）；後續：R60-2a real-data 10 份測試 / R60-2b 英文版 | [x] |
| R60-3 | blood_test | 字型 + cell 比例 + 字級對齊（reference 待補） — 已套用 R60-2 共通樣式（Noto 字型 + 標題去英文 + 移除產出日期 metadata） | [ ] |
| R60-4 | medical_record | 2026-05-23 完成：對齊 `實驗豬隻病歷總表範例.pdf` — 已套用共通樣式（Noto 字型 + 移除產出日期 footer）。layout 本來就接近 reference，無需大改 | [x] |
| R60-5 | pig_approval | 字型 + cell 比例 + 字級對齊（reference 待補） — 已套用 R60-2 共通樣式（Noto 字型 + 標題去英文 + 移除產出日期 metadata） | [ ] |
| R60-6 | review_reply | 對齊 `審查意見回覆表範例.pdf` — 2026-05-21 完成（182 行調整，cell 比例 + 字級對齊） | [x] |
| R60-7 | review_result | 對齊 `審核結果範例.pdf` — 2026-05-21 完成（187 行調整，cell 比例 + 字級對齊） | [x] |
| R60-8 | surgery | 字型 + cell 比例 + 字級對齊（reference 待補） — 已套用 R60-2 共通樣式（Noto 字型 + 標題去英文 + 移除產出日期 metadata） | [ ] |
| R60-9 | vet_patrol | 2026-05-22 完成：(1) col widths F 區 cols 12-14 等寬 7%、label cols 3.5%、tag cols 12.5%；(2) row height 6.25mm 填滿 A4；(3) WeasyPrint `draw_collapsed_borders` monkey-patch 合併同軸 segments 為單線（解決雙線雜訊）；(4) G 區 group cell `position: absolute` + flex 阻止 rowspan 撐高鄰列；(5) F/G label 同 col 15；(6) 字體統一 Noto Sans CJK TC 12pt + footer 10pt | [x] |
| R60-10 | vet_patrol_report | 字型 + cell 比例 + 字級對齊（reference 待補） — 已套用 R60-2 共通樣式（Noto 字型 + 標題去英文 + 移除產出日期 metadata） | [ ] |
| R60-11 | warehouse | 字型 + cell 比例 + 字級對齊（reference 待補） — 已套用 R60-2 共通樣式（Noto 字型 + 標題去英文 + 移除產出日期 metadata） | [ ] |
| R60-2a | aup_protocol real-data 測試 | 拿至少 10 份不同 vet 真實 AUP 資料測試 layout 邊界（極長 study title / 多 PI / 大量 controlled drugs / hazardous 全勾 / personnel 10+ 列 / 訓練清單長 / 各 subsection 滿值組合），收集 visual regression 後微調 | [ ] |
| R60-2b | aup_protocol 英文版 | 2026-05-24 完成（PR #477）：jinja `L(zh, en)` macro 路線、單 template 雙語切換、payload `lang: Literal["zh","en"]`；§1-§8 + cover + TOC + page headers 全 L() 化；en 版頁眉標 `Translation of AD-04-01-01F (zh, authoritative)`；附 GLP_NOTES.md 規範（中文為 master）；衍生 frontend digest 補 8 個 IACUC 必審欄位 + adapter carcass_disposal 3-field compose 解決資料遺失 | [x] |
| R60-2c | §4.4 hazards multi-select | 2026-05-25 完成（PR #478）：危害性物質從單選改為 3 checkbox multi-select（biological / radioactive / chemical 可複選）。前端 HazardsSection 重構 + adapter materials grouping 修正 | [x] |
| R60-2d | adapter 21 silent-data-loss 全修 | 2026-05-25 完成（PR #479）：cross-reference 前端 TS types vs adapter vs PDF schema，21 處欄位未正確傳遞（C7 / H9 / M5）。新增 6 個 helper + 修正 source 硬編碼 / anesthesia_type / ControlledDrugRow / reuse plan_other | [x] |
| R60-2e | lay-reader i18n 擴寫 7 條 | 2026-05-25 完成（PR #480）：GLP / IACUC expansion、KCl / electrocution 白話解釋、survival / non-survival 註解、人道終點解釋、drug frequency 翻譯。zh + en 同步，PDF 不動 | [x] |
| R60-2f | §7 animals housing bug + digest enum 翻譯 | 2026-05-25 完成（PR #481）：housing_location 缺 Input 修正 + React state immutable update + species/strain/sex enum t() 翻譯 + 單位 i18n keys + trainings A→F 排序 + required marker 條件顯示 | [x] |

---

## 📝 R61 — DocuSeal 借鑑項目（2026-05-20 立案）

> **背景**：使用者詢問 [docusealco/docuseal](https://github.com/docusealco/docuseal)（AGPLv3，Rails + Vue，e-signature 平台）能否用於本系統。評估結論：**不整合**（AGPL 風險 + 自製簽章層已對齊 21 CFR §11 / GLP），但其設計有幾項可借鑑補位現有 `services/signature/` 的缺口。
>
> **分類**：A = 直接借鑑（補現有缺口）；B = 概念可參考（依需求觸發）；C = 不採納（記錄 push-back 原因）。
>
> **前置**：任一項落地前須先 surface tradeoff 並等使用者裁定（屬 CLAUDE.md 高風險分流 — 簽章 / 法規路徑）。

### R61-A 直接借鑑（補現有缺口）

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R61-1 | Completion / Audit Certificate PDF | 新增 `GET /api/signatures/:id/certificate.pdf` endpoint，把單筆簽章的完整 audit 視圖（21 CFR §11.10(e)：誰、何時、IP、UA、HMAC v2 chain segment 驗證結果、前後鏈節 hash）渲染為一頁 PDF。法規送件時 reviewer 最常單獨要這份。**最低 ROI 推薦先做**。落地點：`backend/src/handlers/signature/certificate.rs`，沿用 print-pdf 服務或 lopdf 純後端產出。 | [ ] |
| R61-2 | PAdES 簽章嵌入 PDF artifact | IACUC 協議、Amendment 決議、安樂死指令完成簽章後，產出 PDF 內含簽章圖檔 + 欄位值 + 時間戳，並以 **PKCS#7 / PAdES**（ETSI EN 319 142）標準嵌入數位簽章，PDF reader 可離線驗證。對應 eIDAS / FDA 紙本提交。落地點：`backend/src/services/signature_pdf/`（新模組），參考 `printpdf` 或 `lopdf` + `openssl` PKCS#7 簽章。**前置裁定**：簽章用憑證來源（自簽 CA / 商業 CA / HSM）。 | [ ] |
| R61-3 | 多簽署人狀態機抽象化 | 抽出 `services/approval_workflow/`：`ApprovalRoute { steps: Vec<ApprovalStep>, mode: Sequential \| Parallel }`，讓 Amendment / Protocol Review / Disposal 共用單一狀態機（取代散落各 handler 的工作流）。每個 step 狀態 `pending / opened / completed / declined / expired`。落地前先盤點現有 3 個流程的差異點，確認可抽象（避免 over-engineer）。 | [ ] |

### R61-B 概念可參考（依需求觸發，不主動排程）

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R61-4 | 簽章前 SMS / Email OTP 雙因子 | 21 CFR §11.200 嚴格解讀下，每次簽章應要求第二因子驗證（不僅是 session 內已登入）。目前 admin 有 TOTP，可擴展為「簽章 mutation 前要求一次 OTP 確認」。需先確認法規顧問是否認定「session JWT + TOTP login」已足夠（trigger：FDA / PMDA 預審 reviewer 提出 §11.200 質疑時再做）。 | [ ] |
| R61-5 | 簽章請求過期 + 提醒排程 | Amendment / Protocol 送審後若 IACUC 委員 N 天未審，scheduler 自動發送站內信 / email reminder，超過 M 天升級給主席。對應 `scheduler.rs` + `services/inbox/`（站內信 R40 已有基礎）。Trigger：使用者反映審查延宕案例變多時再做。 | [ ] |
| R61-6 | Webhook 事件外推 | `signature.completed / declined / invalidated` 等事件以 webhook 推送給外部系統（未來 LIMS / sponsor portal / ERP 整合）。需先有外部整合需求才開（目前無）。落地點：`services/webhook/` + `webhook_subscriptions` 表。 | [ ] |
| R61-7 | 動態表單欄位型別目錄 | 若未來有「sponsor 客製表單 / 跨研究 ad-hoc 問卷」需求，可參考 DocuSeal 12 種欄位型別（signature / initial / date / text / checkbox / select / radio / file / number / phone / email / image）建 enum + JSON schema。**目前需求不足 3 種表單，不開**；記錄在此避免未來重新評估。 | [ ] |
| R61-8 | PDF 模板拖放編輯器 | DocuSeal 提供 admin 在 PDF 上拖放簽章 / 欄位位置的 UI。本系統表單規制驅動、欄位固定，**不採納**（over-engineer），僅記錄此設計模式供未來若出現「sponsor 上傳自家 PDF 後標欄位」需求時參考。 | [ ] |

### R61-C 不採納（記錄 push-back 原因）

| # | 項目 | 不採納原因 |
|---|------|----------|
| R61-9 | 整套 DocuSeal Rails 服務並行部署 | 多一套 Rails 維運棧 + AGPL 邊界管理成本；且現有簽章流程是 internal approval，非外部寄 PDF 場景 |
| R61-10 | Fork DocuSeal 程式碼整合 | AGPLv3 § 7(b) 會把整個 ipig_system 拖入 AGPL 義務；且技術棧不一致（Rails/Vue vs Rust/React） |
| R61-11 | 更換現有 HMAC chain → DocuSeal submission schema | 法規重驗成本（21 CFR §11.10(a) IQ/OQ/PQ）遠大於收益；自製 chain 已對齊 GLP §10 20 年保存 |

### R61 對應 memory / 路徑

- `backend/src/services/signature/` — 現有簽章服務（HMAC v2 + meaning attestation）
- `backend/src/handlers/signature/` — euthanasia / protocol_review / disposal
- `docs/security/HMAC_VERSIONING.md` — HMAC v1/v2 演進與 Anonymous actor 規範
- `docs/glp/traceability-matrix.md` — 21 CFR §11.10/§11.50/§11.70/§11.200 對應矩陣
- 評估觸發 branch：`claude/evaluate-docuseal-compatibility-FR2vO`

### R61 風險與停機規則

- **任一 R61-A 項目**屬簽章 / 法規路徑高風險變更，落地前**必停**等使用者裁定範圍與驗證計畫。
- **R61-2 PAdES 嵌入**牽涉憑證 / HSM / CA 採購，屬「不可逆 / 多解選錯成本高」，必停 surface tradeoff（自簽 vs 商業 CA vs HSM）。
- 任一項落地需更新 `docs/glp/traceability-matrix.md` 對應條目，並走「PR 屬動 handlers 層 → `cargo test --all-targets` 全綠」測試標準。

---

## 📦 R62 — ERP storage_location_inventory 歷史回填（2026-05-20 立案）

> **背景**：2026-05-20 ERP audit (PR #467 系列) 後，新操作的 storage_location_inventory
> 已正確扣減（PR/DO/SR/RTN/TR 五個 doc type 一致更新；ledger.rs `decrement_storage_location_inventory`
> + `upsert_storage_location_inventory`）。但既有 PR/DO/SR/RTN 已造成的歷史 drift
> 沒 backfill — 政策是「2026-05-20 後正確，之前差異視為 baseline」。本 R 段提供
> 工具讓 ops 想對歷史重算時可用。
>
> **觸發時機**：當 storage_location_inventory 與盤點對不上時、或 GLP 內外稽核要求
> 「請證明儲位庫存自上線以來精確」時，才執行。

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R62-1 | **storage drift recalc 工具** | `bin/reconcile_storage_inventory.rs`：依 `stock_ledger` signed qty 累計運算每個 (location, product, batch, expiry) 應有 `on_hand_qty`，與目前 `storage_location_inventory.on_hand_qty` 對比輸出差異 CSV。**只讀，不寫**。2026-05-25 完成 via PR #482（含 bot review 修正：CASE ELSE 0 + unknown direction 偵測 + CSV RFC-4180 escaping） | [x] |
| R62-2 | **執行 + 對帳簽核** | 跑 R62-1，差異列表給 QAU/admin sign-off 是否套用修正；若套用，加 ops migration 070 用 audit_log + 修正 record 一一執行 | [ ] |

---

## 🗂️ R64 — 補登歷史變更申請（Amendment Import Backfill，2026-06-01 立案 + 落地）

> 匯入計劃（imported_at 非 NULL）補登紙本世界早已核准過的歷史變更，平行 protocol import P1–P2：跳過 live 審查、回填原始日期、不產生 live 電子簽章、直接落 EFFECTIVE。計畫書見 `docs/plans/amendment_import_backfill.md`。

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R64-1 | **P6-1 schema 基礎** | amendments.is_historical（補登標記）+ protocols.imported_at（永久匯入標記，既有 prod imports 由 audit log 回填）；import_approved 寫入 imported_at | [x] |
| R64-2 | **P6-2 補登流程** | create_historical（建 is_historical DRAFT + 回填日期，限匯入計劃 + MAJOR/MINOR）+ finalize_historical（DRAFT→EFFECTIVE，回填生效日，無 live 簽章）；編號 MAX+1 接續；`access::can_backfill_historical_amendment`（SD/admin gate） | [x] |
| R64-3 | **P6-3 審查文件補登** | record_historical_reviews 全量取代 amendment_review_assignments；migration 088 reviewer_id nullable + reviewer_name（院外委員，比照 085）；get_review_assignments LEFT JOIN | [x] |
| R64-4 | **P6-4 前端** | AmendmentsTab「補登歷史變更」入口（匯入計劃 + SD/admin）+ HistoricalAmendmentDialog（create→reviews→finalize 三步）+ HistoricalReviewersEditor | [x] |
| R64-5 | **補登 polish + 匯入研究資料 inline/鎖定** | (a) ✅ is_historical badge（AmendmentListItem 加欄 + 列表 badge）(b) ✅ 補登委員系統內下拉選（REVIEWER 角色 + 院外姓名）(c) ✅ C1 刪除誤匯計劃（admin 硬刪 + 守衛）+ C2 研究資料 inline（ResearchBasicFields 共用 + sponsor 收斂）+ C3 編輯頁鎖定（SectionBasic disabled）。詳見 `docs/plans/import_inline_basic_lock.md` | [x] |
| R64-6 | **R64 micro follow-up（backlog）** | (i) reviewer 選擇器 import-review/ReviewerSelect 與 HistoricalReviewersEditor 概念重複，可抽共用 components/protocol/reviewer/ (ii) SectionBasic 欄位視覺順序微調（功能等價，print 不受影響） | [ ] |
| R64-7 | **PR #544 CodeRabbit deferred（backlog）** | (a) 函數過長重構：`create_historical`/`finalize_historical`/`record_historical_reviews`/`delete_imported_protocol` 拆 helper（>60 行，CLAUDE.md §2）(b) 補登 3-step dialog 可復原性：失敗留孤兒 DRAFT，改 server-side transactional endpoint 或前端 surface 已建 draft (c) 匯入頁研究資料嚴格驗證（歷史資料本就可能不全，需與「補登舊紙本」用途權衡）(d) PI address/phone_ext 收集（D5 下不重複 PI；歷史補登可接受空值）(e) 刪除測試補 byproduct 守衛 + non-admin（HTTP 層）案 (f) historical backfill payload validator-layer 驗證（現服務層已回 4xx） | [ ] |

---

## ♿ R65 — 無障礙（a11y）aria-label i18n 全面化（2026-06-09 立案）

> 來源：PR #657（研究人員計畫書可編輯）gemini / CodeRabbit review。目前全站 action 欄 icon 按鈕的 `aria-label` 多為硬編碼中文（grep `aria-label="[一-龥]` 約 98 處：編輯 / 刪除 / 修正 等），切換英文語系時螢幕報讀器仍念中文。PR #657 為對齊既有慣例（不孤立改單一按鈕造成半套不一致）暫維持硬編碼，改列此處作跨元件一次性遷移。低風險、可漸進分批。

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R65-1 | **action 按鈕 aria-label 改 i18n** | 全站硬編碼中文 `aria-label` 改用既有 i18n key（`common.edit` / `common.delete` / `common.save` 等）；同元件成對處理（編輯+刪除一起）避免半套不一致。範圍：frontend `*.tsx`，約 98 處。可分批 PR。 | [ ] |

---

## 🔒 R66 — 滲透測試評估 follow-up（2026-06-10 立案，static 複查）

> 來源：2026-06-10 全端靜態滲透測試評估（6 領域平行審計）。完整報告見 `docs/security/PENTEST_ASSESSMENT_2026-06.md`。2026-04 `SECURITY_AUDIT_REPORT.md` 的 1 Critical + 多項 High 幾已修復；本輪新發現 1 High + 5 Medium + 5 Low + 2 待驗證。High 為威脅模型 §4.1 DAC-3「新端點遺漏 access check」架構缺口的具體實例。
>
> **風險與停機規則**：R66-A1 屬動 handlers/services 層 → `cargo test --all-targets` 全綠 + 附 access regression test。R66-B4/B5 屬 compliance / 部署拓樸決策，落地前必停 surface tradeoff 等使用者裁定。
>
> **2026-06-10 深化複查 addendum**：以 4 領域平行唯讀掃描橫向擴掃全模組（authz/injection/auth-crypto/frontend-deploy）+ route/middleware 層人工審計。結論：**未發現 A1 以外的新 High/Critical**（protocol/amendment/document/transfer/vet_advice/care_record/hr 雙層授權皆確認完整；注入/檔案/前端/部署全綠）。新增 2 個 Low at-rest 明文項（C6/C7），並就地完成 D1 依賴掃描（結果見 D1 列）。

### R66-A：立即修復（High）

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R66-A1 | **跨計畫寫入 IDOR — 4 個 create handler 補 access check** | `create_animal_weight/vaccination`（`weight_vaccination.rs:48,128`）、`create_animal_surgery`（`surgery.rs:69`）、`create_animal_blood_test`（`blood_test.rs:62`）只查 `require_permission!`，缺同檔 list/get/update/delete 都有的 `access::require_animal_access`。`EXPERIMENT_STAFF`（不在 `VIEW_ALL_ROLES`）可對他人計畫動物寫偽造醫療記錄，GLP 完整性風險。比照 `create_animal_observation:101`，handler + service 雙層加 check + 附 regression test。**【R66↔R75 對帳·已修】由 R75-2 / PR #752 涵蓋並落地：4 個 create handler 皆補守衛（weight/vaccination/blood_test → `require_animal_read_access`、surgery → `require_animal_access`，已 code 驗證）；R75-0 將嚴重度由 High 重評為內部 GLP 資料完整性（`animal.record.create` 僅 EXPERIMENT_STAFF/INTERN 持有且已有 view_all、非跨客戶）** | [x] |

### R66-B：強化項（Medium）

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R66-B1 | **JWT 登出跨實例撤銷** | `middleware/auth.rs:148` 熱路徑只查記憶體黑名單；多實例下 A 登出的 token replay 到 B 仍被接受至自然過期。登出時 bump `tokens_valid_after` 或熱路徑改查 `is_revoked_with_db`。單實例不受影響。**【R66↔R75 對帳】與 R75-P2 ③ caveat 同一 latent gap（per-request `is_revoked` 為記憶體版，多機 cache 不同步）；R75-P2 僅再確認未修，本項維持開啟為唯一追蹤點** | [ ] |
| R66-B2 | **TOTP secret at-rest 加密** | `two_factor.rs` 寫入 `totp_secret_encrypted` 欄位實為明文 base32。DB 洩漏時 2FA 失效。**已實作（PR #779，2026-06-23）**：app 層 **XChaCha20-Poly1305** AEAD（新 `utils/crypto.rs`：信封 `<version>:<base64(nonce‖ct+tag)>`、AAD=user_id、版本化支援輪替、`zeroize` 清記憶體、Debug 遮蔽金鑰）；**專用 `ENCRYPTION_KEY`**（鏡像 AUDIT_HMAC_KEY 載入、與 JWT/HMAC 金鑰隔離、fail-closed）；generate/confirm/disable/verify 四站串接、過渡期相容 legacy 明文（`is_encrypted_envelope` 判別）；`bin/backfill_totp_encryption`（idempotent + dry-run）加密既有明文；8 crypto 單元測試。設計見 `docs/security/AT_REST_ENCRYPTION.md`。演算法/金鑰/zeroize 經使用者裁定 | [x] |
| R66-B3 | **step-up 密碼端點納入暴力破解防護** | `/auth/confirm-password`、`/2fa/disable` 只受 120/min 寫入限流，不含 30/min auth 限流、不計入帳號鎖定。套用 `auth_rate_limit` + `reauth_failure` 納入鎖定計數。**已修（PR #774，2026-06-22）**：依使用者裁定採**獨立計數器**——在咽喉點 `verify_password_by_id` 加鎖定前置檢查（近 15 分鐘 `reauth_failure` 達 5 次即拒絕，先於密碼驗證、正確密碼也擋），只計 `reauth_failure`、不碰 `login_failure`，故鎖 step-up 不影響登入（避免 DoS）。門檻採 const（簽章呼叫端無 Config）。單一咽喉點覆蓋全部 6 個呼叫端（confirm-password / 2fa-disable / 簽章 invalidate+sign）。3 整合測試（達門檻鎖定／未達放行／計數器分離）。**限流 tier 經評估與鎖定重疊（5 次遠嚴於 30/min）故不另加，避免冗餘 middleware 改動** | [x] |
| R66-B4 | **電子簽章 2FA step-up（compliance 決策）** | `signature/mod.rs:847` 簽章僅密碼重驗，TOTP 啟用者也不要求第二因素。21 CFR §11 連續工作階段下屬合規；僅稽核期待每次 TOTP 時為缺口。**需與合規負責人裁定** | [ ] |
| R66-B5 | **proxy header 信任收窄** | `real_ip.rs:40` `TRUST_PROXY_HEADERS=true` 時信任 client 可控 IP header，無 trusted CIDR pin。緩解：鎖定以 email key、port 綁 127.0.0.1。改為只信任單一 header 或驗證 peer CIDR。**【2026-06-22 調研後裁定·accepted-risk `[V]`，結構性硬化延 R56】**：實調 prod 拓樸＝`Internet→Cloudflare(proxy+WAF)→CF Tunnel→nginx(綁 127.0.0.1:8080)→api(docker network 無對外 port)`。**已被部署架構緩解**：API 完全不對外（TCP peer 永遠是 nginx）、nginx loopback-only（外部到不了）、Cloudflare 權威覆寫 `cf-connecting-ip`（client 無法偽造）、nginx 權威覆寫 `X-Real-IP`/append `X-Forwarded-For`（取最右）。「無 CIDR pin」＝防『未來誤把 API 開 port』的縱深，非現役漏洞；且改後端只信 X-Real-IP 會弄壞 IP 解析（CF-Tunnel 下 `$remote_addr`＝tunnel IP、真 client 只在 cf-connecting-ip）。**R56/AWS 遷移把 ingress 換 ALB（移除 tunnel）→ 屆時可信來源變 ALB 已知 CIDR，CIDR pin 屆時才 durable**；現在做 docker-CIDR pin 為 pre-R56 拋棄工。**拓樸不變式（維護者須守）**：①api 服務不得加對外 `ports:` ②web/nginx 維持綁 127.0.0.1 ③CF proxy mode 保持開（authoritative cf-connecting-ip）。結構性 trusted-proxy 硬化見 R56-6 | [x] |

### R66-C：低風險 / 縱深防禦（Low）

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R66-C1 | **Webhook SSRF guard 補強** | `security_notifier.rs` 無 IPv6 ULA/link-local 拒絕、無 DNS-rebinding pin。**已修（PR #773，2026-06-22 merged+部署）**：補 IPv6 ULA(fc00::/7)/link-local(fe80::/10) + IPv4-mapped/compatible（to_ipv4）；連帶修 3 個既有繞過（`[::1]` 方括號致 IP 檢查失效、`localhost.`/`127.0.0.1.` 末尾點 FQDN 繞過、deprecated `::a.b.c.d`）；9 單元測試。**殘留 DNS-rebinding pin** 見 R66-C1b | [x] |
| R66-C1b | **Webhook DNS-rebinding pin（C1 殘留）** | C1 已擋字面私有 IP / 私有 hostname / IPv6 私有段，但**公開 hostname 在 DNS 解析時可指向私有 IP**（TOCTOU rebinding）。**已修（PR #777，2026-06-22）·零新依賴**：`send_webhook` 在 `is_safe_webhook_url` 通過後，以 `tokio::net::lookup_host` 自行解析 → 逐一驗證每個 IP 為公開位址 → reqwest `.resolve_to_addrs(host, &validated)` 把連線 pin 到該組已驗證 IP，使 connect 時不再重新解析、閉合 rebinding。**經評估不需 hickory**（tokio lookup_host + reqwest resolve_to_addrs 既有依賴即足）；TLS 仍對 hostname 驗 SNI/憑證。抽出 `is_safe_public_ip`（C1 字面與 C1b 解析共用，DRY）；5 離線確定性單元測試；改 per-send client（pin 需 per-target，安全告警低頻） | [x] |
| R66-C2 | **`mark_animal_vet_read` 一致性加 access check** | `animal_core.rs:381` 缺 `require_animal_access`；VET 本就可見全部動物、僅翻 flag 無洩漏，修為一致性。**【R66↔R75 對帳·已修】由 R75-2 / PR #752 涵蓋：`animal_core.rs:388` 已補 `require_animal_read_access`（含 404 存在檢查）** | [x] |
| R66-C3 | **`byproduct_sample` per-protocol scoping 確認** | `byproduct_sample.rs` 角色 gated by design，但與週醫療報告 protocol boundary 不一致。確認權限只授予可信全廠角色。**【R66↔R75 對帳·已答】R75-0 釘死 view/write 僅 VET/QAU/admin（內部稽核/獸醫/管理層）→ 本就應全場可見財務再利用紀錄、非 IDOR，by-design（見 R75-3）。殘留 `byproduct_monthly_report` boundary 由 R75-3 追蹤** | [x] |
| R66-C4 | **`impersonated_by` 改 `skip_deserializing`** | `middleware/auth.rs:26` 仍 `#[serde(default)]`（SEC-AUDIT-005 殘留）；已升 ES256 故殘留風險極低。**【2026-06-22 驗證·won't-fix `[V]`】**：模擬登入流程 `handlers/auth/impersonate.rs:35` **必須**從 JWT `.impersonated_by` deserialize 回來才能重簽管理員 token（停止模擬）；改 `skip_deserializing` 會讓欄位永遠 None → **弄壞停止模擬 + audit 失去真實操作者**。且 token 為 ES256 簽章、欄位無法偽造 → 縱深防禦收益為零、風險為負。維持現狀 | [x] |
| R66-C5 | **2FA temp token single-active 強制** | `two_factor.rs:255` 重送密碼可重鑄 temp token。5 次上限 + TOTP replay 防護使實務暴力不可行。加 single-active-token 或 per-token 計數 | [ ] |
| R66-C6 | **簽名 bridge payload at-rest 加密** | `signature_bridge.rs` 手機提交的 `payload`（含明文密碼 + 手寫筆跡 SVG）未加密存 DB。**已實作（PR #780，2026-06-23）·共用 B2 `utils/crypto.rs`**：migration 104 `payload` JSONB→TEXT（AEAD 信封）；submit 加密（AAD=session_id‖user_id，由 SELECT FOR UPDATE 取 user_id）、consume 解密、過渡相容 legacy 明文 JSON（`is_encrypted_envelope` 判別）；缺金鑰 submit fail-closed；payload 短效無需 backfill；consume 後仍清 NULL；4 離線單元測試（roundtrip / session+owner AAD 拒絕 / legacy passthrough / fail-closed）。設計見 `AT_REST_ENCRYPTION.md` §6 | [x] |
| R66-C7 | **邀請 token at-rest hash 化** | `invitation.rs:319,372` `invitation_token` 以明文存 DB。**【2026-06-22 裁定·accepted-risk（方案 B）`[V]`】**：hash 化非無痛 mirror——`InvitationResponse::from_invitation`(:534) 會從儲存值重建邀請連結供 admin 列表/詳情隨時複製重發；hash（單向）後無法重建 raw 連結 → admin 列表不再顯示連結（UX 退化）。邀請 token **短效（有 expiry）+ 單一用途（綁定 email + 預設角色）**，DB 洩漏風險遠低於密碼重設 token。使用者裁定維持明文、記為已知可接受風險。若日後採方案 A（hash + 連結僅建立/重發當下顯示）再重啟 | [x] |

### R66-D：待驗證 / 架構根治（Info）

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R66-D1 | **CI 重跑依賴 CVE 掃描** | **2026-06-10 已就地手動掃描**：前端 `pnpm audit`（含 dev）0 漏洞；後端 `cargo audit`（526 crates）1 漏洞 + 3 警告 — `rsa 0.9.10` RUSTSEC-2023-0071 Marvin timing（Medium，上游無修復；transitive via jsonwebtoken/sqlx-mysql，但本系統 JWT 走 ES256、DB 走 Postgres → RSA 路徑不可達，建議標已接受風險）；警告 `proc-macro-error2` unmaintained（編譯期）、`rand` unsound（情境不適用）。4 月列過的 `quinn-proto` DoS / `printpdf` 已消失。**剩餘工作**：把掃描接進 CI 常態化 + 將 `rsa` 列入 `deny.toml`/`.cargo/audit.toml` 已接受清單。**【R66↔R75 對帳·已完成】CI 已落地：`ci.yml` 有「cargo audit」job（`--ignore RUSTSEC-2023-0071`）+「cargo deny」job，`backend/deny.toml` 已存在。rsa 長期追蹤併入 R75-P2b（同一 advisory，避免重複條目）** | [x] |
| R66-D2 | **DAC-3 全域 access policy layer** | 根治本類 IDOR：威脅模型 §4.1 方案 C（CI handler 白名單掃描），**並把 create handler 納入掃描**（本輪 High 為 create 漏網證明缺口存在）。**【R66↔R75 對帳】與 R75-P4 同一根因（結構性授權缺失），合併為單一決策；R66-D2 = CI 掃描方案（防護網），R75-P4 = 型別/資料層強制（根治）。待使用者核可設計後實作，見 R75-P4** | [ ] |

---

## 🚨 R67 — 業務規則 403 誤觸 IDOR 自動封鎖整治（2026-06-11 事故 + 落地）

> 來源：2026-06-11 prod 事故 — 行動網路使用者打卡第一次因 GPS 未備妥失敗（回 403「不在範圍內」），`middleware/response_logger.rs`(R22-6) 對「所有 403」無差別計數為 IDOR 探測（5 分 20 次→自動停權 + 封 IP），封到辦公室共用對外 NAT IP → 全院 451 無法登入。事故還原 + 根因修復詳見 PROGRESS.md §9。

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R67-1 | **打卡地理圍籬 403→422 + 前端 GPS race** | `handlers/hr/attendance.rs` 地理圍籬失敗改 `BusinessRule`(422) 不再餵安全偵測 + 3 迴歸測試；前端 `useAttendanceMutations.ts` GEO_OPTIONS 改 enableHighAccuracy:true/maximumAge:0/timeout:10s 修「打卡要打兩次」。已部署 prod、實機驗證通過 | [x] |
| R67-2 | **403 全面盤點 + 21 處改正** | 審 219 處 `AppError::Forbidden`，21 處業務規則/狀態/配額/驗證誤標改正（422 BusinessRule×17 / 429 TooManyRequests×1〔mcp notify_secretary 含測試〕 / reauth×3 刻意用 422 非 401 避免前端 refresh/logout 誤踢）；真授權（RBAC/擁有權/SoD-by-role/token、HR 階段審核、upload fail-closed）維持 403。已部署 prod | [x] |
| R67-3 | **IDOR 偵測器根本強化（可選）** | `response_logger`/`check_idor_probe` 對「所有 403」無差別計數，連前端自動抓取的合法 403 GET 也算 → 仍可能誤判。可選強化：排除 GET / 只計物件存取型 403 / 拉高門檻 / 對同端點同訊息去重。**使用者尚未要求，列 backlog** | [ ] |

---

## 📝 R68 — 動物試驗申請須知簽核流程 + admin 駁回通道（2026-06-12 立案 + 落地）

> 來源：使用者要求「計畫送審前須由 SD 或 PI 簽核申請須知」+ 兩筆誤送審計畫需 admin 駁回/移除。全院共用須知 + 版次制（同時間僅一個生效版本），手寫電子簽章複用 electronic_signatures（meaning=ACKNOWLEDGE），submit 前驗證已簽當前生效版本。詳見 PROGRESS.md §9 2026-06-12 條目 + [[legacy-protocol-import]] 階段3。

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R68-1 | **admin 駁回通道 + 軟刪除 + 排序** | 預審中/已送審 → 駁回（admin only，強制 remark）；REJECTED/CLOSED 於「我的計畫」排序沉底；admin 軟刪除（REJECTED→DELETED，列表隱藏、保留資料 + audit）。PR #692 merged + 部署 | [x] |
| R68-2 | **schema（2 新表）** | `098_application_notices.sql`：`application_notices`（version_label UNIQUE、content NOT NULL、生效版 partial unique index `WHERE is_active`）+ `protocol_notice_acknowledgements`（一計劃一筆 protocol_id UNIQUE、FK CASCADE、signature_id/notice_attachment_id 可空承接舊計劃）。補進 `EXPORT_TABLE_ORDER`。PR #693 | [x] |
| R68-3 | **簽署後端** | `signature_meaning` 加 `ACKNOWLEDGE`（不入 HMAC canonical_input，零斷鏈）；`SignatureService::sign_with_handwriting_tx`（手寫+chain、免密碼）；`ProtocolService::acknowledge_notice`（同 tx 原子簽章+upsert）；`access::can_sign_notice`（限 PI/SD）。PR #695 | [x] |
| R68-4 | **須知登記 API** | `ApplicationNoticeService`（list/get_active/create/activate，tx+audit，重複 version_label 回 BusinessRule）；handler 走 `aup.application_notice.manage`（admin bypass）。PR #696 | [x] |
| R68-5 | **admin 登記前端分頁** | ProtocolsPage 加「申請須知版本」分頁（`hidden:!isAdmin`）：版本表 + 建立 dialog + 啟用。PR #698 | [x] |
| R68-6 | **填表簽署前端 + 狀態 API** | ProtocolDetailPage DRAFT 顯示 `NoticeAcknowledgementCard`（正文 + HandwrittenSignaturePad）；`get_notice_status`（active_notice/acknowledged/acknowledged_at）。PR #699 | [x] |
| R68-7 | **舊計劃承接** | `import-approved` 支援 `notice_version_label`/`notice_attachment_id`/`notice_acknowledged_at`，`insert_legacy_tx`（signature_id=NULL、紙本掃描掛 attachment）。PR #697 | [x] |
| R68-8 | **內容匯入 prod（4 版）** | `import_application_notices` bin（ActorContext::System，idempotent，--dry-run，內嵌正文）匯入 AD-04-01-02 A/B/C/D → A/B/C 封存、**D（2025-09-15）唯一生效、閘門啟動**；5 筆 audit 進 HMAC chain、verify CHAIN INTACT。生效日取自 worksheet legend。PR #700 | [x] |
| R68-9 | **Bug 修：補件重送死鎖** | 送審閘門原對 `*_REVISION_REQUIRED` 也檢查須知簽署，但 acknowledge 限 DRAFT + 卡片限 DRAFT → 補件「要簽卻無法簽」死鎖。改閘門僅初次送審（DRAFT→SUBMITTED）檢查 + 迴歸測試。潛在 bug 提早根治（prod 0 受害者） | [x] |
| R68-10 | **Bug 修：正文純文字化** | 卡片 `whitespace-pre-wrap` 無 markdown 渲染器→ `#`／`｜`／`---`／`*` 顯示字面。正文改純文字（時程表條列、分隔線）+ 新增 `update_content`（已簽不可改守衛、TOCTOU 守衛與更新同 tx）+ bin 內容同步；prod 4 版已同步、4 CONTENT_UPDATED audit、chain intact | [x] |
| R68-11 | **submit() 函數過長（backlog）** | `services/protocol/status.rs::submit` 130 行 > 50 行門檻（pre-existing tech debt，非本次引入；CodeRabbit #701 提）。可拆 status 驗證／須知閘門／APIG 產號／版本快照／audit 五個 helper。低優先 | [ ] |

---

## 📚 R69 — SOP 文件簽署 + 訓練考試（2026-06-15 立案）

> 來源：員工教育訓練盤點發現缺口——`training_records` 僅扁平登錄，無 SOP 內容/閱讀確認/簽署/考試。流程：建立 SOP → 員工閱讀（上傳 PDF/Word）→ 電子簽署確認（複用 electronic_signatures，meaning=ACKNOWLEDGE）→ 考試及格（固定 80%、無限重試、後端計分）→ 訓練完成。改版即失效全員重做 + per-SOP 重訓週期。設計規格見 `docs/design/sop-training-acknowledgement-design.md`（§8 PR-A~PR-H 切分、§9 未決、§10 定稿）。**R69-2 起均尚未動工**。

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R69-1 | **設計規格定稿** | 新增 `docs/design/sop-training-acknowledgement-design.md`（7 新表 schema、角色權限、API/前端草案、合規對應、邊界/並發/保留政策）。純文件、無程式碼。PR #711 | [x] |
| R69-2 | **PR-A schema + models + repo** | migration（`sop_documents`/`sop_versions`/`sop_exams`/`sop_exam_questions`/`sop_assignments`/`sop_acknowledgements`/`sop_exam_attempts`/`sop_training_completions` 7~8 表 + index + `sop.manage`/`sop.view_all` 權限種子）+ models + repository。`cargo test --lib`。完成後必停確認 schema（高風險） | [ ] |
| R69-3 | **PR-B SOP 主檔/版本/啟用** | service + handler + 權限；啟用版本走停用舊+啟用新 tx（`SELECT ... FOR UPDATE` 防 TOCTOU）+ 啟用前須有考卷 guard。`cargo test --all-targets` | [ ] |
| R69-4 | **PR-C 考卷/題庫 + 考試計分** | 建/改考卷（是非・單選）+ 交卷 attempt（後端計分、正解不下發、提交前驗 question_id/格式、`attempt_no` 鎖定遞增、無限重試）。`cargo test --all-targets` | [ ] |
| R69-5 | **PR-D 簽署 + 完成判定** | acknowledge（複用簽章、同 tx、驗 entity_type/id）+ completion 判定（簽署+考過、UNIQUE 冪等）+ 同步 `training_records`（去重鍵 `training_record_id`、TIMESTAMPTZ→NaiveDate 時區轉換、同 tx rollback）。`cargo test --all-targets` | [ ] |
| R69-6 | **PR-E 指派 + 狀態總覽 API** | 指派員工 + 全員 SOP 訓練狀態總覽（`sop.view_all`）。`cargo test --all-targets` | [ ] |
| R69-7 | **PR-F 前端員工受訓流程** | 「我的訓練」頁：閱讀 PDF → 手寫簽名板（複用既有元件）→ 考試作答（未過再考）。tsc + eslint；新增表格前走 `/system_table_chats` | [ ] |
| R69-8 | **PR-G 前端 QA/Admin 管理頁** | 版本登記 + 題庫編輯 + 指派 + 全員狀態儀表。tsc + eslint | [ ] |
| R69-9 | **PR-H 改版失效 + 定期重訓排程** | 到期前提醒（複用 scheduler + notifications，僅查 active 版本、過濾停用/刪除帳號、ORDER BY+LIMIT 分批）。`cargo test --all-targets` | [ ] |
| R69-10 | **§9 未決待 sign-off** | 重訓週期具體值、是否允許永不到期（retrain_interval nullable）、抽題策略、是否強制閱讀偵測、指派粒度（逐人 vs 角色/部門批次）。實作前需使用者拍板 | [ ] |

---

## 🧹 R73 — Code review #669–741 多餘 code 整理（2026-06-17 立案）

> 來源：對過去 70 個 PR 的 lazy-senior code review（4 路並行）。整體乾淨、無高嚴重度；以下為標出的**重複 code**，皆非 bug、不影響運作，集中追蹤、有空合併（對齊 DRY §7「同 pattern ≥2 處抽共用」）。

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R73-1 | **維運 bin 重複 secret/arg 解析抽共用** | 6~7 個 `bin/*.rs`（import_application_notices / import_legacy_protocols / enrich_imported_protocols / backfill_import_reviews / patch_milestone_timeline / provision_legacy_pi_accounts）各自複製 `read_database_url`（~7 份）/ `read_audit_hmac_key`（~5 份）/ `arg_value`（~4 份），每份約 30 行相同。抽 `bin/common.rs` 或複用既有 `config::read_secret`。一次性工具，低優先。**#908 已改 backfill_import_reviews + create_guest 用 config::read_secret，清單其餘 ~5 支未動** | [ ] |
| R73-2 | **HR 核准操作欄抽元件** | `pages/hr/components/LeavePendingApprovalsTab.tsx` 與 `PendingApprovalsTabContent.tsx` 的 `can_approve ? <核准/駁回鈕組> : <—>` cell 邏輯一字不差重複。抽 `ApprovalActionsCell` | [ ] |
| R73-3 | **dashboard formatTime 抽共用** | `components/dashboard/CalendarWeekGrid.tsx` 與 `CalendarEventList.tsx` 各自重複定義相同 `formatTime`（`toLocaleTimeString` + `Asia/Taipei`）。移進同層 `calendarWeek.ts` 共用 | [ ] |
| R73-4 | **兩份 Textarea 實作收斂** | `components/ui/textarea.tsx` 與 `ui/input.tsx` 各 export 一份 `Textarea` + `TextareaProps`（pre-existing 重複）；新 code（autoGrowTextarea / StructuredChangeEditor）從 `ui/input` 匯入、notices 從 `ui/textarea` 匯入，兩條路徑並存。收斂為單一來源避免日後 diverge | [ ] |

---

## 🔒 R75 — 對抗式授權稽核 IDOR 發現（2026-06-17 立案，Phase 1）

> 來源：使用者提供的對抗式資安稽核 prompt，Phase 1「授權地圖」。方法：8 個唯讀子代理依領域平行掃 ~95 handler，再由 Claude **親讀 service 層驗證最高風險條目**（不採信僅讀 handler 的告警）。
> **信心標記：`[V]`=Claude 親讀 handler+service 驗證；`[A]`=子代理回報、未親驗。**
> **系統性根因**：全系統無結構性授權——所有 object-level 檢查都是 handler/service body 內「要記得呼叫」的 `require_*()`，忘了呼叫不會編譯失敗（對應上次「漏 7 個 handler」）。結構性修法見 R75-P4（Phase 4，待規劃，勿先實作）。
> **⚠️ 前置阻擋（決定下列嚴重度）**：尚未讀 `startup/permissions.rs` 確認**哪些角色實際持有** `animal.record.create` / `animal.byproduct_sample.*` / `aup.protocol.view_own` / `audit.logs.view`。若外部 PI/CLIENT 持有 → 災難級；若僅內部 staff → 降為職責分離問題。**R75-0 須先做。**

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R75-0 | **【前置】盤點角色↔權限種子 `[V]`** | **已完成**——讀 `startup/permissions.rs` 釘死持有角色。關鍵結論：`aup.protocol.create`=PI/IACUC_STAFF/SD（**PI 可為外部**）；`aup.protocol.view_own`=幾乎所有角色**含 CLIENT**（外部）；`animal.record.create`=**僅 EXPERIMENT_STAFF/INTERN**（內部，且已有 view_all）；`animal.byproduct_sample.view/write`=**VET/QAU/admin**（內部稽核，本就全場可見）；`animal.record.view`=**含 CLIENT**（外部）；`audit.logs.view`=ADMIN_STAFF/QAU | [x] |
| R75-1 | **`copy_protocol` 跨客戶內容讀取 🔴 CRITICAL `[V]`** | `crud.rs:549`→`core.rs:733`：只檢查 `aup.protocol.create`/PI/admin，**不驗來源計畫存取權**；service 撈來源 `working_content` 回傳呼叫者。**R75-0 確認 PI 持有此權 → PI 可讀任一客戶完整計畫內容 = 跨客戶外洩**。**已修（PR #746，2026-06-18 merged+部署 prod）**：handler 加 `access::require_protocol_related_access(source_id)`；回歸測試 `tests/api_protocol_copy_idor.rs`（斷言 `AppError::Forbidden`）；CI 17/17 綠含 backend cargo test 真測試 DB 驗證 | [x] |
| R75-2 | **動物子紀錄 CREATE/UPSERT 越權寫入（內部） `[V]`** | `services/animal/` **從未呼叫 `require_animal_access`**（grep=0），create handler 亦無；僅 `require_animal_has_protocol`（前置條件非擁有權）。影響：surgery(`:63`)/weight/vaccination/blood_test/sudden_death create + sacrifice/pathology upsert(`sacrifice_pathology.rs:36/72`) + `mark_vet_read`(`animal_core.rs:381`) + field_correction。**R75-0 確認權限僅 EXPERIMENT_STAFF/INTERN 持有（內部、已有 view_all）→ 非跨客戶，屬 GLP 資料完整性/職責分離**（實習生可對他組動物偽造手術/犧牲/病理紀錄）。降級為內部 data-integrity。**已修（PR #752，2026-06-18 merged+部署）**：各 create/upsert 補對齊 sibling 的守衛（plan-bound→require_animal_access、基礎→require_animal_read_access） | [x] |
| R75-3 | **byproduct sample 無 object scope → by-design（結案）`[V]`** | `byproduct_sample.rs` 全 CRUD 僅 `require_permission!`。**R75-0 確認 view/write 僅 VET/QAU/admin 持有 = 內部稽核/獸醫/管理層，本就應全場可見財務再利用紀錄 → 非 IDOR、屬 by-design**。`byproduct_monthly_report` 缺 boundary 同理（僅內部稽核持有）。**2026-06-22 結案：accepted by-design，非安全缺口**（持有角色皆可信全廠範圍） | [x] |
| R75-4 | **`get_protocol_animal_stats` 跨客戶 metadata 洩漏 🟠 `[V]`** | `crud.rs:491`：`require_permission!("aup.protocol.view_own")` 後直接查**任一** protocol id 的動物數，無 `require_protocol_*`。**R75-0 確認 CLIENT（最低外部角色）即持有 view_own → 任一外部客戶可查任一計畫動物數 = 跨客戶**。**已修（PR #750，2026-06-18 merged+部署 prod）**：加 `access::require_protocol_related_access(id)`（同 R75-1 pattern，授權契約已由 `api_protocol_copy_idor.rs` 覆蓋）。E2E 為 infra hang，非-E2E 全綠後 admin-merge | [x] |
| R75-5 | **vet-patrol 報告/照片/PDF 跨客戶外洩 🔴 CONFIRMED `[V]`** | 已讀 service 釘死：`vet_patrol_reports` 表**根本無 protocol_id/iacuc_no 欄位**（巡場=全場每週獸醫巡視，非計畫綁定）。`list(Completed/All)`、`get(id)`、photos by id **零呼叫者檢查**；handler 原僅 `require_permission!("animal.record.view")`，而 R75-0 確認外部 CLIENT/PI 亦持該權 → 跨客戶讀全場福利觀察+照片。**已修（PR #747，2026-06-18 merged+部署 prod）**：7 讀取端點改集中式 `access::require_vet_patrol_view`（view_all **或 STUDY_DIRECTOR 角色**，依使用者裁定保留 SD 內部 staff）；排除外部 CLIENT/PI；不動 permissions.rs；3 純單元測試。寫入端點維持 `animal.vet.recommend`（內部，見 R75-12）| [x] |
| R75-6 | **ERP 財務/文件工作流越權（內部）→ by-design（結案）`[V]`** | (b) 文件 approve/admin-approve/reject(`document.rs:206/258/307`) 親驗為 **by-design**：approve 必須是 WAREHOUSE_MANAGER 角色、admin-approve 必須 is_admin——「審核者審別人的單」即 approval 定義，gated 到監督角色非 IDOR。(a) AP/AR 付款收任意 `partner_id`：`erp.document.*` 皆內部角色、partner 為內部 ERP 供應商（非 58 研究客戶）→ 非跨租戶 IDOR，僅「未驗 partner 存在」的內部資料完整性小瑕疵（DB FK 多半已擋）。**2026-06-22 結案：安全面 by-design**；AP/AR partner-exists 檢查列為可選非安全 nicety（R75-6b backlog，低優先）| [x] |
| R75-7 | **audit 讀權限可執行破壞性操作（內部） `[A]`** | `audit.rs:437/517/536`、`ip_blocklist.rs:101`：持 `audit.logs.view` 即可 force-logout 任意 session / 解封任意 IP。**R75-0 確認 QAU 僅有 `audit.logs.view`（無 alerts.manage）卻能 force-logout/解封 IP → 品質稽核角色不應能 DoS 使用者/弱化網路控制**。應收斂為更高權限。（audit log 跨使用者**檢視**=稽核 by-design ✓）。**已修（PR #754，2026-06-18 merged+部署）**：force-logout / 解封 IP / 封鎖 IP 三個變更操作閘門收緊為 `audit.alerts.manage`（QAU 失去、ADMIN_STAFF 保留）；封鎖 IP 收緊由 Gemini #754 補充 | [x] |
| R75-8 | **signature_bridge START 無授權 `[A]`** | `signature_bridge.rs:68`：任何登入者可對任意 `purpose` 開簽署橋接 session。**【2026-06-22 驗證·降級非漏洞 `[V]`】**：`start` 僅驗 purpose 長度（1-50 字、audit 標籤用），session owner-scoped（status/consume 驗 user_id）、mobile_token 只回開啟者本人、用本人憑證簽 → 開 bridge 不賦予任何權限，真正 mutation 在 consume 時各自走 authz，無跨用戶提權。唯一殘留 = payload 明文 at-rest（= R66-C6，綁 R56）。START authz 本身無須修 | [x] |
| R75-9 | **amendment pending-count 無授權 `[V]`** | `amendment.rs:499`：原 `_current_user` 被忽略、回全域待辦數（洩漏全院審查工作量）。**已修（2026-06-22）**：比照 `list_amendments`——staff（`aup.protocol.view_all`）看全域 triage、其餘走新 `get_pending_count_for_user` 僅計自己可見計畫（`user_protocols`）的 pending。sidebar badge 對所有人呼叫故不可 gate 成 staff-only，改 per-user scope | [x] |
| R75-10 | **service-delegated 條目逐項驗證 `[V]`** | **已驗（2026-06-22 讀 handler+service）**。**1 真漏已修**：`list_co_editors`(crud.rs:457) 僅 `view_own`（含 CLIENT）無 protocol scope → 任一登入者列舉任一計畫 co-editor，加 `require_protocol_related_access`。**其餘皆 by-design / 已正確 scope**：remove_co_editor（`aup.review.assign`=staff 監督）、adjust_balance/correct_attendance（HR-admin 管全員）、document list（org-internal ERP）、equipment CRUD（org-internal 共享設備）、training list/get/create（service 已驗 `user_id != current_user.id`→403）、messaging delete（service 驗 `owner != user_id && !admin`→403）、vet_recommendation 舊路徑（`animal.vet.recommend` 僅 VET 持有、VET 有 view_all → 非真漏，consistency-only） | [x] |
| R75-11 | **review comment resolve 無授權 — 任一登入者可改任意審查意見 🟠 CONFIRMED `[V]`（Codex 發現·Claude 親驗）** | `resolve_review_comment`(`handlers/protocol/review.rs:227`)**完全無 `require_permission!`、無 access:: scope、無 protocol 關聯檢查**；service `resolve_comment`(`services/protocol/comment.rs:187`) 僅 `UPDATE review_comments SET is_resolved=true WHERE id=$1`、零 author/reviewer/PI guard。任何登入者(含 CLIENT)可標記**任意計畫**任意審查意見為已解決 → 干擾 IACUC 審查流程(可推向 all_comments_resolved→核准)。**Claude Phase 1 漏網**(僅在子代理 unclear、未進 R75 表)，Codex 去相關複審補上。**已修（PR #751，2026-06-18 merged+部署）**：service resolve_comment 加 require_protocol_related_access（先取意見所屬計畫再驗）；CR query_scalar 收緊一併納入 | [x] |
| R75-12 | **vet-patrol report-level 照片寫入/刪除越權 + 缺 completed-lock 🟠 `[A]`（Codex 發現）** | `upload`(`handlers/animal/vet_patrol.rs:377`) 僅驗 `animal.vet.recommend` + report 存在(`ensure_report_exists`:278 只查存在)；`insert_photo`(:1493) 僅依 report id 寫入、無 created_by/status 檢查；caption update/delete 同。任一 `animal.vet.recommend` 持有者可污染/刪除**任意**巡場報告照片(證據破壞)，且 report-level 照片無 entry-level 的 completed lock。屬 R75-5 家族的**寫入面**(Claude 只標讀取面)。**已修（PR #755，2026-06-18 merged+部署）**：service check_report_photo_writable（completed-lock + 限建立者/admin）+ 4 解析守衛，接 6 個照片寫入端點 | [x] |
| R75-X | **Codex(gpt-5.5) 去相關複審結果 `[V]`** | 2026-06-17 用 Codex CLI(`codex exec --sandbox read-only`, gpt-5.5) 以攻擊者角色重看 R75。**結論：核心全一致 → 最高信心**——R75-1/4/5 agree 可利用(同證據+HTTP request)、R75-2 agree「內部 staff/intern 橫向寫入非跨客戶」、acknowledge_notice **independently 確認乾淨**(can_sign_notice 足夠，我的誤報修正是對的)。**未推翻我任何 confirmed**(無 false-positive)。**補 2 個我漏的**：R75-11(comment resolve)、R75-12(巡場照片寫入)。Codex 獨立 blast 排名：copy_protocol > vet-patrol讀 > 巡場照片寫 > 子紀錄寫 > animal-stats > comment resolve > (notice 乾淨)，與 Claude 一致 | [x] |
| R75-P2 | **Phase 2 去相關性機械檢查 `[V]`** | **已執行**。①`cargo audit`(0.22.1)：1 vuln=**RUSTSEC-2023-0071 rsa 0.9.10 Marvin timing**(medium 5.9，無修補；經 jsonwebtoken 引入，但本系統 JWT 用 **ES256/ECDSA 非 RSA**，rsa 為 transitive 疑非作用路徑)；3 warn=proc-macro-error2 unmaintained(build-time)、rand 0.8/0.9 unsound(僅 custom logger 用 rand::rng() 才觸發)。②`cargo deny`：本機未裝，**CI「Security: cargo deny」job 覆蓋**(近期 PR 綠)、`deny.toml` 存在。③**JWT 撤銷=有查 ✓**：`validate_jwt`(auth.rs:149)查 jti 黑名單 + `enforce_tokens_valid_after`(:116)以 `tokens_valid_after` vs `iat` 批次撤銷(改密碼/角色變更)→**閉合 cso-r2「access token 不撤銷」**；caveat：per-request `is_revoked` 為**記憶體版**，單機 OK，多機(R56/AWS)有 cache 不同步 latent gap。④**危險 pattern grep**：以「僅 CLIENT-held 權限(`animal.record.view`/`aup.protocol.view_own`)且無 access:: scope」為 lens——**獨立重現 Phase 1 結果**(vet_patrol 群=R75-5、animal-stats=R75-4、co-editors=R75-10)，**未發現 Phase 1 漏網新洞**(提高 Phase 1 覆蓋信心) | [x] |
| R75-P2b | **rsa Marvin advisory 追蹤(RUSTSEC-2023-0071) `[V]`** | jsonwebtoken 10.4.0→rsa 0.9.10 無上游修補。本系統 JWT 簽章用 ES256(EC 金鑰)，rsa 應非作用路徑；待 jsonwebtoken 移除 rsa 相依或出修補版再升。低風險、長期追蹤(與 cso-r2 rsa advisory 同條) | [ ] |
| R75-P3 | **Phase 3 ownership 不變式 property test** | proptest 編碼「使用者 X 對非自己資源 R 的任何請求必 403/404、永不 200 帶 R 內容」；跑通後須明說哪些 resource type 未覆蓋。**已完成（PR #775，2026-06-22）**：model-based proptest（perms×roles×membership 隨機空間）驗證 `require_protocol_related_access` / `require_animal_read_access` / `require_animal_access` 的放行集合**恰好等於最小 spec**（view_all perm / 4 view_all 角色 / 計畫成員），含 R75 攻擊者實際持有的 view_own/create/PI/CLIENT → 防授權面 silent drift；同時驗 animal 讀寫之別（`animal.animal.view_all` 只放寬讀）。**未覆蓋**（檔頭明列）：vet_patrol 角色閘〔R75-5〕、`require_protocol_view_access` 4-way 變體、amendment 審查指派、byproduct/messaging/HR/equipment/ERP by-design 角色閘。本機拋棄式 postgres 跑 3×96 cases 全綠 | [x] |
| R75-P4 | **Phase 4 結構性修法（Scoped 遷移已完成；僅剩 D2 CI 掃描防護網）** | 把授權沉進資料層（query fn 強制帶 requesting_user、SQL 內過濾擁有權）或 `Owned<T>` newtype（建構子跑擁有權檢查，忘了就編譯不過），使「漏掉檢查」變編譯錯誤而非稽核項。需使用者核可設計後才動 code。**【R66↔R75 對帳】與 R66-D2 合併為單一結構性決策：R66-D2 = CI handler 白名單掃描（外部防護網、快），R75-P4 = 型別/資料層強制（編譯期根治、慢但徹底）。兩者互補可同時採用**。**【進度】Phase 1（CI 雙軌掃描）已隨 PR #761 完成；Phase 2 protocol 族 `Scoped<ProtocolId>` pilot（3 handler）已實作驗證並經使用者確認 pattern（PR #762）；pilot 後推廣再遷移 5 個呼叫端（copy / review comments / 2 PDF 匯出）。**刻意排除 `change_status`**（被 AI/MCP 等系統情境呼叫，強塞 `Scoped` 需系統後門→削弱保證；**已裁定採方案 A：維持現狀的 handler 層檢查，不開系統後門**，B/C 不採）；`get_protocol`（語意不同 `view_access`）、`get_protocol_animal_stats`（內聯 SQL 無 service 邊界）未納入。**protocol 族（含 #762）已 merged 到 main**。**Phase 2 animal 族 rollout 進行中（PR #763，分批）**：新增 `Scoped<AnimalRead/Write>` 讀寫雙 marker（型別層阻擋唯讀者觸發寫入），pilot 驗證後經使用者確認 pattern；**rollout 完成**：全 animal 模組（surgery / vet_advice / transfer / care_record / observation / sacrifice_pathology / animal_core / 匯出）可遷移授權點皆遷至 `Scoped<AnimalRead/Write>` + 歸屬約束（方案 A）+ copy 來源 IDOR 修補（含 test），28 整合測試綠。排除共用/內部組裝 fn（`list`/`get_by_id`/`get_animal_medical_data`/`AnimalService::update`）與不同 guard（`require_iacuc_protocol_access`/`require_vet_patrol_view`，非 animal-id 物件授權）。**【盤點 + protocol 族補齊，2026-06-22 PR #776】**：依使用者裁定先盤點「真正缺 Scoped 的 object-ownership 資源」——結論 surface 很小：補 `Scoped<ProtocolView>`（get_protocol，= `require_protocol_view_access`）+ `Scoped<ProtocolEdit>`（update_protocol，= `require_protocol_edit`=`can_edit_protocol`），使 protocol 三語意（related/view/edit）皆進編譯期；update service 測試改先 authorize。**裁定排除**：hr/equipment/erp 等 role-gated（非 ownership、抽象錯置）；`change_status`（方案 A）、`get_protocol_animal_stats`（內聯 SQL）、`require_iacuc_protocol_access`（by iacuc_no）。**裁定不做 derive macro**（net-new marker 僅 ~3 個且守衛異質，proc-macro 反更複雜）。**【殘留補齊，2026-06-22】**：notice 簽署改 `Scoped<NoticeSign>`（包 `can_sign_notice`）、amendment create/update/submit 改 `Scoped<AmendmentWrite>`（SYSTEM_ADMIN 短路 或計畫 PI；update/submit id-keyed 以 `ensure_amendment_scope` 綁定 amendment↔已授權 protocol），並移除 `AmendmentService::check_is_pi`（本是 `access::is_protocol_pi` 重複 SQL）；新增 api_amendment_scoped_write.rs 鎖 authorize 契約。**Scoped 結構性遷移收尾**；D2 = CI handler 白名單掃描（防護網）仍另計。**【Follow-up·PR #778 Gemini】existence-oracle 一致性決策（未動）**：mutation 端對「缺失資源」回 404(NotFound) vs 403(Forbidden) 全系統不一致——`Scoped<ProtocolView>::authorize` 回 NotFound、amendment update/submit 亦 NotFound。Gemini 建議 amendment 改 Forbidden 遮蔽存在性；因 (a) 會與既有 ProtocolView NotFound 慣例分歧 (b) UUIDv4 不可枚舉 oracle 無實際可利用性，**未在 #778 單點改**，留作 amendment+protocol 跨模組統一裁定。**【Follow-up·PR #778 CodeRabbit】principal-binding（未動）**：`Scoped<T>` 證明僅承載 resource id、未綁授權者 user id；CodeRabbit 建議加 `principal_id` 並令 service 驗 `actor.id == scope.principal_id`（防 confused-deputy）。因真實流程 handler 對同一 current_user 既授權又建 actor（無不匹配），且加 principal 須改全系統所有 marker（ProtocolId/View/Edit/AnimalRead/Write）+ 所有下游 service、動到已合併碼，屬架構性增強 → 獨立決策，未在收尾 PR 夾帶 | [ ] |
| R75-FP | **【已驗乾淨·勿重查】`acknowledge_notice` `[V]`** | 子代理曾誤報為「無授權可偽造簽名 🔴」；實際 `notice.rs:58` 有 `access::can_sign_notice`(限該計畫 PI/SD)。記此避免日後重複追查。教訓：僅讀 handler 的告警須親讀 service 才能定讞 | [x] |

## 🕒 R76 — HR 打卡地理圍籬修整（2026-06-25 事故 + 落地）

> 來源：使用者 museum（許芮蓁）手機 Safari 打卡失敗。逐 prod log/DB 定案：**單一根因＝室內 GPS 飄移 325~415m > 200m 半徑**（IP 閘對她無效，見下）→ 422 正確阻擋、非 bug。
> **系統性發現**：`ALLOWED_CLOCK_IP_RANGES=10.0.4.0/24`（內網私網段）**永遠不命中**——系統位於 Cloudflare 後 + `TRUST_PROXY_HEADERS=true`，取 `cf-connecting-ip`（`middleware/real_ip.rs:40`）＝辦公室**對外公網 IP**，全史 user_activity_logs 中 10.0.4.x 出現 0 次、110 筆成功打卡全靠 GPS。辦公室對外 IP 為 HiNet **動態 IP**（每 1~4 天輪換、跨 125.231/125.224/1.165 三網段），無法 allowlist 單一 IP。詳見 memory `clock-geofence-ip-gate-dead`。

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R76-1 | **GPS 半徑 200→750（A，立即解卡）** | 室內 GPS 飄移實測 325~415m；因 IP 閘失效、GPS 是唯一有效閘，放寬半徑吸收室內飄移。`.env` line 70 + `docker compose up -d --no-deps api`，已驗證 live（容器 env=750、healthy）。**trade-off**：750m 偏鬆、為唯一關卡，待 R76-3 後可收回 | [x] |
| R76-2 | **打卡失敗寫 audit log（B-now）** | 422 失敗原本只進 tracing log（`attendance.rs` warn）、不進 user_activity_logs，查證需翻 container log。改：`clock_in/out` 失敗時呼叫 `AuditService::log_activity_oneshot`（`event_category=HR`、`event_type=ATTENDANCE_CLOCK_{IN,OUT}_DENIED`、含 reason/IP）。**刻意不用 `log_security_event`**（標 is_suspicious 會撞 R67 自動停權）。`validate_clock_location` 重構為 `clock_location_denial_reason`(回 reason) + `clock_location_business_rule`(422)，原 422-not-403 迴歸測試保留。分支 `fix/attendance-clock-denied-audit`（off main）；cargo check/clippy/unit tests 綠 | [x] 2026-06-25 已合併（**#795**，commit `83435703`）；2026-07-31 台帳對帳時發現此列漏標 |
| R76-3 | **HiNet 固定 IP → 救活 IP 閘 → GPS 半徑收回（B-later）** | 向中華電信申辦辦公室固定 IP（商用，月費數百元）→ 填 `ALLOWED_CLOCK_IP_RANGES` → 在場員工靠 IP 過關、GPS 半徑收回 ~300m 當外勤備援。**blocked**：須使用者對外辦理；到位後僅改設定。同時把現行失效的 `10.0.4.0/24` 改註解標明已失效（避免誤導） | [ ] |

---

## ⏱️ R77 — 加班管理：平日加班費分段計算（2026-06-25 使用者立案）

> 背景：既有 overtime 模組走「補休」制（不計加班費）。本輪導入「加班費」——平日加班(A)按勞基法 §24 分段（前 2h ×1.33、超過 ×1.66），休息日值班(B)按天計，國定假日(C)/天災(D)維持補休。班別兩種：早班 7:30–16:30、常規班 8:30–17:30，下班後起算加班，四捨五入至 30 分（≥15 進位）。本階段不接薪資，僅算時數×係數。設計討論見 PROGRESS §9 2026-06-25。

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R77-1 | **平日加班費分段計算核心 + 班別 schema** | `services/hr/overtime.rs` 新增 `round_overtime_minutes_to_half_hour`/`weekday_overtime_tiers`/`weekday_overtime_weighted_hours` + 常數；`create_overtime` 對平日(A)算 tier1/tier2/weighted。migration 107：`users.work_shift` + `overtime_records` 加 calc_unit/tier1/tier2/weighted/day_count，清空舊資料。`cargo test --lib` 617 綠（+12 計算測試）、clippy clean、臨時 PG 套全 migration + down 驗證。 | [x] |
| R77-2 | **打卡 clock_out 自動產生平日加班草稿 + B 按天入口** | clock_out 依 `users.work_shift`（新增 `WorkShift` enum）算「打卡下班 − 班別下班」自動產生 A draft 加班單，接既有確認/審核流程；B 休息日值班按天 create（day_count）。動 handler → 需 `cargo test --all-targets` + Postgres。 | [ ] |
| R77-3 | **前端加班 UI** | 加班單顯示分段時數/係數、值班按天輸入、班別設定畫面。表格走 `/system_table_chats`。 | [ ] |

### R78 資料庫效能優化（W-series，2026-06-25）

> 為規模主動優化（非僅現況），量測驅動：暫時 PG 灌 5k/50k 合成資料 before/after EXPLAIN。W0-W4/W7/W8 已落地 PR #794 + 部署 prod。詳見 `docs/design/db-performance/db_performance_refactor_plan.md` / `perf_baseline.md` / `db_er_diagram.html`。

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R78-1 | **動物列表兩段式分頁（W1）** | `services/animal/core/query.rs::list()` 先撈頁 id（瘦索引）再 enrich，深分頁 867ms→12ms；結果逐列等價、API/前端不動。 | [x] |
| R78-2 | **pen_location trgm 索引（W2，migration 109）** | 動物 keyword 搜尋 COUNT 31ms→1.4ms（全表 Seq Scan→BitmapOr）。 | [x] |
| R78-3 | **Tier1 業務 JOIN FK 索引 ×5（W4，migration 108）** | stock_ledger.product_id 等補索引；stock_ledger 查 1.6ms→0.48ms。指向 users 的 128 審計欄不加。 | [x] |
| R78-4 | **動物詳情頁前端瀑布（W7）** | `useAnimalDetailQueries` afterParam 子查詢 gate `!boundaryPending`，消 timeline 4 查詢雙重抓取。 | [x] |
| R78-5 | **prod 可觀測性（W0）** | compose db 開 pg_stat_statements + log_min_duration_statement=500 + track_io_timing。 | [x] |
| R78-6 | **寫路徑量測（W8）** | user_activity_logs 16 索引現規模非瓶頸；2 jsonb GIN 邊際成本低，待長期觀測再評估拔除。 | [x] |
| R78-7 | W2 total 策略 | 篩選分頁 total 改精確(trgm)/約略(reltuples)/has-next 三選一，UX 決策待裁定。 | [ ] |
| R78-8 | W5 audit 千萬列實測 | user_activity_logs 灌千萬列量 audit 列表 + HMAC prev-hash 讀 + 寫延遲。 | [ ] |
| R78-9 | W6 schema 結構（條件式，預設不做） | keyset 分頁（需 UI 改「載入更多」）、高頻彙總物化視圖、大日誌表分區修剪檢視。 | [ ] |
| R78-10 | 死索引重盤 | prod 累積 ≥1 月 pg_stat 統計 + 資料量上來後盤 idx_scan=0（現規模太小不可信，450/770 為小表 seq scan 假象）。 | [ ] |
| R78-11 | §7.5 其他面向 | 並發/負載測試、連線池大小、sort 白名單複合索引、access.rs 權限 N+1、分區修剪驗證、autovacuum/stats 新鮮度。 | [ ] |

---

## 🔒 R80 — 資安稽核 follow-up（2026-07-04 六路灰箱稽核）

> 背景：2026-07-04 六路並行灰箱靜態稽核（`docs/security/SECURITY_AUDIT_2026-07-04.md`，0 Critical / 0 High，5 Medium / 4 Low / 4 盲點）。高信心可修者已修+部署（#884/#885）；需權限矩陣/網路拓樸判斷者經使用者裁定（M-3 接受、M-5 調查）。完整處置見 memory `security-audit-2026-07-04`。

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R80-1 | **M-1 設備閒置審批自核守衛** | `approve_idle_request` 補「申請人≠核准人」；抽 `assert_not_self_approval` helper、disposal 一併改用。#884 merged+部署。 | [x] |
| R80-2 | **L-2 設備維護驗收自簽守衛** | `review_maintenance_record` 補「登錄者≠驗收者」。#884。 | [x] |
| R80-3 | **L-4 訊息附件限流層** | `/messages/attachments` 從 write(120/min) 移至 upload_rate_limit(30/min)。#884。 | [x] |
| R80-4 | **M-4 文件 list 依建立者收斂** | `DocumentService::list` 加 created_by_scope，非 WM/admin 只看自建單。#885 merged+部署。 | [x] |
| R80-5 | **B-1/B-2/B-4 設定文件對齊** | session idle 文件↔code、.env.example lockout 15→30、死碼/過時註解。#884。 | [x] |
| R80-6 | **M-3 ERP/GLP 核准 requester≠approver** | 倉庫實際單人，硬守衛會卡死審批 → 接受風險（未改 code，補償控制＝HMAC 稽核鏈）；倉庫 ≥2 人再啟用。 | [x] |
| R80-7 | **M-5 forwarded-ip 信任來源驗證** | 已調查＝現不可利用（api/web 全綁 127.0.0.1 + Cloudflare 唯一入口）；硬化（real_ip 只信反代網段）低急迫 backlog。 | [ ] |
| R80-8 | **L-1 vet_recommendation 物件層授權** | 補 `Scoped` 守衛消未來地雷（自訂角色若把權限給非 view_all 角色即升 High）。 | [ ] |
| R80-9 | **L-3 GDPR 自助刪帳號 cache 殘留** | `deactivate_self` 補 `tokens_valid_after`（撤其他裝置未過期 token，middleware 載權限前先擋）+ handler 補 `permission_cache.invalidate`。**已修+部署 prod（#903）**，測試 `self_deactivate_sets_tokens_valid_after` 綠。 | [x] |
| R80-10 | **滲透測試 live 驗證（隔離 staging）** | 建與 prod 隔離的 staging（假 secret/資料），live 驗證 R80-1~5 修復 + IDOR 水平越權/垂直越權/CSRF/權限守衛/安全 header 共 13 項全正面，無新漏洞。報告 `docs/security/PENTEST_LIVE_RESULTS_2026-07-06.md`。 | [x] |
| R80-11 | **prod 待確認：swagger 應 404 / 應含 HSTS** | 對 prod 實測 `GET /swagger-ui/` 應 404（staging development 才掛）、https 回應應含 `Strict-Transport-Security`（滲透報告動作項）。**2026-07-16：HSTS 部分已確認**（prod https 回應含 `Strict-Transport-Security`，經 R83 zone HSTS 統一補；swagger-ui 404 部分仍待實測）。 | [ ] |
| R80-12 | **F1 功能級授權缺失：庫存告警/藥物/來源無 gate** | 滲透（grey-box + prod loopback）發現 `/alerts/low-stock`+`/alerts/expiry`+`/treatment-drugs`+`/animal-sources` 無 permission gate，任何已認證者（含外部 CLIENT，is_internal=false）可讀全院庫存告警/效期/藥物處方/供應商 PII。補 `require_permission!`（alerts→`erp.stock.view`；drugs/sources→`animal.animal.view_all` 涵蓋內部營運角色、擋 CLIENT view_project）+ 回歸測試 `api_alerts_source_rbac`（4 身分×4 端點）。**已部署 prod（#887 merged→main `0bad9256`，2026-07-06）**：`1d076c90` 初版 + `a8759892` 補 treatment-drugs / 修正 sources gate `source.manage`→`view_all`（避免誤殺 EXPERIMENT_STAFF 建檔下拉）/ 修正測試假通過；`api_alerts_source_rbac` 4 tests 綠 + clippy 0 warning；部署後 smoke：四端點匿名 401、內部角色 200。 | [x] |
| R80-13 | **F2 prod openapi.json 未認證公開** | 使用者決策：所有 AI 都要具名、零匿名自由探索。**已部署 prod（#888→main `e27c2156`，2026-07-06）**：openapi 加認證（具名 session/Bearer 才給完整 schema，匿名 401）；nginx 一併收斂 `/.well-known/{agents,mcp,webmcp}.json`（含工具 input schema）與 `/llms.txt` → 404（`security.txt` 標準聯絡資訊仍公開）。具名 agent 走 admin 發 `mcp_` key + `/api/v1/mcp`（out-of-band）不受影響。smoke：openapi/well-known/llms 匿名皆封鎖、SPA/health 正常。 | [x] |
| R80-14 | **F3 CSP 回報端點走明文 http** | `Reporting-Endpoints` 的 csp-report scheme 由 `$scheme` 硬編 `https`（prod 經 Cloudflare 終結 TLS、origin 是 http 才走明文）。**已部署 prod（#888→`e27c2156`）**；smoke：header 回 `https://`。 | [x] |
| R80-16 | **主機端 NTFS ACL 收斂：`secrets/` + `.env`（新增，2026-07-24）** | 起因：#1039 部署後 api 啟動時的 `[Security/H7] JWT 私鑰檔 mode=777` WARN，原本被判定為「Windows bind mount 顯示假象、不需動作」——**該判定錯誤**。容器內的 mode 顯示確為 bind mount 假象（收斂後該 WARN 仍在，證實與主機 ACL 無關），但去查**真正的控制點**（主機 NTFS ACL）發現 `secrets\` 與 `.env` 自專案根繼承到 `BUILTIN\Users:(RX)`（本機任一帳號可讀）＋ `NT AUTHORITY\Authenticated Users:(M)`（任一已登入帳號可改）＋ `VET\CodexSandboxUsers:(M,DC)`（沙盒群組可改可刪，此條為專案根上的**明確** ACE）。影響全部 24 個 secret 檔，含 `jwt_ec_private_key.pem`（可讀＝可偽造任意使用者含 ADMIN 的 token，直接架空「不可自簽 admin token」紀律）、`audit_hmac_key.txt`（可寫＝GLP §11.10(e) 稽核鏈防竄改性可繞過）、`encryption_key.txt`／`db_password.txt`／`csrf_secret.txt`／`rclone.conf`（離站備份憑證）。**處置（使用者裁定後執行）**：先 `icacls /save` 備份（26 檔 0 失敗）→ `/inheritance:d` 斷繼承 → **先**明確授予 `VET\admin:(F)`（該帳號**不在** Administrators 群組，其存取全靠即將移除的兩條廣泛 ACE，順序反了會鎖死自己與 Docker）→ 移除 `BUILTIN\Users`／`Authenticated Users`／`CodexSandboxUsers`。`.env` 同法（原 ACE 全為繼承，還原僅需 `/inheritance:e`）。**驗證**：`docker compose config` 讀 `.env` 正常；api／web／outbox-worker 三者 `--force-recreate` 後全部起來，api 啟動配置檢查 4 項全 ✅（含 `AUDIT_HMAC_KEY`／`CSRF_SECRET`）、DB self-test 通過、健檢 200，outbox-worker `ChannelRegistry ready`，日誌零 permission/denied。 | [x] 2026-07-24 完成並驗證（prod） |
| R80-17 | **R80-16 殘留三項（新增，2026-07-24；同日依使用者「依序完成」全數處理）** | ① **孤兒 ACE**：`S-1-5-21-...-1347823991:(M,DC)` 無法解析（本機 SID 前綴＋帳號已刪除 → 無 token 能持有，授權對象為零，非風險）。原判「須提權」**是錯的**——`icacls /remove` 對無法解析 SID 回 exit 52、`Set-Acl` 要 `SeSecurityPrivilege`，但那是因為 `Get-Acl`／`Set-Acl` 會連 **SACL（稽核清單）**一起讀寫；改用 .NET `GetAccessControl('Access')`／`SetAccessControl()` **只碰 DACL**，身為 owner 即可，**不需提權**。腳本：`scratchpad/remove-orphan-ace.ps1`。**[x] 已清（secrets\／.env／專案根三處）**。② **`.env` 明文密碼**：查證後**推翻原判斷**——`.env` 154 行／43 設定中**沒有任何真憑證**，所有密碼欄位不是空值（`TEST_USER_PASSWORD`／`DEV_USER_PASSWORD`／`E2E_ADMIN_PASSWORD`，且皆為程式碼註解明講的可選開關）就是路徑，憑證早已全數走 `secrets/`＋`*_FILE`。唯一實質處置＝移除 `SMTP_PASSWORD=CHANGE_ME_...` placeholder：`config.rs::read_secret` 為「`_FILE` 優先、plain 變數 fallback」，留著佔位值會讓 secret 檔讀取失敗時**默默改用 `CHANGE_ME` 當密碼**（SMTP 認證失敗且訊息誤導），移除後才會如實變成「未設定」。**[x] 已處理**。③ **專案根 ACL**：已移除 `BUILTIN\Users:(RX)`＋`Authenticated Users:(M)`＋孤兒 ACE，並明確授予 `VET\admin:(OI)(CI)(F)`。⚠️ **`VET\CodexSandboxUsers:(OI)(CI)(M,DC)` 刻意保留**——該群組是 Codex CLI 沙盒存取 repo 的具名授權，移除會直接打壞該工具；而根目錄下已無憑證（`secrets/`／`.env` 皆已斷繼承並排除該群組），保留它不構成憑證暴露。**[x] 已收斂（保留 Codex 群組待使用者裁定是否一併移除）**。 | [x] 2026-07-24 三項完成 |
| R80-18 | **⚠️ 編輯檔案會重置其 NTFS ACL（新增，2026-07-24，操作陷阱）** | 本輪實測踩到：`.env` 以 `/inheritance:d` 設好明確 ACL 後，**用編輯工具改一次內容，ACL 就被重置回向上繼承**（編輯器多為「寫新檔＋取代」，新檔套用父目錄的繼承規則）。當下若沒重新驗證，會誤以為鎖還在。**推論**：對**經常被編輯的單一檔案**設明確 ACE 本質上脆弱，耐久保護必須來自**父目錄**。現況因專案根已收斂故 `.env` 即使被重置也不會退回「任何本機帳號可讀」，但仍會退回「`CodexSandboxUsers` 可讀寫」。**待做**：① 決定 `.env` 是否改為僅靠根目錄保護（接受 Codex 群組可讀，因其無真憑證）；② 若要維持排除，需在改動 `.env` 的流程後加一步重新套用 ACL＋驗證。**通則：任何 ACL 變更後的驗證要放在所有檔案編輯完成之後，不是變更當下。** | [ ] |
| R80-15 | **F5 2FA/MFA 僅限 admin 啟用** | `two_factor.rs` setup/confirm 為 `is_admin()` gate → 非 admin 特權角色（STUDY_DIRECTOR/PI 等簽 GLP 紀錄者）無法加掛 MFA。**使用者決策（2026-07-06）：維持現狀 backlog**（Low、非急迫），主動提起才啟動。 | [ ] |

---

## 🎭 R81 — Guest demo 全面化 + 執秘存取 + i18n（2026-07-07）

> 背景：使用者走查 guest demo 發現大量空白/crash，並發現執行秘書無法使用邀請管理。系統性修復 + 補架構文件。詳見 `docs/PROGRESS.md` §9 同日條目；guest demo 結構與維護契約見 `docs/spec/architecture/GUEST_DEMO_ARCHITECTURE.md`。

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R81-1 | **執秘邀請管理存取修復** | 根因＝`/admin/invitations` 掛 `<AdminRoute>`（要 admin）底下、內層 `invitation.view` 對非 admin 死碼。#912 選單移人員管理群組、#913 修模擬登入 `/auth/refresh` 400 迴圈、#917 路由移出 AdminRoute→`/hr/invitations`+相容轉址。已驗證執秘可存取+部署。 | [x] |
| R81-2 | **使用者管理預設不顯示停用帳號** | #914，「顯示停用帳號」開關預設 true→false。部署。 | [x] |
| R81-3 | **全前端未翻譯 raw enum 補齊** | #915，稽核 entity(+27)/category(+8)/eventType(+19)+警示+文件/風險狀態+庫存單據+通知+ERP widget i18n；比對 prod DB 實際 distinct 值。部署。 | [x] |
| R81-4 | **ERP PR 標籤正名採購退貨** | #916，依 `DocType` enum 權威（本系統無請購單單據）。部署。 | [x] |
| R81-5 | **Guest demo 全面補假資料（~40 頁）** | #918 補 GLP 8 頁/報表中心/其餘缺口頁（~2200 行）；#919 系統性修 crash（catch-all 物件被當陣列 `.map/.filter`）+ 首頁日曆物件形狀 + 人員訓練 id 對齊。部署。 | [x] |
| R81-6 | **架構文件對齊 prod + Guest Demo 架構文件** | ARCHITECTURE.md 更新（部署圖/技術堆疊/目錄）+ 新增 §7 部門/模組歸屬；新增 `GUEST_DEMO_ARCHITECTURE.md`；校正 `01_ARCHITECTURE_OVERVIEW.md` 版本事實。 | [x] |
| R81-7 | **邀請管理是否 guest 唯讀展示** | 目前刻意隱藏（`GUEST_HIDDEN_CHILD_IDS`，寫入流程）；使用者主動提起才啟動（移除隱藏 + 補邀請列表假資料）。 | [ ] |
| R81-8 | **Guest demo interceptor 支援 query param 過濾** | 現 interceptor 去除 query→demo 選人/日期過濾不生效；若要「選人真過濾」需在頁面層或 interceptor 加 client-side filter。backlog。 | [ ] |
| R81-9 | **殘留「請購單」誤導字眼正名** | ErpWidgets i18n 已改（#916）；殘留 `permissions.rs:501` 註解「可建立請購單」、`zh-TW.json:212` 採購人員角色描述、`docker-compose.yml` print-pdf「WeasyPrint」過時註解（實為 Playwright/Chromium）。純文件/註解（原列 backlog，2026-07-31 完成）。 | [x] 2026-07-31：`permissions.rs` 兩處註解改為「採購退貨」並註明 `DocType::PR` ＝ Purchase Return（權限字串 `erp.pr.create` 本身不改——改動要連 DB seed 一起遷移）、`zh-TW.json` 採購人員描述改「採購與退貨流程」、`docker-compose.yml` 兩處 WeasyPrint 註解改 Playwright/Chromium；另同步修正 `02_CORE_DOMAIN_MODEL.md` 與 `SYSTEM_RELATIONSHIPS.md` 把 PR 誤植為「請購單」以及「PR ──→ PO」的流程圖。 |

---

## 🔍 R82 — 全專案弱點總體檢 follow-up（2026-07-10 五路掃描）

> 背景：使用者詢問「專案弱點在哪」，五路並行唯讀掃描（後端/前端/安全/CI 維運/文件債務）。
> 完整報告與證據位置：`docs/reviews/2026-07-10-weakness-assessment.md`。
> 總評：安全與 CI 紀律紮實；主弱點 = 營運韌性（筆電 prod + 未驗證異地備份）+「巨檔 × 零測試」核心模組。

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R82-1 | **備份還原實機演練** | **完成（2026-07-18 drill PASS）**：今日 02:00 加密備份 → GPG 解密（USB 私鑰+Bitwarden）→ `pg_restore` 到隔離 `ipig_db_drill` → public 表 192＝prod、8 關鍵表 row-count 全相符、RTO ~20 秒；`.env` 三 key 已填、R2+NAS 雙異地今日副本一致。過程抓到並修好 `dr_drill.sh` 的 Windows/Git Bash `/tmp` 路徑 bug。全程不碰 `ipig_db` 本體、演練後私鑰移除復原 USB-only。紀錄見 `docs/runbooks/dr-drill-records.md`。弱點 W1（存亡級）解除。 | [x] |
| R82-2 | **scheduler.rs 補整合測試** | 1866 行零測試。已補 `tests/scheduler_core.rs` 17 測試全綠（低庫存/效期/採購未入庫/手術銷貨稽核各含「該發有發/不誤發/同日不重複」+ leader election 2 + weekly routing 回歸）。掃出 2 疑似 bug 立案 R82-11/12。`should_run_now` 為 private 無法直測（testability gap 已記於測試檔頭）。 | [x] |
| R82-3 | **vet_patrol.rs 補整合測試** | 1941 行零測試。已補 `tests/vet_patrol_core.rs` 12 測試全綠（CRUD 權限 gate、#928 觀察內容三層回歸〔create/GET/audit 快照〕、submit→acknowledge→complete 鎖定生命週期、6 種 audit 事件）。未覆蓋：照片附件端點、PDF 位元組層（範圍外）。 | [x] |
| R82-4 | **CI coverage 改 ratchet** | tarpaulin 改含整合測試量測、門檻=現值下限；前端 vitest 加 `--coverage` + thresholds=現值。**完成（#953 merged + #954 記錄）**：移除 backend coverage matrix 4 組 + ratchet 的 `continue-on-error` → 合併覆蓋率 < baseline−容許誤差即擋 PR；承接 #950 flaky 修 + ENOSPC 消除後啟用。 | [x] |
| R82-5 | **audit_logs HMAC 缺口查證** | legacy `audit_logs`（`services/audit.rs:324-351`）無 HMAC 鏈但承載 SoD 事件。**完成（#934 + #941 merged + 部署 prod 健檢通過）**：清點所有 legacy 寫入點（impersonate start/stop、password reset、force_logout）——**每一個都有並行 HMAC 鏈紀錄**，legacy `audit_logs` 僅舊 dashboard 冗餘副本，W4-1 收斂。查證過程撞到並修復 security bug：`force_logout_session` 原只設 `is_active=false` 不撤 token（中介層不查 `is_active`→強制登出形同失效，access ~15 分＋refresh 最長 7 天仍有效），#941 補 `tokens_valid_after=NOW()`+`revoke_all_user_tokens_tx`、刪重複死碼 `SessionManager::force_logout`、新增回歸測試。opus。 | [x] |
| R82-6 | **CSRF_SECRET 獨立必填** | **完成（#937 merged + 部署）**：改獨立 Docker secret（`./secrets/csrf_secret.txt`，fresh 44 字元）+ `config_check` 軟警告 → `main.rs` `is_production()` fail-fast（比照 `AUDIT_HMAC_KEY`）；dev/CI/test 仍走 JWT 派生 fallback。走 secret file 非 `.env` 明文（對齊 R37）；含 gemini security-high 兩則（空/過短視同未設、`config_check` 查 ≥44 三態）。prod 啟動實測「✅ CSRF_SECRET 獨立設定正確」。opus。 | [x] |
| R82-7 | **前端巨檔試點拆分** | `VetPatrolReportDialog.tsx`（1302 行/25 state+effect）拆為 ≤300 行子元件+hooks，行為零改變；成功後 pattern 批次套用其餘 105 個 >300 行檔。 | [x] |
| R82-8 | **後端巨檔試點拆分** | `services/equipment.rs`（2820 行/39 fn）拆子模組（純搬移不改邏輯、公開 API 不變）；成功後套用其餘 26 個 >800 行檔。 | [x] |
| R82-9 | **通知 job N+1 批次化** | 低庫存/效期通知 per-recipient 2N 次查詢改兩次 `ANY($1)` 批次查詢（**#934 merged**，`has_today_notification` 一併移除）；等價性由 `scheduler_core` 的「該發有發/不誤發/同日不重複」測試在 #934 後的 main 上復跑驗證。 | [x] |
| R82-10 | **死重清理 + README 同步** | (a) `migrations_squashed/` 8 檔查證無引用後刪除，已落地 main（早於本輪）；(b)(c) 已完成（#932）：README migrations 127、狀態列 R81/R82、sqlx 0.9。整項完成。 | [x] |
| R82-11 | **效期通知不吃 admin 設定值** | R82-2 掃出：email 路徑已改吃設定（`fn_expiry_alerts(warn_days,cutoff_days)`），但 in-app 通知 `send_expiry_notifications` 仍獨立重查寫死視窗的 `v_expiry_alerts(-90~+60)`。**完成（fix/r82-followups）**：改收 `&[ExpiryAlert]` 由 scheduler 傳入 config-aware 的 `regular_alerts`，in-app 與 email 同源、管理員設定對兩通道皆生效；補迴歸測試（傳空 alerts red-on-old）。範圍僅通知路徑（儀表板 widget / 月報固定窗語意不同不動）。 | [x] |
| R82-12 | **IACUC 排程註解與實際觸發不符** | R82-2 掃出：`scheduler.rs:558-584` 註解「07:00–15:00」，但 cron `0 0 */2 * * *` 為 UTC 偶數整點＝台灣每日 08/10/…/06 時、全日全週，永不在 07:00 觸發。**完成（fix/r82-followups）**：24/7 每 2 小時通知執秘為合理現行行為，修註解對齊實際 cron（零行為變更），不動 cron。 | [x] |

---

## 🔒 R83 — Cloudflare 邊緣/DNS 資安加固（2026-07-16，帳號 Security Insights CSV）

> 背景：使用者提供 Cloudflare 帳號 Security Insights CSV（~90 條），依真實風險（非 CF severity 標籤）處置 `ipigsystem.asia`（prod 域名）資安缺口。全為 CF 邊緣/DNS 設定與帳號安全，**不涉程式碼、不需重建容器**。詳見 `docs/PROGRESS.md` §9 同日條目 + memory `cloudflare-account-security-2026-07-16` / `hsts-preload-ipigsystem`。

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R83-1 | **CF 帳號 MFA 啟用** | 帳號控 prod Tunnel/DNS/Pages/SSL＝萬能鑰匙，原無 MFA＝最高風險。使用者自綁 TOTP，step-up 實證生效。（認證紅線我不代做。） | [x] |
| R83-2 | **DMARC 上線（p=none）** | 域名有 MX（CF Email Routing）+SPF+DKIM 卻無 DMARC＝可偽冒 `From:@ipigsystem.asia` 寄信。加 `_dmarc TXT v=DMARC1; p=none; rua=…; fo=1`，CF+Google DoH 雙驗生效（系統實從 gmail 寄、不用域名當 From）。 | [x] |
| R83-3 | **zone HSTS 啟用** | 4 個 proxied 子網域（*.pages.dev 別名）原無 HSTS；CF SSL/TLS→Edge Certificates→HSTS 統一補。教訓：預設 6 個月低於 preload 門檻且蓋掉 origin 2 年→改 12 個月。實測全站 `max-age=31536000; includeSubDomains; preload`，preloadable API 全綠。 | [x] |
| R83-4 | **HSTS preload Submit** | hstspreload.org 送出登記進瀏覽器內建清單（補「首次造訪」空窗）。資格已全綠、頁面備好；單向門＋擁有者聲明，使用者一次性手動點 Submit（頁面在自動化下渲染凍結，交回使用者）。 | [ ] |
| R83-5 | **DMARC 升 p=reject** | 1-2 週後收 `rua` 彙整報告、確認無漏算合法寄件來源，把 `_dmarc` 的 `p=none` 改 `p=reject`（域名不當寄件人故安全）。 | [ ] |
| R83-6 | **系統寄信改用 Resend（脫離個人 Gmail SMTP）** | **背景**：2026-08-03 追查 GitHub 歷史外洩（commit `d72c2c3d`，公開 repo 約 4 個月）時發現，外洩的 prod DB dump 內 `system_settings.smtp_password` 為**明文**，且與 prod 當時值的雜湊完全相同＝**從未輪替**；當日已更換 Google 應用程式密碼止血。**現況問題**：① 系統以**個人 Gmail 帳號**當 SMTP relay，系統寄出的密碼重設／邀請連結**副本全留在該個人信箱的寄件備份**——SMTP 憑證一旦外洩即可經 IMAP 讀信、在 token 有效期內劫持任意帳號（含 admin），且 **IMAP 讀信不產生任何登入紀錄**，這是本次事故最危險的衍生路徑；② `smtp_from_email` 雖已設 `noreply@ipigsystem.asia`，但 Gmail 對未驗證別名會**改寫 From** 回帳號地址；③ Cloudflare Email Routing **只能收信轉寄、不提供寄件 SMTP**，故「Gmail 代寄地址」那條路在個人帳號上未必走得通（取決於 Google 是否仍提供「透過 Gmail 傳送」選項）。**做法**：註冊 Resend（免費方案 3,000 封/月、100 封/日、1 網域；實際用量每月數百封，遠低於上限）→ 驗證 `ipigsystem.asia` → 將 Resend 提供的 DKIM／SPF 記錄加進 CF DNS → 產 API key → 於 `/admin/settings`「郵件設定」改四格：`smtp_host=smtp.resend.com`、`smtp_port=587`（STARTTLS）、`smtp_username=resend`（**固定字串，非帳號**）、`smtp_password=<API key>`；`smtp_from_email` 維持 `noreply@ipigsystem.asia`。**程式碼零變更**（`SystemSettingsService::resolve_smtp_config()` 每次寄信直接查 DB、無快取，存檔即生效）。驗收＝該卡片「發送測試信件」＋檢查信件標頭 From 為 `noreply@ipigsystem.asia` 且 DKIM／DMARC pass。**效益／關聯**：DKIM 改用**自家網域**簽章 → DMARC 對齊真正通過 → 為 **R83-5（p=reject）** 的前置條件；同時讓系統郵件與個人 Gmail 完全脫鉤。⚠️ **R83-2 說明中「系統實從 gmail 寄、不用域名當 From」的前提在本項落地後失效**（歷史 section 不回溯改，以本項為準）。⚠️ 落地後 SPF 的 `include:_spf.google.com`（2026-08-03 為嘗試 Gmail 代寄而加）即可移除，注意 SPF 單條記錄的 DNS 查詢上限為 10 次。⚠️ 未查到 Resend 官方明文聲明 SMTP 是否限付費方案，註冊後實測確認。 | [ ] |

> 相關：R80-11「prod https 應含 HSTS」的 HSTS 部分經本輪 zone HSTS 確認在線。`pigmodel.asia` 亦缺 DMARC（走 Amazon SES，需先驗 DKIM 對齊）＝次要、非核心系統，未列追蹤。

---

## 📦 R84 — ERP 現況調查 follow-up（2026-07-22）

> 背景：使用者純討論性提問「調查 ERP 現況」（庫存是否會負值／進銷貨是否記錄品項+批號+來源去向單據／UI 查詢易用性／漏掉什麼／應符合什麼規範）。四路並行唯讀掃描 + 指揮官對關鍵漏洞親自複驗，本輪不動 code。完整報告與證據位置：`docs/reviews/2026-07-22-erp-status-investigation.md`。
>
> **2026-07-22 同日 follow-up**：使用者指出 `docs/spec/modules/ERP_SYSTEM.md` 誤植「銷貨出庫（DO）」為現行流程，討論後確認業務事實（100% 內部耗材領用，無對外銷貨）並對照 code 落實於文件；同時裁定「追溯目標涵蓋全部品項」（R84-3/R84-6 範圍擴大，非僅 GLP 品項）、`R84-8` 查證結果（管制藥品/發票確認在系統外處理，ERP 不做整合）、新增 R84-9/R84-10 兩項技術債清理。本輪同樣**只盤點＋修文件，不動 code**。產出：`docs/spec/modules/ERP_SYSTEM.md`（修正）+ `docs/spec/modules/ERP流程.md`（新增，白話完整流程＋補強計畫）。
>
> **2026-07-22 第三輪 follow-up（prod 查證結果回填）**：使用者在 prod 執行本文件建議的三組 SQL 查證。結果：R84-2（負值庫存）0 筆，查證通過可直接執行；R84-9（DO 單）0 筆，業務事實成立，但補上「PostgreSQL enum 不支援直接刪值，需型別重建」的執行複雜度；R84-10（移除 1200/4100 科目）**查證後推翻原判斷**——這兩個科目仍被 `POST /accounting/ar-receipts`（收款功能）與 `DocType::SR`（銷貨退貨，未被封鎖新建）結構性依賴，與 DO 歷史資料無關，**決定不移除**，標記結案。`ERP_SYSTEM.md`／`ERP流程.md` 同步修正（原本寫「1200/4100 已不需要」的推論是錯的，已訂正）。

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R84-1 | **同單同品項透支漏洞修復** | `process_document` 快照重算延後到整單處理完，同單兩行同品項各自檢查都通過可致負庫存（確定性重現，非低機率 race）；`inventory_snapshots`/`storage_location_inventory` 無 DB CHECK 兜底。修法：建單/核准階段擋同品項重複行，或改逐行即時重算快照；並補整合測試。 | [x] 已修復並合併（#1022，CI 全綠 + CodeRabbit 0 建議） |
| R84-2 | **庫存量表補 `CHECK (>= 0)` migration** | 兩張庫存量表加非負約束（migration 137）＋驗收測試（負值 insert/update 皆被拒）。`document_lines.qty` 依設計定案不在本輪範圍，另案。 | [x] 已落地並合併（#1030，migration 137） |
| R84-3 | **品項批號強制化（2026-07-22 使用者裁定：範圍擴大為全部品項，非僅 GLP 相關）** | `requires_batch_expiry()` 擴大加 PR/TR/SR；migration 138 依 SKU 類別（DRG/MED/CON/CHM）回填既有品項 `track_batch`/`track_expiry`；前端建立品項表單依類別預填 toggle。保守起見只「開啟」該追蹤類別、不強制關 EQP/GEN（避免覆蓋使用者刻意設定）。 | [x] 已落地並合併（#1031，migration 138） |
| R84-4 | **流水/報表單號改可點擊連結** | `StockLedgerReportPage`/`StockLedgerPage`/`PurchaseLinesReportPage`/`SalesLinesReportPage` 的單號改可點擊連結；後端三報表補 `doc_id`。 | [x] 已落地並合併（#1024）；2026-07-23 部署 prod 並實測四個頁面單號連結導向正確 |
| R84-5 | **Reversal（紅單/沖銷）機制** | 🟡 **資料地基已落地**（#1032，migration 139：`documents.reverses_doc_id` + FK + partial unique index + model 欄位）。沖銷邏輯本體（鏡射 `stock_ledger`/`journal_entries`）＋兩階段核准（WAREHOUSE_MANAGER 發起 + ADMIN 核准）＋前端可見性＋新整合測試，因屬合規關鍵路徑且本 session 沙盒無法跑後端測試，**依使用者裁定交付可跑整合測試的環境實作+驗證後再上 prod**（設計見 `ERP流程.md` §6.3.1）。 | [x] 2026-07-23 完成：地基（#1032）+ 沖銷邏輯本體、兩階段核准、5 支整合測試於 local 可測環境實作驗證 |
| R84-6 | **批號追溯視圖（forward/backward traceability，2026-07-22 使用者裁定：涵蓋全部品項）** | 後端無 `/lots/{id}/movements` 類 API，前端無通用批號生命週期（進貨→上架→出庫）追溯頁，僅有倉庫詳情頁的單向「未分配庫存反查來源 GRN」。設計見 `ERP流程.md` §6.2.2。 | [x] 已實作並合併（#1027，CI 全綠 + CodeRabbit 0 建議）；未分配庫存的批號顆粒度追蹤仍是既存限制，見 PR reviewer notes |
| R84-7 | **出庫效期（FEFO）校驗查證** | ~~本輪未查到出庫時是否校驗批號效期，過期批號可能未被擋下扣帳；需另行確認程式碼是否存在此邏輯~~。**2026-07-22 查證完成，確認缺口為真**：`crud.rs`（建單/改單驗證）與 `ledger.rs`（出庫扣帳）皆無任何檢查 `expiry_date` 早於今天就擋下扣帳的邏輯；`batch_no`/`expiry_date` 由使用者手動填在單據行，系統不會自動挑選、也不會拒絕已過期的批號出庫。修復本身（加 FEFO 校驗）未列入本輪範圍，需另案排入開發。 | [x] 2026-07-22 查證完成，確認缺口為真 |
| R84-8 | **管制藥品簿冊／發票流程對帳查證** | ~~麻醉/安樂死管制藥品簿冊、SO 對應的統一發票開立，是否已在系統外處理，需使用者確認~~。**2026-07-22 已確認**：兩者皆在系統外（紙本或其他系統）處理；使用者裁定 ERP 內部**不做**對帳整合，維持現狀。 | [x] 2026-07-22 查證完成，決定不整合 |
| R84-9 | **清除 `DocType::DO` 死碼（2026-07-22 定案：採選項 B，不動 enum 值）** | 規劃書 `docs/reviews/2026-07-22-r84-9-do-enum-removal-plan.md`（#1036）盤點後，**使用者裁定採選項 B**：只清死碼、**保留 DB enum 值 `'DO'`**（無害未用），不做核心表型別重建。範圍＝移除 `models/document.rs` 的 `DocType::DO` match arm 與 2 個測試、`accounting.rs`/`crud.rs`/`workflow.rs`/`notification/erp.rs`/`report.rs` 的 DO 分支、以及 SQL `IN (... 'DO' ...)` 的 `'DO'`（enum 保留故為「不再引用」）、前端 `DocType` union 的 `'DO'` + label。**交由 local 可測環境執行**（本 session 沙盒無法跑後端測試）。 | [x] 2026-07-23 於 local 執行完成：後端 8 檔 + 前端 17 檔清理，`cargo check --tests`／clippy／`cargo test`（照 CI 用 `--test-threads=1`）／`tsc`／`eslint`／`vitest` 全綠 |
| R84-11 | **批號對帳分級 + 8 月盤點逐批重立基準（新增，2026-07-23）** | R84-6 上線後實測 prod：195 個有批號的 lot 有 157 個標紅，其中 150 個是 2026-06-10 前歷史補帳造成的**批號歸屬**差異（品項總量是平的），不是數量出錯，紅字因此失去意義。成因見 `ERP流程.md` §6.2.3。**已做（止血）**：對帳改三級 `balanced`/`attribution_only`/`unbalanced`，紅字降到 7 個且正好是真問題。**待做（根治）**：8 月全倉盤點時寫入 `stock_lot_baselines`，對帳改「期初 + 分界線後異動」，設計見 §6.2.4。⚠️ 一般調整單與盤點都改不了這個差（兩邊同步 +d），只有重立基準有效。 | [x] 分級止血已實作；[ ] 重立基準待 2026-08 全倉盤點 |
| R84-12 | **清除 `DocType::RM`（退料單）死碼（新增，2026-07-22）** | `RM` 同屬死值——前端已隱藏、後端 `process_single_line` 無對應分支。比照 R84-9 選項 B：清 RM 死碼與 SQL 引用、**保留 DB enum 值**，不動核心表。⚠️ **執行前先查證 prod `documents`/`stock_ledger` 皆 0 筆 RM**（DO 已查證過、RM 尚未）。交由 local 可測環境執行。 | [x] 2026-07-23 完成：查證 prod `documents`/`stock_ledger` 皆 **0 筆 RM**（DO 亦 0 筆），與 R84-9 同批清理 |
| R84-13 | **封鎖 SR／RTN 並清除「銷貨收入」會計語意（新增，2026-07-23）** | **使用者裁定（2026-07-23）：業務上不存在銷貨退貨。** ERP 的出庫全是「實驗完成後記錄消耗掉多少耗材／藥品」，**沒有價金**，因此不會有退貨退款這回事。現況問題：`post_sr`（`accounting.rs`）仍停在 DO 時代做法，過帳「借：銷貨收入／貸：應收帳款」——但 SO 從不認列收入，等於**沖銷一筆從未發生的收入**；`report.rs` 6 處 SQL 仍把 SR/RTN 當銷貨退貨計入淨銷貨與毛利；`repositories/accounting.rs:179` 的 AR 帳齡也納入 SR/RTN。**目前無實害**（2026-07-23 查證 prod：SR 0 張、RTN 0 張、科目 1200／4100 分錄 0 筆、有填單價的 SO 明細 0 筆），但屬**條件式地雷**——SR 不像 SO 被擋單價（`validate_line_qty_price` 只對 SO 拒絕），一旦有人開 SR 並填價、核准，帳上就會憑空多出負收入與負應收；單價留空則金額 0、`retain_postable_lines` 會略過那兩行反而正確。**方向**：① 比照 DO（#1005）封鎖 SR/RTN 新建；② 確認無殘留後比照 R84-9 選項 B 清死碼（`post_sr`、`report.rs` 6 處、AR 帳齡、`process_return_in` 等），DB enum 值保留；③「未用完的耗材退回倉庫」若真有需求，用 ADJ 或 R84-5 沖銷單即可，不需要 SR。⚠️ 動到傳票與報表契約，屬合規路徑，執行前需再次確認。 | [ ] 已裁定方向，待排程 |
| R84-14 | **`routes/erp.rs::routes()` 209 行拆分（新增，2026-07-24）** | CodeRabbit 於 #1039 提出。`routes()` 佔 `erp.rs` 第 9–217 行共 **209 行**，是 CLAUDE.md 函式 ≤50 行門檻的 4 倍；R84-5 沖銷只加了 2 行路由，此前已 ~207 行，屬**既有債務**（故未在 #1039 內處理）。修法：依領域（倉庫／儲位／產品+SKU／交易夥伴／單據／庫存）各拆一個 `Router<AppState>` builder，`routes()` 只負責 `.merge()`。純結構重構、零行為變更，驗收＝路由表不變（既有整合測試全綠）。⚠️ **同層其他 router 更嚴重**：`animal.rs` 444 行、`hr.rs` 429 行、`admin.rs` 331 行、`protocol.rs` 266 行皆同一形狀——erp.rs 實為第 5 長而非最長，建議先訂出拆分慣例再逐檔套用，勿只修 erp.rs。 | [ ] |
| R84-15 | **後端整合測試 `setup_pool` 收斂為共用 harness（新增，2026-07-24）** | CodeRabbit 於 #1039 提出，當時以「與 `TestApp::spawn()` 抽象層級不同、只改一檔反而破壞慣例」說明不採納並承諾另案，即本項。現況：`backend/tests/` 下 **17 個檔案各自定義 `async fn setup_pool()`**（`erp_r84_5_reversal`／`erp_r84_1_same_line_overdraft`／`erp_adj_storage_floor`／`api_*` 等），每份都重寫同一段「讀 `TEST_DATABASE_URL` → **fallback `DATABASE_URL`** → `migrate!().run()`」；**共用 harness 自己也是同一段**——`tests/common/mod.rs:34-50` 的 `TestApp::spawn()` 用完全相同的 fallback 契約（且它是 HTTP 層，沒有 service 層對應物），合計 **18 處**。⚠️ **風險不只是重複**：那個 fallback 正是 CLAUDE.md 紅線「禁止在 prod 跑 backend 整合測試」的觸發點——未設 `TEST_DATABASE_URL` 就會對 prod DB 跑 migration + 寫測試資料，污染正式表與稽核鏈。**⚠️ 修法必須連契約一起改（CodeRabbit 於 #1040 指出，已採納）**：單純把 `setup_pool` 集中化而保留 fallback 契約**不會**解除紅線，反而把 18 個各自的錯點收斂成一個影響面更大的錯點。收斂時一併改為 **fail-closed**：① 未設 `TEST_DATABASE_URL` 即拒絕執行，**不** fallback 到 `DATABASE_URL`；② 偵測到 prod DSN／production 環境時，在 `connect` 與 `migrate` **之前**就 fail；③ 補回歸測試鎖住此行為（未設 / 指向 prod 兩種情境皆須 fail）。 | [ ] |
| R84-16 | **prod 實測沖銷流程（R84-5 上線驗收，新增，2026-07-24）** | #1039 已於 **2026-07-24 09:02 (GMT+8)** 部署 prod（api+web 重建、`up -d`、`/api/health` 200、日誌無 error），並以 `POST /api/v1/documents/{id}/reverse` 與 `/reverse-approve` 回 **401**、對照組亂路徑回 **404** 驗證兩條路由確實掛載。**但業務流程本身尚未在 prod 實測。** 待測項：① WAREHOUSE_MANAGER 發起沖銷 → ADMIN 核准的兩階段走通；② 驗收重點＝沖銷必須是**鏡射原單**、而非「用當下庫存重跑業務邏輯」——#1039 的 `663c5a14` 修掉的 `approve()` 漏洞正是後者（GRN 沖銷會再寫一筆 in），需比對 `stock_ledger` 與 `journal_entries` 的沖銷列與原單「方向相反、數量／金額相等」；③ 確認 WM 單獨無法完成沖銷（SoD 擋板生效，對應測試 `reversal_cannot_go_through_normal_approve`）。⚠️ 需真實帳號登入操作，**不可自簽 admin token**。 | [ ] |
| R84-17 | **`663c5a14` 的 SoD 修補補審（零外部 review 即上 prod，新增，2026-07-24）** | #1039 的 `663c5a14` 修掉 `DocumentService::approve` 未檢查 `reverses_doc_id` 的漏洞——沖銷單（`status=submitted` + `manager_approval_status='wm_approved'`）會讓 `needs_admin` 判定為 false，直接落到一般核准分支：① 用**當下庫存**重跑業務邏輯而非鏡射原單；② 只要 `WAREHOUSE_MANAGER` 即可執行，**繞過沖銷設計的 ADMIN 最終核准（SoD）**。⚠️ **該修補未經任何外部 review 即進 main 並部署 prod**：commit 推於 2026-07-23 21:18 (GMT+8)，CodeRabbit 最後一次審是 21:06，之後未再審——2026-07-24 於 #1040 確認**根因是 CodeRabbit 帳號 PR review 額度耗盡**（bot 明言 `Review limit reached / we couldn't start this review`），**不是**審過沒意見。待做：對 `approve()` / `admin_approve()` 兩條擋板與 `reversal.rs` 鏡射邏輯做一次深度 review，確認 `reversal_cannot_go_through_normal_approve` 真的鎖住 SoD、且沖銷確為鏡射而非重跑。**⚠️ 連帶制度問題（需使用者裁定）**：CLAUDE.md 常設授權的「bot 0 建議」閘在額度耗盡時會**靜默 fail-open**——「沒有 bot 意見」與「bot 根本沒審」外觀完全相同；判準宜改為「確認 bot 實際提交了 review」。授權節只有使用者能改。 | [ ] 使用者裁定（2026-07-24）先立案記錄，暫不補審 |
| R84-10 | ~~移除會計科目 1200 應收帳款／4100 銷貨收入~~（新增，2026-07-22） | ~~SO 一段式流程已不使用這兩個科目（僅供舊 DO 單相容顯示），動手前需先查證無歷史分錄~~。**2026-07-22 查證後推翻原判斷、決定不做**：這兩個科目仍被跟 DO 無關的現行功能結構性依賴——`POST /accounting/ar-receipts`（`AccountingService::create_ar_receipt`，記錄客戶收款）寫死需要科目 1200；`DocType::SR`（銷貨退貨）目前未被封鎖新建，核准過帳（`post_sr`）仍會用到 1200 與 4100。移除會直接打壞這兩個現行功能，維持現狀。 | [x] 2026-07-22 查證後決定不移除 |

---

## 🗳️ R85 — 舊計劃書補登：委員意見與獸醫歸屬釐清（2026-07-22）

> 背景：第二批 4 筆 115 年新案（PIG-115014/015/016/017）已完成 4 階段匯入 prod（建單 → working_content → 執秘+獸醫意見 → 里程碑，記於 PROGRESS §9）。**委員意見仍 park**，但查證後發現卡點與先前認知不同：不是「委員沒帳號」（migration 085 已支援 `reviewer_name` 文字 fallback，無帳號也能記），而是**審查意見回覆表全篇不具名**——掃過 PIG-115 全部 58 份回覆表，`吳建男/葉沂萱/陳序宸` 等名字一次都沒出現，只有「委員一~四」代號；姓名僅存在於①輪值表 `3.IACUC\動物實驗申請表審查輪值表.xlsx`②各案 `4-審查同意書\*審核結果.pdf`（每位審查者一頁的手寫簽名掃描）。已用簽名章範本 `3.IACUC\審核結果簽名檔\` 做筆跡比對，**確認 4 筆各自的審查者名單且與輪值表完全一致**，但三種順序（審核結果頁序／輪值表序／回覆表委員序）彼此對不上，無法靠順序推得對應。
> 使用者側處理中（不列入本輪）：洪昭竹帳號已邀請待確認、葉沂萱目前僅需 VET 權限不加 REVIEWER、吳建男定位由使用者釐清。

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R85-1 | **委員N ↔ 姓名對應** | 回覆表「委員一~四」無署名，無法對回真人。建議請執行秘書陳怡均直接指認（僅 4 筆，簽名頁已辨識完畢）；若無法指認則退為「只記名單不綁意見」或 `reviewer_name` 寫「委員一」保持忠於原件。既有 27 筆年代更久，恐只能後者。 | [ ] |
| R85-2 | **獸醫師 12 項審查表歸屬確認** | 現行**全部 31 筆**（既有 27 + 新 4）都掛 **葉沂萱**，係沿用前一 session 慣例、**無文件依據**（回覆表獸醫簽名欄在 docx 內為空白，且無已簽名 PDF）。新證據指向 **吳建男**：輪值表每列都有、每案審核結果都蓋「獸醫師吳建男」紅印；葉沂萱名冊職稱為「委員」。掛錯將使 31 筆獸醫審查指向錯的人。 | [ ] |
| R85-3 | **委員 slot 排序不穩修復** | `build_committee_items` 依意見出現序填 committee_1..4，但查詢為 `ORDER BY COALESCE(parent_comment_id, id), created_at`——主鍵是 **UUID**，故列印的委員一/二/三跨次渲染可能變動、也不對應紙本順序。屬既有行為；補委員意見前需先修，否則印出來對不上原件。 | [ ] |
| R85-4 | **委員意見補登實作** | 依 R85-1/2/3 結果執行。原始資料已抽出可用（115014 委員 16 條含委員四、115015 9 條、115016 15 條、115017 13 條，一審/二審欄位分明）。⚠️ `record_import_reviews` 為**全量取代**，補委員時務必連執秘＋獸醫一起帶，否則既有資料會被清掉。 | [ ] |
| R85-5 | **既有 27 筆試驗/對照物質錯置修正** | 申請表 T14=試驗物質、T15=對照物質，舊抽取器把**兩者都塞進 `control_items`**，UI 會把試驗物質標成「對照物質」。新 4 筆已依型別正確分流 `test_items`/`control_items`；舊 27 筆待修。 | [ ] |
| R85-6 | **PIG-115014 GLP 旗標矛盾確認** | 申請表勾「█ GLP動物試驗」，進度表 col39 卻寫 Non-GLP（PIG-115016 則兩格都沒勾）。本次依進度表填 `is_glp=false`，影響 GLP 專屬區塊（結果分析／文件歸檔）是否顯示，需人工確認何者為準。 | [ ] |
| R85-7 | **補登抽取器與 payload 的歸屬**（2026-07-31 改變做法） | 原立案是「4 個 payload JSON 也進版控」，因為上一輪的 `_phase4/_phase5` 產物被 git clean 清掉。**討論後使用者裁定不進版控**：JSON 是「docx → 抽取器 → JSON → CLI → DB」管線的中間產物，寫進 DB 後即無用途（執行期零程式讀取，已查證），真相源是 DB、憑證是原始申請表；留在版控會造成 DB 改動後兩邊分岔、public repo 曝露聯絡資訊與審查意見全文、review bot 把資料當程式碼審而誤判（本輪實例：`application_no` 被指為筆誤，查 prod 後確認 18 筆中僅 4 筆同號、PIG-115017↔APIG-115018 為真實交錯）。**已做**：`git rm` 3 個 payload JSON、`.gitignore` 排除 `_artifacts/*.json`、工作檔移至 `C:\System Coding\_import-artifacts\`、四支 CLI 移除 repo 內預設路徑改為 `--file` 必填（原預設值三個皆已指向不存在的檔）、`docs/design/README.md` 記錄慣例。兩支抽取器早前已入版控。⚠️ 舊版已於 #1094（`59c6d1ac`）先合進 main，故那 3 個檔在 **git 歷史裡留有一份**（含姓名／委託公司／審查意見全文，不含聯絡方式）；要徹底清除需重寫歷史，另案裁定。 | [x] 2026-07-31 |
| R85-8 | **31 筆 finalize-import 收尾** | 全系統 36 筆計畫、31 筆仍 `import_pending=true`（僅 PIG-115010 已完成補登）。補登內容確認齊備後執行 finalize（清旗標 + 鎖定 + 建 v1 快照）。⚠️ 2026-07-31 補充：finalize 的 **v1 快照就是「匯入內容的凍結紀錄」**——R85-7 撤掉 JSON 版控後，這件事從「收尾」升級為補上凍結紀錄的正解，優先度提高。 | [ ] |
| R85-9 | **`enrich_imported_protocols` 補稽核（新增，2026-07-31）** | 該工具第 90 行是裸的 `UPDATE protocols SET working_content = $1 ...`，**不寫任何 audit**——建單有 `PROTOCOL_IMPORT_APPROVED`（36 筆，`after_data` 約 1.3 KB 的建單骨架）、審查有 `REVIEWS_RECORDED`（62 筆），唯獨「正文被填了什麼」在稽核鏈上是空白，只能看 DB 當前值（可變）。比照其他 bin tool 走 `ActorContext::System` 寫一筆 `PROTOCOL_IMPORT_CONTENT_ENRICHED` + data_diff。合規路徑，動手前確認事件名與 `verify_audit_chain` 對齊。 | [ ] |

---

## 🔍 R86 — 最近十支 PR 獨立 code review 發現（2026-07-27）

> 背景：對 #1046–#1055 做獨立審查（5 個 subagent 並行，明確要求不採信 PR 說明與 commit message、每個發現須說得出具體失敗情境）。本表**只列已由主對話回程式碼／prod DB 逐一查證屬實**的項目；agent 提出但查證後為誤判者不列（例：「羊舍欄位 code 應為 S」——pen code `羊` 確實存在，agent 與我先前都因 `length(code) <= 2` 過濾而漏掉，本 DB `server_encoding=SQL_ASCII`，`length('羊')` 回 3）。
> 已在本輪修掉的不列入：`format_pen_location` panic（PR #1073）、失效的 `is_deleted` SOP/spec SQL（PR #1059）、停用物種代碼救回（PR #1056）。
> 詳細報告：`scratchpad/review-1052.md`、`review-1050-1046.md`、`review-1053-1054.md`、`review-1048-1051.md`、`review-1055-docs.md`（本機，未進版控）。

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R86-1 | **加班核准 SoD 缺口（合規）** | `approve_overtime`（`services/hr/overtime.rs:540-586`）只比對 status，**無「不可自審」也無「兩關不得同人」檢查**。清單過濾（`:227-228`）有擋自審且註解宣稱「與 approve_overtime handler 一致」——**該宣稱不實**，直接打 API 即可核准自己的加班。prod 實測：17 筆兩關 approver 皆同一帳號（間隔約 0.3 秒）。請假模組已有正解可照抄（`leave.rs:258` 自審絕不放寬 + `:267` has_prior_approval + `:285-289` 無人可簽才代批）。使用者裁示：自審絕不放寬、加代批機制、負責人不送加班單。既有 17 筆不回滾、另寫說明。 | [x] 2026-07-28 已修並部署（**#1077**：不可自審 + 終審關 SoD + 無其他合格終審者才放寬代批；`backend/tests/hr_overtime_sod.rs` 三例；api 映像 2026-07-29 22:44 GMT+8 重建） |
| R86-2 | **加班補登可重複執行且不可逆** | `overtime_records` 只有 `pkey(id)`、無防重唯一鍵；`create_overtime` 無重複檢查。`docs/ops/overtime-backfill-template.js:193` 卻教人「中斷就重跑」→ 補休餘額翻倍且無沖銷路徑。**2026-07-31 使用者裁定**：DB 唯一索引 + service 檢查雙層防重，唯一鍵取 `(user_id, overtime_date, start_time, end_time)` 且排除 rejected/voided；另加「作廢已核准加班單」通道（ADMIN 單簽 + 理由必填、不得作廢自己的單、補休已被使用則擋下）。 | [x] 2026-07-31 已合併並部署 prod（**#1093**，migration 142 於 api 啟動時套用、`_sqlx_migrations` 已達 142；唯一索引與 voided 欄位皆已驗；路由 `POST /hr/overtime/:id/void` 回 401 對照亂路徑 404）。⚠️ 業務流程本身尚未在 prod 實測（需真實帳號登入，同 R84-16 性質） |
| R86-3 | **`animalSpeciesLabel` 蓋掉 `breed_other`** | `lib/animalSpecies.ts:22` 讓 `species_name` 優先，選「其他」品種時表單**強制**填的自由文字（如「藏香豬」）永遠顯示不出來。#1052 引入的回歸，改動前 5 個顯示點皆正確。修法：`breed === 'other' && breed_other` 時優先回傳自由文字。 | [x] 2026-07-28 已修並部署（**#1076**） |
| R86-4 | **GLP 品種更正核准後畫面不變** | `field_correction.rs:303-318` 只 `UPDATE breed`、不動 `species_id`，而顯示端已改為優先讀 `species_name` → 走完整套申請與核准流程的欄位更正**在 UI 上完全失效**。 | [ ] |
| R86-5 | **`PUT /animals/:id` 的 `species_id` 繞過所有驗證** | `update.rs:153` 直接 `COALESCE($11, species_id)`，不驗存在／啟用／葉節點、也不重推 `breed`（`requests.rs:84`）。可寫入停用或非葉節點物種，並造出 `species_id` 與 `breed` 矛盾的列。同 struct 上方註解卻寫「breed 建立後不可更改」。 | [ ] |
| R86-6 | **儀表板斷點座標可能寫錯格** | #1053 把斷點記錄改為父層 passive effect，但 RGL 的寬度 effect 在子樹且**先執行**並呼叫 `onLayoutChange`；編輯模式下跨斷點縮放（1680 xl → 1300 lg）再儲存，會把 lg 的 12 欄座標寫進 `byBreakpoint.xl`。⚠️ agent 判定，**尚未獨立查證**。 | [ ] |
| R86-7 | **byproduct 月結報表靜默漏列** | `byproduct_sample.rs:624` 改成 INNER JOIN `a.deleted_at IS NULL`，動物一經軟刪，其**已計費**採樣紀錄即從月結報表/XLSX 消失且無提示。財務列的真相源應為同查詢的 `ebs.deleted_at`。目前該表 0 列，潛伏未爆。是否應含軟刪動物屬財務業務決策。 | [ ] |
| R86-8 | **`pens` 缺 `(zone_id, code)` 唯一約束** | prod 實有兩個 `S01`（羊舍區 active / 羊１ inactive）。`pen_location` 以 code 字串關聯，兩個實體欄位會撞同一字串；#1058 已於查詢端以 `LATERAL LIMIT 1` 迴避，根治需清理重複資料後於 schema 層加約束（schema=必問）。 | [ ] |
| R86-9 | **成員路徑參數綁定無 DB-backed 測試** | #1048 修的是「有佔位符沒 bind → 500」，但新測試只涵蓋 `list()`；`get_my_protocols` 的三個單元測試是 DB-free 字串比對。同類 bug 若發生在成員側，CI 抓不到，後果是一般成員在 /protocols 按篩選整頁 500。 | [ ] |
| R86-10 | **AI 路徑未達「單一真相源」** | `repositories/ai.rs:264-297` 等 7 處 JOIN animals 仍不濾 `deleted_at`：AI 動物清單已排除軟刪豬，但觀察紀錄查詢仍回它們的 14 筆。 | [ ] |
| R86-11 | **`requests.rs:51` 註解與實作不符** | 註解寫「兩者皆未提供則回 422」，實際為 **400**（`error.rs:115` + 測試 assert 400）。 | [x] 2026-07-31：註解改為 400 並註明來源（`SpeciesLink::resolve` 回 `AppError::Validation`，`error.rs:115` 對應 `BAD_REQUEST`） |
| R86-12 | **`.claude/skills/` 未納版控** | `protocol-import-backfill/SKILL.md` 等只存在於開發機（未被 gitignore，只是從未 add），無版控備份與 review 軌跡；該檔記載「查重必做」與 256/257/258 重複事故教訓。使用者裁示暫不納管，列此備忘。（`docs/ops/legacy-sync-sop.md` 已於 PR #1059 納管。）| [ ] |
| R86-13 | **828 出生日期疑似輸入錯誤** | 4 隻山羊中 828 為 `2025-01-01`，其餘三隻與交接文件皆為 `2025-01-30`。`birth_date` 建立後不可直接改，需走動物欄位修正申請流程。 | [ ] |

---

## 🧵 R87 — 多 session 並行環境收斂（2026-07-30）

> 背景：2026-07-30 實測同一 repo 上 5 個 session 並行（transcript jsonl 5 分鐘內 4 份被寫入）。協議 `docs/agents/PARALLEL_SESSIONS.md`（PR #1091）與強制 hook（本輪）已落地，本 section 只留需要「挑時間執行」的環境收斂工作。

| # | 項目 | 說明 | 狀態 |
|---|------|------|------|
| R87-1 | **共用 CARGO_TARGET_DIR 遷移（有時效性）** | 現況每個工作區各有一份 target：`ipig-claude` 18.6 GB + `ipig-alert-unlock` 10.2 GB + `ipig-alert-source-ip` 4.6 GB = **33.4 GB**，而 C: 僅剩 **84 GB（83% 已用）**。這台同時跑 prod，磁碟耗盡會拖垮正式服務（2026-07 已有清磁碟事故）。改指向 `C:\System Coding\.cargo-target-shared` 後只需一份，相依 crate 只編一次。**必須等所有 session 閒置才做**——別人正在 build 時刪 target 會讓編譯中途爆掉；且只刪自己工作區那份。協議 §4 已寫入做法。 | [ ] |

---

## 📊 待辦統計

> **未完成合計 115**，但其中近半為**明確擱置**（提起才動）。下方分區摘要為實際可動的判讀依據；其後的逐輪表為完整歷史台帳。
> 🔴 **權威值判讀（2026-07-24 補；CodeRabbit 於 #1040 指出本區數字互相矛盾）**：本行的 `115`、下方「🟢 可動 backlog」表頭的 `~58` 與其 R84 列的 `7`，**都是 2026-07-22 的舊值，非權威**。權威值一律以本區**最新一則校正紀錄**為準（現為 2026-07-24：合計 **114**、可動 backlog **~57**）。差額來源已列於該則校正紀錄的「對帳註記」：2026-07-23 落地的 R84-5／R84-9／R84-12 三項完成、以及併發 session 新增的 R84-13 皆無對應校正紀錄，尚未併入。**下次制度對帳時一次精算並把本區三處數字改回一致，屆時刪除本行。**
> **校正紀錄（2026-06-22）**：原合計 108 過期（未計入 R75 整輪、R66↔R75 對帳關閉 4 項）；本次補 R75 row + 重算為 103。
> **校正紀錄（2026-06-25）**：R78 DB 效能 W-series 落地 PR #794（6 項 [x]），新增 5 項 backlog（R78-7..11，多為條件式/待裁定）；合計 +5。
> **校正紀錄（2026-07-01）**：新增 R79 動物預約與試驗規劃（Phase 0 schema 已落地 #829/117，Phase 1-4 待做 4 項）；合計 +4（96→100）。匯入體重 ①/②/①b-1 已完成（#823/#826/#828，記於 PROGRESS §9，非 TODO 追蹤列）。
> **校正紀錄（2026-07-02）**：R79 Phase 1-3 完成（R79-2 #837 / R79-3 #839 / R79-4 #840，3 項 [x]），僅剩 Phase 4 前端規劃頁（R79-5）進行中；合計 100→97。另：計劃書「顯示未選選項」rollout 收尾 Purpose #822 + DRY 收斂 #827 + backend cargo fmt #838 完成（記於 PROGRESS §9，非 TODO 追蹤列）。
> **校正紀錄（2026-07-02b）**：R79-5 Phase 4 已合併 #841（[x]）；使用者重新定位規劃頁為「全場活豬清冊」→ 新增 R79-6（Phase 5 清冊改造，進行中）+ R79-7（計畫結案防呆 backlog）；合計 97−1+2 = 98。
> **校正紀錄（2026-07-03）**：R79-6 全場活豬清冊已合併 #845、R79-7 計畫結案防呆已合併 #846（兩者 [x]，均未部署）；標頭同步 98−2 = 96。docs 全面稽核修正（README Zod/React/migration 數/tree、TODO/PROGRESS R79 對齊）+ 部門分類回填 migration 123 + backend cargo fmt 補齊（equipment.rs 重構避 SQL guard）—記於 PROGRESS §9。
> **校正紀錄（2026-07-05）**：新增 R80 資安稽核 follow-up——R80-1..5（M-1/L-2/L-4/M-4/B系列）已修+部署（#884/#885）、R80-6（M-3）接受風險，共 6 項 [x]／已決；R80-7..9（M-5 硬化 / L-1 Scoped / L-3 GDPR cache）為 backlog 3 項；合計 +3（96→99）。
> **校正紀錄（2026-07-06）**：滲透測試 live 驗證完成（R80-10 [x]，隔離 staging 建置 + 13 項正面確認，記於 PROGRESS §9）；新增 R80-11 prod 快檢 backlog 1 項；合計 +1（99→100）。另 agent 工作制度重構（CLAUDE.md 瘦身 + docs/agents/）記於 PROGRESS §9，非 TODO 功能追蹤列。
> **校正紀錄（2026-07-06b）**：滲透測試 grey-box + prod-loopback 這條線的 findings 入列——F1（R80-12，庫存告警/藥物/來源授權 gate）code+test 綠待部署；F2/F3/F5（R80-13..15，openapi 公開決策 / CSP http / 2FA 僅 admin）處置項；F4=R80-6/M-3 已接受（本次獨立 live 復驗風險為真）。新增 4 項；合計 +4（100→104）。findings 報告 `docs/security/PENTEST_FINDINGS_2026-07-05.md`。
> **校正紀錄（2026-07-06c）**：F1（R80-12，#887）、F2（R80-13）、F3（R80-14）三項已修+部署 prod（#888→main `e27c2156`）並 smoke 驗證，各標 [x]；F5（R80-15）依使用者決策維持 backlog。合計 −3（104→101）。
> **校正紀錄（2026-07-07）**：新增 R81（guest demo 全面化 + 執秘存取 + i18n）——R81-1..6 已修+部署（#912–919，6 項 [x]，記於 PROGRESS §9），R81-7..9 為 backlog 3 項（邀請管理唯讀展示決策 / demo query-param 過濾 / 殘留「請購單」註解正名）；合計 +3（101→104）。
> **校正紀錄（2026-07-06d）**：quick win 兩項落地——R80-9（L-3 自助停用撤其他裝置 token，#903）、R73-3（dashboard `formatTime` 抽共用 `formatTimeShort`，#904）已修+部署 prod 並 smoke 驗證；R80-9 標 [x]、R73 群組 4→3。合計 −2（101→99）。
> **校正紀錄（2026-07-07）**：quick win R73-4（兩份 Textarea 收斂為單一實作 `ui/textarea.tsx`，`ui/input.tsx` re-export，#906）已修+部署 prod 並 smoke 驗證；R73 群組 3→2。合計 −1（99→98）。
> **校正紀錄（2026-07-10）**：新增 R82 全專案弱點總體檢 follow-up（五路掃描，報告 `docs/reviews/2026-07-10-weakness-assessment.md`）——R82-1..10 共 10 項 backlog（其中 R82-1 限本機、R82-4 動 CI 需核准、R82-5/6 安全類 opus）；合計 +10（98→108）。
> **校正紀錄（2026-07-10b）**：R82 首批不碰紅線項落地——R82-2（scheduler_core 17 測試）、R82-3（vet_patrol_core 12 測試）標 [x]；R82-10 之 (b)(c) README 同步完成（#932），剩 (a) 待核准；R82-2 掃出 2 疑似 bug 立案 R82-11（效期通知不吃設定值）/R82-12（IACUC cron 註解不符）。合計 −2+2 = 108 不變。
> **校正紀錄（2026-07-10c）**：R82-9 通知 N+1 批次化完成（**#934**，使用者實作+merge）標 [x]；R82-5 部分完成（#934 補 IMPERSONATE_STOP 鏈，殘留 user.rs / session_manager 等 legacy-only 事件查證，維持 [ ]）。合計 −1（108→107）。
> **校正紀錄（2026-07-11）**：R82-6 CSRF_SECRET 獨立 secret + prod fail-fast 完成（**#937** merged+部署，走 Docker secret file、config_check `is_production()` fail-fast、含 gemini security-high 2 則）標 [x]；R82-7（`VetPatrolReportDialog.tsx` 拆 hooks+子元件）/ R82-8（`equipment.rs` 拆 7 子模組）巨檔試點完成（記於 PROGRESS §9）標 [x]。另 R82-10 之 (a) `migrations_squashed/` 8 檔已刪除落地 main（(b)(c) 早於 #932 完成）——整項待使用者確認後標 [x]。合計 −3（107→104）。
> **校正紀錄（2026-07-11b）**：R82-5 audit 鏈殘留查證結案（**#941** merged + 部署 prod 並健檢通過）標 [x]——清點所有 legacy `audit_logs` 寫入點皆有並行 HMAC 鏈、W4-1 收斂；過程修復 `force_logout` 不撤 token 的 security bug（access ~15 分＋refresh 最長 7 天原仍有效，現真斷線）。另 R82-10 之 (a) `migrations_squashed/` 刪除早已落地 main，本輪一併確認結案標 [x]（(b)(c) 早於 #932 完成）。合計 −2（104→102）。tarpaulin coverage job 之紅為 GitHub runner ENOSPC（儀器化編譯階段磁碟耗盡、測試未執行、ratchet skipped）infra flake，非程式/覆蓋率問題，正確性由 `cargo test`（綠）驗證。
> **校正紀錄（2026-07-16）**：新增 R83 Cloudflare 邊緣/DNS 資安加固（帳號 Security Insights CSV）——R83-1/2/3（帳號 MFA / DMARC p=none / zone HSTS）已完成並實測（記於 PROGRESS §9），R83-4/5（HSTS preload Submit 使用者手動 / DMARC 升 p=reject 1-2 週後）為 backlog 2 項；合計 +2（102→104）。另 #978 GRN（migration 131）本 session 已 build+up-d+健檢部署 prod。
> **校正紀錄（2026-07-17）**：對帳台帳漂移——R82-4（CI coverage 硬門檻）實已完成並落地 origin/main（#953 merged + #954 記錄，PROGRESS §9 2026-07-12 有條目），台帳誤標 `[ ]` → 更正 `[x]`、R82 可動待辦 4→3；R76-2（打卡失敗寫 audit）實已 merge（#795，`dc80852e`）非「審核中」→ 更正描述（R76 待辦數不變，仍為 R76-3 blocked）。合計 −1（104→103）、可動 backlog ~58→~57。
> **校正紀錄（2026-07-17b）**：R82-11（效期 in-app 通知改吃 admin 設定、與 email 同源 + 迴歸測試）+ R82-12（IACUC 排程註解對齊實際 cron）完成（fix/r82-followups，與 R82-1 DR 演練腳本 + 本次台帳校正同批）；R82 可動待辦 3→1（僅剩 R82-1 備份演練待 USB 解密）。合計 −2（103→101）、可動 backlog ~57→~55。
> **校正紀錄（2026-07-18）**：R82-1 備份還原實機演練**執行並 PASS**（今日 02:00 加密備份→USB 私鑰解密→pg_restore 到隔離容器→8 表 row-count 全相符、192 表、RTO ~20s；紀錄 `dr-drill-records.md`）；過程修好 `dr_drill.sh` Windows/Git Bash `/tmp` 路徑 bug。R82 可動待辦 1→0（**R82 整輪清零**）、弱點 W1 存亡級解除。合計 −1（101→100）、可動 backlog ~55→~54。
> **校正紀錄（2026-07-22）**：新增 R84 ERP 現況調查 follow-up（四路並行掃描 + 指揮官親自複驗，純討論不動 code，報告 `docs/reviews/2026-07-22-erp-status-investigation.md`）——R84-1..8 共 8 項 backlog（同單同品項透支修復 / 庫存量表 CHECK 約束 / GLP 品項批號強制化 / 流水單號可點擊 / reversal 機制設計 / 批號追溯視圖 / FEFO 查證 / 管制藥品簿冊對帳查證）；合計 +8（100→108）、可動 backlog ~54→~62。
> **校正紀錄（2026-07-22b）**：同日 follow-up——使用者釐清 `ERP_SYSTEM.md` 的 DO/SO 錯誤敘述並確認業務事實（100% 內部耗材領用），產出 `ERP_SYSTEM.md` 修正 + 新增 `ERP流程.md`；R84-8 查證完成標 `[x]`（管制藥品/發票確認系統外處理，裁定不整合）；新增 R84-9（移除 `DocType::DO` enum，需先查證 prod 無歷史 DO 單）、R84-10（移除會計科目 1200/4100，需先查證無歷史分錄）；R84-3/R84-6 範圍擴大為全部品項（非僅 GLP）。合計 −1+2 = +1（108→109）。另核對「可動 backlog」逐行加總後發現與標頭數字長期有落差（非本輪引入，往前追溯至少到 ~62/51 的版本已有 11 項落差）：標頭改為逐行加總的準確值 ~52（62+1→52，而非 63）。
> **校正紀錄（2026-07-22c）**：使用者依 §「DB 查證」提供的 SQL 在 prod 執行查證結果回填——R84-2（負值庫存 0 筆，查證通過可執行）、R84-9（DO 單 0 筆，業務事實成立，但補上 PG enum 型別重建的執行複雜度）皆維持 `[ ]` 但補充執行細節；R84-10（移除會計科目）**查證後推翻原判斷**——因 `POST /accounting/ar-receipts` 與 `DocType::SR` 過帳結構性依賴 1200/4100，決定不移除，標 `[x]` 結案。`ERP_SYSTEM.md`／`ERP流程.md` 原本「1200/4100 已不需要」的錯誤推論已訂正。R84 可動待辦 9→8。合計 −1（109→108）、可動 backlog ~52→~51。
> **校正紀錄（2026-07-22d）**：新增 R85 舊計劃書補登 follow-up——第二批 4 筆（PIG-115014/015/016/017）已 4 階段匯入 prod 完成（記於 PROGRESS §9，非 TODO 追蹤列）；本輪列 R85-1..8 共 8 項 backlog（委員N↔姓名對應 / 獸醫歸屬確認 / 委員 slot 排序修復 / 委員意見補登實作 / 27 筆試驗對照物質錯置 / 115014 GLP 旗標矛盾 / 抽取器進版控 / 31 筆 finalize）；合計 +8（108→116）、可動 backlog ~51→~59（基準取 2026-07-22c 校正後的逐行加總值）。
> **校正紀錄（2026-07-22e）**：R84-7（FEFO 校驗查證）完成——複查 `crud.rs`/`ledger.rs` 確認出庫路徑無任何過期批號校驗，缺口為真，標 `[x]`（修復本身未列入本輪，留待另案）。同輪並針對 R84-1（同單同品項透支修復）、R84-4（流水單號可點擊連結）動手實作，各開一支 PR（`fix/r84-1-same-line-overdraft`、`feat/r84-4-clickable-doc-links`），CI 綠燈前不算完成，狀態維持 `[ ]` 待 PR 合併後再標記。另修復一個與 R84/R85 皆無關、但同日新公告會擋下所有 PR 的 `cargo-deny` 資安檢查失敗（`ammonia` RUSTSEC-2026-0213 patch bump，`chore/deps-ammonia-rustsec-2026-0213`）。R84 可動待辦 8→7。合計 −1（116→115）、可動 backlog ~59→~58。
> **校正紀錄（2026-07-22f）**：R84-3/R84-5/R84-6 設計定案（使用者裁定：R84-3 分類預設值起點、R84-5 WAREHOUSE_MANAGER 發起+ADMIN 核准兩階段權限、R84-6 時間軸+對帳不做族譜樹），寫入 `ERP流程.md` §6.2.1/§6.2.2/§6.3.1（PR `docs/r84-3-5-6-design`）。依風險排序（R84-6 最低風險/純新增 → R84-3 → R84-5）依序動手，本輪完成 R84-6 實作：新增 `GET /inventory/lot-movements`（`backend/src/services/stock/ledger.rs`）回傳批號時間軸（跨倉彙總）+ 數量對帳摘要（分類加總的 `derived_remaining` 對照 `storage_location_inventory` 獨立來源的 `remaining`，不一致即標記 `balanced=false`）；前端新增 `LotMovementsPage` 時間軸頁，`InventoryRow` 的批號徽章改為可點擊連結。開 PR（`feat/r84-6-lot-traceability`），CI 綠燈前不算完成，狀態維持 `[ ]`。R84 backlog 總數與可動數不變（本輪為既有項目動手實作，非新增/移除）。
> **校正紀錄（2026-07-22g）**：`chore/deps-ammonia-rustsec-2026-0213`（cargo-deny 資安修補，解除卡住所有 PR 的 CI 卡點）與 `docs/r84-3-5-6-design`（R84-3/5/6 設計文件）皆已合併，其餘等待中的 PR 依序 rebase 主幹後 CI 全綠。R84-1（`fix/r84-1-same-line-overdraft`，#1022）與 R84-6（`feat/r84-6-lot-traceability`，#1027）皆通過 CI 全綠 + CodeRabbit 0 建議，squash merge 完成，標 `[x]`。R84-4（`feat/r84-4-clickable-doc-links`，#1024）CI 已全綠，CodeRabbit review 仍在跑，待下輪確認後再標記。R84 可動待辦 7→5（扣除 R84-1、R84-6）。合計 −2（115→113）、可動 backlog ~58→~56。
> **校正紀錄（2026-07-22i）**：R84-9 規劃書產出並定案——盤點移除 `DocType::DO` 需動 2 核心表欄位、5 個 view、~15 處程式碼，**使用者裁定採選項 B（只清死碼、保留 enum 值，不動核心表）**，R84-9 由「待規劃型別重建」改為「定案採 B、交 local 執行」（仍 `[ ]`，無淨計數變化）。新增 **R84-12**（清 `DocType::RM` 死碼，比照 B，執行前需查證 prod 0 筆 RM）＝ +1。規劃書 `docs/reviews/2026-07-22-r84-9-do-enum-removal-plan.md`（#1036）。⚠️ 對帳註記：R84-11（批號對帳分級，併發 session 於 main 新增）未見對應校正紀錄、其計數未併入本行；為免跨 session 重複計數，本行僅計自身 +1（110→111，可動 backlog ~53→~54），R84-11 的精算留待下次制度對帳。
> **校正紀錄（2026-07-22h）**：「把未完成的依序完成」執行輪。R84-4（#1024）CodeRabbit 結案後合併，標 `[x]`。新實作三支 PR 全數合併：R84-2（#1030，migration 137 兩張量表非負 `CHECK` + 驗收測試）、R84-3（#1031，`requires_batch_expiry()` 加 PR/TR/SR + migration 138 依 SKU 類別回填 + 前端類別預填 toggle）、R84-5 **地基**（#1032，migration 139 `documents.reverses_doc_id` + FK + partial unique index + model 欄位）皆標 `[x]`／地基完成。R84-5 沖銷邏輯本體＋兩階段核准工作流因屬合規關鍵路徑、本 session 沙盒無法跑後端測試，依使用者裁定交付可測環境實作（R84-5 狀態維持 `[ ]` 但註明地基已落地）。同輪並補一條 CLAUDE.md 環境事實（禁止在 prod 跑 backend 整合測試，#1029）。`ERP流程.md` §5/§6、`PROGRESS.md` §9 同步更新至現況。R84 可動待辦 5→2（扣除 R84-2/3/4；剩 R84-5 邏輯本體、R84-9 DO enum 移除）。合計 −3（113→110）、可動 backlog ~56→~53。
> **校正紀錄（2026-07-24）**：#1039（R84-5 沖銷單本體）merge 時，依使用者裁定把該 PR review 中兩則**既有債務**立案：新增 **R84-14**（`routes/erp.rs::routes()` 209 行拆分——量測同層 router 後發現 `animal.rs` 444／`hr.rs` 429／`admin.rs` 331／`protocol.rs` 266 行皆同形狀，erp.rs 為第 5 長非最長，故條目改為「先訂拆分慣例再逐檔套用」）、**R84-15**（`backend/tests/` 17 檔各自定義 `setup_pool` 收斂為共用 harness；重點是那段 `TEST_DATABASE_URL`→`DATABASE_URL` fallback 散成 17 份，正踩 CLAUDE.md「禁止在 prod 跑 backend 整合測試」紅線）。同輪依使用者指示新增 **R84-16**（prod 實測沖銷流程——#1039 已部署且路由以 401／404 對照驗證掛載，但兩階段核准的業務流程本身未實測，驗收重點是「鏡射原單」而非重跑業務邏輯）。另依使用者裁定新增 **R84-17**（`663c5a14` 的 SoD 修補零外部 review 即上 prod，先立案記錄暫不補審；並記下「bot 0 建議」閘在 CodeRabbit 額度耗盡時會靜默 fail-open 的制度問題）。同日並新增 **R80-16**（`secrets/`＋`.env` 主機端 NTFS ACL 收斂，當日完成並於 prod 驗證，直接標 `[x]`，不計入未完成數）與 **R80-17**（其殘留三項）。**同日使用者指示「依序完成」，R80-17 三項當日全部做完並標 `[x]`**：孤兒 ACE 改用 DACL-only 方式清除（**推翻「須提權」的原判斷**）、`.env` 查證後**推翻「有明文密碼」的原判斷**（實為零真憑證，僅移除一個 placeholder）、專案根收斂但**刻意保留 `CodexSandboxUsers`**（Codex CLI 沙盒的具名授權，移除會打壞該工具；根下已無憑證故不構成暴露）。另新增 **R80-18**（操作陷阱：編輯檔案會重置其 NTFS ACL，耐久保護須靠父目錄）。合計 +6−1 = +5（111→116）、可動 backlog ~54→~59（基準取 2026-07-22i 的 111／~54；R80-16、R80-17 皆為當日完成不計未完成數，R80-18 計 1 項）。⚠️ **對帳註記（留待下次制度對帳精算，本行不計）**：(a) 2026-07-23 落地的 R84-5（#1039）、R84-9／R84-12（#1038）三項完成、以及併發 session 新增的 R84-13（封鎖 SR/RTN）皆無對應校正紀錄，其增減未併入本行；(b) 下方「可動 backlog」表的 R84 列（7 項）與 R85 列仍是 2026-07-22 的舊敘述，尚未反映上述完成項；(c) 本區 `2026-07-22i` 行位置排在 `2026-07-22h` 之前但內容以 h 的結果 110 為基準，實際順序為 h→i，勿依檔案順序判讀。
> **校正紀錄（2026-07-30）**：新增 **R87 多 session 並行環境收斂**——R87-1（共用 `CARGO_TARGET_DIR` 遷移）計 1 項。同輪落地但**不計入未完成數**者：`docs/agents/PARALLEL_SESSIONS.md` 並行協議（#1091）與強制 hook `.claude/hooks/guard-parallel-sessions.sh`（14 條 pipe-test 全過），皆已完成。合計 +1（116→117）。⚠️ **對帳註記（本行不精算）**：逐輪表**缺 R86 整列**（2026-07-27 新增 13 項），故 116／117 這兩個數字都未反映 R86；本行只做 +1 的機械遞增，不動既有漂移——精算仍留待下次制度對帳（見 2026-07-24 行的對帳註記）。
> **校正紀錄（2026-07-31）**：R86（#1074 立案 13 項）在本區**從未有對應校正紀錄**，其 +13 至今未併入任何合計數字——本行同樣不做總數精算（維持 ⚠️ 權威值判讀行的待辦），只記本輪三項狀態變動：**R86-1 加班核准 SoD** 於 2026-07-28 由 #1077 修復並隨 2026-07-29 22:44 (GMT+8) 的 api 映像部署 prod（本輪查證後標 `[x]`，此前台帳誤留 `[ ]`）；**R86-3 品種自由文字回歸**由 #1076 修復並部署（同樣補標 `[x]`）；**R86-2 加班補登防重 + 作廢通道**本輪實作完成（migration 142 唯一索引 + `void_overtime` + 7 例整合測試 + 範本說明更新），依慣例 PR 合併前維持 `[ ]`。另補記 #1077 / #1076 於 `PROGRESS.md` §9（兩者原本只有 commit、無變更紀錄條目）。
> **校正紀錄（2026-08-03）**：新增 **R83-6**（系統寄信改用 Resend，脫離個人 Gmail SMTP）計 1 項。立案觸發＝當日追查 GitHub 歷史外洩事故（ticket 4608154）時，發現外洩 dump 內的 `smtp_password` 為明文且從未輪替，連帶查出「系統郵件副本堆在個人 Gmail 寄件備份」這條可繞過密碼雜湊直接劫持帳號的路徑。同輪落地但**不計入未完成數**者：Google 應用程式密碼已更換（DB 值雜湊已驗證不再等於外洩值）、SPF 補 `include:_spf.google.com`。合計 +1（117→118）。⚠️ **對帳註記（本行不精算）**：沿用 2026-07-30／07-31 兩行的處置——R86 的 +13 與 2026-07-23 那批完成項仍未併入任何合計，本行只做機械遞增，精算留待下次制度對帳（見 2026-07-24 行）。

### 🟢 可動 backlog（我能做，~58；2026-07-22e 再校正一次）

> ⚠️ 本表為 **2026-07-22 舊值**，未反映 2026-07-23 落地的 R84-5／R84-9／R84-12 與新增的 R84-13／R84-14／R84-15／R84-16。權威值見上方「權威值判讀」行。

| 輪 | 待 | 性質 |
|---|---|---|
| 🗳️ R85 舊計劃書補登 follow-up | 8 | 委員N↔姓名對應（需執秘指認）/ 獸醫 12 項歸屬確認（影響 31 筆）/ 委員 slot UUID 排序修復 / 委員意見補登實作 / 27 筆試驗對照物質錯置 / 115014 GLP 旗標矛盾（需使用者確認）/ 抽取器 payload 進版控 / 31 筆 finalize-import |
| 📦 R84 ERP 現況調查 follow-up | 7 | 同單同品項透支修復（PR 開啟中，待 CI）/ 庫存量表 CHECK 約束（查證通過可執行）/ 全品項批號強制化（範圍已擴大）/ 流水單號可點擊（PR 開啟中，待 CI）/ reversal 機制設計（需使用者裁決）/ 批號追溯視圖（範圍已擴大）/ 移除 DO enum（查證通過，待規劃 PG 型別重建步驟）（已完成：R84-7 FEFO 查證確認缺口為真、R84-8 管制藥品/發票查證裁定不整合、R84-10 移除會計科目查證後決定不移除） |
| 🔒 R83 CF 邊緣/DNS 資安加固 | 2 | HSTS preload Submit（使用者手動一次性 R83-4）+ DMARC 升 p=reject（1-2 週後 R83-5）（已完成：R83-1 MFA / R83-2 DMARC p=none / R83-3 zone HSTS） |
| 🔍 R82 弱點總體檢 follow-up | 0 | **全數完成**（R82-1 備份演練 2026-07-18 PASS + dr_drill.sh 上線、R82-2/3 測試、R82-4 coverage ratchet #953、R82-5 audit 鏈殘留#941、R82-6 CSRF #937、R82-7/8 巨檔拆分、R82-9 N+1 #934、R82-10 死重清理+README #932、R82-11 效期通知一致性 + R82-12 排程註解） |
| 📚 R69 SOP 訓練系統 | 9 | 最大功能（schema→考卷→簽署→前端，PR-A~H 未動工）|
| 🔒 R66 滲透測試 follow-up | 4 | 2 Med（B1 park/B4 park）+ 1 Low（C5）+ D2（=R75-P4）；簽章 OTP…（**B2 TOTP 加密 PR #779 + C6 payload 加密 PR #780**/B3 鎖定/C1 主體+C1b DNS-pin/C4/C7/B5 accepted-risk 結案）|
| 🔒 R75 授權稽核收尾 | 2 | R75-P4 結構性（protocol 族 view+edit PR #776；notice-sign + amendment 寫入 Scoped 收尾，殘留僅 D2 CI 掃描防護網）/ P2b rsa（P3 property test 已完成 PR #775；R75-3/6 by-design 結案、8 降級、9/10 已修）|
| 📝 R61 簽章合規（DocuSeal 借鑑）| 8 | audit certificate PDF 等，需求觸發、落地前必停 |
| 🚀 R35 系統 backlog（active 部分）| 7 | 非 park 的 wave 項 |
| 🧹 R73 多餘 code dedup | 2 | 重複 code、非 bug（R73-3 formatTime #904、R73-4 Textarea #906 已完成；**R73-1 部分完成** #908 僅 backfill_import_reviews + create_guest 改用 config::read_secret，清單其餘 ~5 支未動；剩 R73-1(部分)/R73-2）|
| ♿ R65 a11y aria-label i18n | 1 | ~98 處，可分批 |
| 零散 | ~3 | R60-2a real-data 測試 / R67-3 偵測器強化 / R68-11 submit 重構 |
| ⚡ R78 DB 效能 backlog | 5 | W2 total 策略（待裁定）/ W5 audit 千萬列實測 / W6 keyset・物化視圖（條件式）/ 死索引重盤（時間閘）/ §7.5 六項 |

### 🅿️ PARK（明確擱置，提起才動，~49）
| 輪 | 待 | park 原因 |
|---|---|---|
| ☁️ R56 AWS 遷移 | 13 | 擱置（~200h / 月費）|
| 🤖 R43 AUP AI 預審 | 12 | 秘書 1 人、延後 |
| 🌡️ R21 環境監控 | 11 | 場內無感測設備 |
| 🚀 R35 系統 backlog（parked 部分）| 11 | 11/18 已 park |
| 🚨 R36 Backup/NAS 遷移 | 2 | blocked by NAS 採購（R36-11）|

### 🔒 外部手動（非我能做，等 vet/QA/ops，~3）
- R32-A8f、R39-D1：**vet/QA 在 Word 範本加 docxtpl 變數**
- R62-2：**跑 prod + 人工 review CSV + ops migration 070**

---

#### 逐輪歷史台帳

| 優先級 | 數量 (未完成) |
|--------|------|
| 🚨 P0 上線前必要 | 0 |
| 🟡 P1 上線前建議 | 0 |
| 🔴 P2 中優先 | 0 |
| 🔵 P3 低優先 | 0 |
| 🟣 P4 品質提升 | 0 |
| 🟣 R4-100 邁向 100% | 0 |
| ⚪ P5 長期演進 | 0 |
| 🟠 R6 第六輪改善 | 0 |
| 🔒 R7 安全審視 | 0 |
| 🔧 R8 代碼規範重構 | 0 |
| 🔒 R9 安全與品質修復 | 0 |
| 🔒 R10 程式碼審查 | 0 (3 推遲) |
| 🔧 R11 技術債 + Git 修復 | 0 |
| 🟢 R12 長期演進項目 | 0 (1 暫緩) |
| 🎨 R13 UI 一致性 | 0 |
| 📄 R14 PDF 輸出修正 | 0 |
| 🔍 R15 Code Review 發現 | 0 |
| 🔍 R16 全專案 Code Review | 0 |
| 🔒 R17 CSO 安全審計 | 0 (1 已接受, 3 完成) |
| 🫀 R18 Heartbeat 自動化維護 | 0 (4 完成) |
| 🎫 R19 客戶邀請制入口 | 0 (14 完成) |
| 🤖 R20 AI 預審與執行秘書標註 | 0 待 (R20-9/10 park 2026-05-26；8 完成) |
| 🌡️ R21 環境監控子系統（MES-Lite） | 11 (1 暫緩) |
| 🛡️ R22 攻擊偵測與主動告警 | 0 (17 完成, 1 暫緩) |
| 🎨 R23 全站 Table UI 升級 | 0 (20 完成) |
| 🛡️ R24 Observability 補強 | 0 (4 完成) |
| 🔒 R25 安全基礎設施補強 | 0 (5 完成) |
| 🔄 R26 Service-driven Audit 重構延伸 | 0 (R26-15 完成 2026-05-26 PR #490 auth audit trail；15 完成；含 R26-12 保留編號) |
| 🔧 R27 E2E + bot review 後續清理 | 0 (9 完成) |
| 🔧 R28 bot review + R26/R27 code review 發現 | 0 待 (R28-5 完成 2026-05-28 — log_security_event_tx 改走 HMAC chain + backfill_hmac_version bin tool；R28-1 deferred / R28-10 kill-switch 已遮蓋) |
| 🔧 R29 ClawSweeper review follow-up | 0 (全部完成；R29-5 提前實作 PR #258，R29-5b follow-up 列入 R30-J) |
| 🔍 R30 三軸 Code Review 後續（併發 / 操作日誌 / GLP） | 0 (40 完成含 R30-9a/9b 全部；R30-8/15 使用者跳過 ✅) |
| 🔒 R31 CSP 強化 | 0 待 enforce 已落地（R31-9/10/13b 完成 via PR #410 — Playwright 真實 enforce prod 3 engines 0 violations；剩 R31-12 移除 report-uri 觀察期 till 2026-08-07 / R31-13 style-src 長期接受 risk） |
| 📄 R32 PDF 生成重做 | 1 (A1-A7/A8-A9/A8a-e/A8g/A8h/A8i/A8j 完成 via PR #340/#341/#343/A8i 新 PR — 砍 ~3000 行 legacy code + printpdf/lopdf 兩 Cargo dep + audit_log 從 client-side HTML→docx 一致化；剩 A8f vet_patrol 等 vet/QA 加 docxtpl 變數 — **code-only 工作已 100% 清零**) |
| 🔒 R33 滲透測試 follow-up | 0 (R33-1 完成 via PR #393、R33-2/3 完成 via PR #339；R33-4 完成 via PR #428 — JWT access token 15min；R33-5 accepted risk；daily 4 findings 全 merged via PR #337) |
| 🔧 R34 50 項 codebase audit 分批清理 | 0 待 (TAKE 22 中 15 落地 + 7 push-back / 已實作；整批進 PR #340 main；DEFER 9 + coderabbit follow-up D11~D16 條觸發條件追蹤) |
| 🚀 R35 系統改進 backlog（5 wave / 24 PR） | 18 待 (R35-3/4/21 完成 2026-05-28；Wave 1~5 ship 進度同前；parked 11 項不變) |
| 🚨 R36 Backup & DR 緊急修復 + 異地備份 | 2 待 (R36-1~10 完成 — cold-start.md 2026-05-13 補完；R36-11 deferred 情境 A；R36-12/13 blocked by R36-11；R36-9 首次 DR drill 通過 row-count 5 表全相符) |
| 🔐 R37 .env 明文密碼遷移到 Docker Secrets | 0 待（全部完成 2026-05-09 via PR #362；R37-8 拆分到 R38-4，R37-12 完成 dead code cleanup） |
| 📄 R38 Word COM Daemon 取代 Gotenberg 主路徑 | 0 待 ✅ wrap up 2026-05-10 — daemon 上線 + observability + secret + runbook 全部完成；prod fallback rate 0%；R38-D1 字體驗證 deferred 為 ad-hoc QA（infra 全到位） |
| 📄 R39 獸醫巡場報告完整重設計 | 1 待 (R39-D1 vet/QA 在 Word 內加 entry photo nested block；R39-D2 完成 2026-05-27 使用者驗收 PDF OK；R39 PR #363 已 merged + prod deployed 2026-05-10；R39-16/21/24/27 deferred 或 N/A) |
| 💬 R40 站內信 + R39 deferred refactors | 0 待（R40-A MVP 9/9；R40-B 6/6 完成 via PR #407 — 6 commits 完整收尾 + 採納 CodeRabbit 2 項 + Gemini 1 項 deny / 1 項已做）|
| 🛡️ R41 NICS 防護基準合規 gap | 0 待 (8/8 全部完成；Phase A 文件 + Phase B SAST + Phase C 後端 idle + R22 串接驗證 + at-rest 評估全落地；R41-2 旗標啟用為 ops 在 staging 驗證 ≥7 天後手動切換) |
| ⚡ R42 Word COM daemon 效能改善 | 0 待 (R42-8 N/A — COM daemon 已於 R55 PR #489 刪除，WeasyPrint 取代) |
| 🤖 R43 AUP AI 預審（OpenAI） | 12 待 (admin 手動觸發；5 面向 rubric；輸出 = Tab + PDF 附錄 + audit；cloud-only；payload sanitize 去耳號/個資) |
| 🪟 R44 Word/Excel COM daemon 拆分 | 0 待 (R44-5/6 N/A — COM daemon 已於 R55 PR #489 刪除) |
| 📄 R45 PDF 渲染架構收斂 | 0 待 (R45-6/7 N/A 2026-05-27 — 評估後不執行：PagedJS 2026-05-13 已嘗試失敗、WeasyPrint 原生支援所有需要的 CSS、container 大小無改善) |
| 🔔 R46 refresh_token_reuse 告警降噪 + UX | 0 待 (R46-3 觀察完成 2026-05-26：5/21 起零 reuse 事件，R46-1/2 + R57 per-tab idle 有效；R46-1~7 全完成) |
| 🐷 R47 可用豬隻快速查詢（庫存盤點） | 0 待 (8/8 完成 2026-05-14 via PR #386 — backend 4 + frontend 4 + clippy/tsc/eslint/integration tests 全綠) |
| 🛡️ R48 Tiered 安全偵測改善（ATR 借鏡） | 0 待 (R48-2 SARIF 完成 2026-05-26 PR #492；R48-1/4 完成；R48-3 deferred) |
| 👤 R49 Guest mode 全面修整 | 0 待 (10/10 完成 2026-05-14 via PR #390 — 崩潰修補 + 4 處 demo data + GuestBlock 元件 + admin/QAU 解鎖 + 編輯頁擋下 + prod redeploy) |
| 🧹 R50 Post-R49 穩定性 + lettre advisory | 0 待（4/4 完成 2026-05-14 via PR #393/#394/#395/#396）|
| 🚀 R51 Auto-deploy watcher | 0 待（4/4 完成 2026-05-15 via PR #399/#402/#404/#405 — 首次 end-to-end self-deploy 成功）|
| 🔐 R52 SHA-pin 第三方 GitHub Actions | 0 待（2/2 完成 2026-05-14 via PR #398）|
| 🧹 R54 前端 dead-vars 清理 + eslint rule 升級 | 0 待（4/4 完成 via PR #415 — 5 problems → 0 problems）|
| 🧪 R53 廢棄物再利用紀錄 + 豬隻病歷週報 | 0 待 ✅（R53-A 6/6 + R53-B 3/6 + R53-10/10b/11/12/13/14/15 全完成 2026-05-27）|
| 🧹 R55 print-pdf cutover follow-ups | 0 待（R55-4/5 完成 2026-05-26 PR #489 — 刪除 gotenberg + word-convert 源碼 + orphan Prometheus/Grafana 清理 -1697 行；R55-1~6 全完成）|
| ☁️ R56 AWS Migration（prod-on-laptop → AWS hybrid + CDN 拆前後端） | 13 待（Phase 0~10 + 4a/4b/4c；詳見 `docs/plans/r56-aws-migration.md` §10 補充 — 162h + contingency 1.3x = ~200-220h，日曆 3-4 個月，月費 ~NT$4,800-3,500）|
| 🔄 R57 Sliding Session follow-ups | 0 待 + 1 deferred（R57-12 完成 PR #499 43 files selectors + R57-14 完成 PR #500 E2E；R57-10 deferred）|
| 🧹 R58 前端 lib Zod 移除 | 0 待（R58-2~5 全部完成 2026-05-17 via PR #451；~130 callsite 從 zodResolver 遷移到 RHF native rules）|
| 🧹 R59 Handler 命名 codebase-wide refactor | 0 待（R59-1 完成 2026-05-26 PR #491 — 選 (b) 修 CLAUDE.md spec 配合既有 list_/create_/get_ 風格 + 新增 Handler 命名慣例表）|
| 📄 R60 PDF 模板視覺對齊 11/11 | 1 後續 (11/11 完成 2026-05-27 PR #501 — 4 clean + 2 fix；R60-2a real-data 測試 backlog) |
| 📝 R61 DocuSeal 借鑑項目 | 8 待 (R61-A 3 項補位缺口 + R61-B 5 項依需求觸發；R61-C 3 項已 push-back 不計入；任一項落地前必停 surface tradeoff — 簽章 / 法規路徑高風險) |
| 📦 R62 ERP storage_location_inventory 歷史回填 | 1 待（R62-1 完成 2026-05-25 PR #482；R62-2 待 — 跑 prod + review CSV + ops migration 070）|
| 🔒 R63 CSO 綜合安全審計（9 輪） | 0 待（全部完成 2026-05-28：A1-A3 GLP 合規（此 PR）+ R63-C 掃清 + B9 PR #503 + C10 deferred + 20 項直接修復）|
| ♿ R65 無障礙 aria-label i18n 全面化 | 1 待（2026-06-09 立案，來源 PR #657 review）|
| 🔒 R66 滲透測試評估 follow-up（static 複查） | 6 待（2026-06-10 立案；2026-06-19 對帳關 A1/C2/C3/D1；2026-06-22 C4 won't-fix + C7 accepted-risk + C1 主體已修部署〔PR #773〕 + C1b DNS-rebinding pin 已修〔零新依賴 lookup_host+resolve_to_addrs，PR #777〕、B3 step-up 鎖定已修〔PR #774〕、B5 proxy header 調研後 accepted-risk〔拓樸已緩解：API 不對外+nginx loopback+CF authoritative；結構性硬化延 R56-6〕；餘 0 High + 2 Medium〔B1 park/B4 park〕 + 1 Low〔C5〕+ 1 待驗證〔D2=R75-P4〕；B2 TOTP〔PR #779〕+ C6 payload〔PR #780〕at-rest 加密已實作；報告見 `docs/security/PENTEST_ASSESSMENT_2026-06.md`）|
| 🚨 R67 業務規則 403 誤觸 IDOR 整治 | 1 待（R67-1/2 完成+部署 2026-06-11；R67-3 偵測器根本強化列 backlog）|
| 📝 R68 申請須知簽核流程 + admin 駁回通道 | 1 待（10 完成；8 項上線 2026-06-12 PR #692/#693/#695/#696/#697/#698/#699/#700；R68-9/10 bug 修 2026-06-13——補件死鎖 + 正文純文字化；R68-11 submit 過長 backlog）|
| 📚 R69 SOP 文件簽署 + 訓練考試 | 9 待（R69-1 設計規格定稿 PR #711；R69-2~9 = PR-A~PR-H 實作、R69-10 §9 未決待 sign-off，尚未動工）|
| 🐷 R70 動物紀錄計畫前置需求落實 | 0 待（全部完成：R70-1 PR #712；R70-2/3/4 PR #713；R70-5 PR #716，整併取代 #717 窄版 404）|
| 🔍 R71 「核准」按鈕運作邏輯盤點 follow-up | **12 全數收尾**：R71-1~10 實作（PR #722/#724/#725/#726/#729/#730/#732/#733/#734）+ R71-11 不適用（內部頁不需 i18n）+ R71-12 盤點完成（Amendment 決議 UI 缺漏 → backlog，已實作 PR #740）|
| 🔍 R72 「核准」按鈕盤點 Round 2（HR + 安樂死） | **4 全數收尾**：R72-1 安樂死 Chair gate+防連點（#736）、R72-2 HR 確認框（#736）+ 逐列 can_approve gate（#738）、R72-3 HR 核准通知（#737）、R72-4 維持 role-based（由 can_approve 解決）|
| 🧹 R73 Code review #669–741 多餘 code 整理 | 2 待（R73-1 bin secret/arg 抽共用【部分完成 #908】 / R73-2 HR 核准操作欄抽元件；R73-3 formatTime #904、R73-4 Textarea #906 已完成；皆重複 code、非 bug）|
| 🔒 R75 對抗式授權稽核 IDOR | 2 待（2026-06-17 立案；外部跨客戶面 R75-1/4/5 + 內部 R75-2/7/9/10/11/12 全修+部署，R75-0/X/P2 完成；2026-06-22 R75-3/6 by-design 結案、8 降級、9/10 已修、P3 ownership property test 完成〔PR #775〕；剩 R75-P2b rsa 追蹤 + R75-P4 結構性〔Phase1/2 已 merged，剩收尾〕）|
| 🕒 R76 HR 打卡地理圍籬修整 | 1 待（R76-1 GPS 半徑 750 done+live；R76-2 失敗寫 audit 完成〔#795 merged〕；R76-3 HiNet 固定 IP 救活 IP 閘 blocked-待對外申辦） |
| 🔒 R83 Cloudflare 邊緣/DNS 資安加固 | 2 待（R83-1/2/3 帳號 MFA / DMARC p=none / zone HSTS 完成 2026-07-16；R83-4 HSTS preload Submit 使用者手動 / R83-5 DMARC 升 p=reject 1-2 週後）|
| 📦 R84 ERP 現況調查 follow-up | 8 待（同單同品項透支修復 / 庫存量表 CHECK 約束 / GLP 品項批號強制化 / 流水單號可點擊 / reversal 機制設計 / 批號追溯視圖 / FEFO 查證 / 管制藥品簿冊對帳查證，皆未動工）|
| 🗳️ R85 舊計劃書補登：委員意見與獸醫歸屬釐清 | 8 待（委員N↔姓名對應〔回覆表全篇不具名，需執秘指認〕/ 獸醫 12 項歸屬確認〔31 筆現掛葉沂萱無依據，證據指向吳建男〕/ 委員 slot UUID 排序修復 / 委員意見補登實作 / 27 筆試驗對照物質錯置 / 115014 GLP 旗標矛盾 / 抽取器 payload 進版控 / 31 筆 finalize-import，皆未動工）|
| 🧵 R87 多 session 並行環境收斂 | 1 待（R87-1 共用 CARGO_TARGET_DIR 遷移——33.4 GB 舊 target 待回收，C: 僅剩 84 GB；須等所有 session 閒置才能做）|
| **合計（未完成）** | **117** |
| ↳ R71-12 backlog ✅ 已實作（PR #740） | Amendment 審查決議前端 UI：獨立詳情頁 `/protocols/amendments/:id` + 共識投票 + 結構化變更明細（目的 + 項次/前後對照）；純前端、零 migration |


---

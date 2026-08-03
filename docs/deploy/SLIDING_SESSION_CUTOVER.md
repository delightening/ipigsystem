# Sliding Session Cutover Runbook

> 對應 PR #428 — Google-style sliding session 五部曲 (A1+A2+B1+C1+D1+CI fix+DRY refactor) merge into main 後的部署 SOP。
>
> 適用環境：prod-on-laptop (Windows + Docker Desktop)。NAS / AWS 環境部署原理相同，命令依當地 docker compose 路徑調整。

---

## 一、Merge 前 checklist

PR #428 merge 之前先確認：

- [ ] CI 全綠（37/37 checks PASS）
- [ ] Gemini Code Assist review 處理完畢
- [ ] CodeRabbit review 處理完畢
- [ ] 此 runbook 與你目前 prod `.env` 內容對得起來

---

## 二、Merge 流程

```bash
# 在任何能用 gh CLI 的環境
gh pr merge 428 --merge --delete-branch

# 切回 main 並拉
cd "C:/System Coding/ipig_system"
git checkout main
git pull origin main
```

確認 main HEAD 是 sliding session 的 merge commit：

```bash
git log --oneline -1
# 預期看到：xxxxxxx Merge pull request #428 ...
```

---

## 三、Prod `.env` 修改（核心步驟）

⚠️ **這步沒做，新預設 15min 不會生效**，仍會用 `.env` 內舊的 60min。

**選 PowerShell 或 Git Bash 其一執行，不要混貼**：

### PowerShell（Windows 原生）

```powershell
cd "C:\System Coding\ipig_system"

# 備份目前 .env
Copy-Item .env ".env.bak.$(Get-Date -Format yyyyMMdd-HHmmss)"

# 方式 A（推薦）：刪掉該行，使用新預設 15
(Get-Content .env) | Where-Object { $_ -notmatch '^JWT_EXPIRATION_MINUTES=' } | Set-Content .env

# 方式 B：顯式設為 15
(Get-Content .env) -replace '^JWT_EXPIRATION_MINUTES=.*', 'JWT_EXPIRATION_MINUTES=15' | Set-Content .env

# 驗證
if (Select-String -Path .env -Pattern '^JWT_EXPIRATION_MINUTES' -Quiet) {
  Select-String -Path .env -Pattern '^JWT_EXPIRATION_MINUTES'
} else {
  Write-Output 'removed (using default 15)'
}
```

### Git Bash / WSL

```bash
cd "/c/System Coding/ipig_system"

# 備份目前 .env
cp .env ".env.bak.$(date +%Y%m%d-%H%M%S)"

# 方式 A（推薦）：刪掉該行，使用新預設 15
sed -i '/^JWT_EXPIRATION_MINUTES=/d' .env

# 方式 B：顯式設為 15
sed -i 's/^JWT_EXPIRATION_MINUTES=.*/JWT_EXPIRATION_MINUTES=15/' .env

# 驗證
grep -E '^JWT_EXPIRATION_MINUTES' .env || echo 'removed (using default 15)'
```

---

## 四、重新部署

```bash
cd "C:/System Coding/ipig_system"

# 拉新 main 對應的 image / build
docker compose down
docker compose up -d --build

# 觀察起來
docker compose ps
docker compose logs -f api 2>&1 | head -40
```

預期 backend 啟動 log 不再看到：

```
WARN ... [R41-1] access token TTL ≥ idle window: 閒置偵測精度受限
```

（這個 warning 在 access TTL 6h vs idle 30min 時會 fire；改 15min 後不再 fire。）

---

## 五、健康檢查（5 分鐘內完成）

### 5.1 後端 health

```bash
curl -s https://ipigsystem.asia/api/health
# 預期：{"status":"ok"}
```

### 5.2 登入流程

開瀏覽器 → https://ipigsystem.asia → 登入 → 進 dashboard。

DevTools Network 應看到：
- `POST /api/v1/auth/login` → 200，response `expires_in: 900`（15min × 60s）
- Cookie 設 `access_token`、`refresh_token`

### 5.3 Proactive refresh 驗證（A2）

留在 dashboard 12 分鐘（建議開計時器）。預期：

- 12 分鐘後 Network 自動出現 `POST /api/v1/auth/refresh` → 200
- **沒有** 401 error
- **沒有** 「登入已過期」toast
- response `expires_in: 900` 重置 TTL

### 5.4 Multi-tab 廣播驗證（B1）

開三個分頁全部到 dashboard。等 12 分鐘觀察 Network：

- **只有一個** 分頁 fire `POST /api/v1/auth/refresh`
- 後端 audit log 也只有 1 筆 rotation（檢查 `/admin/audit`）
- 沒有 `refresh_token_reuse_race_window` warning 出現

### 5.5 Network retry 驗證（C1）

DevTools → Network → throttle 「Slow 3G」或 offline 1 秒 → online。

- 短暫離線回來後，**不會** 看到「登入已過期」toast
- Refresh 有 1 秒延遲後自動重試成功

### 5.6 Visibility refresh 驗證（D1）

闔上筆電 30 分鐘 → 打開 → 馬上回到 ipig 分頁（不要先點別的）。

DevTools Network 應立即看到 `POST /api/v1/auth/refresh`，無重登。

---

## 六、Rollback

### Rollback 範圍

- 程式碼：單一 revert 即可
- Schema：**無動到**，不需 migration rollback
- Data：**無動到**，不需 data restore
- Cookie：**無需處理**（舊 token cookie 自然過期）

### Rollback 步驟

```bash
# 找出 PR #428 的 merge commit
git log --oneline --merges | grep "#428"
# 例如：abc1234 Merge pull request #428 ...

# Revert merge
git revert -m 1 abc1234
git push origin main

# Prod .env 恢復 60min — upsert（避免 `>>` 追加造成同名鍵重複）

# PowerShell
if (Select-String -Path .env -Pattern '^JWT_EXPIRATION_MINUTES=' -Quiet) {
  (Get-Content .env) -replace '^JWT_EXPIRATION_MINUTES=.*', 'JWT_EXPIRATION_MINUTES=60' | Set-Content .env
} else {
  Add-Content .env 'JWT_EXPIRATION_MINUTES=60'
}

# 或 Git Bash / WSL
if grep -qE '^JWT_EXPIRATION_MINUTES=' .env; then
  sed -i 's/^JWT_EXPIRATION_MINUTES=.*/JWT_EXPIRATION_MINUTES=60/' .env
else
  echo 'JWT_EXPIRATION_MINUTES=60' >> .env
fi

# 重新部署
docker compose down
docker compose up -d --build
```

---

## 七、合規 follow-up（merge 後 1 週內）

- [ ] 更新 `docs/security/NICS_COMPLIANCE_AUDIT_2026-05.md` 對齊新 15min TTL
- [ ] R41-1 段落補註「access TTL 已從 6h 降到 15min，warn_if_idle_window_unusable 不再觸發」
- [ ] 若有外部 audit 排程，提交 changelog

---

## 八、後續 backlog（非必做）

| 項目 | 動機 | 優先級 |
|---|---|---|
| `SessionTimeoutWarning` 邏輯對齊 idle deadline 而非 6h 固定 | 目前 warning 用 sessionExpiresAt=6h，A1 後不再準確 | 低 |
| 把 `attemptRefreshWithRetry` 加指數退避（5xx 持續時） | C1 只 retry 1 次，極端情境下 retry 變大 | 低 |
| `useProactiveRefresh` 在 tab hidden 時暫停 timer 省電 | 微優化，瀏覽器已 throttle | 低 |
| Risk-based step-up（IP/UA mismatch 強制 re-auth） | D2 提案但 < 10 人系統 UX 干擾大於收益 | 不做 |

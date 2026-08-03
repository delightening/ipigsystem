#!/usr/bin/env bash
# 多 session 並行協議的強制守衛（docs/agents/PARALLEL_SESSIONS.md）。
#
# 用法：Claude Code PreToolUse hook，matcher = Bash / Write|Edit。
# 輸入：stdin 的 hook JSON（含 .session_id、.tool_input.command 或 .tool_input.file_path）。
# 輸出：要擋下時印一段 permissionDecision=deny 的 JSON 並 exit 0；放行則無輸出。
#
# 設計取捨：規則寫成獨立腳本而非 settings.json 內嵌指令，因為這五條都需要 pipe-test，
# 內嵌在 JSON 字串裡無法單獨驗證，改一次就要重讀整份設定。
#
# ⚠️ 本腳本是護欄，不是權限系統：它只看得到指令字串，繞過方式很多（換寫法、用別的工具）。
# 目的是攔住「順手打錯」而不是防惡意。真正的約束仍在 PARALLEL_SESSIONS.md。

set -uo pipefail

MAIN_CHECKOUT_BASENAME='ipig_system'
DEPLOY_LOCK='C:/System Coding/.deploy.lock'

input="$(cat)"
sid="$(printf '%s' "$input" | jq -r '.session_id // ""' | cut -c1-8)"
cmd="$(printf '%s' "$input" | jq -r '.tool_input.command // ""')"
path="$(printf '%s' "$input" | jq -r '.tool_input.file_path // ""')"

deny() {
  jq -nc --arg reason "$1" '{
    hookSpecificOutput: {
      hookEventName: "PreToolUse",
      permissionDecision: "deny",
      permissionDecisionReason: $reason
    }
  }'
  exit 0
}

# ── 規則 5：不得碰別的 session 的工作區（Bash 指令與 Write/Edit 檔案路徑都檢查）─────────
check_foreign_worktree() {
  local text="$1"
  local hit
  # 工作區命名為 wt-<8 碼>；出現非自己短碼者即擋
  for hit in $(printf '%s' "$text" | grep -oE 'wt-[0-9a-f]{8}' | sort -u); do
    if [ "$hit" != "wt-$sid" ]; then
      deny "PARALLEL_SESSIONS.md §2：$hit 是別的 session 的專屬工作區，不得讀寫／checkout／remove。本 session 只能動 wt-$sid。"
    fi
  done
}

check_foreign_worktree "$cmd"
check_foreign_worktree "$path"

# ── 規則 6：主 checkout 不得被 Write/Edit 改檔 ───────────────────────────────────
# 2026-08-03 補。規則 5 只比對「別的 session 的 wt-<短碼>」，主 checkout 自己的路徑
# 不在任何檢查範圍內 —— 直接 Edit 主 checkout 的檔案完全不會被攔（當日實際踩過一次）。
# 規則 4 擋的是 Bash git 指令，管不到 Write/Edit 這條路。
if [ -n "$path" ]; then
  # Claude Code 傳來的是 Windows 反斜線路徑，正規化後再比對
  norm="$(printf '%s' "$path" | tr '\\' '/')"
  if printf '%s' "$norm" | grep -qE "/${MAIN_CHECKOUT_BASENAME}/"; then
    deny "PARALLEL_SESSIONS.md §2：主 checkout $MAIN_CHECKOUT_BASENAME 唯讀 + 部署專用，不得直接 Write/Edit 其中的檔案。請在自己的工作區 wt-$sid 內修改後走 PR。"
  fi
fi

# 以下規則只針對 Bash 指令
[ -n "$cmd" ] || exit 0

# 去掉行內註解以免誤判（例如註解裡提到 down）
scan="$(printf '%s' "$cmd" | sed 's/#.*$//')"

is_compose() { printf '%s' "$scan" | grep -qE '(^|[;&|[:space:]])docker[[:space:]]+compose([[:space:]]|$)'; }
is_test_compose() { printf '%s' "$scan" | grep -qE 'docker-compose\.test\.ya?ml'; }

# ── 規則 1：compose down 與 --remove-orphans 一律擋 ────────────────────────────────
if printf '%s' "$scan" | grep -qE '\-\-remove-orphans'; then
  deny "PARALLEL_SESSIONS.md §5：禁止 --remove-orphans。test 與 prod 共用 compose project 名，prod 的 12 個容器會被列為 orphan 而一併移除（2026-07-29 實測）。"
fi
if is_compose && printf '%s' "$scan" | grep -qE '(^|[;&|[:space:]])down([[:space:]]|$)'; then
  deny "PARALLEL_SESSIONS.md §5：禁止對任何 compose 檔下 down。要收掉自己建的測試容器請用 docker rm -f <自己建的容器名>；ipig-db-test 是共用的，不得移除。"
fi

# ── 規則 2：test compose 只准 up db-test ─────────────────────────────────────────
if is_test_compose && printf '%s' "$scan" | grep -qE '(^|[;&|[:space:]])up([[:space:]]|$)'; then
  # 取 up 之後的服務名（濾掉旗標與 -f 的檔名）
  services="$(printf '%s' "$scan" \
    | sed -E 's/.*(^|[;&|[:space:]])up([[:space:]]|$)/ /' \
    | tr ' ' '\n' \
    | grep -vE '^-' \
    | grep -vE 'docker-compose|\.ya?ml$|^$' || true)"
  for svc in $services; do
    if [ "$svc" != "db-test" ]; then
      deny "PARALLEL_SESSIONS.md §5：docker-compose.test.yml 只准 up db-test（偵測到 '$svc'）。api-test 對外是 host 8000，與 prod 的 ipig-api 同埠，會直接打到正式服務。"
    fi
  done
  if [ -z "$services" ]; then
    deny "PARALLEL_SESSIONS.md §5：對 docker-compose.test.yml 下 up 必須指名 db-test，不得整份帶起（api-test 佔 host 8000＝prod api 同埠）。"
  fi
fi

# ── 規則 3：部署（prod compose 的 build / up）必須先押鎖 ──────────────────────────
if is_compose && ! is_test_compose \
   && printf '%s' "$scan" | grep -qE '(^|[;&|[:space:]])(build|up)([[:space:]]|$)'; then
  if [ ! -f "$DEPLOY_LOCK" ]; then
    deny "PARALLEL_SESSIONS.md §6：部署前必須先押 .deploy.lock。取鎖指令見該節；取不到鎖要停下回報，不得硬上。"
  fi
  if ! grep -q "sid=$sid" "$DEPLOY_LOCK" 2>/dev/null; then
    holder="$(head -n1 "$DEPLOY_LOCK" 2>/dev/null || echo '無法讀取')"
    deny "PARALLEL_SESSIONS.md §6：部署鎖被別的 session 佔用（$holder），本 session 是 $sid。停下回報，不要等也不要硬上；鎖超過 40 分鐘才可接手且須在回報中說明。"
  fi
fi

# ── 規則 4：主 checkout 不得跑改寫 git 狀態的指令 ─────────────────────────────────
# 只在「cd 進主 checkout」時判定，避免指令內容單純提到路徑就誤擋
if printf '%s' "$scan" | grep -qE "cd[[:space:]]+[\"']?[^\"']*/${MAIN_CHECKOUT_BASENAME}[\"']?([[:space:]]*(&&|;|\||$))"; then
  if printf '%s' "$scan" | grep -qE 'git[[:space:]]+(commit|checkout|switch|reset|stash|rebase|merge|cherry-pick|apply|restore)([[:space:]]|$)'; then
    deny "PARALLEL_SESSIONS.md §2：主 checkout $MAIN_CHECKOUT_BASENAME 唯讀 + 部署專用，不得跑改寫 git 狀態的指令（commit/checkout/reset/stash/rebase/merge…）。要改 code 回自己的 wt-$sid。（唯讀查詢與 git pull --ff-only 不受限）"
  fi
fi

exit 0

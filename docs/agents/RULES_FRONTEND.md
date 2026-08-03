# Frontend 規範（TypeScript / React）

> 何時讀本檔：任何會動到 `frontend/` 下 .ts/.tsx 檔的任務，動手前先讀完。
> UI 視覺決策（色彩/字體/間距）另讀 `DESIGN.md`；表格元件另跑 `/system_table_chats` skill（強制）。
> 內容抽自 2026-07-04 之前的 CLAUDE.md（原文備份：`docs/agents/backup/CLAUDE.md.2026-07-04.bak`）。

## 1. 目錄職責

| 目錄 | 職責 | 禁止事項 |
|------|------|----------|
| `pages/` | 頁面級元件（對應路由）。可含同層 `components/`、`hooks/`、`constants.ts` | ❌ 跨頁面復用的元件或 hook |
| `components/` | 可復用元件（≥2 頁面）。按業務域分子目錄；`ui/` 為基礎元件庫 | ❌ 頁面級路由邏輯 |
| `hooks/` | 全域共用 Custom Hooks（≥2 頁面），檔名 `use` 開頭 | ❌ 包含 JSX |
| `lib/` | 核心工具（utils, validation, queryKeys, logger） | ❌ React 相關邏輯 |
| `lib/api/` | API 層，按業務域拆分（client.ts / animal.ts / hr.ts / protocol.ts / index.ts） | — |
| `lib/constants/` | 跨頁面常數、狀態對應表（≥10 行的常數物件） | — |
| `types/` | 共用型別，每業務域一檔 | ❌ 頁面內重複定義 |
| `stores/` | Zustand 全域狀態（auth、UI 偏好） | ❌ 頁面級狀態 |

## 2. 專項規則

- API 呼叫統一 TanStack Query，禁止裸 `fetch` / `axios`。
- **禁止 Zod 或任何用 `new Function()` / `eval()` 做 feature-probe 的 schema 庫**（撞 strict CSP
  `script-src no-unsafe-eval`，R58 已全面移除）。改用：(a) RHF `register('field', {required, pattern})`
  (b) hand-rolled type guards（discriminated union 走 `switch` + narrowing）(c) `lib/apiError.ts`。
- Custom Hook 提取時機：state + effect 邏輯 >15 行，或 ≥2 元件重複。
- 內聯常數 ≥10 行禁止放頁面內 → `lib/constants/` 或同層 `constants.ts`。
- ESLint 零警告；未使用 import / 變數不得殘留。
- 日期格式一律用 `lib/utils` 的 `uiLocale()` / `getDateFnsLocale()`，禁止硬編 `zh-TW` / `zhTW`；
  E2E 斷言勿硬編中文文字（CI 渲染 en）。
- 表格儲存格禁止 truncate（省略號截斷）：文字自然換行或調欄寬。
- 硬編碼色彩禁止（`text-slate-*`、`bg-blue-*`），一律 CSS Variable token（見 DESIGN.md）。

## 3. useEffect deps 穩定性（高頻踩坑）

**禁止把 custom hook 回傳的整個物件放進 deps**——它每次 render 都是新 reference，會造成無限迴圈
或覆蓋使用者輸入。解構取出穩定值再放。

| 值的來源 | Reference 穩定? | 做法 |
|---|---|---|
| `useRef(...)` 回傳值 | ✅ | 可直接放 deps |
| `useState` setter | ✅ | 可直接放 deps |
| `useCallback` / `useMemo` 結果 | ✅（deps 不變時） | 可直接放 deps |
| custom hook 回傳的 `{}` 物件 | ❌ 每次都新 | 解構取穩定值 |
| props 裡的 callback | ⚠️ 視上層 | 確認上層有 useCallback 再放 |
| 陣列/物件 literal | ❌ | 移出 component 或 useMemo |

## 4. Zustand 決策流程

1. 需要在**不相鄰元件**間共用？否 → props / context
2. 需要**跨路由存活**？否 → React state 或 URL search params
3. 需要**重新整理後存活**？是 → Zustand + persist middleware
4. 以上皆是 → Zustand Store

## 5. 錯誤處理

- 全域 QueryClient onError 統一處理 401/403/500；queries 401 不重試，其他 retry ≤3；
  mutations onError 統一 `toast.error(getApiErrorMessage(error))`。
- 渲染錯誤用 `PageErrorBoundary`。
- ❌ 禁止裸 try-catch + `console.error`。

## 6. Import 排序（ESLint import/order 自動化）

React 核心 → 第三方庫 → 空行 → `@/lib/`,`@/hooks/`,`@/stores/` → `@/components/` → `@/types/` → 同層相對路徑。

## 7. 命名

元件 `AnimalCard.tsx`（PascalCase）、hook `useAnimalList.ts`、一般檔 `camelCase.ts`、
常數檔 `constants.ts`、型別檔 `types/animal.ts`。

## 8. 驗證方式（環境限制）

- **不要跑 `npm run build`**（會干擾現行 Docker prod）。驗證用：
  `rtk tsc`（或 `node_modules/.bin/tsc --noEmit`）+ `npx eslint`。
- 前端跑的是 production build（非 Vite dev server）：改完要 rebuild image 才會生效。
- 新 worktree 跑 tsc/eslint 前，先用 PowerShell `New-Item -ItemType Junction` 把主 repo 的
  `node_modules` junction 過去（非 mklink）。

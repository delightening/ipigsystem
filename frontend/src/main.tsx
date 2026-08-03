import React from 'react'
import ReactDOM from 'react-dom/client'
import { focusManager, MutationCache, QueryCache, QueryClient, QueryClientProvider } from '@tanstack/react-query'
import { BrowserRouter } from 'react-router-dom'
import { AxiosError } from 'axios'
import { ErrorBoundary } from '@/components/ui/error-boundary'
import { toast } from '@/components/ui/use-toast'
import { getApiErrorMessage } from '@/lib/apiError'
import { useAuthStore } from '@/stores/auth'
import App from './App'
import './index.css'
import './lib/i18n' // Initialize i18n
import { reportWebVitals } from './lib/webVitals'

// R28-10：runtime session 過期 redirect kill-switch（與 client.ts interceptor 各自獨立）。
// 公開頁面不 redirect（已在 /login 等頁時不重複跳）；guest 模式無 session 不適用。
function forceRedirectToLogin() {
  if (window.location.pathname.startsWith('/login')) return
  if (useAuthStore.getState().isGuest()) return
  useAuthStore.getState().clearAuth()
  window.location.href = '/login'
}

// #380：step-up 二級認證端點（敏感操作前重驗登入密碼）。密碼輸錯時後端回 401，
// 但這不是 session 過期 —— 不可套用全域強制登出，否則 admin 在重設他人密碼 / 改角色等
// 流程打錯一次密碼就被踢出。這類 401 交還元件自行 onError（toast 重試）。
const STEP_UP_REAUTH_PATHS = ['/auth/confirm-password']
function isStepUpReauthError(error: AxiosError): boolean {
  const url = error.config?.url ?? ''
  return STEP_UP_REAUTH_PATHS.some((p) => url.includes(p))
}

const queryClient = new QueryClient({
  /**
   * QueryCache 全域錯誤處理（R28-10 防禦層 A）
   *
   * client.ts interceptor 的 401 流程不可靠時（refresh 卡死 / clearAuth 沒跑 /
   * setTimeout 沒排程），此處作為第二層保險：query 失敗 401 直接強制 redirect
   * 到 /login。Mutation 走 mutationCache.onError（同條件）。
   */
  queryCache: new QueryCache({
    onError: (error) => {
      if (
        error instanceof AxiosError &&
        error.response?.status === 401 &&
        !isStepUpReauthError(error)
      ) {
        forceRedirectToLogin()
      }
    },
  }),
  /**
   * MutationCache 全域錯誤處理
   *
   * 無論個別 mutation 是否自行處理 onError，此 callback 都會被觸發。
   * 僅在 mutation 未定義 onError 時顯示 toast，避免重複提示。
   */
  mutationCache: new MutationCache({
    onError: (error, _variables, _context, mutation) => {
      // R28-10：mutation 401 也走 redirect 保險（與 query 一致）。
      // #380：step-up reauth（密碼輸錯）的 401 例外 —— 不登出，交還元件 onError 處理。
      if (
        error instanceof AxiosError &&
        error.response?.status === 401 &&
        !isStepUpReauthError(error)
      ) {
        forceRedirectToLogin()
        return
      }

      // 如果元件已自行定義 onError，由元件自行處理
      if (mutation.options.onError) return

      toast({
        title: '操作失敗',
        description: getApiErrorMessage(error),
        variant: 'destructive',
      })
    },
  }),
  defaultOptions: {
    queries: {
      retry: (failureCount, error) => {
        // 401/403 不重試：token 無效或權限不足無需重試
        if (error instanceof Error && 'response' in error) {
          const status = (error as { response?: { status?: number } }).response?.status
          if (status === 401 || status === 403) return false
        }
        return failureCount < 1
      },
      refetchOnWindowFocus: false,
      refetchOnMount: true,
      staleTime: 2 * 60 * 1000,
      gcTime: 5 * 60 * 1000,
    },
  },
})

// Auth 清除時立即取消所有 queries，停止 polling
// R28-10 防禦層 B：isAuthenticated 由 true → false 一律強制 redirect /login（保險）。
// 主路徑為 client.ts interceptor + ProtectedRoute，這裡是兜底（runtime session 失效時）。
useAuthStore.subscribe(
  (state, prev) => {
    if (prev.isAuthenticated && !state.isAuthenticated) {
      queryClient.cancelQueries()
      queryClient.clear()
      forceRedirectToLogin()
    }
  },
)

// 部署後舊 HTML 指向已移除的 JS chunk 時自動刷新
window.addEventListener('vite:preloadError', (event) => {
  event.preventDefault()
  window.location.reload()
})

// Throttle focus events: at most one focus refetch every 10 seconds
let lastFocusTime = 0
focusManager.setEventListener((handleFocus) => {
  const onFocus = () => {
    const now = Date.now()
    if (now - lastFocusTime > 10_000) {
      lastFocusTime = now
      handleFocus()
    }
  }
  window.addEventListener('visibilitychange', () => {
    if (!document.hidden) onFocus()
  })
  window.addEventListener('focus', onFocus)
  return () => {
    window.removeEventListener('visibilitychange', onFocus)
    window.removeEventListener('focus', onFocus)
  }
})

// 將 React mount 點從靜態語意骨架中取出後丟棄骨架；骨架僅供爬蟲/AI agent/無 JS 環境讀取
const rootElement = document.getElementById('root')!
const staticLanding = document.getElementById('static-landing')
if (staticLanding && staticLanding.contains(rootElement)) {
  document.body.appendChild(rootElement)
  staticLanding.remove()
}

ReactDOM.createRoot(rootElement).render(
  <React.StrictMode>
    <QueryClientProvider client={queryClient}>
      <BrowserRouter>
        <ErrorBoundary>
          <App />
        </ErrorBoundary>
      </BrowserRouter>
    </QueryClientProvider>
  </React.StrictMode>,
)

reportWebVitals()

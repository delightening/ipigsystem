import { useRef, useState } from 'react'
import { Check, Loader2, X } from 'lucide-react'

import { useUpdateRemark } from '../hooks/useReservationPlanning'

interface Props {
  animalId: string
  remark: string | null
}

/**
 * 備註 inline 編輯（Phase 5）：整格可點 → 輸入框 + ✓存 / ✕取消。
 * 桌機：Enter / ✓ / 失焦存、Esc / ✕ 取消；手機：點 ✓ / ✕（不靠虛擬鍵盤）。
 * 存檔走 useUpdateRemark（audited）；pending 顯示 spinner + 樂觀顯示送出值，失敗由 mutation toast、
 * 清單 invalidate 後回原值。commit guard 防止 blur 與按鈕 click 重複送出。
 */
export function EditableRemarkCell({ animalId, remark }: Props) {
  const [editing, setEditing] = useState(false)
  const [draft, setDraft] = useState('')
  const committed = useRef(false)
  const { mutate, isPending, variables } = useUpdateRemark()

  const startEdit = () => {
    committed.current = false
    setDraft(remark ?? '')
    setEditing(true)
  }

  const commit = (persist: boolean) => {
    if (committed.current) return
    committed.current = true
    setEditing(false)
    const next = draft.trim()
    if (persist && next !== (remark ?? '')) {
      mutate({ animalId, remark: next })
    }
  }

  // pending 中且是這一隻 → 樂觀顯示送出值，避免 refetch 前閃回舊值
  const showPending = isPending && variables?.animalId === animalId
  const display = showPending ? variables?.remark || '—' : remark || '—'

  if (editing) {
    return (
      <span className="flex items-center gap-1">
        <input
          autoFocus
          type="text"
          enterKeyHint="done"
          className="w-full max-w-[240px] rounded-md border border-accent bg-background px-2 py-0.5 text-sm text-foreground"
          value={draft}
          onChange={(e) => setDraft(e.target.value)}
          onKeyDown={(e) => {
            if (e.key === 'Enter') {
              e.preventDefault()
              commit(true)
            } else if (e.key === 'Escape') {
              e.preventDefault()
              commit(false)
            }
          }}
          onBlur={() => commit(true)}
        />
        <button
          type="button"
          aria-label="儲存備註"
          className="flex h-7 w-7 items-center justify-center rounded-md bg-accent text-accent-foreground"
          onMouseDown={(e) => e.preventDefault()}
          onClick={() => commit(true)}
        >
          <Check className="h-4 w-4" />
        </button>
        <button
          type="button"
          aria-label="取消編輯"
          className="flex h-7 w-7 items-center justify-center rounded-md border text-muted-foreground"
          onMouseDown={(e) => e.preventDefault()}
          onClick={() => commit(false)}
        >
          <X className="h-4 w-4" />
        </button>
      </span>
    )
  }

  return (
    <span
      className="-mx-1 flex cursor-text items-center gap-1 rounded px-1 hover:bg-accent/10"
      title="點擊編輯備註"
      onClick={startEdit}
    >
      <span className="truncate">{display}</span>
      {showPending && <Loader2 className="h-3 w-3 shrink-0 animate-spin text-muted-foreground" />}
    </span>
  )
}

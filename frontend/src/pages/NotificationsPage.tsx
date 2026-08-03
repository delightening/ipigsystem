import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import api from '@/lib/api'
import { cn, uiLocale } from '@/lib/utils'
import type { NotificationItem } from '@/types/notification'
import { notificationTypeNames } from '@/types/notification'
import { Button } from '@/components/ui/button'
import { toast } from '@/components/ui/use-toast'
import {
    Bell, CheckCheck, ExternalLink, Loader2, ChevronLeft, ChevronRight,
} from 'lucide-react'

const PER_PAGE = 20

export default function NotificationsPage() {
    const navigate = useNavigate()
    const queryClient = useQueryClient()
    const [page, setPage] = useState(1)

    const { data, isLoading } = useQuery({
        queryKey: ['notifications-all', page],
        queryFn: async () => {
            const res = await api.get<{ data: NotificationItem[]; total: number; page: number; per_page: number }>(
                `/notifications?page=${page}&per_page=${PER_PAGE}`,
            )
            return res.data
        },
    })

    const markReadMutation = useMutation({
        mutationFn: async (ids: string[]) => api.post('/notifications/read', { notification_ids: ids }),
        onSuccess: () => {
            queryClient.invalidateQueries({ queryKey: ['notifications-all'] })
            queryClient.invalidateQueries({ queryKey: ['notifications-unread-count'] })
            queryClient.invalidateQueries({ queryKey: ['notifications-recent'] })
        },
    })

    const markAllReadMutation = useMutation({
        mutationFn: async () => api.post('/notifications/read-all'),
        onSuccess: () => {
            queryClient.invalidateQueries({ queryKey: ['notifications-all'] })
            queryClient.invalidateQueries({ queryKey: ['notifications-unread-count'] })
            queryClient.invalidateQueries({ queryKey: ['notifications-recent'] })
            toast({ title: '已全部標記為已讀' })
        },
    })

    const handleClick = (n: NotificationItem) => {
        if (!n.is_read) markReadMutation.mutate([n.id])
        if (!n.related_entity_type) return
        switch (n.related_entity_type) {
            case 'protocol': navigate(`/protocols/${n.related_entity_id}`); break
            case 'document': navigate(`/documents/${n.related_entity_id}`); break
            case 'animal': navigate(`/animals/${n.related_entity_id}`); break
            case 'amendment': navigate(`/protocols/amendments/${n.related_entity_id}`); break
            case 'leave_request': navigate('/hr/leaves'); break
            case 'overtime_record': case 'overtime': navigate('/hr/overtime'); break
            case 'euthanasia_order': case 'euthanasia_appeal':
                if (n.related_entity_id) navigate(`/animals/${n.related_entity_id}`)
                break
            case 'invitation': navigate('/hr/invitations'); break
            case 'expiry_warning': navigate('/inventory?filter=expiry_warning'); break
            case 'low_stock': navigate('/inventory'); break
            case 'equipment': navigate('/equipment'); break
            case 'vet_patrol_reports': navigate('/vet-patrol-reports'); break
        }
    }

    const formatTime = (dateStr: string) => {
        const d = new Date(dateStr)
        return d.toLocaleString(uiLocale(), { timeZone: 'Asia/Taipei', month: '2-digit', day: '2-digit', hour: '2-digit', minute: '2-digit' })
    }

    const notifications = data?.data ?? []
    const total = data?.total ?? 0
    const totalPages = Math.ceil(total / PER_PAGE)
    const unreadCount = notifications.filter(n => !n.is_read).length

    return (
        <div className="p-4 md:p-6 max-w-3xl mx-auto space-y-4">
            <div className="flex items-center justify-between">
                <div>
                    <h1 className="text-2xl font-bold flex items-center gap-2">
                        <Bell className="h-6 w-6" />
                        通知中心
                    </h1>
                    <p className="text-sm text-muted-foreground mt-1">
                        共 {total} 筆通知
                    </p>
                </div>
                {unreadCount > 0 && (
                    <Button
                        variant="outline"
                        size="sm"
                        onClick={() => markAllReadMutation.mutate()}
                        disabled={markAllReadMutation.isPending}
                    >
                        <CheckCheck className="h-4 w-4 mr-1" />
                        全部標記已讀
                    </Button>
                )}
            </div>

            <div className="border rounded-lg overflow-hidden divide-y">
                {isLoading ? (
                    <div className="p-8 text-center text-muted-foreground">
                        <Loader2 className="h-6 w-6 animate-spin mx-auto mb-2" />
                        載入中...
                    </div>
                ) : notifications.length === 0 ? (
                    <div className="p-8 text-center text-muted-foreground">
                        <Bell className="h-8 w-8 mx-auto mb-2 opacity-50" />
                        尚無通知
                    </div>
                ) : notifications.map(n => {
                    const isPinned = (n.priority ?? 0) > 0
                    return (
                    <div
                        key={n.id}
                        onClick={() => handleClick(n)}
                        className={cn(
                            'px-4 py-3 cursor-pointer hover:bg-muted/50 transition-colors flex items-start gap-3',
                            isPinned
                                ? 'border-l-4 border-l-status-warning-solid bg-status-warning-bg/40'
                                : !n.is_read && 'bg-status-info-bg',
                        )}
                    >
                        <div className={cn(
                            'w-2 h-2 rounded-full mt-2 shrink-0',
                            isPinned ? 'bg-status-warning-solid' : !n.is_read ? 'bg-status-info-bg0' : 'bg-transparent',
                        )} />
                        <div className="flex-1 min-w-0">
                            {isPinned && (
                                <span className="inline-block mb-1 text-xs font-medium px-1.5 py-0.5 rounded bg-status-warning-bg text-status-warning-text">
                                    待處理
                                </span>
                            )}
                            <p className={cn('text-sm', !n.is_read && 'font-semibold')}>
                                {n.title}
                            </p>
                            {n.content && (
                                <p className="text-sm text-muted-foreground mt-0.5 line-clamp-2">
                                    {n.content}
                                </p>
                            )}
                            <div className="flex items-center gap-2 mt-1">
                                <span className="text-xs text-muted-foreground">
                                    {formatTime(n.created_at)}
                                </span>
                                <span className="text-xs px-1.5 py-0.5 rounded bg-muted text-muted-foreground">
                                    {notificationTypeNames[n.type] ?? n.type}
                                </span>
                            </div>
                        </div>
                        {n.related_entity_type && (
                            <ExternalLink className="h-4 w-4 text-muted-foreground shrink-0 mt-1" />
                        )}
                    </div>
                    )
                })}
            </div>

            {totalPages > 1 && (
                <div className="flex items-center justify-center gap-2">
                    <Button
                        variant="outline"
                        size="sm"
                        disabled={page <= 1}
                        onClick={() => setPage(p => p - 1)}
                    >
                        <ChevronLeft className="h-4 w-4" />
                    </Button>
                    <span className="text-sm text-muted-foreground">
                        第 {page} / {totalPages} 頁
                    </span>
                    <Button
                        variant="outline"
                        size="sm"
                        disabled={page >= totalPages}
                        onClick={() => setPage(p => p + 1)}
                    >
                        <ChevronRight className="h-4 w-4" />
                    </Button>
                </div>
            )}
        </div>
    )
}

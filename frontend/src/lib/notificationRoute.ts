/**
 * 通知 → 目的地路徑的**唯一**對照表。
 *
 * 這張表原本各自複製在 NotificationDropdown、NotificationsPage 兩處，
 * 分家後驚嘆號入口會是第三處。三份副本已經漂移：
 * 通知中心那份少了 `report`、且 `low_stock` 沒帶 `?filter=`（點進去看到的是未過濾的庫存頁）。
 * 抽成一處後這些差異一併收斂到較完整的那份。
 *
 * 回傳 `null` ＝ 這則通知沒有可跳轉的目的地（呼叫端據此決定不顯示外連圖示）。
 */
export function notificationTargetPath(notification: {
    related_entity_type?: string
    related_entity_id?: string
}): string | null {
    const { related_entity_type: type, related_entity_id: id } = notification
    if (!type) return null

    switch (type) {
        case 'protocol':
            return `/protocols/${id}`
        case 'document':
            return `/documents/${id}`
        case 'animal':
            return `/animals/${id}`
        case 'amendment':
            return `/protocols/amendments/${id}`
        case 'leave_request':
            return '/hr/leaves'
        case 'overtime_record':
        case 'overtime':
            return '/hr/overtime'
        case 'euthanasia_order':
        case 'euthanasia_appeal':
            // 這兩種以動物為落點，沒帶 id 就無處可去
            return id ? `/animals/${id}` : null
        case 'invitation':
            return '/hr/invitations'
        case 'expiry_warning':
            return '/inventory?filter=expiry_warning'
        case 'low_stock':
            return '/inventory?filter=low_stock'
        case 'equipment':
            return '/equipment'
        case 'vet_patrol_reports':
            return '/vet-patrol-reports'
        case 'report':
            return '/admin/settings'
        default:
            return null
    }
}

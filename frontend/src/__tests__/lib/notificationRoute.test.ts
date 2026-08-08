import { describe, it, expect } from 'vitest'

import { notificationTargetPath } from '@/lib/notificationRoute'

/**
 * 這張對照表原本各自複製在鈴鐺下拉與通知中心兩處，且已經漂移
 * （通知中心那份少了 `report`、`low_stock` 也沒帶 `?filter=`）。
 * 分家後驚嘆號入口成為第三個呼叫端，故抽成一處。
 *
 * 本測試鎖住合併後的行為，避免日後又被就地複製回去而各自演化。
 */
describe('notificationTargetPath', () => {
    it('帶 id 的實體導向該實體詳情頁', () => {
        expect(
            notificationTargetPath({ related_entity_type: 'protocol', related_entity_id: 'p1' }),
        ).toBe('/protocols/p1')
        expect(
            notificationTargetPath({ related_entity_type: 'animal', related_entity_id: 'a1' }),
        ).toBe('/animals/a1')
        expect(
            notificationTargetPath({ related_entity_type: 'amendment', related_entity_id: 'm1' }),
        ).toBe('/protocols/amendments/m1')
    })

    it('別名指向同一目的地', () => {
        expect(notificationTargetPath({ related_entity_type: 'overtime' })).toBe('/hr/overtime')
        expect(notificationTargetPath({ related_entity_type: 'overtime_record' })).toBe(
            '/hr/overtime',
        )
    })

    it('庫存類通知要帶過濾參數，否則點進去看到的是未過濾的庫存頁', () => {
        expect(notificationTargetPath({ related_entity_type: 'low_stock' })).toBe(
            '/inventory?filter=low_stock',
        )
        expect(notificationTargetPath({ related_entity_type: 'expiry_warning' })).toBe(
            '/inventory?filter=expiry_warning',
        )
    })

    it('安樂死類以動物為落點；沒帶 id 就無處可去，回 null', () => {
        expect(
            notificationTargetPath({
                related_entity_type: 'euthanasia_order',
                related_entity_id: 'a9',
            }),
        ).toBe('/animals/a9')
        expect(notificationTargetPath({ related_entity_type: 'euthanasia_appeal' })).toBeNull()
    })

    it('沒有實體或不認得的實體回 null，呼叫端據此不顯示外連圖示', () => {
        expect(notificationTargetPath({})).toBeNull()
        expect(notificationTargetPath({ related_entity_type: 'something_new' })).toBeNull()
    })

    it('巡場報告與排程報表（合併前通知中心漏掉的那兩個）', () => {
        expect(notificationTargetPath({ related_entity_type: 'vet_patrol_reports' })).toBe(
            '/vet-patrol-reports',
        )
        expect(notificationTargetPath({ related_entity_type: 'report' })).toBe('/admin/settings')
    })
})

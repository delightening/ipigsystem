// 施打/用藥結構化選項（GLP/AAALAC 用藥分類 + 施打途徑）
// value = 儲存標準碼（與後端 jsonb_validation TREATMENT_CATEGORIES / TREATMENT_ROUTES 對齊）
// label = 顯示中文全稱

export interface TreatmentOption {
    value: string
    label: string
}

/** 藥品類別 */
export const TREATMENT_CATEGORY_OPTIONS: readonly TreatmentOption[] = [
    { value: 'dewormer', label: '驅蟲藥' },
    { value: 'antibiotic', label: '抗生素' },
    { value: 'other', label: '其他' },
]

/** 施打途徑 */
export const TREATMENT_ROUTE_OPTIONS: readonly TreatmentOption[] = [
    { value: 'IM', label: 'IM 肌肉注射' },
    { value: 'IV', label: 'IV 靜脈注射' },
    { value: 'SC', label: 'SC 皮下注射' },
    { value: 'PO', label: 'PO 口服' },
]

/** 藥品類別碼 → 中文全稱（查無回原字串） */
export function treatmentCategoryLabel(value?: string): string {
    if (!value) return ''
    return TREATMENT_CATEGORY_OPTIONS.find((o) => o.value === value)?.label ?? value
}

/** 施打途徑碼 → 中文全稱（查無回原字串） */
export function treatmentRouteLabel(value?: string): string {
    if (!value) return ''
    return TREATMENT_ROUTE_OPTIONS.find((o) => o.value === value)?.label ?? value
}

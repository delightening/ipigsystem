import { useQuery } from '@tanstack/react-query'

export interface InternalUserBrief {
  id: string
  display_name: string
}

/**
 * 內部員工精簡清單（id + display_name），來源 `/hr/internal-users`。
 * 供部門主管下拉、部門成員指派等 ≥2 處復用（DRY）。
 * @param enabled 控制查詢啟用時機（例如 dialog 開啟時才抓）。
 */
export function useInternalUsersBrief(enabled = true) {
  return useQuery({
    queryKey: ['internal-users-brief'],
    queryFn: async () => {
      const res = await import('@/lib/api').then(m => m.default.get<InternalUserBrief[]>('/hr/internal-users'))
      return res.data
    },
    enabled,
  })
}

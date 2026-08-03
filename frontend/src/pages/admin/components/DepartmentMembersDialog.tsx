import { useState } from 'react'
import { useQuery, useMutation, useQueryClient } from '@tanstack/react-query'
import { useTranslation } from 'react-i18next'
import { facilityApi } from '@/lib/api/facility'
import { useInternalUsersBrief } from '@/hooks/useInternalUsersBrief'
import { useConfirmDialog } from '@/hooks/useConfirmDialog'
import { ConfirmDialog } from '@/components/ui/confirm-dialog'
import { Button } from '@/components/ui/button'
import { FormField } from '@/components/ui/form-field'
import { Dialog, DialogContent, DialogFooter, DialogHeader, DialogTitle } from '@/components/ui/dialog'
import { Select, SelectContent, SelectItem, SelectTrigger, SelectValue } from '@/components/ui/select'
import { Table, TableBody, TableCell, TableHead, TableHeader, TableRow } from '@/components/ui/table'
import { TableEmptyRow } from '@/components/ui/empty-state'
import { TableSkeleton } from '@/components/ui/table-skeleton'
import { toast } from '@/components/ui/use-toast'
import { getApiErrorMessage } from '@/lib/apiError'
import { Trash2, Loader2, Users } from 'lucide-react'
import type { DepartmentWithManager } from '@/types/facility'

interface DepartmentMembersDialogProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  department: DepartmentWithManager
  canManage: boolean
}

export function DepartmentMembersDialog({ open, onOpenChange, department, canManage }: DepartmentMembersDialogProps) {
  const { t } = useTranslation()
  const queryClient = useQueryClient()
  const { dialogState, confirm } = useConfirmDialog()
  const [selectedUser, setSelectedUser] = useState<string>('')

  const { data: members = [], isLoading } = useQuery({
    queryKey: ['department-members', department.id],
    queryFn: async () => (await facilityApi.listDepartmentMembers(department.id)).data,
    enabled: open,
  })

  const { data: internalUsers = [] } = useInternalUsersBrief(open)

  // 全部門成員 + 部門清單：用來偵測「選到的人目前屬於其他部門」，避免靜默轉調。
  const { data: allMembers = [] } = useQuery({
    queryKey: ['department-members-all'],
    queryFn: async () => (await facilityApi.listAllDepartmentMembers()).data,
    enabled: open,
  })
  const { data: departments = [] } = useQuery({
    queryKey: ['departments'],
    queryFn: async () => (await facilityApi.listDepartments()).data,
    enabled: open,
  })

  const invalidate = () => {
    queryClient.invalidateQueries({ queryKey: ['department-members', department.id] })
    queryClient.invalidateQueries({ queryKey: ['department-members-all'] })
    queryClient.invalidateQueries({ queryKey: ['departments'] })
  }

  const assignMutation = useMutation({
    mutationFn: (userId: string) => facilityApi.assignDepartmentMember(department.id, userId),
    onSuccess: () => { invalidate(); setSelectedUser(''); toast({ title: t('admin.departmentTab.members.assignSuccess') }) },
    onError: (err: unknown) => toast({ title: t('admin.departmentTab.members.assignFailed'), description: getApiErrorMessage(err), variant: 'destructive' }),
  })

  const removeMutation = useMutation({
    mutationFn: (userId: string) => facilityApi.removeDepartmentMember(department.id, userId),
    onSuccess: () => { invalidate(); toast({ title: t('admin.departmentTab.members.removeSuccess') }) },
    onError: (err: unknown) => toast({ title: t('admin.departmentTab.members.removeFailed'), description: getApiErrorMessage(err), variant: 'destructive' }),
  })

  // 排除已是本部門成員者，避免重複指派。
  const memberIds = new Set(members.map(m => m.id))
  const assignableUsers = internalUsers.filter(u => !memberIds.has(u.id))

  // 加入成員：若選到的人目前已屬於「其他」部門，先確認再轉調（避免一鍵靜默把人移出原部門）。
  const handleAdd = async () => {
    if (!selectedUser) return
    const current = allMembers.find(m => m.id === selectedUser)
    if (current?.department_id && current.department_id !== department.id) {
      const fromName = departments.find(d => d.id === current.department_id)?.name ?? ''
      const ok = await confirm({
        title: t('admin.departmentTab.members.transferTitle'),
        description: t('admin.departmentTab.members.transferConfirm', {
          name: current.display_name,
          from: fromName,
          to: department.name,
        }),
      })
      if (!ok) return
    }
    assignMutation.mutate(selectedUser)
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent size="lg">
        <DialogHeader>
          <DialogTitle>{t('admin.departmentTab.members.title', { name: department.name })}</DialogTitle>
        </DialogHeader>

        {canManage && (
          <FormField label={t('admin.departmentTab.members.addMember')}>
            <div className="flex gap-2">
              <Select value={selectedUser} onValueChange={setSelectedUser}>
                <SelectTrigger><SelectValue placeholder={t('admin.departmentTab.members.selectUser')} /></SelectTrigger>
                <SelectContent>
                  {assignableUsers.map(u => <SelectItem key={u.id} value={u.id}>{u.display_name}</SelectItem>)}
                </SelectContent>
              </Select>
              <Button
                onClick={handleAdd}
                disabled={!selectedUser || assignMutation.isPending}
              >
                {assignMutation.isPending && <Loader2 className="h-4 w-4 mr-1 animate-spin" />}
                {t('admin.departmentTab.members.add')}
              </Button>
            </div>
          </FormField>
        )}

        <div className="rounded-lg border bg-card overflow-hidden">
          <Table>
            <TableHeader>
              <TableRow className="bg-muted/50 hover:bg-muted/50">
                <TableHead>{t('admin.departmentTab.members.colName')}</TableHead>
                <TableHead>{t('admin.departmentTab.members.colEmail')}</TableHead>
                {canManage && <TableHead className="w-16 text-right">{t('common.actions')}</TableHead>}
              </TableRow>
            </TableHeader>
            <TableBody>
              {isLoading ? (
                <TableRow><TableCell colSpan={canManage ? 3 : 2} className="p-0"><TableSkeleton rows={3} cols={canManage ? 3 : 2} /></TableCell></TableRow>
              ) : members.length === 0 ? (
                <TableEmptyRow colSpan={canManage ? 3 : 2} icon={Users} title={t('admin.departmentTab.members.empty')} />
              ) : members.map(m => (
                <TableRow key={m.id}>
                  <TableCell>{m.display_name}</TableCell>
                  <TableCell className="text-sm text-muted-foreground">{m.email}</TableCell>
                  {canManage && (
                    <TableCell>
                      <div className="flex justify-end">
                        <Button
                          variant="ghost"
                          size="icon"
                          onClick={() => removeMutation.mutate(m.id)}
                          disabled={removeMutation.isPending && removeMutation.variables === m.id}
                          aria-label={t('admin.departmentTab.members.remove')}
                        >
                          {removeMutation.isPending && removeMutation.variables === m.id ? (
                            <Loader2 className="h-4 w-4 animate-spin" />
                          ) : (
                            <Trash2 className="h-4 w-4 text-destructive" />
                          )}
                        </Button>
                      </div>
                    </TableCell>
                  )}
                </TableRow>
              ))}
            </TableBody>
          </Table>
        </div>

        <DialogFooter>
          <Button type="button" variant="outline" onClick={() => onOpenChange(false)}>{t('admin.departmentTab.members.close')}</Button>
        </DialogFooter>
      </DialogContent>
      <ConfirmDialog state={dialogState} />
    </Dialog>
  )
}

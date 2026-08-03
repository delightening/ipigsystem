import { Link } from 'react-router-dom'
import { Button } from '@/components/ui/button'
import { Switch } from '@/components/ui/switch'
import { GuestHide } from '@/components/ui/guest-hide'
import { PageHeader } from '@/components/ui/page-header'
import { Plus, Download, Mail } from 'lucide-react'
import { useAuthHasPermission } from '@/stores/auth'
import { useUserManagement } from './hooks/useUserManagement'
import { UserTable } from './components/UserTable'
import {
  UserCreateDialog,
  UserEditDialog,
  UserRolesDialog,
  UserDeleteDialog,
  UserResetPasswordDialog,
} from './components/UserFormDialogs'
import { ConfirmPasswordModal } from '@/components/auth/ConfirmPasswordModal'
import { confirmPassword, isAxiosError } from '@/lib/api'
import { useToast } from '@/components/ui/use-toast'
import type { ApiErrorPayload } from '@/types/error'

export function UsersPage() {
  const mgmt = useUserManagement()
  const { toast } = useToast()
  // 邀請使用者：重用既有「邀請管理」流程（email + 名稱 + 角色 → 寄信 → 設密碼登入）
  const canInvite = useAuthHasPermission()('invitation.view')

  return (
    <div className="space-y-6">
      <PageHeader
        title="使用者管理"
        description="管理系統使用者帳號與角色"
        actions={
          <GuestHide>
            <div className="flex items-center gap-2">
              <label htmlFor="show-inactive-switch" className="flex items-center gap-2 text-sm text-muted-foreground cursor-pointer select-none">
                <Switch
                  id="show-inactive-switch"
                  checked={mgmt.showInactive}
                  onCheckedChange={mgmt.setShowInactive}
                />
                顯示停用帳號
              </label>
              <Button variant="outline" size="sm" onClick={mgmt.handleExportUsers} disabled={!mgmt.sortedUsers?.length || mgmt.isLoading}>
                <Download className="h-4 w-4 mr-2" />
                {mgmt.showInactive ? '匯出所有使用者' : '匯出啟用使用者'}
              </Button>
              {canInvite && (
                <Button variant="outline" size="sm" asChild>
                  <Link to="/hr/invitations">
                    <Mail className="h-4 w-4 mr-2" />
                    邀請使用者
                  </Link>
                </Button>
              )}
              <Button size="sm" data-testid="add-user-button" onClick={() => mgmt.setShowCreateDialog(true)}>
                <Plus className="h-4 w-4 mr-2" />
                新增使用者
              </Button>
            </div>
          </GuestHide>
        }
      />

      <UserTable
        users={mgmt.users}
        isLoading={mgmt.isLoading}
        currentUserId={mgmt.currentUser?.id}
        actions={{
          onEdit: mgmt.handleEdit,
          onManageRoles: mgmt.handleManageRoles,
          onResetPassword: mgmt.openResetPasswordDialog,
          onToggleActive: mgmt.handleToggleActive,
          onDelete: (user) => {
            mgmt.setUserToDelete(user)
            mgmt.setShowDeleteDialog(true)
          },
          onImpersonate: (user) => {
            mgmt.setUserToImpersonate(user)
            mgmt.setShowReauthForImpersonate(true)
          },
        }}
        sorting={{
          sortRole: mgmt.sortRole,
          sortStatus: mgmt.sortStatus,
          sortLastLogin: mgmt.sortLastLogin,
          onToggleSortRole: mgmt.toggleSortRole,
          onToggleSortStatus: mgmt.toggleSortStatus,
          onToggleSortLastLogin: mgmt.toggleSortLastLogin,
        }}
        pagination={{
          currentPage: mgmt.currentPage,
          totalPages: mgmt.totalPages,
          sortedUsersLength: mgmt.sortedUsers.length,
          onPrevPage: () => mgmt.setCurrentPage((p) => Math.max(1, p - 1)),
          onNextPage: () => mgmt.setCurrentPage((p) => Math.min(mgmt.totalPages, p + 1)),
        }}
      />

      <UserCreateDialog
        open={mgmt.showCreateDialog}
        onOpenChange={mgmt.setShowCreateDialog}
        roles={mgmt.roles}
        isPending={mgmt.createMutation.isPending}
        onSubmit={mgmt.handleCreateWithData}
      />

      <UserEditDialog
        open={mgmt.showEditDialog}
        onOpenChange={mgmt.setShowEditDialog}
        initialData={{
          email: mgmt.formData.email,
          display_name: mgmt.formData.display_name,
          entry_date: mgmt.formData.entry_date || '',
          aup_roles: mgmt.formData.aup_roles || [],
          trainings: mgmt.formData.trainings || [],
        }}
        isPending={mgmt.updateMutation.isPending}
        onSubmit={mgmt.handleUpdateWithData}
      />

      <UserRolesDialog
        open={mgmt.showRolesDialog}
        onOpenChange={mgmt.setShowRolesDialog}
        selectedUser={mgmt.selectedUser}
        formData={mgmt.formData}
        roles={mgmt.roles}
        isPending={mgmt.updateMutation.isPending}
        onSubmit={mgmt.handleUpdateRoles}
        toggleRole={mgmt.toggleRole}
      />

      <UserDeleteDialog
        open={mgmt.showDeleteDialog}
        onOpenChange={(o) => {
          mgmt.setShowDeleteDialog(o)
          if (!o) mgmt.setUserToDelete(null)
        }}
        userToDelete={mgmt.userToDelete}
        showReauth={mgmt.showReauthForDelete}
        onReauthOpenChange={(o) => {
          mgmt.setShowReauthForDelete(o)
          if (!o) mgmt.setUserToDelete(null)
        }}
        onConfirmDelete={() => mgmt.setShowReauthForDelete(true)}
        onReauthSubmit={async (password) => {
          // 密碼驗證失敗（401）→ 讓錯誤冒泡到 ConfirmPasswordModal 顯示「密碼錯誤」
          const { reauth_token } = await confirmPassword(password)
          if (!mgmt.userToDelete) return
          const targetId = mgmt.userToDelete.id
          try {
            await mgmt.deleteUserWithReauth(targetId, reauth_token)
            mgmt.setShowDeleteDialog(false)
            mgmt.setUserToDelete(null)
          } catch (err) {
            // 刪除失敗（非密碼問題），關閉刪除對話框並 toast 實際錯誤
            mgmt.setShowDeleteDialog(false)
            const message = isAxiosError(err)
              ? (err.response?.data as ApiErrorPayload | undefined)?.error?.message ?? '刪除使用者失敗'
              : '刪除使用者失敗'
            toast({ title: '刪除失敗', description: message, variant: 'destructive' })
            // 不 re-throw：密碼已確認，讓 ConfirmPasswordModal 正常關閉
          }
        }}
      />

      <ConfirmPasswordModal
        open={mgmt.showReauthForImpersonate}
        onOpenChange={(o) => {
          mgmt.setShowReauthForImpersonate(o)
          if (!o) mgmt.setUserToImpersonate(null)
        }}
        title="模擬登入確認"
        description={
          mgmt.userToImpersonate
            ? `確定要以「${mgmt.userToImpersonate.display_name}」的身分登入？請輸入您的登入密碼以確認。`
            : ''
        }
        onSubmit={async (password) => {
          const { reauth_token } = await confirmPassword(password)
          if (!mgmt.userToImpersonate) return
          await mgmt.handleImpersonate(reauth_token)
        }}
      />

      <UserResetPasswordDialog
        open={mgmt.showResetPasswordDialog}
        onOpenChange={mgmt.setShowResetPasswordDialog}
        userToResetPassword={mgmt.userToResetPassword}
        isPending={mgmt.resetPasswordMutation.isPending || mgmt.confirmPasswordMutation.isPending}
        onSubmit={mgmt.handleResetPasswordWithData}
        onClose={() => {
          mgmt.setUserToResetPassword(null)
        }}
      />
    </div>
  )
}

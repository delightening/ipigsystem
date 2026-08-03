import { useEffect } from 'react'
import { useForm } from 'react-hook-form'
import { useTranslation } from 'react-i18next'
import {
  Dialog,
  DialogContent,
  DialogDescription,
  DialogFooter,
  DialogHeader,
  DialogTitle,
} from '@/components/ui/dialog'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { FormField } from '@/components/ui/form-field'
import { badgeVariants } from '@/components/ui/badge'
import { cn } from '@/lib/utils'
import { Loader2 } from 'lucide-react'
import type { CreateUserData } from '../hooks/useUserManagement'
import type { Role } from '@/lib/api'

interface CreateUserFormData {
  email: string
  password: string
  display_name: string
  phone: string
  organization: string
  role_ids: string[]
}

const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/

interface UserCreateDialogProps {
  open: boolean
  onOpenChange: (open: boolean) => void
  roles: Role[] | undefined
  isPending: boolean
  onSubmit: (data: CreateUserData) => void
  defaultValues?: Partial<CreateUserData>
}

export function UserCreateDialog({
  open,
  onOpenChange,
  roles,
  isPending,
  onSubmit,
  defaultValues,
}: UserCreateDialogProps) {
  const { t } = useTranslation()
  const {
    register,
    handleSubmit,
    watch,
    setValue,
    reset,
    formState: { errors },
  } = useForm<CreateUserFormData>({
    defaultValues: {
      email: '',
      password: '',
      display_name: '',
      phone: '',
      organization: '',
      role_ids: [],
      ...defaultValues,
    },
  })

  const roleIds = watch('role_ids')

  useEffect(() => {
    if (open) {
      reset({
        email: '',
        password: '',
        display_name: '',
        phone: '',
        organization: '',
        role_ids: [],
        ...defaultValues,
      })
    }
  }, [open, reset, defaultValues])

  const toggleRole = (roleId: string) => {
    const current = roleIds || []
    const next = current.includes(roleId)
      ? current.filter((id) => id !== roleId)
      : [...current, roleId]
    setValue('role_ids', next, { shouldValidate: true })
  }

  const onValid = (data: CreateUserFormData) => {
    onSubmit({
      ...data,
      role_ids: data.role_ids,
      entry_date: '',
      position: '',
      aup_roles: [],
      years_experience: 0,
      trainings: [],
    })
  }

  return (
    <Dialog open={open} onOpenChange={onOpenChange}>
      <DialogContent>
        <DialogHeader>
          <DialogTitle>{t('admin.userCreateDialog.title')}</DialogTitle>
          <DialogDescription>{t('admin.userCreateDialog.description')}</DialogDescription>
        </DialogHeader>
        <form onSubmit={handleSubmit(onValid)} className="space-y-4 py-4">
          <FormField label={t('admin.userCreateDialog.emailLabel')} required error={errors.email?.message} htmlFor="email">
            <Input
              id="email"
              type="email"
              {...register('email', {
                required: t('admin.userCreateDialog.emailInvalid'),
                pattern: { value: EMAIL_PATTERN, message: t('admin.userCreateDialog.emailInvalid') },
              })}
              placeholder="user@example.com"
            />
          </FormField>
          <FormField label={t('admin.userCreateDialog.passwordLabel')} required error={errors.password?.message} htmlFor="password">
            <Input
              id="password"
              type="password"
              {...register('password', {
                required: t('admin.userCreateDialog.passwordMinLength'),
                minLength: { value: 10, message: t('admin.userCreateDialog.passwordMinLength') },
              })}
              placeholder={t('admin.userCreateDialog.passwordPlaceholder')}
            />
          </FormField>
          <FormField label={t('admin.userCreateDialog.displayNameLabel')} required error={errors.display_name?.message} htmlFor="display_name">
            <Input
              id="display_name"
              {...register('display_name', { required: t('admin.userCreateDialog.displayNameRequired') })}
              placeholder={t('admin.userCreateDialog.displayNamePlaceholder')}
            />
          </FormField>
          <FormField label={t('admin.userCreateDialog.rolesLabel')} error={errors.role_ids?.message}>
            <input type="hidden" {...register('role_ids', {
              validate: v => (v && v.length > 0) || t('admin.userCreateDialog.rolesRequired'),
            })} />
            <div className="flex flex-wrap gap-2 p-3 border rounded-md">
              {roles?.map((role) => {
                const selected = roleIds.includes(role.id)
                return (
                  <button
                    key={role.id}
                    type="button"
                    className={cn(
                      badgeVariants({ variant: selected ? 'default' : 'outline' }),
                      'cursor-pointer',
                    )}
                    aria-pressed={selected}
                    onClick={() => toggleRole(role.id)}
                  >
                    {role.name}
                  </button>
                )
              })}
            </div>
          </FormField>
          <DialogFooter>
            <Button type="button" variant="outline" onClick={() => onOpenChange(false)}>
              {t('common.cancel')}
            </Button>
            <Button type="submit" disabled={isPending}>
              {isPending && <Loader2 className="h-4 w-4 mr-2 animate-spin" />}
              {t('common.create')}
            </Button>
          </DialogFooter>
        </form>
      </DialogContent>
    </Dialog>
  )
}

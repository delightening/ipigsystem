import { useState } from 'react'
import { useForm } from 'react-hook-form'
import { useTranslation } from 'react-i18next'
import { useMutation, useQuery } from '@tanstack/react-query'
import { Copy, Loader2, CheckCircle2 } from 'lucide-react'

import { invitationApi } from '@/lib/api/invitation'
import { getApiErrorMessage } from '@/lib/apiError'
import { uiLocale } from '@/lib/utils'
import { onActivateKey } from '@/lib/a11y'
import { Badge } from '@/components/ui/badge'
import { Button } from '@/components/ui/button'
import { Input } from '@/components/ui/input'
import { FormField } from '@/components/ui/form-field'
import { toast } from '@/components/ui/use-toast'
import {
    Dialog,
    DialogContent,
    DialogDescription,
    DialogFooter,
    DialogHeader,
    DialogTitle,
} from '@/components/ui/dialog'
import type { CreateInvitationResponse } from '@/types/invitation'

interface CreateInvitationForm {
    email: string
    display_name: string
    organization: string
    phone?: string
    position?: string
    role_ids: string[]
}

const EMAIL_PATTERN = /^[^\s@]+@[^\s@]+\.[^\s@]+$/

interface InvitationCreateDialogProps {
    open: boolean
    onOpenChange: (open: boolean) => void
    onSuccess: () => void
}

export function InvitationCreateDialog({ open, onOpenChange, onSuccess }: InvitationCreateDialogProps) {
    const { t } = useTranslation()
    const [result, setResult] = useState<CreateInvitationResponse | null>(null)

    const form = useForm<CreateInvitationForm>({
        defaultValues: {
            email: '',
            display_name: '',
            organization: '',
            phone: '',
            position: '',
            role_ids: [],
        },
    })

    const rolesQuery = useQuery({
        queryKey: ['invitation-available-roles'],
        queryFn: () => invitationApi.availableRoles().then((r) => r.data),
        enabled: open,
        staleTime: 5 * 60 * 1000,
    })

    const roleIds = form.watch('role_ids')
    const toggleRole = (id: string) => {
        const next = roleIds.includes(id) ? roleIds.filter((x) => x !== id) : [...roleIds, id]
        form.setValue('role_ids', next, { shouldValidate: true })
    }

    const createMutation = useMutation({
        mutationFn: (data: CreateInvitationForm) =>
            invitationApi.create({
                email: data.email,
                display_name: data.display_name,
                organization: data.organization,
                phone: data.phone || undefined,
                position: data.position || undefined,
                role_ids: data.role_ids,
            }),
        onSuccess: (res) => {
            setResult(res.data)
            onSuccess()
        },
        onError: (error: unknown) => {
            const msg = getApiErrorMessage(error)
            toast({ variant: 'destructive', title: t('admin.invitationCreateDialog.createFailed'), description: msg })
        },
    })

    const handleClose = () => {
        setResult(null)
        form.reset()
        onOpenChange(false)
    }

    const handleCopyLink = async (link: string) => {
        try {
            await navigator.clipboard.writeText(link)
            toast({ title: t('admin.invitationCreateDialog.linkCopied') })
        } catch {
            toast({ variant: 'destructive', title: t('admin.invitationCreateDialog.copyFailed') })
        }
    }

    if (result) {
        return (
            <Dialog open={open} onOpenChange={handleClose}>
                <DialogContent>
                    <DialogHeader>
                        <DialogTitle className="flex items-center gap-2">
                            <CheckCircle2 className="h-5 w-5 text-status-success-text" />
                            {t('admin.invitationCreateDialog.sentTitle')}
                        </DialogTitle>
                        <DialogDescription>
                            {t('admin.invitationCreateDialog.sentDescription', { email: result.invitation.email })}
                        </DialogDescription>
                    </DialogHeader>
                    <div className="space-y-4">
                        <div>
                            <p className="text-sm text-muted-foreground mb-2">
                                {t('admin.invitationCreateDialog.copyLinkHint')}
                            </p>
                            <div className="flex items-center gap-2">
                                <Input value={result.invite_link} readOnly className="font-mono text-xs" />
                                <Button
                                    variant="outline"
                                    size="icon"
                                    onClick={() => handleCopyLink(result.invite_link)}
                                    aria-label={t('admin.invitationCreateDialog.copyLinkAria')}
                                >
                                    <Copy className="h-4 w-4" />
                                </Button>
                            </div>
                        </div>
                        <p className="text-sm text-muted-foreground">
                            {t('admin.invitationCreateDialog.expiresAt', { date: new Date(result.invitation.expires_at).toLocaleDateString(uiLocale()) })}
                        </p>
                    </div>
                    <DialogFooter>
                        <Button onClick={handleClose}>{t('admin.invitationCreateDialog.done')}</Button>
                    </DialogFooter>
                </DialogContent>
            </Dialog>
        )
    }

    return (
        <Dialog open={open} onOpenChange={handleClose}>
            <DialogContent>
                <DialogHeader>
                    <DialogTitle>{t('admin.invitationCreateDialog.title')}</DialogTitle>
                    <DialogDescription>
                        {t('admin.invitationCreateDialog.description')}
                    </DialogDescription>
                </DialogHeader>
                <form
                    onSubmit={form.handleSubmit((data) => createMutation.mutate(data))}
                    className="space-y-4 max-h-[70vh] overflow-y-auto pr-1"
                >
                    <FormField label={t('common.email')} htmlFor="invite-email" error={form.formState.errors.email?.message} required>
                        <Input
                            id="invite-email"
                            type="email"
                            placeholder="wang.daming@hospital.org"
                            {...form.register('email', {
                                required: t('admin.invitationCreateDialog.emailRequired'),
                                pattern: { value: EMAIL_PATTERN, message: t('admin.invitationCreateDialog.emailRequired') },
                            })}
                        />
                    </FormField>

                    <FormField label={t('admin.invitationCreateDialog.nameLabel')} htmlFor="invite-name" error={form.formState.errors.display_name?.message} required>
                        <Input id="invite-name" placeholder={t('admin.invitationCreateDialog.namePlaceholder')} {...form.register('display_name', {
                            required: t('admin.invitationCreateDialog.nameRequired'),
                            maxLength: { value: 100, message: t('admin.invitationCreateDialog.nameMaxLength') },
                        })} />
                    </FormField>

                    <FormField label={t('admin.invitationCreateDialog.orgLabel')} htmlFor="invite-org" error={form.formState.errors.organization?.message} required>
                        <Input id="invite-org" placeholder={t('admin.invitationCreateDialog.orgPlaceholder')} {...form.register('organization', {
                            required: t('admin.invitationCreateDialog.orgRequired'),
                            maxLength: { value: 255, message: t('admin.invitationCreateDialog.orgMaxLength') },
                        })} />
                    </FormField>

                    <div className="grid grid-cols-2 gap-3">
                        <FormField label={t('admin.invitationCreateDialog.phoneLabel')} htmlFor="invite-phone" error={form.formState.errors.phone?.message}>
                            <Input id="invite-phone" placeholder="0912345678" {...form.register('phone', {
                                maxLength: { value: 20, message: t('admin.invitationCreateDialog.phoneMaxLength') },
                            })} />
                        </FormField>
                        <FormField label={t('admin.invitationCreateDialog.positionLabel')} htmlFor="invite-position" error={form.formState.errors.position?.message}>
                            <Input id="invite-position" placeholder={t('admin.invitationCreateDialog.positionPlaceholder')} {...form.register('position', {
                                maxLength: { value: 100, message: t('admin.invitationCreateDialog.positionMaxLength') },
                            })} />
                        </FormField>
                    </div>

                    <FormField label={t('admin.invitationCreateDialog.rolesLabel')} error={form.formState.errors.role_ids?.message} required>
                        <input
                            type="hidden"
                            {...form.register('role_ids', {
                                validate: v => (v && v.length > 0) || t('admin.invitationCreateDialog.rolesRequired'),
                            })}
                        />
                        <div className="flex flex-wrap gap-2 p-3 border rounded-md min-h-[3rem]">
                            {rolesQuery.isLoading && (
                                <span className="text-sm text-muted-foreground">{t('admin.invitationCreateDialog.rolesLoading')}</span>
                            )}
                            {rolesQuery.data?.map((role) => {
                                const selected = roleIds.includes(role.id)
                                return (
                                    <Badge
                                        key={role.id}
                                        variant={selected ? 'default' : 'outline'}
                                        className="cursor-pointer"
                                        role="checkbox"
                                        tabIndex={0}
                                        aria-checked={selected}
                                        onClick={() => toggleRole(role.id)}
                                        onKeyDown={onActivateKey(() => toggleRole(role.id))}
                                    >
                                        {role.name}
                                        {role.is_internal && (
                                            <span className="ml-1 text-[10px] opacity-60">{t('admin.invitationCreateDialog.internalRole')}</span>
                                        )}
                                    </Badge>
                                )
                            })}
                        </div>
                    </FormField>

                    <DialogFooter>
                        <Button type="button" variant="outline" onClick={handleClose}>{t('common.cancel')}</Button>
                        <Button type="submit" disabled={createMutation.isPending}>
                            {createMutation.isPending && <Loader2 className="mr-2 h-4 w-4 animate-spin" />}
                            {t('admin.invitationCreateDialog.submit')}
                        </Button>
                    </DialogFooter>
                </form>
            </DialogContent>
        </Dialog>
    )
}

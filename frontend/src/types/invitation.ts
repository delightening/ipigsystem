/**
 * 邀請制型別
 */

export type InvitationStatus = 'pending' | 'accepted' | 'expired' | 'revoked'

export interface InvitationRoleSummary {
    id: string
    code: string
    name: string
}

export interface InvitationAvailableRole {
    id: string
    code: string
    name: string
    is_internal: boolean
}

export interface Invitation {
    id: string
    email: string
    organization: string | null
    display_name: string | null
    phone: string | null
    position: string | null
    status: InvitationStatus
    invited_by_name: string
    expires_at: string
    accepted_at: string | null
    created_at: string
    roles: InvitationRoleSummary[]
}

export interface CreateInvitationRequest {
    email: string
    display_name: string
    organization: string
    phone?: string
    position?: string
    role_ids: string[]
}

export interface CreateInvitationResponse {
    invitation: Invitation
    invite_link: string
}

export interface InvitationListResponse {
    data: Invitation[]
    total: number
    page: number
    per_page: number
}

export interface InvitationVerifyResponse {
    valid: boolean
    email?: string
    organization?: string | null
    display_name?: string | null
    phone?: string | null
    position?: string | null
    roles: InvitationRoleSummary[]
    reason?: 'already_accepted' | 'expired' | 'revoked' | 'not_found'
}

export interface AcceptInvitationRequest {
    invitation_token: string
    display_name: string
    phone: string
    organization: string
    password: string
    position?: string
    agree_terms: boolean
}

export interface AcceptInvitationResponse {
    user: import('@/types/auth').User
    access_token: string
    refresh_token: string
    token_type: string
    expires_in: number
}

export const invitationStatusNames: Record<InvitationStatus, string> = {
    pending: '待接受',
    accepted: '已接受',
    expired: '已過期',
    revoked: '已撤銷',
}

export const invitationStatusColors: Record<InvitationStatus, 'default' | 'success' | 'secondary' | 'destructive'> = {
    pending: 'default',
    accepted: 'success',
    expired: 'secondary',
    revoked: 'destructive',
}

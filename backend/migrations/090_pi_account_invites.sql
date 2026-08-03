-- 090: PI 帳號開通信追蹤（pi_account_invites）
--
-- 補登歷史計畫的外部 PI 沒有系統帳號 → 無法登入回應（安樂死/審查/簽章）。
-- 流程（見 PROGRESS）：有權者（建立者/SD/admin）「開通 PI 帳號」= 建帳號 + relink
-- protocols.pi_user_id，但**不寄信**；寄送「設定密碼」開通信須由 admin 核准後才放行。
-- 本表追蹤每次開通的待核准/已寄送狀態。

CREATE TABLE pi_account_invites (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    protocol_id     UUID NOT NULL REFERENCES protocols(id) ON DELETE CASCADE,
    pi_user_id      UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    email           VARCHAR(255) NOT NULL,
    -- pending：已開通帳號、等待 admin 核准寄信；sent：admin 已核准並寄出設定密碼信
    status          VARCHAR(20) NOT NULL DEFAULT 'pending',
    provisioned_by  UUID NOT NULL REFERENCES users(id),
    provisioned_at  TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    approved_by     UUID REFERENCES users(id),
    sent_at         TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- 同一計畫只追蹤一筆有效開通信（重複開通以最新覆蓋；用 partial unique 擋重複 pending）
CREATE UNIQUE INDEX uq_pi_account_invites_protocol_pending
    ON pi_account_invites(protocol_id) WHERE status = 'pending';
CREATE INDEX idx_pi_account_invites_status ON pi_account_invites(status, created_at DESC);

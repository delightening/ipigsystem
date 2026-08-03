-- 125: 補登版本名冊 — protocols.source_form_version
--
-- 記錄計畫書當前所依循的「表單版本」鍵（C/D/E/F…），驅動前端依版本名冊(manifest)
-- 過濾渲染欄位。與 original_version_label（原版標籤自由文字、finalize 時填）區分：
-- source_form_version 為標準化版本鍵，變更升級最新版時可更新。null = 視為最新版。
-- 設計依據：docs/design/protocol-import/version-manifest-backfill-plan.md §10.1。
ALTER TABLE protocols
    ADD COLUMN source_form_version TEXT;

COMMENT ON COLUMN protocols.source_form_version IS
  '計畫書表單版本鍵（C/D/E/F…）；驅動版本名冊 manifest 渲染；null=最新版；變更升級時更新';

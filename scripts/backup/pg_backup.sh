#!/bin/bash
set -euo pipefail

BACKUP_DIR="${BACKUP_DIR:-/backups}"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/ipig_${TIMESTAMP}.sql.gz"
DB_HOST="${DB_HOST:-db}"
DB_USER="${DB_USER:-postgres}"
DB_NAME="${POSTGRES_DB:-${DB_NAME:-ipig_db}}"
RETENTION_DAYS="${RETENTION_DAYS:-30}"

mkdir -p "$BACKUP_DIR"

# High 5: 優先從 Docker Secret 檔讀取密碼，避免 PGPASSWORD 暴露於 process listing
if [ -n "${POSTGRES_PASSWORD_FILE:-}" ] && [ -f "$POSTGRES_PASSWORD_FILE" ]; then
  export PGPASSWORD=$(cat "$POSTGRES_PASSWORD_FILE")
elif [ -n "${DB_PASSWORD:-}" ]; then
  export PGPASSWORD="${DB_PASSWORD}"
fi

echo "[$(date -Iseconds)] Starting backup of ${DB_NAME}..."

# Create compressed backup
pg_dump \
  -h "$DB_HOST" \
  -U "$DB_USER" \
  -Fc \
  "$DB_NAME" > "${BACKUP_FILE%.gz}"

gzip "${BACKUP_FILE%.gz}"

# Verify integrity
echo "Verifying backup integrity..."
gunzip -t "$BACKUP_FILE" || {
  echo "ERROR: Backup file is corrupt: $BACKUP_FILE"
  exit 1
}

# Verify pg_restore can read the backup
# 使用 temp 檔避免 pipefail + pg_restore 提早關 stdin 觸發 gunzip SIGPIPE 的偽失敗
TMP_VERIFY=$(mktemp)
trap 'rm -f "$TMP_VERIFY"' EXIT
gunzip -c "$BACKUP_FILE" > "$TMP_VERIFY"
if ! pg_restore --list "$TMP_VERIFY" > /dev/null 2>&1; then
  echo "ERROR: pg_restore cannot read backup: $BACKUP_FILE"
  exit 1
fi
rm -f "$TMP_VERIFY"
trap - EXIT

# High 7: 若設定 BACKUP_GPG_RECIPIENT 則加密備份；生產可強制要求加密
if [ -n "${BACKUP_REQUIRE_ENCRYPTION:-}" ] && [ "${BACKUP_REQUIRE_ENCRYPTION}" = "true" ]; then
  if [ -z "${BACKUP_GPG_RECIPIENT:-}" ]; then
    echo "ERROR: Production backup requires BACKUP_GPG_RECIPIENT to be set."
    exit 1
  fi
fi

FINAL_FILE="$BACKUP_FILE"
if [ -n "${BACKUP_GPG_RECIPIENT:-}" ]; then
  # H11: 先驗證 GPG 金鑰存在，防止金鑰 ID 錯誤時靜默產生未加密備份
  if ! gpg --list-keys "$BACKUP_GPG_RECIPIENT" > /dev/null 2>&1; then
    echo "ERROR: GPG key not found for recipient '$BACKUP_GPG_RECIPIENT'. Import the key before running backup."
    exit 1
  fi
  echo "Encrypting backup with GPG for recipient: $BACKUP_GPG_RECIPIENT"
  gpg --batch --yes --encrypt --recipient "$BACKUP_GPG_RECIPIENT" -o "${BACKUP_FILE}.gpg" "$BACKUP_FILE" || {
    echo "ERROR: GPG encryption failed"
    exit 1
  }
  rm -f "$BACKUP_FILE"
  FINAL_FILE="${BACKUP_FILE}.gpg"
fi

# Generate SHA256 checksum for final file
sha256sum "$FINAL_FILE" > "${FINAL_FILE}.sha256"
echo "Checksum: $(cat "${FINAL_FILE}.sha256")"

# Cleanup old backups（P1-R4-11：含 .sql.gz 與 .sql.gz.gpg）
DELETED=0
DELETED=$((DELETED + $(find "$BACKUP_DIR" -name "ipig_*.sql.gz" -mtime +${RETENTION_DAYS} -delete -print | wc -l)))
DELETED=$((DELETED + $(find "$BACKUP_DIR" -name "ipig_*.sql.gz.gpg" -mtime +${RETENTION_DAYS} -delete -print | wc -l)))
find "$BACKUP_DIR" -name "ipig_*.sha256" -mtime +${RETENTION_DAYS} -delete

FILESIZE=$(du -h "$FINAL_FILE" | cut -f1)
echo "[$(date -Iseconds)] Backup complete: $FINAL_FILE ($FILESIZE)"
echo "  Retention: ${RETENTION_DAYS} days, cleaned up ${DELETED} old backups"

# R36-5/6/7: 上傳到異地 (rclone dual remote)
# BACKUP_RCLONE_REMOTES=r2:bucket-name,ds918:share-name 逗號分隔
# 上傳失敗即視為整次 backup 失敗（cron 失敗 → R36-3 alert 觸發）
if [ -n "${BACKUP_RCLONE_REMOTES:-}" ]; then
    UPLOAD_DATE=$(date +%Y/%m)
    UPLOAD_FAILED=0
    IFS=','
    for remote_path in $BACKUP_RCLONE_REMOTES; do
        echo "  → 上傳到 ${remote_path}/${UPLOAD_DATE}/..."
        if ! rclone copy "$FINAL_FILE" "${remote_path}/${UPLOAD_DATE}/" --no-traverse 2>&1; then
            echo "ERROR: 上傳失敗: ${remote_path}"
            UPLOAD_FAILED=$((UPLOAD_FAILED + 1))
            continue
        fi
        # 同時上傳 sha256 檢核檔
        rclone copy "${FINAL_FILE}.sha256" "${remote_path}/${UPLOAD_DATE}/" --no-traverse 2>&1 || true
    done
    unset IFS
    if [ "$UPLOAD_FAILED" -gt 0 ]; then
        echo "ERROR: ${UPLOAD_FAILED} 個 remote 上傳失敗，本機 backup 仍保留"
        exit 1
    fi
    echo "  ✅ 異地上傳完成"
fi

# R36-3: 寫 prometheus textfile metric（node-exporter --collector.textfile.directory 撿）
# 路徑：/backup-metrics（compose 共享 volume backup_metrics）
# Alert：backup_last_success_timestamp_seconds 25h 沒更新即視為 backup 失敗
METRICS_DIR="/backup-metrics"
if [ -d "$METRICS_DIR" ]; then
  FINAL_SIZE_BYTES=$(stat -c %s "$FINAL_FILE")
  TOTAL_BACKUPS=$(find "$BACKUP_DIR" -maxdepth 1 -type f \( -name 'ipig_*.sql.gz' -o -name 'ipig_*.sql.gz.gpg' \) | wc -l)
  cat > "$METRICS_DIR/ipig_backup.prom.tmp" <<EOF
# HELP backup_last_success_timestamp_seconds Unix timestamp of last successful backup
# TYPE backup_last_success_timestamp_seconds gauge
backup_last_success_timestamp_seconds $(date +%s)
# HELP backup_last_success_size_bytes Size in bytes of last successful backup file
# TYPE backup_last_success_size_bytes gauge
backup_last_success_size_bytes ${FINAL_SIZE_BYTES}
# HELP backup_retained_files_total Number of backup files currently retained
# TYPE backup_retained_files_total gauge
backup_retained_files_total ${TOTAL_BACKUPS}
EOF
  # atomic rename — node-exporter watches inode changes
  mv "$METRICS_DIR/ipig_backup.prom.tmp" "$METRICS_DIR/ipig_backup.prom"
fi

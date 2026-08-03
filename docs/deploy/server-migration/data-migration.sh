#!/bin/bash
# ============================================================
# iPig System — 資料搬移腳本（本機 → 自建伺服器）
# ============================================================
# 在本機（來源端）執行此腳本，將資料打包並傳到新伺服器
#
# 前提：
#   - 新伺服器已開啟 SSH（區網或 Tailscale，不對外開）
#   - 已設定 SSH key 或知道密碼
#   - 本機 Docker 服務已停止（確保資料一致性）
#
# 使用方式：
#   chmod +x data-migration.sh
#   ./data-migration.sh <SERVER_USER> <SERVER_IP>
#
# 範例：
#   ./data-migration.sh ipig 192.168.1.100
# ============================================================

set -euo pipefail

SERVER_USER="${1:?用法: $0 <SERVER_USER> <SERVER_IP>}"
SERVER_IP="${2:?用法: $0 <SERVER_USER> <SERVER_IP>}"
SERVER_BASE="/opt/ipig"
BACKUP_DIR="./server-migration-backup"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)

echo "============================================"
echo "iPig 資料搬移"
echo "目標: ${SERVER_USER}@${SERVER_IP}:${SERVER_BASE}"
echo "時間: ${TIMESTAMP}"
echo "============================================"

# --------------------------------------------------
# Step 0: 確認 Docker 服務已停止
# --------------------------------------------------
echo ""
echo "[Step 0] 確認 Docker 服務狀態..."
if docker compose ps --status running 2>/dev/null | grep -q "ipig"; then
    echo "⚠️  偵測到 iPig 容器仍在運行！"
    echo "   請先執行: docker compose down"
    echo "   確保資料一致性後再繼續。"
    read -p "   是否繼續？(y/N) " confirm
    [ "$confirm" = "y" ] || exit 1
fi

# --------------------------------------------------
# Step 1: 新伺服器端建立目錄結構
# --------------------------------------------------
echo ""
echo "[Step 1] 在新伺服器建立目錄結構..."
ssh "${SERVER_USER}@${SERVER_IP}" "
    sudo mkdir -p ${SERVER_BASE}/{repo,uploads}
    sudo chown -R ${SERVER_USER}:${SERVER_USER} ${SERVER_BASE}
    echo '目錄結構建立完成'
    find ${SERVER_BASE} -maxdepth 2 -type d
"
# 注意：secrets/ 不在這裡建立。它必須落在 ${SERVER_BASE}/repo/secrets/（docker-compose
# 的 secrets: 區塊用 ./secrets/... 相對路徑，解析基準是 repo/），且是敏感資料，不放進
# 這支自動腳本，照 migration-sop.md Step 3 手動 scp。

# --------------------------------------------------
# Step 2: 匯出 PostgreSQL 資料（最可靠的方式）
# --------------------------------------------------
echo ""
echo "[Step 2] 匯出 PostgreSQL 資料庫..."
mkdir -p "${BACKUP_DIR}"

echo "  啟動臨時 DB 容器匯出..."
docker compose up -d db
sleep 5  # 等待 DB 就緒

docker compose exec -T db pg_dumpall \
    -U "${POSTGRES_USER:-postgres}" \
    --clean \
    > "${BACKUP_DIR}/pg_dumpall_${TIMESTAMP}.sql"

echo "  SQL dump 大小: $(du -h "${BACKUP_DIR}/pg_dumpall_${TIMESTAMP}.sql" | cut -f1)"

docker compose down

# --------------------------------------------------
# Step 3: 打包 uploads 目錄
# --------------------------------------------------
echo ""
echo "[Step 3] 打包 uploads 目錄..."
if [ -d "./uploads" ]; then
    tar czf "${BACKUP_DIR}/uploads_${TIMESTAMP}.tar.gz" -C . uploads/
    echo "  uploads 打包大小: $(du -h "${BACKUP_DIR}/uploads_${TIMESTAMP}.tar.gz" | cut -f1)"
else
    echo "  ⚠️  ./uploads 不存在，跳過"
fi

# --------------------------------------------------
# Step 4: 傳輸到新伺服器
# --------------------------------------------------
echo ""
echo "[Step 4] 傳輸資料到新伺服器..."

echo "  傳輸 DB dump..."
scp "${BACKUP_DIR}/pg_dumpall_${TIMESTAMP}.sql" \
    "${SERVER_USER}@${SERVER_IP}:${SERVER_BASE}/repo/pg_dump.sql"

if [ -f "${BACKUP_DIR}/uploads_${TIMESTAMP}.tar.gz" ]; then
    echo "  傳輸 uploads..."
    scp "${BACKUP_DIR}/uploads_${TIMESTAMP}.tar.gz" \
        "${SERVER_USER}@${SERVER_IP}:${SERVER_BASE}/"
fi

echo "  secrets/ 與 repo/ 請手動搬（見 migration-sop.md Step 3，敏感資料不放進這支自動腳本）"

echo "  傳輸完成！"

# --------------------------------------------------
# Step 5: 新伺服器端解壓 uploads
# --------------------------------------------------
echo ""
echo "[Step 5] 新伺服器端解壓 uploads..."
ssh "${SERVER_USER}@${SERVER_IP}" "
    cd ${SERVER_BASE}
    if [ -f uploads_${TIMESTAMP}.tar.gz ]; then
        tar xzf uploads_${TIMESTAMP}.tar.gz
        rm -f uploads_${TIMESTAMP}.tar.gz
        echo '  uploads 解壓完成'
    fi
"

echo ""
echo "============================================"
echo "✅ 資料傳輸完成！"
echo ""
echo "接下來請到新伺服器上執行（見 migration-sop.md Step 3-5）："
echo "  1. git clone ipig_system 到 ${SERVER_BASE}/repo（若還沒 clone）"
echo "  2. 手動 scp secrets/ 與 .env 到 ${SERVER_BASE}/repo/（不是 ${SERVER_BASE}/ 本身）"
echo "  3. 匯入 DB: 見 migration-sop.md Step 5"
echo "  4. 啟動: 見 migration-sop.md Step 6"
echo "============================================"

# 後端整合測試說明

本文件說明如何在本機執行後端 API 整合測試，以及常見錯誤的排除方式。

---

## 前置需求

- PostgreSQL 已安裝且可連線
- 已安裝 [sqlx-cli](https://github.com/launchbadge/sqlx)（`cargo install sqlx-cli --no-default-features --features postgres`）
- 環境變數：`TEST_DATABASE_URL` 指向**獨立的丟棄用**測試資料庫

---

## ⚠️ 手動跑 migration 一定要帶 `--database-url`

**這台開發機同時是 prod，`DATABASE_URL` 指向正式庫。**

`sqlx-cli` **只認 `DATABASE_URL` 與 `.env`，完全不看 `TEST_DATABASE_URL`**。所以下面這組
指令看起來安全，實際上會把全部 migration 跑在**正式庫**上：

```bash
export TEST_DATABASE_URL="postgres://user:pass@localhost:5432/ipig_db_test"
sqlx migrate run        # ← 錯：這行打的是 DATABASE_URL，不是上面那個
```

正確寫法是明確指定目標（本文以下所有範例都已照此修正）：

```bash
sqlx migrate run --database-url "$TEST_DATABASE_URL"
```

`scripts/run-integration-tests.*` 已在腳本內處理好，並額外把 `DATABASE_URL` 覆寫成測試庫，
確保該路徑上沒有任何子行程看得到 prod DSN。**手動執行時請自己帶。**

---

## 建議：使用專用測試資料庫

整合測試會執行 migration 並操作資料庫，且**沒有 teardown**。務必使用與正式庫分離的
丟棄用測試 DB，例如：

```bash
# 建立測試專用 DB
createdb ipig_db_test

# 設定環境變數
export TEST_DATABASE_URL="postgres://user:password@localhost:5432/ipig_db_test"
```

---

## 執行方式

### 方式一：使用腳本（推薦）

**Windows (PowerShell)：**
```powershell
.\scripts\run-integration-tests.ps1
```

**Linux / macOS：**
```bash
chmod +x scripts/run-integration-tests.sh
./scripts/run-integration-tests.sh
```

腳本會檢查 `TEST_DATABASE_URL`（未設定即中止，不 fallback 到 `DATABASE_URL`）、把
`DATABASE_URL` 覆寫成同一個值，再依序執行 `sqlx migrate run --database-url ...` 與 `cargo test`。

### 方式二：手動執行

```bash
cd backend
export TEST_DATABASE_URL="postgres://user:pass@localhost:5432/ipig_db_test"
# 同時覆寫 DATABASE_URL，避免 harness 或 Config::from_env() 讀到 prod 那條
export DATABASE_URL="$TEST_DATABASE_URL"
sqlx migrate run --database-url "$TEST_DATABASE_URL"
rtk cargo test
```

---

## 常見錯誤：VersionMismatch(1)

### 現象

```
Failed to run migrations on test database: VersionMismatch(1)
```

### 原因

`sqlx::migrate!` 會比對 `_sqlx_migrations` 表中已記錄的 checksum 與 migration 檔案的 checksum。當兩者不符時會拋出此錯誤。常見原因：

1. **Migration 檔案曾被修改**：SQLx 會對每個 migration 計算 checksum，修改後會與 DB 紀錄不符
2. **CRLF vs LF**：Windows 與 Unix 換行符號不同會導致 checksum 差異（專案已透過 `.gitattributes` 強制 migration 使用 LF）
3. **測試 DB 與開發 DB 混用**：開發 DB 可能套用過舊版 migration，與目前程式碼不一致

### 解法

**選項 A：Drop 並重建測試 DB（最乾淨）**

```bash
dropdb ipig_db_test
createdb ipig_db_test
sqlx migrate run --database-url "$TEST_DATABASE_URL"
rtk cargo test
```

**選項 B：移除有問題的 migration 紀錄**

若已知是 version 1 有問題：

```bash
# fix_migration 只讀 DATABASE_URL、不看 TEST_DATABASE_URL，
# 所以要先覆寫，否則它會連到 prod（本機的 DATABASE_URL 指向正式庫）。
export DATABASE_URL="$TEST_DATABASE_URL"
rtk cargo run --bin fix_migration 1
sqlx migrate run --database-url "$TEST_DATABASE_URL"
rtk cargo test
```

**選項 C：使用全新 Docker 容器**

```bash
rtk docker run -d --name ipig-test-db -e POSTGRES_PASSWORD=password -e POSTGRES_DB=ipig_db_test -p 5433:5432 postgres:16
export TEST_DATABASE_URL="postgres://postgres:password@localhost:5433/ipig_db_test"
./scripts/run-integration-tests.sh
```

---

## CI 環境

GitHub Actions 的 `backend-test` job 會：

1. 啟動全新的 PostgreSQL 16 容器
2. 設定 `DATABASE_URL`
3. 執行 `sqlx migrate run`
4. 執行 `cargo test`

因此 CI 使用全新 DB，不會遇到 VersionMismatch。本地失敗多半是 DB 狀態與程式碼不一致所致。

> ⚠️ 第 3 步在 CI **可以**裸跑，因為那裡的 `DATABASE_URL` 指向 job 自己的 PostgreSQL
> service container。**本機不要照抄**——這台機器的 `DATABASE_URL` 指向 prod，見上方
> 「手動跑 migration 一定要帶 `--database-url`」。

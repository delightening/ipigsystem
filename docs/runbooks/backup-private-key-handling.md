# Backup 私鑰存放 SOP

> **目的**：規範 GPG backup 私鑰（`backup@ipigsystem.asia`）的物理存放、使用時機、輪替與災難復原流程。
>
> **適用對象**：iPig system 維運（目前 solo = Jason）。
>
> **建立**：2026-05-09（R36 setup 完成同日）。

---

## 1. 為什麼要嚴格管私鑰

GPG 私鑰是 **解開所有異地 backup 的唯一鑰匙**。R2 + DS918 SMB 上面所有 `.gpg` 檔，沒有私鑰 = **永遠解不開** = backup 等於沒有。

換句話說：

| 情境 | 結果 |
|---|---|
| Prod DB 損毀 + 私鑰還在 | ✅ 從 R2/DS918 還原（4 小時內服務恢復） |
| Prod DB 損毀 + 私鑰**全部遺失** | ❌ **資料永久消失**（無 amount of money 能還原） |
| 私鑰**外洩**給攻擊者 | ⚠️ 攻擊者拿到 R2/SMB 後可解開所有歷史 backup（含已撤銷的個資） |

→ 私鑰比 prod DB 本身**更重要**。

---

## 2. 私鑰目前的存放狀態

| 位置 | 媒介 | Label | 用途 | 備註 |
|---|---|---|---|---|
| **USB #1** | 16GB USB 隨身碟 | `BLACKSLIVER` | 主份 | 平常**收在公司保險箱 / 抽屜** |
| **USB #2** | 32GB USB 隨身碟 | `King` | 備份 | 平常**收在家裡 / 親戚家**（異地） |
| Prod 機 keyring | — | — | 平常**空** | 只在 restore drill / 輪替時暫時 import |
| Bitwarden | 雲端密碼管理器 | — | 存 **GPG passphrase**（不是私鑰本身） | item: `ipig backup GPG passphrase` |

### Key 識別資訊

```
Email:        backup@ipigsystem.asia
Fingerprint:  E1301B885EBC9873FFC70F8851D03ED986A32367
Algorithm:    RSA 4096
Created:      2026-05-08
Expires:      Never
File size:    7,532 bytes (ASCII-armored)
File name:    backup_gpg_privkey.asc
```

---

## 3. 黃金規則

### 🟢 平常狀態（99% 時間）

- ✅ **兩支 USB 都拔下來**，分散在兩個物理地點
- ✅ **Prod 機 keyring 是空的**（只有公鑰）
- ✅ 公鑰流向 prod 用於加密 backup（單向，無法從公鑰反推私鑰）

### 🟡 例外狀態（限定時機）

**只在以下 4 種情況下**才應該插 USB：

| 時機 | 動作 | 完成後 |
|---|---|---|
| **季度 DR drill**（每 3 個月 1 次） | 插任一支 USB → 跑 restore 驗證 | 拔掉 + 從 keyring 刪私鑰 |
| **真實災難復原**（DB 損毀） | 插任一支 USB → 還原 prod | 拔掉 + 從 keyring 刪私鑰 |
| **USB 老化更新**（每 3-5 年） | 插舊 USB → 複製到新 USB → 驗證 | 拔掉 + 報廢舊 USB（物理銷毀） |
| **GPG passphrase 輪替**（每 5 年） | 插任一支 → `gpg --passwd` → **兩支都更新** | 拔掉 + 同步更新 Bitwarden |

### 🔴 永遠不要做

- ❌ **把私鑰複製到 OneDrive / Google Drive / Dropbox / 雲端**（即使加密）
- ❌ **email / LINE / Slack 傳私鑰檔**
- ❌ **commit 私鑰到 git**（公開或 private repo 都不行）
- ❌ **把 .gnupg 目錄包進 docker image**
- ❌ **prod 容器內存私鑰**（容器只該有公鑰）
- ❌ **長時間插著 USB 不拔**（攻擊面）
- ❌ **只留一支 USB 沒備份**（USB 物理上會壞 / 接觸不良）

---

## 4. USB 物理管理

### 命名 / 標記

實體 USB 上**用麥克筆寫**（或貼貼紙）：

```
ipig backup
2026-05-08
1/2     ← 表示「2 支中的第 1 支」
```

### 收存位置建議

| USB | 收在哪 | 為什麼 |
|---|---|---|
| `BLACKSLIVER` (主份) | 公司辦公室抽屜 / 小保險箱 | 接近 prod，drill 時方便拿 |
| `King` (備份) | **家裡 / 親戚家**（不同建築） | 公司失火/失竊不會一起完蛋 |

> 💡 **物理距離 > 5 公里** = 同一場災難（地震、火災）難以同時影響兩處。

### USB 老化

USB flash memory 寫入循環有限（3D NAND 約 1,000~10,000 次），但**讀取沒上限**。我們的 USB 寫一次後幾乎只讀，理論上可用 10+ 年。但：

- **接觸不良**：USB 接頭氧化，2-3 年就可能讀不出來
- **韌體故障**：低品質 USB 韌體 bug 導致 brick
- **物理損壞**：摔到、受潮、靜電

→ **每 3 年**主動換新 USB（即使舊的還能讀）。

---

## 5. 災難復原 SOP

### 情境 A：Prod DB 損毀，但 USB 私鑰還在

1. 拿 USB（任一支即可）插到任何 Linux/Windows + GPG 機器
2. 跑 `gpg --import /path/to/backup_gpg_privkey.asc`（pinentry 問 passphrase，從 Bitwarden 取）
3. 從 R2 或 DS918 下載最新 `.gpg`
4. 跑 `gpg --decrypt` → `pg_restore`
5. 詳細步驟見 [`backup-setup.md`](backup-setup.md) Step 6

**RTO**：< 30 分鐘（自動化後）

### 情境 B：USB #1 (BLACKSLIVER) 壞掉 / 弄丟

1. 用 USB #2 (King) 還原至少能用
2. **48 小時內**買新 USB → 從 King 複製私鑰 → 重新標記為 USB #1
3. King 暫存到原 BLACKSLIVER 位置；新 USB 帶到家裡（角色互換）
4. 紀錄事件到 [`dr-drill-records.md`](dr-drill-records.md) §5

### 情境 C：兩支 USB 都壞 / 都不見

🚨 **完整資料無法救回**（從加密 backup 解開）。可能挽救：

1. 檢查 prod 機 `~/.gnupg/private-keys-v1.d/` 是否還有殘留（極少數情況下還在）
2. 從**最近一次 import 的 SHA256 證明**反推（如果有寫進系統 log）
3. **業務應對**：通知所有 stakeholder，計畫從 raw DB（如還活著）重建狀態

→ 為了避免情境 C，**第三份 backup**（paper key 紙本）是建議：
- `paperkey --secret-key=backup_gpg_privkey.asc --output=paperkey.txt`
- 列印實體紙本 → 塑膠袋封 → 鎖**真正的保險箱**（銀行 safe deposit box 等級）
- 紙本只在情境 C 時 OCR 還原（很慢但可行）

> ⚠️ **目前未做** paper key — 列為 R36 follow-up。

---

## 6. Passphrase 管理

### 目前做法

- **GPG passphrase** 存在 Bitwarden item `ipig backup GPG passphrase`
- Bitwarden master password 寫紙本鎖抽屜
- Bitwarden 開啟 2FA（TOTP，不是 SMS）

### 為什麼 passphrase 跟私鑰**分開存**

如果攻擊者**只**拿到 USB（私鑰）→ 沒 passphrase 解不開
如果攻擊者**只**拿到 Bitwarden（passphrase）→ 沒 USB 也無用
**兩個都拿到才能解** = 多一層防禦

→ **絕對不要**把 passphrase 寫在 USB 上（USB 上**只**放加密過的私鑰）。

### Passphrase 輪替週期

- **建議每 5 年輪替**一次（NIST 800-63 過去要求 90 天，但 [現代規範改為「除非外洩否則不換」](https://pages.nist.gov/800-63-3/sp800-63b.html#-5113-memorized-secret-verifiers)）
- **必輪替時機**：懷疑外洩 / 經手人異動

### 輪替程序（5 年後）

1. 插 USB G: → `gpg --import`
2. `gpg --passwd backup@ipigsystem.asia` → pinentry：舊密碼 → 新密碼 → 確認
3. 重新匯出私鑰：`gpg --armor --export-secret-key backup@ipigsystem.asia > newkey.asc`
4. 把 `newkey.asc` 覆蓋到 G: 跟 F: 兩支 USB（都要更新！）
5. Bitwarden item 更新成新密碼
6. `gpg --batch --yes --delete-secret-keys <fingerprint>` 清 keyring
7. 拔 USB
8. 紀錄到 [`dr-drill-records.md`](dr-drill-records.md)

---

## 7. 例行檢查（每月）

- [ ] **每月一次**：插 USB → `gpg --list-packets backup_gpg_privkey.asc` → 確認檔案結構正常（不需 import）
- [ ] **每月一次**：Grafana 看 `backup_last_success_timestamp_seconds` 持續更新中
- [ ] **每季一次**：完整 DR drill（Step 6）
- [ ] **每年一次**：驗證**離家那支** USB 還能讀（請家人/親戚試插一次回報）
- [ ] **每 3 年**：USB 換新

---

## 8. 反向引用

- 完整 backup 設定流程：[`backup-setup.md`](backup-setup.md)
- DR drill 紀錄：[`dr-drill-records.md`](dr-drill-records.md)
- HMAC 相關（不是 GPG，但同類議題）：[`../security/HMAC_VERSIONING.md`](../security/HMAC_VERSIONING.md)
- TODO backlog：`docs/TODO.md` R36（backup）+ R37（其他 secrets 遷移）

---

## 9. 變更紀錄

| 日期 | 變更 | 操作者 |
|---|---|---|
| 2026-05-08 | GPG keypair 產生 (E1301...A32367) | Jason |
| 2026-05-09 | 私鑰匯出至 USB G: BLACKSLIVER + USB F: King | Jason |
| 2026-05-09 | 從 prod 機 keyring 刪除私鑰（留公鑰）| Jason |
| 2026-05-09 | 完成首次 DR drill 驗證 USB 私鑰可救回 | Jason |
| 2026-05-09 | 本 SOP 文件建立 | Jason |

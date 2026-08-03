# DB At-Rest Encryption 評估 (R41-8)

> **評估日期**：2026-05-11
> **對應 R41 子項**：R41-8（NICS 附表十「系統與通訊保護 / 靜置資料保護」高級要求）
> **結論**：採方案 A（Windows BitLocker），其他不追

---

## 1. 背景

NICS 附表十「系統與通訊保護 / 靜置資料保護 (Protection of Information at Rest)」標記為**僅高級要求**（普中級無此項）。ipig_system 自評為普級基準，本評估僅為 **best-effort 補強**，無強制義務。

現況：
- DB（PostgreSQL）資料目錄為 Docker volume `pgdata`，掛在 Windows host C: 槽
- 應用層**部分加密**：TOTP secret 已用 AES-GCM 加密儲存（`services/auth/two_factor.rs`）；密碼用 Argon2id 雜湊（不可逆）
- 備份**已加密**：R36 完成 pg_dump → 加密 tar.gz → NAS（DS923+）
- **缺口**：作業中的 DB data dir 在 host 磁碟層級是明碼

---

## 2. 方案比較

| 方案 | 工時 | 成本 | 適用性 | 推薦 |
|---|:-:|:-:|:-:|:-:|
| **A. Windows BitLocker（host C: 槽）** | 1h | 0 元 | Windows 11 Pro 內建；整顆磁碟加密 | **✅ 採納** |
| B. Postgres pgcrypto column-level | 20h+ | 0 元 | 需動 schema + app code；對單表只加密數欄 | ❌ |
| C. Postgres TDE（商業：Cybertec / EDB）| 10h | 月費 ~$200+ | 開源 Postgres 不支援原生 TDE | ❌ |
| D. Docker volume 加密（dm-crypt LUKS on container host）| 8h | 0 元 | 需 Linux host；Windows 不適用 | ❌ |
| E. 改部署到加密 NAS（DS925+）| 50h+ | 機器 ~$2 萬+ | 整套搬家工程；已列 `nas-setup` 記憶 | ⏸ 未來 |

---

## 3. 方案 A 採納理由

- **無成本**：Windows 11 Pro（已是本系統 host OS）內建 BitLocker，授權含 TPM 自動解鎖
- **零程式改動**：DB、app、備份流程都不需要動
- **整顆磁碟覆蓋**：不只 Postgres data，連 Docker images、logs、temp files 都受保護
- **效能影響可忽略**：AES-NI 硬體加速下開啟 BitLocker 對 Postgres 寫入 IOPS 影響 < 5%

### 殘留風險

- **OS-level threats** 仍未防範：root/Administrator 拿到的攻擊者可直接讀 mounted volume
  → 補償控制：強密碼 + Windows Hello（已啟用）+ 不開遠端桌面
- **記憶體中明碼**：Postgres shared_buffers 仍是明碼
  → 補償控制：實體機器在上鎖辦公室；磁碟層加密針對「機器遺失/被盜」場景

---

## 4. 啟用步驟（建議排程）

由於本機**已含正式營運資料**，啟用 BitLocker 對作業中磁碟做加密**需停機 + 加密時間**（依資料量約 1–4 小時）。建議排程於：

1. **完整 backup 驗證後**（最近一次 DR drill 通過：2026-05-08 R36-9 row-count 全相符）
2. **離峰時段**（週末晚間）
3. **TPM 復原金鑰備份到 USB + 列印一份放保險箱**（金鑰遺失等同資料遺失）

操作流程：

```powershell
# 1. 確認 TPM 啟用
Get-Tpm

# 2. 啟用 BitLocker（C: 槽）
Enable-BitLocker -MountPoint "C:" -EncryptionMethod Aes256 -UsedSpaceOnly -TpmProtector

# 3. 備份復原金鑰
Get-BitLockerVolume -MountPoint "C:" | Select-Object -ExpandProperty KeyProtector

# 4. 加密期間可正常使用，背景作業
Get-BitLockerVolume -MountPoint "C:"
```

---

## 5. 合規對照

| 控制項 | 啟用 BitLocker 前 | 啟用後 |
|---|:-:|:-:|
| NICS 附表十「靜置資料保護」（高級）| 🟡 PARTIAL | ✅ PASS |
| ISO 27001 A.10.1.1 加密政策 | 🟡 部分 | ✅ |
| 21 CFR Part 11 §11.10 records protection | ✅（簽章 + audit chain）| ✅（加上磁碟層）|
| HIPAA Security Rule §164.312(a)(2)(iv)（如本系統含 PHI）| ❌ | ✅ |

---

## 6. 後續工作

- [ ] 排定啟用日期（建議 2026-06 月內，與下一次 DR drill 同時段執行）
- [ ] 復原金鑰備份程序文件化（加進 `docs/runbooks/`）
- [ ] BitLocker 狀態納入 monthly health check 項目
- [ ] 移轉至 DS925+ prod 時，新機評估 NAS encrypted volume（已記憶 `nas-setup`）

---

## 7. 不採納方案 B–E 理由

- **方案 B (pgcrypto)**：對單欄加密增加應用複雜度，且查詢時必須 decrypt → index 失效。對 ipig 多表結構成本太高
- **方案 C (商業 TDE)**：月費對 solo 系統不成比例；開源 Postgres 17 仍無原生 TDE
- **方案 D (LUKS)**：需 Linux host；遷移 OS 工作量遠超效益
- **方案 E (DS925+)**：已列入未來計畫（記憶 `nas-setup`），但獨立於本評估範圍

---

*評估完成；本文件由 R41-8 落地產出。實際 BitLocker 啟用為後續單獨任務。*

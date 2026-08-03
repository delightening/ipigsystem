-- 141: backfill animals.species_id（補 44 筆）＋ 補建 species 主檔缺漏的 'LYD' 列
--
-- 背景：animals 有兩套「動物種類」表述——寫死的 animals.breed（animal_breed enum）與可自助維護的
-- animals.species_id（FK → species）。目標終態是讓 species_id 成為唯一真相源、breed enum 退役
-- （設計書：docs/design/self-service-animal-species/DESIGN.md）。本 migration 是該計畫 P1 的資料前置。
--
-- 實測（prod，2026-07-25）：
--   * animals 共 159 列，species_id 為 NULL 者 44 列（breed=miniature 21、white 23）。
--   * 已填 species_id 的 115 列與 breed 完全一致（miniature→miniature 101、white→white 14），無矛盾列。
--   * breed 只用到 miniature / white；LYD 與 other 從未被任何動物使用。
-- 因此 breed → species 為 1:1，backfill 為確定性 UPDATE，不需人工判讀。
--
-- 關於補建 'LYD'：animal_breed enum 有 LYD，species 主檔沒有對應列。以 is_active=false 補上，理由——
--   (a) 讓 enum ↔ species 主檔維持 1:1，P3 移除 enum 時有完整對照可稽核；
--   (b) 不改變現有表單可選項（表單只列出啟用中的物種），符合外科手術式變更；
--   (c) 真的要用時 admin 可在物種管理自助啟用，不需再跑 migration。
--
-- 另補一個 functional unique index：species 原本的 UNIQUE(code) 區分大小寫，擋不住
-- 'lyd' 與 'LYD' 併存。code 是匯入比對與品種推導的查表鍵，同一個代碼有兩種大小寫版本
-- 會直接造成對應錯亂，故在 lower(code) 上建唯一索引，讓 DB 端真正擋下。
-- （service 層的不分大小寫預檢只負責回可讀訊息，併發下的保證在這個索引。）
--
-- 鎖定/部署 tradeoff：backfill 為純 INSERT/UPDATE；唯一的 DDL 是這個索引，
-- species 僅個位數列，建立瞬間完成，鎖定影響可忽略。

-- ── 補建 LYD 物種列（pig 之子物種，停用狀態）──
INSERT INTO species (id, code, name, name_en, parent_id, is_active, sort_order)
VALUES (
    'a0000000-0000-0000-0000-000000000005',
    'LYD',
    'LYD',
    'LYD',
    'a0000000-0000-0000-0000-000000000001',  -- parent = pig
    false,
    3
)
ON CONFLICT (code) DO NOTHING;

-- ── backfill：以 breed 文字對應 species.code ──
-- animal_breed 的 enum label（miniature / white / LYD / other）與 species.code 逐字相同，
-- 故可直接對接；上面補建 LYD 後四個值皆有對應列。
UPDATE animals a
SET species_id = s.id,
    updated_at = NOW()
FROM species s
WHERE a.species_id IS NULL
  AND s.code = a.breed::text;

-- ── code 大小寫不分的唯一性（真正的併發防線）──
CREATE UNIQUE INDEX IF NOT EXISTS uq_species_code_lower ON species (lower(code));

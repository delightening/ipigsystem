# -*- coding: utf-8 -*-
"""F 版（AD-04-01-01F）動物試驗研究計畫書 docx → working_content 抽取器。

重建自已遺失的 `_phase4_extract.py`（原針對 D/E/F 版）。本版專攻 F 版：
以「文件段落標題 → 緊接其後的表格」配對（heading-driven），再對表格內
以 ■/□ 勾選錨點與 label 欄比對取值，避免依賴固定表格索引。

驗收方式：對 PIG-115012（F 版、prod 已補登完成）跑一次，與 DB 既有
working_content 比對關鍵欄位。

依賴：`python-docx`（未列入 pyproject.toml——本檔為一次性補登工具，非專案
執行期相依）。執行前先 `pip install python-docx`。

Usage:
    python _phase4f_extract.py <docx> [<docx> ...] -o out.json --iacuc PIG-115014 ...
"""
import argparse
import json
import re
import sys

from docx import Document
from docx.table import Table
from docx.text.paragraph import Paragraph

# 勾選符號各案不一致：多數用 ■(U+25A0)，PIG-115014 全篇用 █(U+2588)。
# 一律以字元類比對，勿寫死單一字元（否則整份抽不到，且會靜默抽成空）。
CHECKED_CHARS = "■█☑▓"
UNCHECKED_CHARS = "□☐"
CHK = "[" + CHECKED_CHARS + "]"
UNCHK = "[" + UNCHECKED_CHARS + "]"
BOX = "[" + CHECKED_CHARS + UNCHECKED_CHARS + "]"


def is_checked(text):
    return any(ch in text for ch in CHECKED_CHARS)

SPECIES_MAP = {"豬": "pig", "羊": "goat", "牛": "cattle", "兔": "rabbit"}
STRAIN_MAP = {
    "迷你豬": "mini_pig",
    "白豬": "white_pig",
    "蘭嶼豬": "lanyu_pig",
    "努比亞山羊": "nubian_goat",
}
SEX_MAP = {"公": "male", "母": "female", "不限": "any"}

PROJECT_TYPE_KEYS = [
    "1_basic_research", "2_applied_research", "3_pre_market_testing",
    "4_educational", "5_biologics_manufacturing", "6_other",
]
PROJECT_CATEGORY_KEYS = [
    "1_medical", "2_agricultural", "3_drugs_vaccines", "4_supplements",
    "5_food", "6_toxics_chemicals", "7_medical_materials", "8_pesticide",
    "9_animal_drugs_vaccines", "10_animal_supplements_feed",
    "11_cosmetics", "12_other",
]
FUNDING_KEYS = ["moa", "mohw", "nstc", "moe", "env", "other"]

ALT_PLATFORMS = [
    ("ALTBIB", "altbib"),
    ("DB-ALM", "db_alm"),
    ("歐洲動物替代試驗資源平台", "re_place"),
    ("Johns Hop", "johns_hopkins"),
    ("TAAT", "taat"),
    ("台灣動物替代", "taat"),
    ("EDA", "nc3rs_eda"),
    ("Refinement", "nc3rs_refinement"),
]

PAIN_CATEGORIES = ["B", "C", "D", "E"]


# ─────────────────────────── docx 走訪工具 ───────────────────────────
def iter_blocks(doc):
    """依文件順序產出 (kind, obj)：kind ∈ {'p','t'}。"""
    body = doc.element.body
    for child in body.iterchildren():
        tag = child.tag.split("}")[-1]
        if tag == "p":
            yield "p", Paragraph(child, doc)
        elif tag == "tbl":
            yield "t", Table(child, doc)


def labelled_tables(doc):
    """回傳 [(heading, Table)]；heading = 表格前最近的非空段落文字。"""
    out = []
    heading = ""
    for kind, obj in iter_blocks(doc):
        if kind == "p":
            txt = obj.text.strip()
            if txt:
                heading = txt
        else:
            out.append((heading, obj))
    return out


def row_cells(row):
    """去除水平合併造成的重複儲存格。

    ⚠️ 必須以底層 <w:tc> 元素判同（合併儲存格會重複回傳同一個 tc），
    不可用「文字相同就併」——那會把兩個**不同的空欄**併成一個，
    造成後續欄位整列位移（PIG-115017 體重欄空 → 動物來源被讀成體重）。
    """
    out = []
    last_tc = None
    for c in row.cells:
        if c._tc is last_tc:
            continue
        last_tc = c._tc
        out.append(c.text.strip())
    return out


def table_text(tb):
    return "\n".join(
        "\t".join(row_cells(r)) for r in tb.rows
    )


def find_table(tables, *needles, skip=0):
    """找第一個 heading 或內容含全部 needles 的表格。"""
    hit = 0
    for heading, tb in tables:
        blob = heading + "\n" + table_text(tb)
        if all(n in blob for n in needles):
            if hit >= skip:
                return heading, tb
            hit += 1
    return None, None


def label_value(tb, label, col=1):
    """在 label-driven 表格中，找 label 所在列並取其後第一個非空欄。"""
    for r in tb.rows:
        cells = row_cells(r)
        for i, c in enumerate(cells):
            if label in c:
                for v in cells[i + 1:]:
                    if v:
                        return v
    return None


def checked_options(text):
    """回傳所有被勾選的項目文字（以勾選符號切段，取到下一個框或換行前）。"""
    out = []
    for m in re.finditer(CHK + r"\s*([^" + CHECKED_CHARS + UNCHECKED_CHARS + r"\n]+)", text):
        val = m.group(1).strip(" 　\t")
        if val:
            out.append(val)
    return out


def numbered_checked(text, keys):
    """『□1.xxx。■2.yyy。』→ 回傳被勾選的序號對應 key。"""
    out = []
    for m in re.finditer("(" + BOX + r")\s*(\d+)\s*[.、]", text):
        if is_checked(m.group(1)):
            idx = int(m.group(2)) - 1
            if 0 <= idx < len(keys):
                out.append(keys[idx])
    return out


def clean(s):
    if s is None:
        return None
    s = re.sub(r"[ \t　]+", " ", s).strip()
    return s or None


# ─────────────────────────── 各 Section 抽取 ───────────────────────────
def extract_basic(tables):
    _, tb = find_table(tables, "計畫主持人資料", "專案主持人")
    basic = {}
    if tb is None:
        return basic

    pi = {
        "name": clean(label_value(tb, "計畫主持人(PI)")),
        "position": clean(label_value(tb, "職稱")),
        "phone": clean(label_value(tb, "連絡電話")),
        "email": clean(label_value(tb, "電子信箱")),
        "address": clean(label_value(tb, "地址")),
    }
    basic["pi"] = {k: v for k, v in pi.items() if v}
    # 外部 PI（pi_user_id=None）時後端硬性要求 basic.pi.name 非空
    # （services/protocol/core.rs），此處若因標題文字不符而抓空，會延到匯入時
    # 才被後端打回、且錯誤訊息不指向真正原因，故當場示警。
    if not basic["pi"].get("name"):
        print("  !! 警告：抓不到計畫主持人(PI)姓名 → 匯入時後端會拒收，請檢查申請表標題文字")

    # 委託 / 試驗單位：名稱 + 聯絡人 + 該段之後的電話 / email
    sponsor = {"name": clean(label_value(tb, "試驗單位名稱"))}
    rows = [row_cells(r) for r in tb.rows]
    for i, cells in enumerate(rows):
        joined = " ".join(cells)
        if "聯絡人" in joined:
            sponsor["contact_person"] = clean(cells[-1])
            for nxt in rows[i + 1:i + 3]:
                nj = " ".join(nxt)
                if "連絡電話" in nj:
                    sponsor["contact_phone"] = clean(nxt[-1])
                elif "電子信箱" in nj:
                    sponsor["contact_email"] = clean(nxt[-1])
            break
    basic["sponsor"] = {k: v for k, v in sponsor.items() if v}

    facility_title = clean(label_value(tb, "試驗機構名稱"))
    if facility_title:
        basic["facility"] = {"title": facility_title}
    housing = clean(label_value(tb, "試驗機構地址"))
    if housing:
        basic["housing_location"] = housing

    sd = clean(label_value(tb, "專案主持人(SD)"))
    if sd:
        basic["sd"] = {"name": sd}

    # 計畫類型 / 種類 / 經費來源
    _, tb3 = find_table(tables, "計畫類型及種類", "經費來源")
    if tb3 is not None:
        for r in tb3.rows:
            cells = row_cells(r)
            if not cells:
                continue
            head, body = cells[0], " ".join(cells[1:])
            if "類型" in head and "種類" not in head:
                v = numbered_checked(body, PROJECT_TYPE_KEYS)
                if v:
                    basic["project_type"] = v
            elif "種類" in head:
                v = numbered_checked(body, PROJECT_CATEGORY_KEYS)
                if v:
                    basic["project_category"] = v
            elif "經費" in head:
                v = numbered_checked(body, FUNDING_KEYS)
                if v:
                    basic["funding_sources"] = v
    return basic


def extract_animals(tables):
    _, tb = find_table(tables, "動物別", "使用量", "動物飼養場所")
    if tb is None:
        return {}
    out = []
    for r in tb.rows[1:]:
        cells = row_cells(r)
        if len(cells) < 5 or not is_checked(cells[0]):
            continue
        sp_raw = re.sub(BOX, "", cells[0]).strip()
        parts = [p.strip() for p in sp_raw.split("/")]
        sp_txt, strain_txt = (parts + ["", ""])[:2]
        a = {}
        # ProtocolAnimalItem.species 只收 'pig' | 'other'；品系只收 white_pig/mini_pig。
        # 以「品系」為準判物種：豬品系→pig，其餘（如努比亞山羊）→other + *_other 保留原文。
        strain_code = STRAIN_MAP.get(strain_txt)
        if strain_code in ("mini_pig", "white_pig"):
            a["species"] = "pig"
            a["strain"] = strain_code
        else:
            a["species"] = "other"
            if sp_txt and sp_txt not in ("其他",):
                a["species_other"] = sp_txt
            elif strain_txt:
                a["species_other"] = strain_txt
            if strain_txt:
                a["strain_other"] = strain_txt
        # 性別 / 數量："公/1 頭 母/ 頭 不限/ 頭"。可能同時填公與母（如 公/3 母/3），
        # ProtocolAnimalItem.sex 是單值 → 每個有數量的性別各出一筆，避免覆寫掉總量。
        sexes = []
        for zh, code in SEX_MAP.items():
            m = re.search(zh + r"\s*/\s*(\d+)", cells[1])
            if m:
                sexes.append((code, m.group(1)))
        age = clean(cells[2]) if len(cells) > 2 else None
        if age:
            if "不限" in age or "不拘" in age:
                a["age_unlimited"] = True
            else:
                # 「大於5月齡」/「5-8月齡」→ 取數字（與既有補登資料同格式）
                nums = re.findall(r"\d+", age)
                if nums:
                    a["age_min"] = nums[0]
                    if len(nums) > 1:
                        a["age_max"] = nums[1]
                else:
                    a["age_min"] = age
        wt = clean(cells[3]) if len(cells) > 3 else None
        if wt:
            if "不限" in wt or "不拘" in wt:
                a["weight_unlimited"] = True
            else:
                m = re.search(r"(\d+)\s*[-~～]\s*(\d+)", wt)
                if m:
                    a["weight_min"], a["weight_max"] = m.group(1), m.group(2)
                else:
                    nums = re.findall(r"\d+", wt)
                    if nums:
                        a["weight_min"] = nums[0]
        src = clean(cells[4]) if len(cells) > 4 else None
        if src:
            # ProtocolAnimalItem 用 source_name（無 source 欄）
            a["source_name"] = src.replace("\n", " ")
        hl = clean(cells[5]) if len(cells) > 5 else None
        if hl:
            a["housing_location"] = hl
        base = {k: v for k, v in a.items() if v is not None}
        if sexes:
            for code, n in sexes:
                out.append(dict(base, sex=code, number=n))
        else:
            out.append(base)
    return {"animals": out} if out else {}


def extract_personnel(tables):
    _, tb = find_table(tables, "工作內容", "參與動物試驗年數")
    if tb is None:
        return []
    out = []
    for r in tb.rows[1:]:
        cells = row_cells(r)
        if len(cells) < 5:
            continue
        name = clean(cells[1])
        if not name:
            continue
        roles_raw = cells[3] or ""
        roles = sorted(set(re.findall(r"\b([a-l])\b", roles_raw.lower())))
        years = re.sub(r"[^\d]", "", cells[4] or "")
        trainings_raw = (cells[5] or "").strip() if len(cells) > 5 else ""
        trainings = sorted(set(re.findall(r"^\s*([A-D])[\s(（]",
                                          trainings_raw, re.M)))
        p = {"name": name, "position": clean(cells[2])}
        if roles:
            p["roles"] = roles
        if years:
            p["years_experience"] = years
        if trainings:
            p["trainings"] = trainings
        if trainings_raw:
            p["trainings_raw"] = trainings_raw
        out.append(p)
    return out


def extract_purpose(tables):
    purpose = {}
    _, nec = find_table(tables, "必要性")
    if nec is None:
        # 必要性通常是「請說明活體動物試驗之必要性…」標題後的 1x1 表
        for heading, tb in tables:
            if "必要性" in heading:
                nec = tb
                break
    if nec is not None:
        purpose.setdefault("replacement", {})["rationale"] = clean(table_text(nec))

    # 2.2.2 替代方案搜尋平台
    for heading, tb in tables:
        blob = table_text(tb)
        if "ALTBIB" in blob or "DB-ALM" in blob:
            plats = []
            for needle, code in ALT_PLATFORMS:
                if re.search(CHK + r"\s*" + re.escape(needle), blob):
                    if code not in plats:
                        plats.append(code)
            alt = {}
            if plats:
                alt["platforms"] = plats
            tail = blob.split("\n")[-1].strip()
            if tail and "ALTBIB" not in tail:
                alt["conclusion"] = clean(tail)
            if alt:
                purpose.setdefault("replacement", {})["alt_search"] = alt
            break

    # 減量：「請以實驗動物應用3Rs之減量原則…」
    for heading, tb in tables:
        if "減量" in heading:
            purpose.setdefault("reduction", {})["design"] = clean(table_text(tb))
            break

    # 精緻化
    for heading, tb in tables:
        if "精緻化" in heading:
            purpose["refinement_description"] = clean(table_text(tb))
            break
    return purpose


def extract_design(tables):
    design = {}

    # 疼痛等級（Category B–E）
    _, tb = find_table(tables, "Category")
    if tb is not None:
        blob = table_text(tb)
        for cat in PAIN_CATEGORIES:
            if re.search(CHK + r"\s*Category\s*" + cat, blob):
                design["pain"] = {"category": cat}
                break

    # 麻醉
    _, tb = find_table(tables, "麻醉前禁食")
    if tb is not None:
        blob = table_text(tb)
        design.setdefault("anesthesia", {})["is_under_anesthesia"] = (
            bool(re.search(CHK + r"\s*是", blob))
        )
    _, tb = find_table(tables, "存活手術", "非存活手術")
    if tb is not None:
        blob = table_text(tb)
        if re.search(CHK + r"\s*非存活手術", blob):
            design.setdefault("anesthesia", {})["anesthesia_type"] = "non_survival_surgery"
        elif re.search(CHK + r"\s*存活手術", blob):
            design.setdefault("anesthesia", {})["anesthesia_type"] = "survival_surgery"

    # 實驗終點 / 人道終點（同一格，切開）
    for heading, tb in tables:
        blob = table_text(tb)
        if "實驗終點" in blob:
            ep = {}
            m = re.search(r"實驗終點[：:]\s*(?:\(請說明\))?\s*(.*?)"
                          r"(?=人道終點|$)", blob, re.S)
            if m and clean(m.group(1)):
                ep["experimental"] = clean(m.group(1))
            m = re.search(r"人道終點[：:]\s*(?:\(請說明\))?\s*(.*)", blob, re.S)
            if m and clean(m.group(1)):
                ep["humane"] = clean(m.group(1))
            if ep:
                design["endpoints"] = ep
            break

    # 動物最終處置
    _, tb = find_table(tables, "安樂死(Euthanized)")
    if tb is not None:
        opts = checked_options(table_text(tb))
        if opts:
            design["final_handling"] = {"description": " / ".join(opts)}

    # 屍體處理
    for heading, tb in tables:
        if "屍體" in heading:
            design["carcass_disposal"] = {"description": clean(table_text(tb))}
            break

    # 試驗流程
    for heading, tb in tables:
        if "動物試驗內容及流程" in heading:
            design["procedures"] = {"description": clean(table_text(tb))}
            break

    # 危害性物質 / 管制藥品
    restrictions = {}
    _, tb = find_table(tables, "危害性物質")
    if tb is not None:
        restrictions["hazardous"] = not bool(
            re.search(CHK + r"\s*否", table_text(tb))
        )
    _, tb = find_table(tables, "管制藥品")
    if tb is not None:
        restrictions["controlled_drugs"] = not bool(
            re.search(CHK + r"\s*否", table_text(tb))
        )
    if restrictions:
        design["restrictions"] = restrictions
    return design


def extract_items(tables):
    _, tb = find_table(tables, "試驗物質之資訊")
    if tb is None:
        return {}
    blob = table_text(tb)
    use = not bool(re.search(CHK + r"\s*否", blob))
    out = {"use_test_item": use}

    # 鍵名對齊 ProtocolWorkingContent.items.{test_items,control_items} 型別
    keymap = {"名稱": "name", "效期": "expiry_date", "批號": "lot_no",
              "用途": "purpose", "保存規定": "storage_conditions"}
    test_items, control_items = [], []
    for heading, t in tables:
        rows = [row_cells(r) for r in t.rows]
        flat = " ".join(" ".join(r) for r in rows)
        if not (flat.startswith("名稱:") or flat.startswith("名稱：")):
            continue
        it = {}
        for r in rows:
            if len(r) < 2:
                continue
            k, v = r[0].rstrip(":：").strip(), clean(r[1])
            if not v:
                continue
            if k in keymap:
                it[keymap[k]] = v
            elif "滅菌" in k:
                it["is_sterile"] = bool(re.search(CHK + r"\s*是", v))
        # 無名稱者視為空白欄位（未使用試驗/對照物質），不產生空殼項目
        if not it.get("name"):
            continue
        # 依表格前的標題分流：試驗物質 → test_items；對照物質 → control_items
        if "對照物質" in heading:
            control_items.append(it)
        else:
            test_items.append(it)
    if test_items:
        out["test_items"] = test_items
    if control_items:
        out["control_items"] = control_items
    return out


def extract_surgery(tables):
    surgery = {}
    _, tb = find_table(tables, "存活手術", "非存活手術")
    if tb is not None:
        blob = table_text(tb)
        if re.search(CHK + r"\s*非存活手術", blob):
            surgery["surgery_type"] = "non_survival"
        elif re.search(CHK + r"\s*存活手術", blob):
            surgery["surgery_type"] = "survival"

    heading_map = [
        ("術前準備", "preop_preparation"),
        ("動物術前準備", "preop_preparation"),
        ("無菌", "aseptic_techniques"),
        ("手術內容說明", "surgery_description"),
        ("術中監控", "monitoring"),
        ("術後照護", "postop_care"),
        ("術後可能對實驗動物造成之影響", "postop_expected_impact"),
    ]
    for heading, tb in tables:
        for needle, key in heading_map:
            if needle in heading and key not in surgery:
                surgery[key] = clean(table_text(tb))

    _, tb = find_table(tables, "藥品名稱", "投與途徑")
    if tb is not None:
        drugs = []
        for r in tb.rows[1:]:
            cells = row_cells(r)
            if len(cells) < 5 or not clean(cells[0]):
                continue
            drugs.append({
                "name": clean(cells[0]), "dose": clean(cells[1]),
                "route": clean(cells[2]), "frequency": clean(cells[3]),
                "purpose": clean(cells[4]),
            })
        if drugs:
            surgery["drugs"] = drugs
    return surgery


def extract_guidelines(tables):
    for heading, tb in tables:
        blob = table_text(tb)
        if "AGRICOLA" in blob:
            codes = sorted(set(
                m.group(1) for m in
                re.finditer(r"([A-L])\.\s*" + CHK, blob)
            ))
            codes2 = sorted(set(
                m.group(1) for m in
                re.finditer(r"([A-L])\.\s*\t*" + CHK, blob)
            ))
            got = sorted(set(codes) | set(codes2))
            return {"databases": got} if got else {}
    return {}


def extract_raw_sections(tables):
    out = {}
    for heading, tb in tables:
        if len(tb.rows) == 1 and len(tb.columns) == 1:
            txt = clean(table_text(tb))
            if txt and heading:
                # F 版存在**完全同名**的標題（例：「動物是否需要特殊照護」出現兩次，
                # 一段是特殊照護條件說明、一段是單獨飼養科學理由）。直接以標題當 key
                # 會讓後者覆蓋前者而靜默掉一整節原文——PIG-115014 實際就少了一節
                # （raw 23 vs 其他案 24）。同名時加序號後綴保住每一節。
                # 註：加長截斷長度無用，兩個標題連全文都相同。
                key = heading[:30]
                if key in out and out[key] != txt:
                    n = 2
                    while "%s #%d" % (key, n) in out:
                        n += 1
                    key = "%s #%d" % (key, n)
                out[key] = txt
    return out


def extract(path):
    doc = Document(path)
    tables = labelled_tables(doc)
    wc = {}
    basic = extract_basic(tables)
    if basic:
        wc["basic"] = basic
    animals = extract_animals(tables)
    if animals:
        wc["animals"] = animals
    personnel = extract_personnel(tables)
    if personnel:
        wc["personnel"] = personnel
    purpose = extract_purpose(tables)
    if purpose:
        wc["purpose"] = purpose
    design = extract_design(tables)
    if design:
        wc["design"] = design
    items = extract_items(tables)
    if items:
        wc["items"] = items
    surgery = extract_surgery(tables)
    if surgery:
        wc["surgery"] = surgery
    guidelines = extract_guidelines(tables)
    if guidelines:
        wc["guidelines"] = guidelines
    raw = extract_raw_sections(tables)
    if raw:
        wc["_raw_sections"] = raw
    return wc


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("docx", nargs="+")
    ap.add_argument("--iacuc", nargs="+", required=True)
    ap.add_argument("-o", "--out", required=True)
    args = ap.parse_args()
    if len(args.docx) != len(args.iacuc):
        sys.exit("docx 與 --iacuc 數量需相同")
    out = {}
    for path, iacuc in zip(args.docx, args.iacuc):
        wc = extract(path)
        out[iacuc] = wc
        print("%s  basic=%d animals=%d personnel=%d design=%d surgery=%d raw=%d"
              % (iacuc, len(wc.get("basic", {})),
                 len(wc.get("animals", {}).get("animals", [])),
                 len(wc.get("personnel", [])), len(wc.get("design", {})),
                 len(wc.get("surgery", {})), len(wc.get("_raw_sections", {}))))
    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=1)
    print("wrote", args.out)


if __name__ == "__main__":
    main()

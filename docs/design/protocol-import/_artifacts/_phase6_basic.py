# -*- coding: utf-8 -*-
"""階段6：補抽計畫書 Section 1（研究資料 / basic）的細節欄位。
之前 _phase4 只抽了 pi.name/is_glp/sponsor.name/project_type/category，漏掉
PI 聯絡資料、委託單位聯絡人、試驗機構、經費來源、起訖日。本工具 label-driven +
group 追蹤解析申請表 basic 表，產出：
  protocol-content-enrich-basic.json  → 餵 enrich_imported_protocols（deep_merge working_content）
  protocol-basic-dates.json           → start/end 日期（另以 SQL 更新 protocols 欄）
只新增缺欄（pi.phone/email/address、sponsor.contact_*、facility.title、housing_location、
funding_sources/funding_other），不動既有 pi.name/sponsor.name/is_glp/project_type/category。純讀取。"""
import os, re, json, unicodedata
import docx

BASE = r'C:\Users\admin\Downloads\計劃書匯入'
OUT_BASIC = r'C:\System Coding\ipig_system\docs\design\protocol-content-enrich-basic.json'
OUT_DATES = r'C:\System Coding\ipig_system\docs\design\protocol-basic-dates.json'

# 27 筆 import_pending（115010 已 finalize 排除），iacuc 末三碼前綴用於找資料夾。
PIGS = [
    'PIG-109032', 'PIG-110005', 'PIG-113002', 'PIG-113003', 'PIG-114003', 'PIG-114004',
    'PIG-114005', 'PIG-114006', 'PIG-114009', 'PIG-114010', 'PIG-114016', 'PIG-114017',
    'PIG-114019', 'PIG-114022', 'PIG-114023', 'PIG-114025', 'PIG-115001', 'PIG-115002',
    'PIG-115003', 'PIG-115005', 'PIG-115006', 'PIG-115007', 'PIG-115008', 'PIG-115009',
    'PIG-115011', 'PIG-115012', 'PIG-115013',
]

PTYPE = {1: '1_basic_research', 2: '2_applied_research', 3: '3_pre_market_testing',
         4: '4_educational', 5: '5_biologics_manufacturing', 6: '6_other'}
PCAT = {1: '1_medical', 2: '2_agricultural', 3: '3_drugs_vaccines', 4: '4_supplements',
        5: '5_food', 6: '6_toxics_chemicals', 7: '7_medical_materials', 8: '8_pesticide',
        9: '9_animal_drugs_vaccines', 10: '10_animal_supplements_feed', 11: '11_cosmetics',
        12: '12_other'}
FUNDING = {1: 'moa', 2: 'mohw', 3: 'nstc', 4: 'moe', 5: 'env', 6: 'other'}
SELECTED = set('■▇▓☑✓✔')   # 已勾選標記


def nf(s):
    return unicodedata.normalize('NFKC', s or '').strip()


def find_folder(pig):
    yd = 'PIG-' + pig.split('-')[1][:3]
    yp = os.path.join(BASE, yd)
    if not os.path.isdir(yp):
        return None
    for d in os.listdir(yp):
        if d.startswith(pig) and os.path.isdir(os.path.join(yp, d)):
            return os.path.join(yp, d)
    return None


def latest_application(fp):
    """1-申請表 下最新一份 .docx（依檔名日期數字）。"""
    cands = []
    for root, _, fz in os.walk(fp):
        if '申請表' not in root:
            continue
        for f in fz:
            if f.startswith('~$') or not f.lower().endswith('.docx'):
                continue
            ds = re.findall(r'\d{6,8}', f)            # 20260610 / _0610 等
            key = max(ds) if ds else '0'
            cands.append((key, os.path.join(root, f)))
    if not cands:
        # 退而求其次：整個資料夾找「計畫書」docx
        for root, _, fz in os.walk(fp):
            for f in fz:
                if f.startswith('~$') or not f.lower().endswith('.docx'):
                    continue
                if '計畫書' in f or '計劃書' in f:
                    ds = re.findall(r'\d{6,8}', f)
                    cands.append((max(ds) if ds else '0', os.path.join(root, f)))
    cands.sort()
    return cands[-1][1] if cands else None


def row_cells(row):
    cells = [nf(c.text.replace('\n', ' ')) for c in row.cells]
    out = []
    for c in cells:
        if not out or out[-1] != c:
            out.append(c)
    return out


NA_SET = {'', 'n/a', 'na', 'n.a.', '-', '–', '—', '無', '略'}


def clean(v):
    """N/A / 無 / 略 等視為空。"""
    return '' if (v or '').strip().lower() in NA_SET else (v or '').strip()


def put(d, k, v):
    """first-wins：同欄位只填一次，且跳過 N/A/空（避免後續 N/A 列覆蓋正確值）。"""
    v = clean(v)
    if v and k not in d:
        d[k] = v


def first_value(cells):
    """label 後第一個非空欄。"""
    for c in cells[1:]:
        if c:
            return c
    return ''


import calendar


def _clamp(y, mo, d):
    """消毒非法日：月份越界夾到 1-12、日越界夾到當月最大日（容忍表單筆誤如 4/31）。"""
    mo = min(max(mo, 1), 12)
    d = min(max(d, 1), calendar.monthrange(y, mo)[1])
    return '%04d-%02d-%02d' % (y, mo, d)


def parse_dates(val):
    """'年 月 日 至 2028 年 6 月 30 日' → (start, end)。空段回 None。"""
    parts = re.split(r'至|~|－|-(?=\s*\d{2,4}\s*年)', val, maxsplit=1)
    def one(seg):
        m = re.search(r'(\d{2,4})\s*年\s*(\d{1,2})\s*月\s*(\d{1,2})', seg)
        if not m:
            m = re.search(r'(\d{4})\D{1,2}(\d{1,2})\D{1,2}(\d{1,2})', seg)
        if m:
            y, mo, d = int(m.group(1)), int(m.group(2)), int(m.group(3))
            if y < 200:                                # 民國
                y += 1911
            return _clamp(y, mo, d)
        return None
    start = one(parts[0]) if parts else None
    end = one(parts[1]) if len(parts) > 1 else None
    return start, end


UNCHECKED = '□☐'   # 未勾選的空框


def parse_checkbox(val, mapping):
    """兩種慣例混用：(a) 新表 ■=選/□=未選；(b) 舊表刪框、裸數字=選/□數字=未選。
    規則：數字緊鄰前一個非空白字元若是空框(□)則未選，否則視為已選。"""
    keys, other_text = [], None
    for m in re.finditer(r'(^|[^\s])\s*(\d{1,2})\s*[\.、]', val):
        mark, num = m.group(1), int(m.group(2))
        if num not in mapping:
            continue
        if mark and mark in UNCHECKED:
            continue
        keys.append(mapping[num])
    return keys, other_text


def extract(pig):
    fp = find_folder(pig)
    if not fp:
        return None, None, 'no folder'
    path = latest_application(fp)
    if not path:
        return None, None, 'no application docx'
    try:
        doc = docx.Document(path)
    except Exception as e:  # noqa: BLE001
        return None, None, 'docx error: %s' % e

    pi, sponsor, facility = {}, {}, {}
    housing = None
    funding, funding_other = [], None
    ptype, pcat = [], []
    start = end = None
    group = None

    for t in doc.tables:
        for row in t.rows:
            cells = row_cells(row)
            if not cells:
                continue
            label = cells[0]
            val = first_value(cells)
            low = label.lower()

            # group 切換（PI 區塊跨版本標籤：計畫主持人(PI)/研究主持人/試驗主持人）
            if '計畫主持人' in label or '研究主持人' in label or '試驗主持人' in label:
                group = 'pi'
            elif '委託單位名稱' in label or '試驗單位名稱' in label or ('試驗單位' in label and 'name' in low):
                group = 'sponsor'
                put(sponsor, 'name', val)
            elif '專案主持人' in label:
                group = 'sd'
            elif '試驗機構' in label and '名稱' in label:
                group = 'facility'
                put(facility, 'title', val)
                continue
            elif '試驗機構及動物飼養' in label:
                group = 'facility'

            # 欄位擷取（依 group；first-wins + 跳過 N/A）
            if ('電話' in label or 'phone' in low) and val:
                if group == 'pi':
                    put(pi, 'phone', val)
                elif group == 'sponsor':
                    put(sponsor, 'contact_phone', val)
            elif ('信箱' in label or 'mail' in low or 'e-mail' in low) and val:
                if group == 'pi':
                    put(pi, 'email', val)
                elif group == 'sponsor':
                    put(sponsor, 'contact_email', val)
            elif ('地址' in label or 'address' in low or 'adress' in low) and val:
                if group == 'pi':
                    put(pi, 'address', val)
                elif group == 'facility' and housing is None:
                    housing = clean(val) or None
            elif ('聯絡人' in label or '研究委託者' in label) and val and group == 'sponsor':
                put(sponsor, 'contact_person', val)
            elif ('試驗預計起始' in label or '試驗時程' in label or 'initiation' in low
                  or '起始日' in label) and val:
                s, e = parse_dates(val)
                start = start or s
                end = end or e

            # 類型 / 種類 / 經費（checkbox 行）
            if '類型' in label and '物質' not in label and '技術' not in label:
                k, _ = parse_checkbox(val, PTYPE)
                if k:
                    ptype = k
            elif '種類' in label:
                k, _ = parse_checkbox(val, PCAT)
                if k:
                    pcat = k
            elif '經費來源' in label:
                k, _ = parse_checkbox(val, FUNDING)
                if k:
                    funding = k

    # 組 enrich overlay（只放新增缺欄；既有 name/is_glp/type/category 不動）
    basic = {}
    if pi:
        basic['pi'] = pi
    sp = {kk: vv for kk, vv in sponsor.items() if kk != 'name'}   # 不覆蓋既有 name
    if sp:
        basic['sponsor'] = sp
    if facility:
        basic['facility'] = facility
    if housing:
        basic['housing_location'] = housing
    if funding:
        basic['funding_sources'] = funding
    overlay = {'basic': basic} if basic else None
    dates = {}
    if start:
        dates['start'] = start
    if end:
        dates['end'] = end
    diag = 'pi:%d sponsor:%d facility:%s housing:%s funding:%s type:%s cat:%s dates:%s/%s' % (
        len(pi), len(sp), 'Y' if facility else '-', 'Y' if housing else '-',
        ','.join(funding) or '-', ','.join(ptype) or '-', ','.join(pcat) or '-',
        start or '-', end or '-')
    return overlay, (dates or None), diag


if __name__ == '__main__':
    import sys
    args = sys.argv[1:]
    pigs = PIGS if (not args or args == ['--all']) else args
    write = (not args or args == ['--all'])
    enrich, datesmap = {}, {}
    for pig in pigs:
        overlay, dates, diag = extract(pig)
        if overlay is None and dates is None:
            print('SKIP %-12s | %s' % (pig, diag))
            continue
        if overlay:
            enrich[pig] = overlay
        if dates:
            datesmap[pig] = dates
        print('OK   %-12s | %s' % (pig, diag))
    if write:
        json.dump(enrich, open(OUT_BASIC, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
        json.dump(datesmap, open(OUT_DATES, 'w', encoding='utf-8'), ensure_ascii=False, indent=1)
        print('\n寫出 basic %d 筆 → %s' % (len(enrich), OUT_BASIC))
        print('寫出 dates %d 筆 → %s' % (len(datesmap), OUT_DATES))
    else:
        print('\n（樣本模式，未寫檔）')

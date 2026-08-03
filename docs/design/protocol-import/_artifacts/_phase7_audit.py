# -*- coding: utf-8 -*-
"""階段7 稽核：對照 form-fields-spec 必填/重點欄位，掃 prod working_content（_audit_wc.json），
找出仍缺/空的欄位，彙總「哪些 protocol 缺哪些欄」。供判斷是否需回原始表單補抽。純讀取。"""
import json

WC = json.load(open(r'docs/design/_audit_wc.json', encoding='utf-8'))


def get(d, path):
    cur = d
    for p in path.split('.'):
        if isinstance(cur, dict) and p in cur:
            cur = cur[p]
        else:
            return None
    return cur


def empty(v):
    if v is None:
        return True
    if isinstance(v, str):
        return v.strip() == '' or v.strip().lower() in ('n/a', 'na', '-', '無', '略')
    if isinstance(v, (list, dict)):
        return len(v) == 0
    return False


# (section, 欄位標籤, path, 檢查型態)  type: 'val'=非空值 / 'list'=非空陣列 / 'set'=需已選(非 null)
CHECKS = [
    ('S2', '2.1 研究重要性', 'purpose.significance', 'val'),
    ('S2', '2.2.1 必要性', 'purpose.replacement.rationale', 'val'),
    ('S2', '2.2.2 替代搜尋平台', 'purpose.replacement.alt_search.platforms', 'list'),
    ('S2', '2.2.2 關鍵字', 'purpose.replacement.alt_search.keywords', 'val'),
    ('S2', '2.2.2 結論', 'purpose.replacement.alt_search.conclusion', 'val'),
    ('S2', '2.2.3 重複性狀態', 'purpose.duplicate.status', 'val'),
    ('S2', '2.3 實驗設計', 'purpose.reduction.design', 'val'),
    ('S2', '2.4 精緻化', 'purpose.refinement_description', 'val'),
    ('S3', '3.0 是否投予試驗物質', 'items.use_test_item', 'set'),
    ('S4', '4.1.1 是否麻醉', 'design.anesthesia.is_under_anesthesia', 'set'),
    ('S4', '4.1.2 流程', 'design.procedures', 'val'),
    ('S4', '4.1.3 疼痛等級', 'design.pain.category', 'val'),
    ('S4', '4.1.4 痛苦症狀', 'design.pain.distress_signs', 'list'),
    ('S4', '4.1.5 緩解措施', 'design.pain.relief_measures', 'list'),
    ('S4', '4.1.7 實驗終點', 'design.endpoints.experimental_endpoint', 'val'),
    ('S4', '4.1.7 人道終點', 'design.endpoints.humane_endpoint', 'val'),
    ('S4', '4.1.8 最終處置', 'design.final_handling.method', 'val'),
    ('S4', '4.2 屍體處理', 'design.carcass_disposal.method', 'val'),
    ('S5', '5.1 法源/文獻', 'guidelines.content', 'val'),
    ('S7', '7 動物清單', 'animals.animals', 'list'),
    ('S8', '8 人員清單', 'personnel', 'list'),
]

# 手術 gating：needsSurgeryPlan
SURG_CHECKS = [
    ('S6', '6.2 術前準備', 'surgery.preop_preparation', 'val'),
    ('S6', '6.4 手術內容', 'surgery.surgery_description', 'val'),
    ('S6', '6.5 術中監控', 'surgery.monitoring', 'val'),
    ('S6', '6.8 術後照護', 'surgery.postop_care', 'val'),
    ('S6', '6.10 手術用藥', 'surgery.drugs', 'list'),
]


def needs_surgery(wc):
    a = get(wc, 'design.anesthesia')
    if not isinstance(a, dict):
        return False
    return a.get('is_under_anesthesia') is True and \
        a.get('anesthesia_type') in ('survival_surgery', 'non_survival_surgery')


def check_one(wc):
    miss = []
    for sec, label, path, typ in CHECKS:
        v = get(wc, path)
        if typ == 'set':
            if v is None:
                miss.append((sec, label, path))
        elif empty(v):
            miss.append((sec, label, path))
    if needs_surgery(wc):
        for sec, label, path, typ in SURG_CHECKS:
            v = get(wc, path)
            if empty(v):
                miss.append((sec, label, path))
    return miss


if __name__ == '__main__':
    from collections import Counter
    agg = Counter()
    per = {}
    for iacuc in sorted(WC):
        miss = check_one(WC[iacuc])
        per[iacuc] = miss
        for sec, label, path in miss:
            agg[(sec, label)] += 1

    print('=== 每筆缺漏（prod working_content 仍缺/空的重點欄）===')
    for iacuc in sorted(per):
        m = per[iacuc]
        if not m:
            print('  %-12s ✓ 完整' % iacuc)
        else:
            print('  %-12s 缺 %d：%s' % (iacuc, len(m), '、'.join(l for _, l, _ in m)))

    print('\n=== 彙總：各欄位缺漏筆數（共 27 筆）===')
    for (sec, label), n in sorted(agg.items(), key=lambda x: -x[1]):
        print('  [%s] %-20s 缺 %d 筆' % (sec, label, n))

# -*- coding: utf-8 -*-
"""審查意見回覆表 docx → backfill_import_reviews 用 payload。

重建自已遺失的 `_phase5_reviews.py`。依**表格結構**辨識三種區塊（不靠段落標題，
因各案標題文字不一致）：
  * 執行秘書：3 欄（項次 / 審查意見 / 申請人回覆）
  * 獸醫師  ：4 欄（審查項目 / 符合(v) / 審查意見 / 申請人回覆），末列為簽名＋日期
  * 委員    ：5 欄（項次 / 一審意見 / 意見回覆 / 二審意見 / 意見回覆）→ 依既有慣例 park

合併策略（與既有 27 筆一致）：
  * 執秘＝掃該案**所有輪次**檔案，依意見內容去重合併，同一條取最長的回覆。
  * 獸醫＝取**簽名日期最大**那一份的完整項目（含全 V 者），保留 V / X / - compliance。

⚠️ record_import_reviews 是「全量取代」：日後補委員時務必連執秘＋獸醫一起帶。

依賴：`python-docx`（未列入 pyproject.toml——本檔為一次性補登工具，非專案
執行期相依）。執行前先 `pip install python-docx`。

Usage:
    python _phase5f_reviews.py --root "<PIG-115 資料夾>" \
        --case PIG-115014 --case PIG-115015 -o out.json
"""
import argparse
import glob
import json
import os
import re

from docx import Document

SECRETARY_ID = "4c581960-10e2-4733-8da4-a08c93d9933f"   # 陳怡均（IACUC_STAFF）
# ⚠️ 葉沂萱（VET）——此歸屬沿用前一批 27 筆的慣例，**無文件依據**：回覆表獸醫簽名欄
# 在 docx 內為空白，且無已簽名 PDF。新證據指向吳建男（輪值表每列都有、每案審核結果
# 都蓋「獸醫師吳建男」印）。重跑前先確認 TODO §R85-2 是否已裁定。
VET_ID = "3b527ae2-1bd8-4bf2-97cb-8205de12798b"

DATE_RE = re.compile(r"(20\d{2})\s*[./年\-]\s*(\d{1,2})\s*[./月\-]\s*(\d{1,2})")


def cells_of(row):
    out, last = [], None
    for c in row.cells:
        if c._tc is last:
            continue
        last = c._tc
        out.append(c.text.strip())
    return out


def norm(s):
    return re.sub(r"\s+", "", s or "")


def classify(tb):
    hdr = " ".join(cells_of(tb.rows[0]))
    ncol = len(cells_of(tb.rows[0]))
    if "審查項目" in hdr and "符合" in hdr:
        return "vet"
    if "一審意見" in hdr:
        return "committee"
    if "審查意見" in hdr and "申請人回覆" in hdr and ncol <= 3:
        return "secretary"
    return None


def parse_secretary(tb):
    out = []
    for r in tb.rows[1:]:
        c = cells_of(r)
        if len(c) < 2:
            continue
        # 欄位可能是 [項次, 審查意見, 申請人回覆] 或省略項次
        if len(c) >= 3:
            section, content, reply = c[0], c[1], c[2]
        else:
            section, content, reply = "", c[0], c[1]
        if not norm(content):
            continue
        out.append({
            "reviewer_id": SECRETARY_ID,
            "reviewer_name": None,
            "content": content,
            "reply": reply or None,
            "section_no": section or None,
        })
    return out


def parse_vet(tb):
    items, signed_at = [], None
    for r in tb.rows[1:]:
        c = cells_of(r)
        if not c:
            continue
        joined = " ".join(c)
        if "獸醫師簽名" in joined:
            m = DATE_RE.search(joined)
            if m:
                # ImportVetReview.signed_at 是 DateTime<Utc> → 需 RFC3339（與既有 payload 同格式）
                signed_at = "%04d-%02d-%02dT00:00:00Z" % (
                    int(m.group(1)), int(m.group(2)), int(m.group(3)))
            continue
        if len(c) < 2 or not norm(c[0]):
            continue
        # VetReviewItem.compliance 是必填 String（非 Option）→ 原件空白時給 ""，不可給 null
        compliance = (c[1] or "").strip().upper()
        compliance = {"V": "V", "X": "X", "－": "-", "-": "-"}.get(compliance, compliance)
        items.append({
            "item_name": c[0],
            "compliance": compliance,
            "comment": (c[2] or None) if len(c) > 2 else None,
            "pi_reply": (c[3] or None) if len(c) > 3 else None,
        })
    return items, signed_at


def harvest_case(case_dir):
    files = [f for f in sorted(glob.glob(os.path.join(case_dir, "3-審查意見回覆表", "*.docx")))
             if not os.path.basename(f).startswith("~$")]
    sec_map = {}          # norm(content) -> comment dict（同條取最長 reply）
    best_vet = None       # (signed_at, items, filename)
    committee_seen = 0

    for f in files:
        try:
            doc = Document(f)
        except Exception as e:                      # noqa: BLE001
            print("  !! 讀取失敗 %s: %s" % (os.path.basename(f), e))
            continue
        for tb in doc.tables:
            kind = classify(tb)
            if kind == "secretary":
                for c in parse_secretary(tb):
                    k = norm(c["content"])
                    prev = sec_map.get(k)
                    if prev is None or len(c["reply"] or "") > len(prev["reply"] or ""):
                        sec_map[k] = c
            elif kind == "vet":
                items, signed = parse_vet(tb)
                if not items:
                    continue
                key = (signed or "", len(items))
                if best_vet is None or key > best_vet[0]:
                    best_vet = (key, items, signed, os.path.basename(f))
            elif kind == "committee":
                for r in tb.rows[1:]:
                    c = cells_of(r)
                    if len(c) > 1 and norm(c[1]):
                        committee_seen += 1

    payload = {
        "secretary_comments": list(sec_map.values()),
        "committee_reviewers": [],     # 依既有慣例 park（委員帳號未進系統）
        "vet_review": None,
    }
    if best_vet:
        payload["vet_review"] = {
            "vet_id": VET_ID,
            "vet_name": None,
            "decision": None,
            "decision_remark": None,
            "items": best_vet[1],
            "signed_at": best_vet[2],
        }
    return payload, len(files), committee_seen, (best_vet[3] if best_vet else None)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", required=True)
    ap.add_argument("--case", action="append", required=True)
    ap.add_argument("-o", "--out", required=True)
    args = ap.parse_args()

    out = {}
    for case in args.case:
        # 前綴比對可能命中多個資料夾（例：改名/留舊版），glob 順序不保證穩定，
        # 排序後取第一個並示警，避免不同次執行悄悄抓到不同資料夾。
        dirs = sorted(glob.glob(os.path.join(args.root, case + "*")))
        if not dirs:
            print("%s: 找不到資料夾" % case)
            continue
        if len(dirs) > 1:
            print("%s: !! 命中多個資料夾 %s → 取排序後第一個，請確認是否正確"
                  % (case, [os.path.basename(d) for d in dirs]))
        payload, nfiles, ncom, vetfile = harvest_case(dirs[0])
        out[case] = payload
        vet_n = len(payload["vet_review"]["items"]) if payload["vet_review"] else 0
        vet_d = payload["vet_review"]["signed_at"] if payload["vet_review"] else None
        print("%s | 回覆表 %d 份 | 執秘 %d 條 | 獸醫 %d 項 (簽名日 %s, 取自 %s) | 委員 %d 條(park)"
              % (case, nfiles, len(payload["secretary_comments"]), vet_n, vet_d,
                 vetfile, ncom))
    with open(args.out, "w", encoding="utf-8") as f:
        json.dump(out, f, ensure_ascii=False, indent=1)
    print("wrote", args.out)


if __name__ == "__main__":
    main()

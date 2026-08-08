"""一次性驗證腳本：巡場報告 PDF 的一頁化 + 圖說兩行（2026-08-07）。

不是 runtime 依賴，也不進 CI。用途是在改 `templates/vet_patrol_report.html`
（字級/行高/padding 階梯、簽名區分頁行為、圖說結構）之後，對著真的 Chromium
render 出來的 PDF 驗證頁數與內容，而不是靠讀 CSS 推論。

用法：先起一個掛上修改後檔案的拋棄式容器，再指向它：

    rtk docker run --rm -d --name ipig-print-pdf-verify -p 127.0.0.1:9211:9200 \
      -v .../main.py:/app/main.py:ro -v .../templates:/app/templates:ro \
      -v .../adapters:/app/adapters:ro -v .../schemas:/app/schemas:ro \
      ipig_system-print-pdf
    python _tools/verify_vet_patrol_report_layout.py http://127.0.0.1:9211

驗證完記得收掉：`rtk docker stop ipig-print-pdf-verify`（帶 --rm，stop 即移除）。
"""

from __future__ import annotations

import base64
import io
import json
import sys
import urllib.request

from pypdf import PdfReader

ENDPOINT = "/render-vet-patrol-report/from-report-data"

# 1x1 紅點 PNG（內容不重要，只要是合法影像讓 adapter 的 Pillow 壓縮走得過去）
_DOT = base64.b64decode(
    "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg=="
)
DOT_URL = "data:image/png;base64," + base64.b64encode(_DOT).decode()


def cat(label: str, entries: list[tuple[str, str, str]]) -> dict:
    return {
        "label": label,
        "observation": "",
        "suggestion": "",
        "follow_up": "",
        "entries": [{"observation": o, "suggestion": s, "follow_up": f} for o, s, f in entries],
        "photos": [],
    }


def payload(pig_entries: list[tuple[str, str, str]], groups: list[dict] | None = None) -> dict:
    return {
        "vet_name": "程景章",
        "companion": "王永發",
        "patrol_date": "2026-07-20",
        "patrol_date_display": "2026年07月20日",
        "categories": [
            cat("豬隻狀況", pig_entries),
            cat("防疫及消毒計畫", [("全場定期清洗消毒（每週一次，週三）。分娩舍消毒噴霧罐已補。", "", "")]),
            cat("病歷紀錄", []),
            cat(
                "其他",
                [
                    (
                        "1. 09:50 A棟溫度27.7°C，濕度73%，前半無風、悶，風扇未啟動。"
                        "B棟溫度28.2°C，濕度77%，檢疫舍溫度27.9°C，濕度83%。\n"
                        "2. 檢疫舍羊飼料槽高度已改善，有放置鹽磚，飲水槽乾淨，原蹄甲異常已修正。",
                        "1. 檢疫舍豬隻精神食慾尚可(有殘飼)，無其他明顯異常。\n"
                        "2. 如有鼻分泌液偏多，以長效 penicillin 治療。",
                        "羊隻部分維持觀察，如有鼻分泌過多，給予Penicillin及Meloxicam IM SID 7天",
                    )
                ],
            ),
        ],
        "photos": [],
        "photo_groups": groups or [],
    }


def render(base: str, body: dict) -> bytes:
    req = urllib.request.Request(
        base + ENDPOINT,
        data=json.dumps(body).encode(),
        headers={"Content-Type": "application/json"},
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=120) as r:
        return r.read()


def pages(pdf: bytes) -> list[str]:
    return [p.extract_text() or "" for p in PdfReader(io.BytesIO(pdf)).pages]


SIGN_MARK = "巡場獸醫師"


def photo_pages(pdf: bytes) -> list[str]:
    """只取照片頁的文字。

    照片區塊在範本中排在簽名區之後、且每組都帶 `page-break-before: always`，
    所以「簽名頁之後的頁」就是照片頁。用來把圖說的計數與主表格的內文隔開
    （耳號字串在兩邊都會出現）。
    """
    txt = pages(pdf)
    sign_idx = next((i for i, t in enumerate(txt) if SIGN_MARK in t), -1)
    return txt[sign_idx + 1 :] if sign_idx >= 0 else []


def check(name: str, pdf: bytes, want_pages: int | None, want_sign_page_has_table: bool) -> bool:
    txt = pages(pdf)
    n = len(txt)
    sign_idx = next((i for i, t in enumerate(txt) if SIGN_MARK in t), -1)
    ok = True
    detail = [f"pages={n}", f"sign_on_page={sign_idx + 1}"]

    if want_pages is not None and n != want_pages:
        ok = False
        detail.append(f"EXPECTED pages={want_pages}")
    if sign_idx < 0:
        ok = False
        detail.append("SIGN BLOCK MISSING")
    elif want_sign_page_has_table:
        # 簽名所在頁必須還有表格內容，否則就是「簽名獨佔一頁」的老問題
        page_txt = txt[sign_idx]
        has_table = any(k in page_txt for k in ("觀察內容", "豬隻狀況", "其他", "維持觀察"))
        detail.append(f"sign_page_has_table={has_table}")
        if not has_table:
            ok = False
            detail.append("SIGN ALONE ON ITS OWN PAGE")

    print(("PASS " if ok else "FAIL ") + name + " :: " + ", ".join(detail))
    return ok


def main() -> int:
    base = sys.argv[1] if len(sys.argv) > 1 else "http://127.0.0.1:9211"
    results = []

    # A. 短報告（1 條目）——本來就塞得下，不應被壓縮，且必須 1 頁
    results.append(
        check("A 短報告", render(base, payload([("#592 精神採食良好，雙眼無明顯異常。", "維持觀察。", "維持觀察")])), 1, True)
    )

    # 依使用者 2026-07-20 那份截圖重建的內容。注意：**這組在修正前也是 1 頁**——
    # 截圖的第 1 頁上緣被裁掉，實際條目比看得到的多，所以它不是有效的迴歸案例，
    # 只當「不要把原本正常的報告弄壞」的守門用。真正的失效樣態見 B。
    real = [
        ("#215 無皮膚紅疹，精神尚可。", "維持觀察。", "維持觀察"),
        ("#282、#283、#284精神食慾正常，肩胛植入電刺激器之傷口對合良好，無明顯發炎。", "維持正常照護。", "維持照護"),
        ("#674、#691、#818 右頸注射部位無明顯異常，#691精神食慾尚可，輕微腹式呼吸。", "維持觀察", "維持觀察"),
        ("#592 精神採食良好，雙眼無明顯異常。", "維持觀察。", "維持觀察"),
    ]
    results.append(check("A2 截圖重建（修正前後皆應 1 頁）", render(base, payload(real)), 1, True))

    # B. 真正的失效樣態：5 條目時表格剛好把簽名區擠過頁緣，
    #    修正前＝2 頁且第 2 頁「只有簽名」，修正後＝1 頁。
    #    （2026-08-07 對照實測：n=4/5/16/17 都會讓對照組出現簽名獨佔一頁。）
    repro = [
        (
            f"#{700 + i} 精神食慾正常，體表無明顯異常，採食量穩定，飲水正常，糞便成形，活動力佳。",
            "維持正常照護。",
            "維持觀察",
        )
        for i in range(5)
    ]
    results.append(check("B 簽名獨佔一頁的重現案例", render(base, payload(repro)), 1, True))

    # C. 超長報告（24 條目）——壓縮到下限仍會跨頁，但簽名不得單獨成頁
    long_entries = [
        (f"#{700 + i} 精神食慾正常，體表無明顯異常，採食量穩定，飲水正常，糞便成形。", "維持正常照護。", "維持觀察")
        for i in range(24)
    ]
    results.append(check("C 超長報告", render(base, payload(long_entries)), None, True))

    # D. 圖說：一張有說明、一張沒填 —— 有填的要印出說明，沒填的只印耳號
    groups = [
        {
            "caption": "#674、#691、#818",
            "description": "右頸注射部位無明顯異常",
            "srcs": [DOT_URL, DOT_URL],
            "photos": [
                {"src": DOT_URL, "caption": "右頸注射部位，無紅腫熱痛"},
                {"src": DOT_URL, "caption": ""},
            ],
        }
    ]
    pdf = render(base, payload(real, groups))
    # 只在**照片頁**範圍內計數：耳號字串也出現在主表格的觀察內容裡，對整份 PDF
    # 數會多算一次。照片頁都帶 page-break-before 且排在簽名區之後，故取簽名頁之後。
    photo_txt = "\n".join(photo_pages(pdf))
    # 用 count 而非 `in`：本次修的 bug 正是「同組每張照片共用同一個圖說」，
    # 只檢查「有出現」的話，範本若把第一張的說明複製到第二張，測試照樣會過
    # （CodeRabbit #44 指出）。故要求說明**恰好一次**、耳號**每張各一次**。
    want_tags = len(groups[0]["photos"])
    desc_n = photo_txt.count("右頸注射部位，無紅腫熱痛")
    tag_n = photo_txt.count("#674、#691、#818")
    ok_d = desc_n == 1 and tag_n == want_tags
    print(
        ("PASS " if ok_d else "FAIL ")
        + f"D 圖說帶說明 :: desc={desc_n}(want 1), tags={tag_n}(want {want_tags})"
    )
    results.append(ok_d)

    # E. 舊 payload（只有 srcs、沒有 photos）仍須正常出圖說＝耳號
    old_groups = [{"caption": "#275", "description": "", "srcs": [DOT_URL]}]
    pdf = render(base, payload(real, old_groups))
    txt = "\n".join(pages(pdf))
    ok_e = "#275" in txt
    print(("PASS " if ok_e else "FAIL ") + "E 舊 payload 相容 :: tag_rendered=" + str(ok_e))
    results.append(ok_e)

    print("\n" + ("ALL PASS" if all(results) else "SOME FAILED"))
    return 0 if all(results) else 1


if __name__ == "__main__":
    raise SystemExit(main())

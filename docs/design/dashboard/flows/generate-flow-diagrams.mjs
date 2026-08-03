// 產生儀表板 4 張流程圖（SVG）。純手繪 SVG，無外部相依，任何瀏覽器/檢視器可開。
import { writeFileSync } from 'node:fs'

const FONT = `-apple-system,"Noto Sans CJK TC","Microsoft JhengHei",sans-serif`
const C = {
  start: { fill: '#dcfce7', stroke: '#16a34a' },
  proc:  { fill: '#e0f2fe', stroke: '#0284c7' },
  api:   { fill: '#f3e8ff', stroke: '#9333ea' },
  dec:   { fill: '#fef9c3', stroke: '#ca8a04' },
  end:   { fill: '#fee2e2', stroke: '#dc2626' },
}

function esc(s) { return s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;') }

function box(x, y, w, h, lines, kind = 'proc') {
  const { fill, stroke } = C[kind]
  const cx = x + w / 2
  const ls = Array.isArray(lines) ? lines : [lines]
  const lh = 19
  const startY = y + h / 2 - ((ls.length - 1) * lh) / 2 + 5
  const txt = ls.map((l, i) =>
    `<text x="${cx}" y="${startY + i * lh}" text-anchor="middle" font-size="14" font-family='${FONT}' fill="#0f172a">${esc(l)}</text>`
  ).join('')
  return `<rect x="${x}" y="${y}" width="${w}" height="${h}" rx="9" fill="${fill}" stroke="${stroke}" stroke-width="1.6"/>${txt}`
}

function diamond(cx, cy, hw, hh, text) {
  const { fill, stroke } = C.dec
  const pts = `${cx},${cy - hh} ${cx + hw},${cy} ${cx},${cy + hh} ${cx - hw},${cy}`
  return `<polygon points="${pts}" fill="${fill}" stroke="${stroke}" stroke-width="1.6"/>` +
    `<text x="${cx}" y="${cy + 5}" text-anchor="middle" font-size="14" font-family='${FONT}' fill="#0f172a">${esc(text)}</text>`
}

function arrow(x1, y1, x2, y2, label) {
  let s = `<path d="M ${x1} ${y1} L ${x2} ${y2}" stroke="#475569" stroke-width="1.6" fill="none" marker-end="url(#a)"/>`
  if (label) {
    const mx = (x1 + x2) / 2, my = (y1 + y2) / 2
    s += `<rect x="${mx - label.length * 4 - 6}" y="${my - 11}" width="${label.length * 8 + 12}" height="20" rx="4" fill="#fff" stroke="#cbd5e1"/>` +
         `<text x="${mx}" y="${my + 3}" text-anchor="middle" font-size="12" font-family='${FONT}' fill="#334155">${esc(label)}</text>`
  }
  return s
}

function svg(w, h, title, body) {
  return `<?xml version="1.0" encoding="UTF-8"?>
<svg xmlns="http://www.w3.org/2000/svg" width="${w}" height="${h}" viewBox="0 0 ${w} ${h}" font-family='${FONT}'>
<defs><marker id="a" markerWidth="10" markerHeight="10" refX="8" refY="3" orient="auto" markerUnits="strokeWidth">
<path d="M0,0 L8,3 L0,6 Z" fill="#475569"/></marker></defs>
<rect width="${w}" height="${h}" fill="#f8fafc"/>
<text x="${w / 2}" y="34" text-anchor="middle" font-size="19" font-weight="700" font-family='${FONT}' fill="#0f172a">${esc(title)}</text>
${body}
</svg>`
}

// ---- 圖 1：載入與排版分流 ----
{
  const W = 780, w = 420, x = (W - w) / 2, h = 50
  let y = 60, b = ''
  const ys = []
  const nodes = [
    ['① 使用者開啟儀表板', 'start'],
    ['GET /me/preferences/dashboard_widgets（取存檔佈局）', 'api'],
    ['合併「預設新增的 widget」→ currentLayout', 'proc'],
    ['權限過濾 isWidgetPermitted → availableWidgets', 'proc'],
    ['過濾 visible≠false → visibleWidgets', 'proc'],
  ]
  for (const [t, k] of nodes) { b += box(x, y, w, h, t, k); ys.push(y); y += 78 }
  // 連線（線性）
  for (let i = 0; i < nodes.length - 1; i++) b += arrow(W / 2, ys[i] + h, W / 2, ys[i + 1])
  // 決策
  const dcy = y + 30
  b += arrow(W / 2, ys[ys.length - 1] + h, W / 2, dcy - 38)
  b += diamond(W / 2, dcy, 95, 40, '螢幕寬度？')
  // 分支
  const by = dcy + 70
  const lb = box(40, by, 320, 64, ['桌機 lg / md / sm', '沿用存檔座標，僅夾寬度'], 'proc')
  const rb = box(420, by, 320, 64, ['手機 xs / xxs', '單欄依重要度堆疊 stackByPriority'], 'proc')
  b += lb + rb
  b += arrow(W / 2 - 60, dcy + 20, 200, by, '桌機')
  b += arrow(W / 2 + 60, dcy + 20, 580, by, '手機')
  // 合併渲染
  const ey = by + 100
  b += box(x, ey, w, h, '渲染 ResponsiveGridLayout（不重疊）', 'end')
  b += arrow(200, by + 64, W / 2, ey)
  b += arrow(580, by + 64, W / 2, ey)
  writeFileSync('docs/design/dashboard/flows/1-載入與排版分流.svg', svg(W, ey + h + 30, '圖 1 · 儀表板載入與排版分流', b))
}

// ---- 圖 2：編輯模式操作（拖曳 + ✕ 隱藏）----
{
  const W = 780, h = 56
  let b = ''
  // 起點
  const topY = 60
  b += box((W - 420) / 2, topY, 420, 50, '① 點「編輯佈局」→ isEditMode = true', 'start')
  // 兩欄
  const colW = 320
  const lx = 40, rx = 420
  const ay = topY + 95
  const A = [
    ['拖曳 / 縮放 widget', 'proc'],
    ['其他 widget 自動讓位', 'proc'],
    ['handleLayoutChange：', 'proc'],
  ]
  const B = [
    ['點 widget 右上角 ✕', 'proc'],
    ['handleHideWidget：', 'proc'],
  ]
  // A 欄
  let ya = ay
  const aYs = []
  const Atext = [
    ['拖曳 / 縮放 widget'],
    ['其他 widget 讓位（preventCollision=false）'],
    ['handleLayoutChange 記錄 lg 座標 → pendingLayout'],
  ]
  for (const t of Atext) { b += box(lx, ya, colW, h, t, 'proc'); aYs.push(ya); ya += 84 }
  // B 欄
  let yb = ay
  const bYs = []
  const Btext = [
    ['點 widget 右上角 ✕'],
    ['handleHideWidget：visible=false（即時消失）'],
  ]
  for (const t of Btext) { b += box(rx, yb, colW, h, t, 'proc'); bYs.push(yb); yb += 84 }
  // fork 線
  b += arrow(W / 2, topY + 50, lx + colW / 2, aYs[0], '拖曳')
  b += arrow(W / 2, topY + 50, rx + colW / 2, bYs[0], '✕ 隱藏')
  for (let i = 0; i < aYs.length - 1; i++) b += arrow(lx + colW / 2, aYs[i] + h, lx + colW / 2, aYs[i + 1])
  for (let i = 0; i < bYs.length - 1; i++) b += arrow(rx + colW / 2, bYs[i] + h, rx + colW / 2, bYs[i + 1])
  // 合併
  const my = Math.max(ya, yb) + 6
  b += box((W - 420) / 2, my, 420, h, 'hasUnsavedChanges = true（畫面即時更新）', 'end')
  b += arrow(lx + colW / 2, aYs[aYs.length - 1] + h, W / 2, my)
  b += arrow(rx + colW / 2, bYs[bYs.length - 1] + h, W / 2, my)
  // 提示下一步
  const ny = my + 84
  b += box((W - 420) / 2, ny, 420, 44, '↓ 下一步：點「儲存佈局」（見圖 3）', 'proc')
  b += arrow(W / 2, my + h, W / 2, ny)
  writeFileSync('docs/design/dashboard/flows/2-編輯模式操作.svg', svg(W, ny + 44 + 30, '圖 2 · 編輯模式：拖曳讓位 + ✕ 隱藏', b))
}

// ---- 圖 3：儲存佈局 ----
{
  const W = 560, w = 380, x = (W - w) / 2, h = 50
  let b = '', y = 60
  b += box(x, y, w, h, '① 點「儲存佈局」', 'start'); const n1 = y; y += 88
  const dcy = y + 30
  b += arrow(W / 2, n1 + h, W / 2, dcy - 38)
  b += diamond(W / 2, dcy, 130, 42, '有未存變更？')
  // yes 分支（右下）
  const yY = dcy + 78
  b += box(x, yY, w, h, 'PUT /me/preferences/dashboard_widgets', 'api')
  b += arrow(W / 2, dcy + 22, W / 2, yY, '是')
  const tY = yY + 84
  b += box(x, tY, w, h, '成功 toast「佈局已儲存」', 'proc')
  b += arrow(W / 2, yY + h, W / 2, tY)
  // 合併：退出編輯
  const eY = tY + 100
  b += box(x, eY, w, h, '退出編輯模式 isEditMode=false', 'end')
  b += arrow(W / 2, tY + h, W / 2, eY)
  // no 分支（左側直接退出）
  b += arrow(W / 2 - 130, dcy, 70, dcy, '否')
  b += `<path d="M 70 ${dcy} L 70 ${eY + h / 2} L ${x} ${eY + h / 2}" stroke="#475569" stroke-width="1.6" fill="none" marker-end="url(#a)"/>`
  writeFileSync('docs/design/dashboard/flows/3-儲存佈局.svg', svg(W, eY + h + 30, '圖 3 · 儲存佈局', b))
}

// ---- 圖 4：重設佈局（自適應最佳化重排）----
{
  const W = 600, w = 480, x = (W - w) / 2, h = 54
  let b = '', y = 60
  const nodes = [
    ['① 點「重設佈局」', 'start'],
    ['取預設佈局 DEFAULT_DASHBOARD_LAYOUT', 'proc'],
    ['權限過濾 isWidgetPermitted（只留此使用者看得到的）', 'proc'],
    ['分成「顯示中」/「隱藏」兩組', 'proc'],
    ['packLayoutCompact(顯示中)：貪婪壓實、保留語意順序', 'proc'],
    ['合併「隱藏」組（保留以便日後還原）', 'proc'],
    ['PUT 儲存 → toast「佈局已重設」', 'end'],
  ]
  const ys = []
  for (const [t, k] of nodes) { b += box(x, y, w, h, t, k); ys.push(y); y += 84 }
  for (let i = 0; i < nodes.length - 1; i++) b += arrow(W / 2, ys[i] + h, W / 2, ys[i + 1])
  writeFileSync('docs/design/dashboard/flows/4-重設佈局重排.svg', svg(W, y + 10, '圖 4 · 重設佈局（自適應最佳化重排）', b))
}

console.log('done')

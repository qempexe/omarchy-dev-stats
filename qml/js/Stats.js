.pragma library

// Everything that comes from outside the shell (account names, hosts, fetch
// results) passes through this file before it reaches QML. Remote error text is
// never shown, only the fixed messages below.

const MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
const WEEKDAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

const PROVIDERS = {
  github: { label: "GitHub", glyph: "\uf09b" },
  gitlab: { label: "GitLab", glyph: "\uf296" },
  forgejo: { label: "Forgejo", glyph: "\uf1d3" }
}

const ERRORS = {
  "no-cli": "The command-line tool for this platform is not installed.",
  "request-failed": "Request failed. Check your login, profile visibility or network.",
  "bad-response": "The platform returned something unexpected.",
  "bad-account": "Invalid account entry.",
  "unsupported": "Day details are only available for GitHub accounts so far."
}

const ISO_DAY = /^\d{4}-\d{2}-\d{2}$/
const MAX_ACCOUNTS = 12

function pad(n) { return n < 10 ? "0" + n : "" + n }
function iso(d) { return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate()) }
function atNoon(d) { return new Date(d.getFullYear(), d.getMonth(), d.getDate(), 12) }
function addDays(d, n) { let r = new Date(d.getTime()); r.setDate(r.getDate() + n); return r }

// Strip control and bidi-override characters and cap the length.
function clean(value, max) {
  let s = String(value === undefined || value === null ? "" : value)
  s = s.replace(/[\u0000-\u001f\u007f-\u009f\u200e\u200f\u202a-\u202e\u2066-\u2069]/g, "")
  return s.length > max ? s.slice(0, max) : s
}

const DEFAULT_COLOR = "#39d353"
const HEX_COLOR = /^#[0-9a-fA-F]{6}$/

// Returns a valid "#rrggbb" color, or the default green.
function validColor(value) {
  return typeof value === "string" && HEX_COLOR.test(value) ? value.toLowerCase() : DEFAULT_COLOR
}

const PRESET_COLORS = [
  { name: "Green", hex: "#39d353" },
  { name: "Blue", hex: "#58a6ff" },
  { name: "Purple", hex: "#bc8cff" },
  { name: "Orange", hex: "#ff6b2c" },
  { name: "Red", hex: "#f85149" },
  { name: "Yellow", hex: "#e3b341" }
]

// Darkens a "#rrggbb" color toward black by t (0 = unchanged, 1 = black).
function shade(hex, t) {
  const n = parseInt(hex.slice(1), 16)
  const r = Math.round(((n >> 16) & 255) * (1 - t))
  const g = Math.round(((n >> 8) & 255) * (1 - t))
  const b = Math.round((n & 255) * (1 - t))
  return "#" + ((1 << 24) | (r << 16) | (g << 8) | b).toString(16).slice(1)
}

// Four intensity levels, least busy first; the last one is the chosen color.
function palette(value) {
  const base = validColor(value)
  return [shade(base, 0.6), shade(base, 0.35), shade(base, 0.15), base]
}

// Mixes two "#rrggbb" colors: t = 0 is a, t = 1 is b.
function mix(a, b, t) {
  const x = parseInt(a.slice(1), 16), y = parseInt(b.slice(1), 16)
  const ch = (sh) => Math.round(((x >> sh) & 255) * (1 - t) + ((y >> sh) & 255) * t)
  return "#" + ((1 << 24) | (ch(16) << 16) | (ch(8) << 8) | ch(0)).toString(16).slice(1)
}

// Four levels running from `low` (quiet days, a little darkened) to `high` (busy days).
// With a single color this is the same as palette().
function palette2(low, high) {
  const lo = validColor(low), hi = validColor(high)
  if (lo === hi) return palette(hi)
  return [shade(lo, 0.45), mix(shade(lo, 0.2), hi, 1 / 3), mix(lo, hi, 2 / 3), hi]
}

// Where the grid's colors come from (setting gridColorFrom):
//   accent  the theme's accent
//   border  the window border's gradient, first color for quiet days, last for busy ones
//   theme   one of the theme's named colors (gridThemeColor)
//   custom  gridColor
// `theme` is { accent, named: {green: "#..", ...}, border: ["#..", ...] }; anything
// missing falls back to the custom color.
function gridPalette(cfg, theme) {
  const t = theme || {}
  const custom = validColor(cfg.gridColor)
  const hex = (v) => typeof v === "string" && HEX_COLOR.test(v) ? v.toLowerCase() : ""
  const from = cfg.gridColorFrom
  if (from === "accent" && hex(t.accent)) return palette(hex(t.accent))
  if (from === "theme" && t.named && hex(t.named[cfg.gridThemeColor])) return palette(hex(t.named[cfg.gridThemeColor]))
  if (from === "border" && Array.isArray(t.border) && t.border.length > 0) {
    const first = hex(t.border[0]), last = hex(t.border[t.border.length - 1])
    if (first && last) return palette2(first, last)
  }
  return palette(custom)
}

function providerLabel(p) { return PROVIDERS[p] ? PROVIDERS[p].label : "Unknown" }
function providerGlyph(p) { return PROVIDERS[p] ? PROVIDERS[p].glyph : "\uf1d3" }
function errorText(code) { return ERRORS[code] || ERRORS["request-failed"] }
function accountKey(a) { return a.provider + "|" + a.host + "|" + a.user }
// Rolling "last year" results use the plain account key; calendar years add the year.
function resultKey(a, year) { return year > 0 ? accountKey(a) + "|" + year : accountKey(a) }

function parseAccounts(text) {
  let raw
  try { raw = JSON.parse(text) } catch (e) { return [] }
  if (!Array.isArray(raw)) return []
  const out = []
  for (let i = 0; i < raw.length && out.length < MAX_ACCOUNTS; i++) {
    const a = raw[i]
    if (!a || typeof a !== "object" || !PROVIDERS[a.provider]) continue
    if (typeof a.host !== "string" || typeof a.user !== "string") continue
    const host = clean(a.host, 100), user = clean(a.user, 64)
    if (host === "" || user === "") continue
    out.push({ provider: a.provider, host: host, user: user })
  }
  return out
}

function parseResult(text) {
  let raw
  try { raw = JSON.parse(text) } catch (e) { return { error: "bad-response" } }
  if (!raw || typeof raw !== "object") return { error: "bad-response" }
  if (raw.error !== undefined) return { error: ERRORS[raw.error] ? raw.error : "request-failed" }
  if (!raw.days || typeof raw.days !== "object") return { error: "bad-response" }
  const days = {}
  for (const k in raw.days) {
    const n = raw.days[k]
    if (ISO_DAY.test(k) && typeof n === "number" && isFinite(n) && n >= 0) days[k] = Math.floor(n)
  }
  const years = []
  if (Array.isArray(raw.years)) {
    for (let j = 0; j < raw.years.length && years.length < 30; j++) {
      const y = raw.years[j]
      if (typeof y === "number" && y === Math.floor(y) && y >= 1970 && y <= 2200 && years.indexOf(y) < 0) years.push(y)
    }
    years.sort((p, q) => q - p)
  }
  return { days: days, years: years, fetchedAt: Date.now() }
}

// Builds the GitHub-style grid: 7 rows (Sun..Sat), one column per week, ending
// on `now`. Cells outside the 365-day window are marked `skip` (drawn
// transparent) so columns stay aligned.
function buildGrid(days, now, year) {
  const today = atNoon(now)
  const y = year > 0 ? year : 0
  let end, windowStart
  if (y) {
    windowStart = new Date(y, 0, 1, 12)
    end = y === today.getFullYear() ? today : new Date(y, 11, 31, 12)
  } else {
    end = today
    windowStart = addDays(end, -364)
  }
  let cursor = addDays(windowStart, -windowStart.getDay())
  const cols = [], months = [], flat = []
  let total = 0, max = 0, lastMonth = -1

  while (cursor <= end) {
    const col = []
    if (cursor.getMonth() !== lastMonth) {
      months.push({ col: cols.length, label: MONTHS[cursor.getMonth()] })
      lastMonth = cursor.getMonth()
    }
    for (let r = 0; r < 7; r++) {
      const d = addDays(cursor, r)
      const skip = d > end || d < windowStart
      const count = skip ? 0 : (days[iso(d)] || 0)
      const cell = {
        date: iso(d),
        count: count,
        level: 0,
        skip: skip,
        when: WEEKDAYS[d.getDay()] + ", " + d.getDate() + " " + MONTHS[d.getMonth()] + " " + d.getFullYear()
      }
      if (!skip) { total += count; if (count > max) max = count; flat.push(cell) }
      col.push(cell)
    }
    cols.push(col)
    cursor = addDays(cursor, 7)
  }

  if (months.length > 1 && months[1].col - months[0].col < 3) months.shift()
  // A label in the last two columns would run past the right edge.
  while (months.length > 0 && months[months.length - 1].col > cols.length - 2) months.pop()

  const scale = levelScale(flat.map(c => c.count))
  let i
  for (i = 0; i < flat.length; i++) flat[i].level = levelOf(flat[i].count, scale)

  let longest = 0, run = 0, busiest = null
  for (i = 0; i < flat.length; i++) {
    run = flat[i].count > 0 ? run + 1 : 0
    if (run > longest) longest = run
    if (flat[i].count > 0 && (!busiest || flat[i].count > busiest.count)) busiest = flat[i]
  }
  let current = 0
  i = flat.length - 1
  if (i >= 0 && flat[i].count === 0) i--   // today may simply not have happened yet
  for (; i >= 0 && flat[i].count > 0; i--) current++

  return { year: y, showCurrent: !y || y === today.getFullYear(), cols: cols, flat: flat, months: months, total: total, max: max, current: current, longest: longest, busiest: busiest, scale: scale, legend: legendLabels(scale) }
}

// The shades follow your own activity: like GitHub's graph, each of the four colors
// covers about a quarter of the days you were active (quartiles of the non-zero
// days), so one huge day doesn't wash out the rest. Returns the upper bounds of
// levels 1-3; level 4 is everything above the last one.
function levelScale(counts) {
  const active = counts.filter(c => c > 0).sort((a, b) => a - b)
  if (active.length === 0) return [1, 2, 3]
  const q = (p) => active[Math.floor(p * (active.length - 1))]
  const t1 = Math.max(1, q(0.25))
  const t2 = Math.max(t1 + 1, q(0.5))
  const t3 = Math.max(t2 + 1, q(0.75))
  return [t1, t2, t3]
}

function levelOf(count, scale) {
  if (count <= 0) return 0
  if (count <= scale[0]) return 1
  if (count <= scale[1]) return 2
  if (count <= scale[2]) return 3
  return 4
}

// What each color stands for: ["0", "1-2", "3-5", "6-11", "12+"]
function legendLabels(scale) {
  const range = (lo, hi) => lo === hi ? String(lo) : lo + "\u2013" + hi
  return ["0", range(1, scale[0]), range(scale[0] + 1, scale[1]), range(scale[1] + 1, scale[2]), (scale[2] + 1) + "+"]
}

function summaryLine(grid, streaks) {
  let s = grid.total + (grid.total === 1 ? " contribution" : " contributions")
  s += grid.year ? " in " + grid.year : " in the last year"
  if (streaks === false) return s
  if (grid.showCurrent) s += "  \u00b7  current streak " + grid.current
  s += "  \u00b7  longest " + grid.longest
  return s
}

// "26 Jun", or "26 Jun 2025" when it isn't this year
function shortDay(cell) {
  const p = cell.date.split("-")
  const label = Number(p[2]) + " " + MONTHS[Number(p[1]) - 1]
  return Number(p[0]) === new Date().getFullYear() ? label : label + " " + p[0]
}

function describe(cell) {
  return cell.count + (cell.count === 1 ? " contribution" : " contributions") + " on " + cell.when
}

// ---- one day: commits and pull requests (bin/dev-stats.sh day) -----------------

const MAX_COMMITS = 200
const MAX_PRS = 100
const REPO_NAME = /^[A-Za-z0-9_.-]{1,100}\/[A-Za-z0-9_.-]{1,100}$/
const SHA = /^[0-9a-f]{7,64}$/
// Same rule as BarWidget.openUrl: plain https links only.
const SAFE_URL = /^https:\/\/[A-Za-z0-9.-]+(\/[A-Za-z0-9._~%!$&'()*+,;=:@\/?#-]*)?$/

function dayKey(a, date) { return accountKey(a) + "|" + date }

function safeUrl(u) {
  return typeof u === "string" && u.length <= 300 && SAFE_URL.test(u) ? u : ""
}

// "21:27" in local time, or "" for anything that isn't a date
function clock(iso) {
  const t = Date.parse(iso)
  if (!isFinite(t)) return ""
  const d = new Date(t)
  return pad(d.getHours()) + ":" + pad(d.getMinutes())
}

function parseDay(text, date) {
  let raw
  try { raw = JSON.parse(text) } catch (e) { return { error: "bad-response" } }
  if (!raw || typeof raw !== "object") return { error: "bad-response" }
  if (raw.error !== undefined) return { error: ERRORS[raw.error] ? raw.error : "request-failed" }
  if (!Array.isArray(raw.commits) || !Array.isArray(raw.prs)) return { error: "bad-response" }
  if (raw.date !== date) return { error: "bad-response" }

  const commits = []
  for (let i = 0; i < raw.commits.length && commits.length < MAX_COMMITS; i++) {
    const c = raw.commits[i]
    if (!c || typeof c !== "object" || typeof c.repo !== "string" || !REPO_NAME.test(c.repo)) continue
    if (typeof c.sha !== "string" || !SHA.test(c.sha)) continue
    commits.push({
      repo: c.repo,
      branch: clean(c.branch, 120),
      sha: c.sha.slice(0, 7),
      title: clean(c.title, 200) || "(no message)",
      url: safeUrl(c.url),
      at: clock(c.at),
      time: isFinite(Date.parse(c.at)) ? Date.parse(c.at) : 0
    })
  }
  commits.sort((p, q) => q.time - p.time)

  const prs = []
  for (let j = 0; j < raw.prs.length && prs.length < MAX_PRS; j++) {
    const r = raw.prs[j]
    if (!r || typeof r !== "object" || typeof r.repo !== "string" || !REPO_NAME.test(r.repo)) continue
    const num = r.number
    if (typeof num !== "number" || num !== Math.floor(num) || num < 1 || num > 1e9) continue
    const ev = typeof r.event === "string" ? r.event.split(",") : []
    const state = ["OPEN", "CLOSED", "MERGED"].indexOf(r.state) >= 0 ? r.state.toLowerCase() : ""
    prs.push({
      repo: r.repo,
      number: num,
      title: clean(r.title, 200) || "(no title)",
      url: safeUrl(r.url),
      opened: ev.indexOf("opened") >= 0,
      merged: ev.indexOf("merged") >= 0,
      state: state
    })
  }

  return { date: date, commits: commits, prs: prs, partial: raw.partial === true, fetchedAt: Date.now() }
}

// Commits grouped by repository, the busiest repository first.
function commitGroups(commits) {
  const by = {}, order = []
  for (const c of commits || []) {
    if (!by[c.repo]) { by[c.repo] = []; order.push(c.repo) }
    by[c.repo].push(c)
  }
  return order.map(r => ({ repo: r, commits: by[r] })).sort((p, q) => q.commits.length - p.commits.length)
}

// "Tue, 24 Nov 2026"
function longDay(date) {
  if (!ISO_DAY.test(date)) return ""
  const p = date.split("-")
  const d = new Date(Number(p[0]), Number(p[1]) - 1, Number(p[2]), 12)
  return WEEKDAYS[d.getDay()] + ", " + d.getDate() + " " + MONTHS[d.getMonth()] + " " + d.getFullYear()
}

function daySummary(day) {
  const c = day.commits.length, r = day.prs.length
  return c + (c === 1 ? " commit" : " commits") + "  ·  " + r + (r === 1 ? " pull request" : " pull requests")
}

function prLine(pr) {
  const what = pr.opened && pr.merged ? "opened and merged" : (pr.merged ? "merged" : "opened")
  return pr.repo + "  ·  " + what + (pr.state === "open" ? "  ·  still open" : "")
}

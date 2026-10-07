.pragma library

// Everything that comes from outside the shell (account names, hosts, fetch
// results) passes through this file before it reaches QML. Remote error text is
// never shown, only the fixed messages below.

var MONTHS = ["Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"]
var WEEKDAYS = ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"]

var PROVIDERS = {
  github: { label: "GitHub", glyph: "\uf09b" },
  gitlab: { label: "GitLab", glyph: "\uf296" },
  forgejo: { label: "Forgejo", glyph: "\uf1d3" }
}

var ERRORS = {
  "no-cli": "The command-line tool for this platform is not installed.",
  "request-failed": "Request failed. Check your login, profile visibility or network.",
  "bad-response": "The platform returned something unexpected.",
  "bad-account": "Invalid account entry."
}

var ISO_DAY = /^\d{4}-\d{2}-\d{2}$/
var MAX_ACCOUNTS = 12

function pad(n) { return n < 10 ? "0" + n : "" + n }
function iso(d) { return d.getFullYear() + "-" + pad(d.getMonth() + 1) + "-" + pad(d.getDate()) }
function atNoon(d) { return new Date(d.getFullYear(), d.getMonth(), d.getDate(), 12) }
function addDays(d, n) { var r = new Date(d.getTime()); r.setDate(r.getDate() + n); return r }

// Strip control and bidi-override characters and cap the length.
function clean(value, max) {
  var s = String(value === undefined || value === null ? "" : value)
  s = s.replace(/[\u0000-\u001f\u007f-\u009f\u200e\u200f\u202a-\u202e\u2066-\u2069]/g, "")
  return s.length > max ? s.slice(0, max) : s
}

var DEFAULT_COLOR = "#39d353"
var HEX_COLOR = /^#[0-9a-fA-F]{6}$/

// Returns a valid "#rrggbb" color, or the default green.
function validColor(value) {
  return typeof value === "string" && HEX_COLOR.test(value) ? value.toLowerCase() : DEFAULT_COLOR
}

var PRESET_COLORS = [
  { name: "Green", hex: "#39d353" },
  { name: "Blue", hex: "#58a6ff" },
  { name: "Purple", hex: "#bc8cff" },
  { name: "Orange", hex: "#ff6b2c" },
  { name: "Red", hex: "#f85149" },
  { name: "Yellow", hex: "#e3b341" }
]

// Darkens a "#rrggbb" color toward black by t (0 = unchanged, 1 = black).
function shade(hex, t) {
  var n = parseInt(hex.slice(1), 16)
  var r = Math.round(((n >> 16) & 255) * (1 - t))
  var g = Math.round(((n >> 8) & 255) * (1 - t))
  var b = Math.round((n & 255) * (1 - t))
  return "#" + ((1 << 24) | (r << 16) | (g << 8) | b).toString(16).slice(1)
}

// Four intensity levels, least busy first; the last one is the chosen color.
function palette(value) {
  var base = validColor(value)
  return [shade(base, 0.6), shade(base, 0.35), shade(base, 0.15), base]
}

function providerLabel(p) { return PROVIDERS[p] ? PROVIDERS[p].label : "Unknown" }
function providerGlyph(p) { return PROVIDERS[p] ? PROVIDERS[p].glyph : "\uf1d3" }
function errorText(code) { return ERRORS[code] || ERRORS["request-failed"] }
function accountKey(a) { return a.provider + "|" + a.host + "|" + a.user }
// Rolling "last year" results use the plain account key; calendar years add the year.
function resultKey(a, year) { return year > 0 ? accountKey(a) + "|" + year : accountKey(a) }

function parseAccounts(text) {
  var raw
  try { raw = JSON.parse(text) } catch (e) { return [] }
  if (!Array.isArray(raw)) return []
  var out = []
  for (var i = 0; i < raw.length && out.length < MAX_ACCOUNTS; i++) {
    var a = raw[i]
    if (!a || typeof a !== "object" || !PROVIDERS[a.provider]) continue
    if (typeof a.host !== "string" || typeof a.user !== "string") continue
    var host = clean(a.host, 100), user = clean(a.user, 64)
    if (host === "" || user === "") continue
    out.push({ provider: a.provider, host: host, user: user })
  }
  return out
}

function parseResult(text) {
  var raw
  try { raw = JSON.parse(text) } catch (e) { return { error: "bad-response" } }
  if (!raw || typeof raw !== "object") return { error: "bad-response" }
  if (raw.error !== undefined) return { error: ERRORS[raw.error] ? raw.error : "request-failed" }
  if (!raw.days || typeof raw.days !== "object") return { error: "bad-response" }
  var days = {}
  for (var k in raw.days) {
    var n = raw.days[k]
    if (ISO_DAY.test(k) && typeof n === "number" && isFinite(n) && n >= 0) days[k] = Math.floor(n)
  }
  var years = []
  if (Array.isArray(raw.years)) {
    for (var j = 0; j < raw.years.length && years.length < 30; j++) {
      var y = raw.years[j]
      if (typeof y === "number" && y === Math.floor(y) && y >= 1970 && y <= 2200 && years.indexOf(y) < 0) years.push(y)
    }
    years.sort(function(p, q) { return q - p })
  }
  return { days: days, years: years, fetchedAt: Date.now() }
}

// Builds the GitHub-style grid: 7 rows (Sun..Sat), one column per week, ending
// on `now`. Cells outside the 365-day window are marked `skip` (drawn
// transparent) so columns stay aligned.
function buildGrid(days, now, year) {
  var today = atNoon(now)
  var y = year > 0 ? year : 0
  var end, windowStart
  if (y) {
    windowStart = new Date(y, 0, 1, 12)
    end = y === today.getFullYear() ? today : new Date(y, 11, 31, 12)
  } else {
    end = today
    windowStart = addDays(end, -364)
  }
  var cursor = addDays(windowStart, -windowStart.getDay())
  var cols = [], months = [], flat = []
  var total = 0, max = 0, lastMonth = -1

  while (cursor <= end) {
    var col = []
    if (cursor.getMonth() !== lastMonth) {
      months.push({ col: cols.length, label: MONTHS[cursor.getMonth()] })
      lastMonth = cursor.getMonth()
    }
    for (var r = 0; r < 7; r++) {
      var d = addDays(cursor, r)
      var skip = d > end || d < windowStart
      var count = skip ? 0 : (days[iso(d)] || 0)
      var cell = {
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

  var i
  for (i = 0; i < flat.length; i++)
    flat[i].level = flat[i].count <= 0 ? 0 : Math.min(4, Math.ceil(4 * flat[i].count / max))

  var longest = 0, run = 0, busiest = null
  for (i = 0; i < flat.length; i++) {
    run = flat[i].count > 0 ? run + 1 : 0
    if (run > longest) longest = run
    if (flat[i].count > 0 && (!busiest || flat[i].count > busiest.count)) busiest = flat[i]
  }
  var current = 0
  i = flat.length - 1
  if (i >= 0 && flat[i].count === 0) i--   // today may simply not have happened yet
  for (; i >= 0 && flat[i].count > 0; i--) current++

  return { year: y, showCurrent: !y || y === today.getFullYear(), cols: cols, flat: flat, months: months, total: total, max: max, current: current, longest: longest, busiest: busiest }
}

function summaryLine(grid) {
  var s = grid.total + (grid.total === 1 ? " contribution" : " contributions")
  s += grid.year ? " in " + grid.year : " in the last year"
  if (grid.showCurrent) s += "  \u00b7  current streak " + grid.current
  s += "  \u00b7  longest " + grid.longest
  return s
}

function describe(cell) {
  return cell.count + (cell.count === 1 ? " contribution" : " contributions") + " on " + cell.when
}

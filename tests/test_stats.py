"""Runs Stats.js (the model behind the bar and the grid) under node with fixed dates."""
import json, os, subprocess, tempfile

root = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
src = open(os.path.join(root, "Stats.js"), encoding="utf-8").read().replace(".pragma library", "")

check = r"""
const assert = require('assert');
const now = new Date(2026, 9, 11, 15);                        // Sun 11 Oct 2026
const days = {};
for (const d of ['2026-10-11','2026-10-10','2026-10-09']) days[d] = 2;   // streak of 3 up to today
days['2026-10-05'] = 6;
const g = buildGrid(days, now, 0);
assert.strictEqual(g.cols.length, 53);
assert.strictEqual(g.total, 12);
assert.strictEqual(g.current, 3);
assert.strictEqual(g.longest, 3);
assert.strictEqual(g.max, 6);
assert.strictEqual(g.busiest.date, '2026-10-05');
assert.strictEqual(summaryLine(g), '12 contributions in the last year  \u00b7  current streak 3  \u00b7  longest 3');

// A day that has not happened yet must not break the current streak.
const g2 = buildGrid({ '2026-10-10': 1 }, now, 0);
assert.strictEqual(g2.current, 1);

// A past calendar year: no "current streak" in the summary.
const g3 = buildGrid({ '2025-03-03': 4 }, now, 2025);
assert.strictEqual(g3.total, 4);
assert.strictEqual(g3.showCurrent, false);
assert(summaryLine(g3).indexOf('in 2025') > 0 && summaryLine(g3).indexOf('current') < 0);

// colors
assert.strictEqual(validColor('#ABCDEF'), '#abcdef');
assert.strictEqual(validColor('red'), DEFAULT_COLOR);
assert.strictEqual(validColor(5), DEFAULT_COLOR);
const p = palette('#39d353');
assert.strictEqual(p.length, 4); assert.strictEqual(p[3], '#39d353');

// remote data is cleaned
assert.deepStrictEqual(parseAccounts('[{"provider":"github","host":"github.com","user":"a\u202eb"},{"provider":"evil","host":"x","user":"y"},5]'),
  [{ provider: 'github', host: 'github.com', user: 'ab' }]);
assert.deepStrictEqual(parseAccounts('not json'), []);
assert.strictEqual(parseResult('{"error":"<script>"}').error, 'request-failed');
assert.strictEqual(parseResult('{"error":"no-cli"}').error, 'no-cli');
const r = parseResult('{"days":{"2026-10-11":3,"bad":9,"2026-10-10":-1},"years":[2026,2025,2025,5]}');
assert.deepStrictEqual(r.days, { '2026-10-11': 3 });
assert.deepStrictEqual(r.years, [2026, 2025]);
assert.strictEqual(errorText('whatever'), ERRORS['request-failed']);
console.log('ok');
"""
with tempfile.NamedTemporaryFile("w", suffix=".js", delete=False) as f:
    f.write(src + "\n" + check)
r = subprocess.run(["node", f.name], capture_output=True, text=True)
os.unlink(f.name)
print(r.stdout.strip() or r.stderr.strip())
raise SystemExit(r.returncode)

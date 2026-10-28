// node tests/test_model.js
// The pure logic (Stats.js, Schema.js, Theme.js), the fetch helper's input checks
// and the manifest, without Qt.
const fs = require("fs"), path = require("path"), assert = require("assert"), cp = require("child_process");
const root = path.join(__dirname, "..");
const load = (file, names) => new Function(fs.readFileSync(path.join(root, "qml", "js", file), "utf8")
    .replace(/^\.pragma.*$/m, "") + "; return { " + names.join(", ") + " };")();

const M = load("Stats.js", ["buildGrid", "summaryLine", "validColor", "palette", "parseAccounts", "parseResult",
    "errorText", "ERRORS", "DEFAULT_COLOR", "shortDay", "describe"]);
const S = load("Schema.js", ["groups", "settingKeys", "defaults", "resolve"]);
const T = load("Theme.js", ["parseBorder"]);

let n = 0;
const t = (name, fn) => { fn(); n++; console.log("  ok   " + name); };

t("the grid counts the year and its streaks", () => {
    const now = new Date(2026, 9, 11, 15);                       // Sun 11 Oct 2026
    const days = {};
    for (const d of ["2026-10-11", "2026-10-10", "2026-10-09"]) days[d] = 2;
    days["2026-10-05"] = 6;
    const g = M.buildGrid(days, now, 0);
    assert.strictEqual(g.cols.length, 53);
    assert.deepStrictEqual([g.total, g.current, g.longest, g.max, g.busiest.date], [12, 3, 3, 6, "2026-10-05"]);
    assert.strictEqual(M.summaryLine(g), "12 contributions in the last year  ·  current streak 3  ·  longest 3");
    assert.strictEqual(M.summaryLine(g, false), "12 contributions in the last year");
    // a day that has not happened yet doesn't break the current streak
    assert.strictEqual(M.buildGrid({ "2026-10-10": 1 }, now, 0).current, 1);
    // a past year has no current streak
    const g3 = M.buildGrid({ "2025-03-03": 4 }, now, 2025);
    assert.strictEqual(g3.total, 4);
    assert.ok(M.summaryLine(g3).includes("in 2025") && !M.summaryLine(g3).includes("current"));
});

t("grid colors are hex only, with four levels", () => {
    assert.strictEqual(M.validColor("#ABCDEF"), "#abcdef");
    assert.strictEqual(M.validColor("red"), M.DEFAULT_COLOR);
    assert.strictEqual(M.validColor(5), M.DEFAULT_COLOR);
    const p = M.palette("#39d353");
    assert.strictEqual(p.length, 4);
    assert.strictEqual(p[3], "#39d353");
});

t("what comes from the platforms is cleaned", () => {
    assert.deepStrictEqual(M.parseAccounts('[{"provider":"github","host":"github.com","user":"a‮b"},{"provider":"evil","host":"x","user":"y"},5]'),
        [{ provider: "github", host: "github.com", user: "ab" }]);
    assert.deepStrictEqual(M.parseAccounts("not json"), []);
    assert.strictEqual(M.parseResult('{"error":"<script>"}').error, "request-failed");
    assert.strictEqual(M.parseResult('{"error":"no-cli"}').error, "no-cli");
    const r = M.parseResult('{"days":{"2026-10-11":3,"bad":9,"2026-10-10":-1},"years":[2026,2025,2025,5]}');
    assert.deepStrictEqual(r.days, { "2026-10-11": 3 });
    assert.deepStrictEqual(r.years, [2026, 2025]);
    assert.strictEqual(M.errorText("whatever"), M.ERRORS["request-failed"]);
    const day = { date: "2025-06-26", count: 2, when: "Thu, 26 Jun 2025" };
    assert.strictEqual(M.shortDay(day), "26 Jun 2025");
    assert.strictEqual(M.describe(day), "2 contributions on Thu, 26 Jun 2025");
});

t("settings are clamped to what the schema allows", () => {
    const c = S.resolve({ days: 99, colorMode: "pink", autoRefresh: "false", gridColor: "#58A6FF", windowWidth: "5000" }, {});
    assert.deepStrictEqual([c.days, c.colorMode, c.autoRefresh, c.gridColor, c.windowWidth], [14, "theme", false, "#58a6ff", 1200]);
    assert.strictEqual(S.resolve({ gridColor: "green" }, {}).gridColor, "#39d353");
    assert.deepStrictEqual(Object.keys(c).sort(), S.settingKeys.slice().sort());
    assert.deepStrictEqual(S.resolve({}, {}), S.defaults);
    assert.strictEqual(S.resolve({ days: 5 }, { days: 9 }).days, 5);
    assert.strictEqual(S.resolve({}, { days: 9 }).days, 9);
});

t("settings saved by 1.2 still apply", () => {
    const c = S.resolve({ panelColor: "custom", panelCustomColor: "#bb9af7", days: 10 }, {});
    assert.deepStrictEqual([c.colorMode, c.accentColor, c.days], ["custom", "#bb9af7", 10]);
    assert.strictEqual(S.resolve({ panelColor: "monochrome" }, {}).colorMode, "monochrome");
    // once a new color setting is saved, the old ones no longer count
    assert.strictEqual(S.resolve({ panelColor: "monochrome", colorMode: "borders" }, {}).colorMode, "borders");
});

t("a custom text color that was never picked reads on the background", () => {
    assert.strictEqual(S.resolve({ colorMode: "custom", customBg: "#f8f8f2" }, {}).customFg, "#141414");
    assert.strictEqual(S.resolve({ colorMode: "custom", customBg: "#1f1714" }, {}).customFg, "#e0e0e0");
    assert.strictEqual(S.resolve({ colorMode: "custom", customBg: "#f8f8f2", customFg: "#ffffff" }, {}).customFg, "#ffffff");
});

t("the window border is read from the theme's files", () => {
    const lua = T.parseBorder('local active_border_color = { colors = { "rgba(1ee9d6ee)", "rgba(fe4fb6ee)" }, angle = 45 }');
    assert.deepStrictEqual(lua, { colors: ["#1ee9d6", "#fe4fb6"], angle: 45 });
    assert.deepStrictEqual(T.parseBorder("col.active_border = rgba(33ccffee) rgba(00ff99ee) 45deg").colors, ["#33ccff", "#00ff99"]);
    assert.deepStrictEqual(T.parseBorder("").colors, []);
});

t("the fetch helper refuses odd accounts before running anything", () => {
    const run = (...args) => {
        const r = cp.spawnSync("bash", [path.join(root, "bin", "dev-stats.sh"), ...args],
            { encoding: "utf8", env: Object.assign({}, process.env, { PATH: "/usr/bin:/bin" }) });
        return r.stdout.trim();
    };
    for (const bad of [["fetch", "github", "-x", "me"], ["fetch", "github", "a b", "me"], ["fetch", "evil", "github.com", "me"],
                       ["fetch", "github", "github.com", "--me"], ["fetch", "github", "github.com", "me", "20x6"], ["nope"]])
        assert.strictEqual(run(...bad), '{"error":"bad-account"}', bad.join(" "));
});

t("text is drawn plain, and no native text field reads the clipboard", () => {
    const walk = (d) => fs.readdirSync(d, { withFileTypes: true }).flatMap((e) =>
        e.isDirectory() ? walk(path.join(d, e.name)) : [path.join(d, e.name)]);
    for (const f of walk(path.join(root, "qml")).filter((f) => f.endsWith(".qml"))) {
        const src = fs.readFileSync(f, "utf8");
        assert.ok(!/\b(TextInput|TextField|TextArea|TextEdit)\s*\{/.test(src), f + " creates a native text field");
        assert.ok(!src.includes("import QtQuick.Controls"), f + " imports QtQuick.Controls");
        assert.ok(!/Text\.(RichText|StyledText|AutoText)/.test(src), f + " allows markup");
    }
});

t("manifest matches Schema.js", () => {
    const m = JSON.parse(fs.readFileSync(path.join(root, "manifest.json"), "utf8"));
    assert.strictEqual(m.id, "io.github.qempexe.dev-stats");
    assert.deepStrictEqual(m.barWidget.schema.map((e) => e.key), S.settingKeys);
    assert.deepStrictEqual(m.barWidget.defaults, S.defaults);
    assert.strictEqual(S.defaults.gridColor, M.DEFAULT_COLOR);
    assert.ok(fs.existsSync(path.join(root, m.entryPoints.barWidget)));
});

console.log("\nALL OK (" + n + ")");

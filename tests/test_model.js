// node tests/test_model.js
// The pure logic (Stats.js, Schema.js, Theme.js), the fetch helper's input checks
// and the manifest, without Qt.
const fs = require("fs"), path = require("path"), assert = require("assert"), cp = require("child_process");
const root = path.join(__dirname, "..");
const load = (file, names) => new Function(fs.readFileSync(path.join(root, "qml", "js", file), "utf8")
    .replace(/^\.pragma.*$/m, "") + "; return { " + names.join(", ") + " };")();

const M = load("Stats.js", ["buildGrid", "summaryLine", "validColor", "palette", "parseAccounts", "parseResult",
    "errorText", "ERRORS", "DEFAULT_COLOR", "shortDay", "describe",
    "parseDay", "commitGroups", "longDay", "daySummary", "prLine", "dayKey",
    "levelScale", "levelOf", "legendLabels", "gridPalette", "palette", "palette2"]);
const S = load("Schema.js", ["groups", "settingKeys", "defaults", "resolve"]);
const T = load("Theme.js", ["parseBorder", "parseNamed"]);

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

t("a day's commits and pull requests are cleaned before they are shown", () => {
    const raw = {
        date: "2026-11-24", partial: true,
        commits: [
            { repo: "acme/web", branch: "feat/x", sha: "65fc9b2e38f46eba7b44d57954b30cbaa842ecfb",
              title: "web: split‮ the table", url: "https://github.com/acme/web/commit/65fc9b2", at: "2026-11-25T02:27:37Z" },
            { repo: "acme/web", branch: "main", sha: "bcb6b7f0", title: "older", url: "https://github.com/acme/web/commit/bcb6b7f0", at: "2026-11-24T17:41:49Z" },
            { repo: "acme/api", branch: "main", sha: "aaaaaaa", title: "<img src=https://x.invalid/t>", url: "javascript:alert(1)", at: "nope" },
            { repo: "../../etc", branch: "main", sha: "bbbbbbb", title: "bad repo", url: "", at: "" },
            { repo: "acme/web", branch: "main", sha: "not-a-sha", title: "bad sha", url: "", at: "" }
        ],
        prs: [
            { repo: "acme/web", number: 12, title: "Add a thing", url: "https://github.com/acme/web/pull/12", state: "MERGED", event: "opened,merged" },
            { repo: "acme/web", number: 1.5, title: "bad number", url: "", state: "OPEN", event: "opened" },
            { repo: "acme/web", number: 13, title: "", url: "http://github.com/acme/web/pull/13", state: "WEIRD", event: "opened" }
        ]
    };
    const d = M.parseDay(JSON.stringify(raw), "2026-11-24");
    assert.strictEqual(d.commits.length, 3);
    assert.deepStrictEqual(d.commits.map((c) => c.sha), ["65fc9b2", "bcb6b7f", "aaaaaaa"]);   // newest first, bad time last
    assert.strictEqual(d.commits[0].title, "web: split the table");                       // bidi override gone
    assert.strictEqual(d.commits[2].url, "");                                              // no javascript: links
    assert.strictEqual(d.commits[2].at, "");
    assert.strictEqual(d.prs.length, 2);
    assert.deepStrictEqual([d.prs[0].opened, d.prs[0].merged, d.prs[0].state], [true, true, "merged"]);
    assert.deepStrictEqual([d.prs[1].title, d.prs[1].url, d.prs[1].state], ["(no title)", "", ""]);  // http refused
    assert.strictEqual(d.partial, true);
    assert.strictEqual(M.prLine(d.prs[0]), "acme/web  ·  opened and merged");
    assert.strictEqual(M.daySummary(d), "3 commits  ·  2 pull requests");
    const g = M.commitGroups(d.commits);
    assert.deepStrictEqual(g.map((x) => [x.repo, x.commits.length]), [["acme/web", 2], ["acme/api", 1]]);
});

t("a day result for another date, or an error, is not shown as data", () => {
    assert.deepStrictEqual(M.parseDay('{"date":"2026-11-23","commits":[],"prs":[]}', "2026-11-24"), { error: "bad-response" });
    assert.deepStrictEqual(M.parseDay('{"error":"unsupported"}', "2026-11-24"), { error: "unsupported" });
    assert.deepStrictEqual(M.parseDay('{"error":"<b>boom</b>"}', "2026-11-24"), { error: "request-failed" });
    assert.deepStrictEqual(M.parseDay("not json", "2026-11-24"), { error: "bad-response" });
    assert.strictEqual(M.longDay("2026-11-24"), "Tue, 24 Nov 2026");
    assert.strictEqual(M.longDay("24/11/2026"), "");
    assert.strictEqual(M.dayKey({ provider: "github", host: "github.com", user: "me" }, "2026-11-24"), "github|github.com|me|2026-11-24");
});

t("the day helper refuses bad input before running anything", () => {
    const run = (...a) => cp.spawnSync("bash", [path.join(root, "bin", "dev-stats.sh"), "day", ...a], { encoding: "utf8" }).stdout.trim();
    assert.strictEqual(run("github", "github.com", "me", "2026-13-01"), '{"error":"bad-account"}');
    assert.strictEqual(run("github", "github.com", "me", "2026-11-24; rm -rf ~"), '{"error":"bad-account"}');
    assert.strictEqual(run("github", "bad host", "me", "2026-11-24"), '{"error":"bad-account"}');
    assert.strictEqual(run("gitlab", "gitlab.com", "me", "2026-11-24"), '{"error":"unsupported"}');
});

t("shades follow quartiles of the active days, and the legend says what they mean", () => {
    // one huge day no longer pushes everything else into the faintest shade
    const counts = [0, 1, 1, 2, 2, 3, 4, 5, 6, 8, 46];
    const sc = M.levelScale(counts);
    assert.deepStrictEqual(sc, [2, 3, 5]);
    assert.deepStrictEqual(counts.map((c) => M.levelOf(c, sc)), [0, 1, 1, 1, 1, 2, 3, 3, 4, 4, 4]);
    assert.deepStrictEqual(M.legendLabels(sc), ["0", "1–2", "3", "4–5", "6+"]);
    // few distinct values still give four increasing bands
    assert.deepStrictEqual(M.levelScale([1, 1, 1]), [1, 2, 3]);
    assert.deepStrictEqual(M.levelScale([]), [1, 2, 3]);
    const g = M.buildGrid({ "2026-10-05": 46, "2026-10-06": 1, "2026-10-07": 2 }, new Date(2026, 9, 11, 15), 0);
    assert.deepStrictEqual(g.legend, M.legendLabels(g.scale));
    assert.strictEqual(g.flat.find((c) => c.date === "2026-10-06").level, 1);
});

t("grid colors come from the theme, or the custom color", () => {
    const theme = { accent: "#8FBC8F", named: { cyan: "#4ecdc4" }, border: ["#1ee9d6", "#fe4fb6"] };
    const cfg = (from, extra) => Object.assign({ gridColorFrom: from, gridColor: "#ff6b2c", gridThemeColor: "cyan" }, extra || {});
    assert.deepStrictEqual(M.gridPalette(cfg("accent"), theme), M.palette("#8fbc8f"));
    assert.deepStrictEqual(M.gridPalette(cfg("theme"), theme), M.palette("#4ecdc4"));
    assert.deepStrictEqual(M.gridPalette(cfg("custom"), theme), M.palette("#ff6b2c"));
    const b = M.gridPalette(cfg("border"), theme);
    assert.strictEqual(b[3], "#fe4fb6");
    assert.deepStrictEqual(b, M.palette2("#1ee9d6", "#fe4fb6"));
    // missing theme pieces fall back to the custom color
    assert.deepStrictEqual(M.gridPalette(cfg("theme", { gridThemeColor: "magenta" }), theme), M.palette("#ff6b2c"));
    assert.deepStrictEqual(M.gridPalette(cfg("border"), { border: [] }), M.palette("#ff6b2c"));
    assert.deepStrictEqual(M.gridPalette(cfg("accent"), { accent: "javascript:" }), M.palette("#ff6b2c"));
    assert.deepStrictEqual(T.parseNamed('accent = "#8FBC8F"\ncyan = "#4ECDC4"\nbackground = "#1a2125"\nevil = "#ffffff"'),
        { accent: "#8fbc8f", cyan: "#4ecdc4" });
});

t("a grid color picked before 1.4 keeps the grid on Custom", () => {
    assert.strictEqual(S.resolve({ gridColor: "#ff6b2c" }, {}).gridColorFrom, "custom");
    assert.strictEqual(S.resolve({}, {}).gridColorFrom, "accent");
    assert.strictEqual(S.resolve({ gridColor: "#ff6b2c", gridColorFrom: "border" }, {}).gridColorFrom, "border");
});

t("manifest matches Schema.js", () => {
    const m = JSON.parse(fs.readFileSync(path.join(root, "manifest.json"), "utf8"));
    assert.strictEqual(m.id, "io.github.qempexe.dev-stats");
    assert.strictEqual(m.version, "1.3.2");
    assert.ok(fs.readFileSync(path.join(root, "CHANGELOG.md"), "utf8").includes("## [" + m.version + "] - "), "the version has a changelog entry");
    assert.deepStrictEqual(m.barWidget.schema.map((e) => e.key), S.settingKeys);
    assert.deepStrictEqual(m.barWidget.defaults, S.defaults);
    assert.strictEqual(S.defaults.gridColor, M.DEFAULT_COLOR);
    assert.ok(fs.existsSync(path.join(root, m.entryPoints.barWidget)));
});

console.log("\nALL OK (" + n + ")");

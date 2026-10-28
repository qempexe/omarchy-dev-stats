.pragma library

// Every setting, in the groups and order the Settings tab shows them. tools/gen-manifest.js
// writes manifest.json from this, and resolve() turns what is saved into clean values.
//
//   kind     enum, int, bool, string, color, or palette (a few colors edited together)
//   control  how an enum is drawn: scheme, tiles, seg or chips (seg or chips when left out)
//   section  a heading the row sits under, inside its tab
//   when     the row is dimmed unless another setting has one of these values

const PALETTE = [
    "#141414", "#1d1510", "#1a1b26", "#282a36", "#2e3440", "#2d353b", "#1f1f28", "#3b2a1f",
    "#e0e0e0", "#eadbc8", "#ffffff", "#c0caf5", "#d8dee9", "#dcd7ba", "#f8f8f2", "#e0def4",
    "#d4a35a", "#c8925a", "#7aa2f7", "#cba6f7", "#a7c080", "#88c0d0", "#fabd2f", "#ff6a1f"
];

const groups = [
    {
        title: "Colors",
        items: [
            { key: "colorMode", label: "Colors", kind: "enum", fallback: "theme", control: "scheme", section: "Scheme",
              options: ["theme", "borders", "custom", "monochrome"],
              labels: { theme: "Follow theme", borders: "Window borders", custom: "Custom", monochrome: "Monochrome" },
              hint: "Follow theme matches your Omarchy theme live. Window borders takes the accent from your theme's window border. Custom lets you choose the background, text and accent. Monochrome removes every hue." },
            { key: "customColors", label: "Custom colors", kind: "palette", section: "Scheme", presets: PALETTE,
              when: [{ key: "colorMode", is: ["custom"] }],
              fallback: { customBg: "#141414", customFg: "#e0e0e0", accentColor: "#7aa2f7" },
              targets: [{ key: "customBg", label: "Background" }, { key: "customFg", label: "Text" }, { key: "accentColor", label: "Accent" }],
              hint: "Background, text and accent, used exactly as you pick them." },
            { key: "textColor", label: "Text", kind: "enum", fallback: "auto", section: "Text",
              options: ["auto", "theme", "custom"],
              labels: { auto: "Always readable", theme: "Theme", custom: "My text color" },
              hint: "Always readable keeps your theme's text color, and switches to black or white when the window is too light or too dark for it. My text color uses the Text color from Custom colors. Custom colors always use their own text color." },
            { key: "gridColor", label: "Grid color", kind: "color", fallback: "#39d353", section: "Grid",
              presets: ["#39d353", "#58a6ff", "#bc8cff", "#ff6b2c", "#f85149", "#e3b341"],
              hint: "The color of the busiest days, on the bar and in the grid. Quieter days are darker shades of it." }
        ]
    },
    {
        title: "Appearance",
        items: [
            { key: "cardStyle", label: "Card style", kind: "enum", fallback: "soft", control: "tiles",
              options: ["soft", "outline", "flat"], labels: { soft: "Soft", outline: "Outline", flat: "Flat" },
              hint: "Soft fills cards lightly, outline draws a border only, flat has neither." },
            { key: "density", label: "Spacing", kind: "enum", fallback: "comfortable", control: "tiles",
              options: ["compact", "comfortable", "spacious"], labels: { compact: "Compact", comfortable: "Comfortable", spacious: "Spacious" },
              hint: "How much air there is between things." },
            { key: "cornerRadius", label: "Roundness", kind: "int", fallback: 4, min: 0, max: 20, step: 2,
              hint: "0 is square, 20 is very round. The grid's squares follow it too." },
            { key: "fontScale", label: "Text size", kind: "int", fallback: 100, min: 80, max: 150, step: 5, divisor: 100, decimals: 2,
              hint: "1 is normal, 1.25 is a quarter bigger." },
            { key: "showStreaks", label: "Show streaks", kind: "bool", fallback: true, section: "Grid",
              hint: "The current and the longest streak next to the total." },
            { key: "showLegend", label: "Show the legend", kind: "bool", fallback: true, section: "Grid",
              hint: "The Less to More row under the grid." },
            { key: "showCards", label: "Show the numbers", kind: "bool", fallback: true, section: "Grid",
              hint: "Cards under the grid: contributions, active days, longest streak and busiest day." }
        ]
    },
    {
        title: "Window",
        items: [
            { key: "windowWidth", label: "Window width", kind: "int", fallback: 640, min: 480, max: 1200, step: 20, section: "Size",
              hint: "How wide Dev Stats opens. The grid's squares grow with it." },
            { key: "windowHeight", label: "Window height", kind: "int", fallback: 520, min: 420, max: 1100, step: 20, section: "Size",
              hint: "How tall Dev Stats opens." },
            { key: "openAs", label: "Open as", kind: "enum", fallback: "panel", control: "tiles", section: "Layout",
              options: ["panel", "window"], labels: { panel: "Bar panel", window: "Own window" },
              hint: "Where the bar button opens Dev Stats. You can always pop it out or dock it back from the header." },
            { key: "frame", label: "Window outline", kind: "bool", fallback: false, section: "Look",
              hint: "Draw the edge in your window border's colors instead of a plain neutral line." },
            { key: "frameGradient", label: "Outline gradient", kind: "bool", fallback: true, section: "Look",
              when: [{ key: "frame", is: [true] }],
              hint: "Use the window border's whole gradient, at its angle, when it has more than one color." },
            { key: "frameColor", label: "Outline color", kind: "enum", fallback: "accent", section: "Look",
              options: ["accent", "first", "middle", "last"],
              labels: { accent: "Accent", first: "Border's first", middle: "Border's middle", last: "Border's last" },
              when: [{ key: "frame", is: [true] }],
              hint: "The one color the outline takes when it isn't a gradient." },
            { key: "surfaceTint", label: "Window tint", kind: "int", fallback: 0, min: 0, max: 30, step: 2, section: "Look",
              hint: "How much of the accent washes over the background. 0 keeps it plain." },
            { key: "opacity", label: "Window opacity", kind: "int", fallback: 97, min: 50, max: 100, step: 1, section: "Look",
              hint: "100 is solid." }
        ]
    },
    {
        title: "Bar",
        items: [
            { key: "showIcon", label: "Show platform icon", kind: "bool", fallback: true,
              hint: "The GitHub, GitLab or Forgejo logo before the squares." },
            { key: "days", label: "Days on the bar", kind: "int", fallback: 7, min: 3, max: 14, step: 1,
              hint: "How many recent days show as squares." },
            { key: "squareSize", label: "Square size", kind: "int", fallback: 9, min: 6, max: 14, step: 1,
              hint: "How big each day's square is on the bar." },
            { key: "squareRound", label: "Square roundness", kind: "int", fallback: 2, min: 0, max: 7, step: 1,
              hint: "0 is square, 7 makes them dots." },
            { key: "clickAction", label: "Left click", kind: "enum", fallback: "panel",
              options: ["panel", "refresh", "none"], labels: { panel: "Open Dev Stats", refresh: "Refresh", none: "Nothing" },
              hint: "What a left click on the widget does. Right click always opens the settings." },
            { key: "middleAction", label: "Middle click", kind: "enum", fallback: "refresh",
              options: ["refresh", "panel", "none"], labels: { refresh: "Refresh", panel: "Open Dev Stats", none: "Nothing" },
              hint: "What a middle click on the widget does." }
        ]
    },
    {
        title: "Data",
        items: [
            { key: "autoRefresh", label: "Refresh automatically", kind: "bool", fallback: true,
              hint: "Fetch new numbers in the background. Off means only when you ask." },
            { key: "refreshMinutes", label: "Refresh every", kind: "int", fallback: 30, min: 5, max: 240, step: 5,
              when: [{ key: "autoRefresh", is: [true] }],
              hint: "Minutes between updates. Each one runs your own gh, glab or curl." }
        ]
    }
];

// every key that is saved: a palette row saves its targets
const items = [];
const settingKeys = [];
const defaults = {};
for (const g of groups) {
    for (const it of g.items) {
        items.push(it);
        if (it.kind === "palette") {
            for (const t of it.targets) { settingKeys.push(t.key); defaults[t.key] = it.fallback[t.key]; }
        } else {
            settingKeys.push(it.key);
            defaults[it.key] = it.fallback;
        }
    }
}
const itemByKey = {};
for (const it of items) itemByKey[it.key] = it;

function isHex(v) { return typeof v === "string" && /^#[0-9a-fA-F]{6}$/.test(v); }

// one value, made safe: a known option, a whole number in range, a real boolean,
// a hex color, or plain text that is not too long. Anything else is the default.
function clean(key, v) {
    const it = itemByKey[key];
    if (!it) {
        // a palette color
        for (const p of items) if (p.kind === "palette" && p.fallback[key] !== undefined) return isHex(v) ? v.toLowerCase() : p.fallback[key];
        return undefined;
    }
    if (v === undefined || v === null) return it.fallback;
    if (it.kind === "enum") return it.options.map(String).indexOf(String(v)) >= 0 ? String(v) : it.fallback;
    if (it.kind === "bool") return v === true || v === "true" ? true : (v === false || v === "false" ? false : it.fallback);
    if (it.kind === "int") {
        const n = typeof v === "number" ? v : (typeof v === "string" && /^-?[0-9]{1,6}$/.test(v) ? parseInt(v, 10) : NaN);
        return isFinite(n) ? Math.max(it.min, Math.min(it.max, Math.round(n))) : it.fallback;
    }
    if (it.kind === "color") return isHex(v) ? v.toLowerCase() : it.fallback;
    if (it.kind === "string") {
        const s = (typeof v === "string" ? v : "").replace(/[\u0000-\u001f<>]/g, "").trim().slice(0, it.maxLength || 64);
        return s !== "" ? s : it.fallback;
    }
    return it.fallback;
}

// Dev Stats 1.2 kept the window's colors in panelColor (theme, custom or monochrome)
// and its custom accent in panelCustomColor; they are still read. They only count
// while the file has none of the new color settings.
const OLD_MODES = { theme: "theme", custom: "custom", monochrome: "monochrome" };
const COLOR_KEYS = ["colorMode", "customBg", "customFg", "accentColor"];
function migrate(saved) {
    const src = saved && typeof saved === "object" ? saved : {};
    const out = {};
    for (const k of settingKeys) if (src[k] !== undefined) out[k] = src[k];
    if (!COLOR_KEYS.some((k) => src[k] !== undefined)) {
        if (OLD_MODES[src.panelColor] !== undefined) out.colorMode = OLD_MODES[src.panelColor];
        if (src.panelCustomColor !== undefined) out.accentColor = src.panelCustomColor;
    }
    return out;
}

// Black or white text for a background, whichever reads better.
function readableOn(bg) {
    const n = parseInt(bg.slice(1), 16);
    const lum = (0.299 * (n >> 16 & 255) + 0.587 * (n >> 8 & 255) + 0.114 * (n & 255)) / 255;
    return lum > 0.5 ? "#141414" : "#e0e0e0";
}

// every setting, clean. `saved` (the settings file) wins over `shell` (what the
// shell's bar settings hold for this widget).
function resolve(saved, shell) {
    const a = migrate(saved), b = migrate(shell);
    const out = {};
    for (const k of settingKeys) out[k] = clean(k, a[k] !== undefined ? a[k] : b[k]);
    // A custom text color that was never picked follows the custom background, so a
    // light background gets dark text. A picked one is used exactly as it is.
    if (a.customFg === undefined && b.customFg === undefined) out.customFg = readableOn(out.customBg);
    return out;
}

function isSetting(key) { return settingKeys.indexOf(key) >= 0; }

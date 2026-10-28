import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "core"
import "js/Stats.js" as Model
import "js/Schema.js" as Schema
import "js/Theme.js" as Theme

// Dev Stats: the last few days of your contribution graph as squares on the bar,
// and the whole year in its window. The numbers come from bin/dev-stats.sh, which
// runs your own gh, glab, tea/fj or curl.
//
// This file is also the "service" the window talks to (`ui.service`): the accounts
// and their results, refreshing, opening links, the capped clipboard read, the
// manifest, and the theme's window border.
BarWidget {
    id: root
    moduleName: "io.github.qempexe.dev-stats"

    // ---- settings ------------------------------------------------------------------
    // Local overrides (Settings tab, see SettingsStore.qml) win over `omarchy bar set`.
    // Every key read here is declared in manifest.json (tools/gen-manifest.js).
    SettingsStore { id: settingsStore }

    function shellValues() {
        const out = {}
        for (const k of Schema.settingKeys) {
            const v = setting(k, undefined)
            if (v !== undefined && v !== null) out[k] = v
        }
        return out
    }
    readonly property var cfg: Schema.resolve(settingsStore.values, shellValues())
    function setValue(key, value) { settingsStore.set(key, value) }

    // ---- what the window and the bar show --------------------------------------------
    property var accounts: []
    property var results: ({})
    property int selected: 0
    property int selectedYear: 0          // 0 = rolling last year
    property var yearReq: null            // pending on-demand year fetch
    property var yearRunning: null        // year fetch currently in flight
    property bool busy: false
    property real updatedAt: 0
    property int fetchIndex: 0

    readonly property string scriptPath: decodeURIComponent(
        String(Qt.resolvedUrl("../bin/dev-stats.sh")).replace(/^file:\/\//, ""))

    readonly property var current: accounts.length > selected ? accounts[selected] : null

    readonly property string updatedText: busy ? "Updating…"
        : (updatedAt > 0 ? "Updated " + Qt.formatTime(new Date(updatedAt), "HH:mm") : "")
    readonly property string statusLine: (current
        ? Model.providerLabel(current.provider) + " · " + current.user
        : (busy ? "Looking for accounts" : "No accounts yet"))
        + (updatedText !== "" ? "  ·  " + updatedText.toLowerCase() : "")

    // Newest `n` visible cells of the grid, oldest first.
    function lastDays(grid, n) {
        const out = []
        for (let c = grid.cols.length - 1; c >= 0 && out.length < n; c--)
            for (let r = 6; r >= 0 && out.length < n; r--)
                if (!grid.cols[c][r].skip) out.unshift(grid.cols[c][r])
        return out
    }
    readonly property var recent: {
        const res = current ? results[Model.accountKey(current)] : null
        const days = (res && !res.error) ? lastDays(Model.buildGrid(res.days, new Date()), cfg.days) : []
        while (days.length < cfg.days) days.unshift({ level: 0, count: 0 })
        return days
    }
    readonly property var palette: Model.palette(cfg.gridColor)

    // opening a link: only plain https addresses, through xdg-open
    function openUrl(url) {
        const u = String(url || "")
        if (!/^https:\/\/[A-Za-z0-9.-]+(\/[A-Za-z0-9._~%!$&'()*+,;=:@\/?#-]*)?$/.test(u) || u.length > 300) return
        opener.command = ["xdg-open", u]
        opener.running = true
    }
    Process { id: opener }

    // ---- refresh pipeline: list accounts, then fetch each one in turn -------
    function refresh() {
        if (busy) return
        busy = true
        const keep = {}
        for (const k in results) if (k.split("|").length === 3) keep[k] = results[k]
        results = keep
        watchdog.restart()
        listProc.running = true
    }

    function finish() {
        busy = false
        watchdog.stop()
        updatedAt = Date.now()
        if (selectedYear > 0) selectYear(selectedYear)
    }

    // ---- account / year selection (called from the Grid tab) ------------
    function selectAccount(i) {
        selected = i
        selectedYear = 0
    }

    function selectYear(y) {
        selectedYear = y
        if (y > 0 && current && !results[Model.resultKey(current, y)]) {
            yearReq = { account: current, year: y }
            yearTimer.restart()
        }
    }

    function launchYear() {
        if (!yearReq) return
        if (yearProc.running) { yearTimer.restart(); return }
        yearRunning = yearReq
        yearReq = null
        const a = yearRunning.account
        yearProc.command = ["bash", scriptPath, "fetch", a.provider, a.host, a.user, String(yearRunning.year)]
        yearProc.running = true
    }

    function onYearFetched(text) {
        const q = yearRunning
        yearRunning = null
        if (q) {
            const next = Object.assign({}, results)
            next[Model.resultKey(q.account, q.year)] = Model.parseResult(text)
            results = next
        }
        if (yearReq) yearTimer.restart()
    }

    function fetchNext() {
        if (fetchProc.running) { stepTimer.restart(); return }
        if (fetchIndex >= accounts.length) { finish(); return }
        const a = accounts[fetchIndex]
        fetchProc.command = ["bash", scriptPath, "fetch", a.provider, a.host, a.user]
        fetchProc.running = true
    }

    function onAccounts(text) {
        const list = Model.parseAccounts(text)
        accounts = list
        if (selected >= list.length) selected = 0
        fetchIndex = 0
        stepTimer.restart()
    }

    function onFetched(text) {
        const a = accounts[fetchIndex]
        if (a) {
            const next = Object.assign({}, results)
            next[Model.accountKey(a)] = Model.parseResult(text)
            results = next
        }
        fetchIndex++
        stepTimer.restart()
    }

    // ---- one-time move of the color saved by 1.1 (~/.config/dev-stats/color) ----------
    property string legacyColor: ""
    function migrateLegacyColor() {
        if (legacyColor === "" || !settingsStore.loaded) return
        if (settingsStore.get("gridColor") === null) settingsStore.set("gridColor", Model.validColor(legacyColor))
        legacyColor = ""
    }
    Connections {
        target: settingsStore
        function onLoadedChanged() { root.migrateLegacyColor() }
    }
    FileView {
        id: legacyFile
        path: (Quickshell.env("XDG_CONFIG_HOME") || Quickshell.env("HOME") + "/.config") + "/dev-stats/color"
        onLoaded: {
            const t = root.readText(legacyFile).trim().slice(0, 16)
            if (/^#[0-9a-fA-F]{6}$/.test(t)) { root.legacyColor = t; root.migrateLegacyColor() }
        }
    }

    Process {
        id: listProc
        command: ["bash", root.scriptPath, "list"]
        stdout: StdioCollector { onStreamFinished: root.onAccounts(text) }
    }

    Process {
        id: fetchProc
        stdout: StdioCollector { onStreamFinished: root.onFetched(text) }
    }

    Process {
        id: yearProc
        stdout: StdioCollector { onStreamFinished: root.onYearFetched(text) }
    }

    Timer { id: yearTimer; interval: 60; onTriggered: root.launchYear() }

    // Lets a finished process fully exit before the next one is started.
    Timer { id: stepTimer; interval: 60; onTriggered: root.fetchNext() }

    // Never stay "busy" forever if a process failed to start.
    Timer { id: watchdog; interval: 180000; onTriggered: root.busy = false }

    Timer {
        interval: root.cfg.refreshMinutes * 60 * 1000
        repeat: true
        running: root.cfg.autoRefresh
        onTriggered: root.refresh()
    }

    Component.onCompleted: root.refresh()

    // ---- the plugin's own manifest (the About tab shows its version) ----------------
    property var manifest: null
    FileView {
        id: manifestFile
        path: decodeURIComponent(Qt.resolvedUrl("../manifest.json").toString().replace(/^file:\/\//, ""))
        onLoaded: {
            let m = null
            try { m = JSON.parse(root.readText(manifestFile)) } catch (e) { m = null }
            const v = m && typeof m.version === "string" && /^[0-9A-Za-z.+-]{1,32}$/.test(m.version) ? m.version : ""
            root.manifest = { version: v }
        }
    }
    function readText(fv) {
        try { return String(typeof fv.text === "function" ? fv.text() : fv.text) } catch (e) { return "" }
    }

    // ---- the theme's window border ----------------------------------------------------
    // For the Window borders color scheme and the window outline: the active border's
    // colors and angle, from the theme's hyprland.lua (or .conf, or the line some themes
    // keep in colors.toml). Only #rrggbb values and an angle are taken from these files.
    property var tomlBorder: ({ colors: [], angle: 0 })
    property var luaBorder: ({ colors: [], angle: 0 })
    property var confBorder: ({ colors: [], angle: 0 })
    property bool luaMissing: false
    readonly property var borderColors: luaBorder.colors.length > 0 ? luaBorder.colors
        : (confBorder.colors.length > 0 ? confBorder.colors : tomlBorder.colors)
    readonly property real borderAngle: luaBorder.colors.length > 0 ? luaBorder.angle
        : (confBorder.colors.length > 0 ? confBorder.angle : tomlBorder.angle)
    readonly property string themeDir: {
        try { return Color.currentThemePath ? String(Color.currentThemePath) : "" } catch (e) { return "" }
    }

    FileView {
        id: paletteFile
        path: root.themeDir !== "" ? root.themeDir + "/colors.toml" : ""
        watchChanges: true
        onFileChanged: reload()
        onLoaded: root.tomlBorder = Theme.parseBorder(root.readText(paletteFile))
        onLoadFailed: { root.tomlBorder = ({ colors: [], angle: 0 }); root.retryTheme() }
    }
    FileView {
        id: borderLua
        path: root.themeDir !== "" ? root.themeDir + "/hyprland.lua" : ""
        watchChanges: true
        onFileChanged: reload()
        onLoaded: { root.luaMissing = false; root.luaBorder = Theme.parseBorder(root.readText(borderLua)) }
        onLoadFailed: { root.luaBorder = ({ colors: [], angle: 0 }); root.luaMissing = true }
    }
    FileView {
        id: borderConf
        // only looked at when the theme has no hyprland.lua
        path: root.themeDir !== "" && root.luaMissing ? root.themeDir + "/hyprland.conf" : ""
        watchChanges: true
        onFileChanged: reload()
        onPathChanged: if (path === "") root.confBorder = ({ colors: [], angle: 0 })
        onLoaded: root.confBorder = Theme.parseBorder(root.readText(borderConf))
        onLoadFailed: root.confBorder = ({ colors: [], angle: 0 })
    }
    // A theme switch replaces the theme folder, so for a moment the files are gone and
    // the watch can lose track of them: read them again shortly after, a few times at most.
    property int themeTries: 0
    function retryTheme() { if (themeTries < 3) { themeTries++; themeRetry.restart() } }
    Timer {
        id: themeRetry
        interval: 800
        onTriggered: { paletteFile.reload(); borderLua.reload(); borderConf.reload() }
    }
    Connections {
        target: Color
        ignoreUnknownSignals: true
        function onAccentChanged() { root.themeTries = 0; themeRetry.restart() }
        function onBackgroundChanged() { root.themeTries = 0; themeRetry.restart() }
    }

    // ---- clipboard paste (capped, no shell) -------------------------------------------
    // Pasting into a text field never reads the clipboard on the UI thread. wl-paste
    // runs directly (no shell) and its output is read in chunks. Reading stops as soon
    // as 1024 bytes are in, or after 2 seconds, and the process is stopped. The text is
    // then sent back through `pasted`, addressed to the field that asked.
    property string pasteKey: ""
    property string pasteBuf: ""
    readonly property int pasteMax: 1024
    signal pasted(string key, string text)

    function requestPaste(key) {
        if (pasteKey !== "" || pasteProc.running) return   // one paste at a time
        pasteKey = key
        pasteBuf = ""
        pasteProc.running = true
        pasteKill.restart()
    }
    function finishPaste() {
        const k = pasteKey
        if (k === "") return                              // already delivered
        pasteKey = ""
        pasteKill.stop()
        const text = pasteBuf.slice(0, pasteMax)
        pasteBuf = ""
        if (pasteProc.running) pasteProc.running = false  // stop reading the clipboard
        root.pasted(k, text)
    }
    Timer { id: pasteKill; interval: 2000; onTriggered: root.finishPaste() }
    Process {
        id: pasteProc
        running: false
        command: ["wl-paste", "--no-newline"]
        stdout: SplitParser {
            splitMarker: ""
            onRead: function(data) {
                if (root.pasteBuf.length >= root.pasteMax) return
                root.pasteBuf += data
                if (root.pasteBuf.length >= root.pasteMax) root.finishPaste()
            }
        }
        onExited: root.finishPaste()
    }

    // ---- the window: docked to the bar, or popped out ----------------------------------
    // One UiState feeds whichever surface is showing, so the tab, the search and the
    // history filter survive popping out and docking back.
    property bool popped: false
    // Set only by the header's Pop out / Dock buttons. Until then "Open as" decides
    // how the bar button opens, every time, so a change in settings takes effect at once.
    property bool userPicked: false

    // The bar's own colours. Fall back to the shell palette if the bar does not expose them.
    readonly property color barFg: (root.bar && root.bar.barForeground !== undefined)
        ? root.bar.barForeground : (Color.foreground !== undefined ? Color.foreground : "white")
    readonly property color barBg: (root.bar && root.bar.barBackground !== undefined)
        ? root.bar.barBackground : (Color.background !== undefined ? Color.background : "#121217")

    // The shell theme's accent, tried under a few likely names. Unknown names are
    // skipped, and with none found the window falls back to the bar foreground.
    function themeColor(names) {
        for (const name of names) {
            let raw
            try { raw = Color[name] } catch (e) { raw = undefined }
            if (raw === undefined || raw === null) continue
            try {
                const c = Qt.color(raw)
                if (c && c.valid !== false) return c
            } catch (e2) { }
        }
        return null
    }
    readonly property var shellAccent: themeColor(["accent", "primary", "highlight", "accentColor", "color4", "blue"])

    UiState {
        id: ux
        service: root
        themeAccent: root.shellAccent ? root.shellAccent : "transparent"
        store: settingsStore
        cfg: root.cfg
        opened: root.panelOpened || root.windowShown
        popped: root.popped
        barFg: root.barFg
        barBg: root.barBg
        fontName: root.bar && root.bar.fontFamily ? root.bar.fontFamily : Style.font.family
        onPopOutRequested: root.popOut()
        onDockRequested: root.dock()
        onCloseRequested: root.close()
    }

    readonly property bool panelOpened: panelLoader.item ? panelLoader.item.opened === true : false
    readonly property bool windowShown: windowLoader.item ? windowLoader.item.visible === true : false

    // The shell only knows about the bar-panel state.
    readonly property bool opened: panelOpened
    readonly property bool popoutSwitchClosing: panelLoader.item
        ? panelLoader.item.popoutSwitchClosing === true : false

    // Until the header's buttons are used, "Open as" decides.
    function chooseMode() {
        if (userPicked) return
        const want = cfg.openAs === "window"
        if (want === popped) return
        if (windowShown) hideWindow()
        if (panelOpened) closePanel()
        popped = want
    }

    // The window exists exactly while it is wanted. Showing it again after it was
    // closed (by the header, or by the window manager) always creates a fresh one,
    // so a dead window handle can never leave the bar button doing nothing.
    property bool windowRequested: false
    function showWindow() {
        windowRequested = true
        if (windowLoader.item) windowLoader.item.visible = true
    }
    function hideWindow() { windowRequested = false }

    // The window manager closed the window while we still wanted it: forget it, so
    // the next click on the bar button builds a new one.
    Connections {
        target: windowLoader.item
        ignoreUnknownSignals: true
        function onVisibleChanged() {
            if (windowLoader.item && !windowLoader.item.visible && root.windowRequested)
                root.windowRequested = false
        }
    }

    // If the bar panel cannot be shown (Panel.qml failed to load, or the shell never
    // reported it open), show Dev Stats as its own window instead of doing nothing.
    // The reason goes to the shell log (`qs log`).
    property bool wantPanel: false
    function fallbackToWindow(reason) {
        console.warn("dev-stats: " + reason + "; opening as a window instead")
        wantPanel = false
        panelCheck.stop()
        popped = true
        showWindow()
    }
    function openPanel() {
        if (panelLoader.status === Loader.Error || !panelLoader.item) {
            fallbackToWindow("Panel.qml is not loaded (status " + panelLoader.status + ")")
            return
        }
        injectPanel()
        wantPanel = true
        panelLoader.item.open()
        panelCheck.restart()
    }
    function closePanel() {
        wantPanel = false
        panelCheck.stop()
        if (panelLoader.item) panelLoader.item.close()
    }
    function open() {
        chooseMode()
        if (popped) showWindow()
        else openPanel()
    }
    function close() {
        closePanel()
        hideWindow()
    }
    function toggle() {
        chooseMode()
        if (popped) {
            if (windowShown) hideWindow()
            else showWindow()
        } else if (panelOpened) {
            closePanel()
        } else if (!(panelLoader.item && panelLoader.item.justClosedByGrab === true)) {
            openPanel()
        }
    }
    function closeForPopoutSwitch() { if (panelLoader.item) panelLoader.item.closeForPopoutSwitch() }
    function popOut() {
        userPicked = true
        popped = true
        closePanel()
        showWindow()
    }
    function dock() {
        userPicked = true
        hideWindow()
        popped = false
        Qt.callLater(root.openPanel)
    }
    onPanelOpenedChanged: if (panelOpened) { wantPanel = false; panelCheck.stop() }
    Timer {
        id: panelCheck
        interval: 600
        repeat: false
        onTriggered: if (root.wantPanel && !root.panelOpened && !root.popped)
            root.fallbackToWindow("the panel did not open")
    }

    // Open on a tab (or keep it open and switch to it).
    function showTab(name) {
        ux.tabName = name
        open()
    }

    function injectPanel() {
        if (!panelLoader.item) return
        panelLoader.item.bar = root.bar
        panelLoader.item.anchorItem = button
        panelLoader.item.hostWidget = root
        panelLoader.item.ui = ux
    }

    onBarChanged: injectPanel()

    Loader {
        id: panelLoader
        active: true
        source: Qt.resolvedUrl("panel/Panel.qml")
        onLoaded: {
            root.injectPanel()
            Qt.callLater(root.injectPanel)
        }
        onStatusChanged: if (status === Loader.Error)
            console.warn("dev-stats: Panel.qml failed to load; run `qs log` for the QML error")
    }

    // A real, resizable, movable window. Only exists while popped out.
    Loader {
        id: windowLoader
        active: root.windowRequested
        source: Qt.resolvedUrl("panel/PopoutWindow.qml")
        onLoaded: {
            item.ui = ux
            item.visible = root.windowRequested
        }
        onStatusChanged: if (status === Loader.Error)
            console.warn("dev-stats: PopoutWindow.qml failed to load; run `qs log` for the QML error")
    }

    // ---- the bar button --------------------------------------------------------------
    readonly property real square: Style.space(cfg.squareSize)
    readonly property real gap: Style.space(2)
    readonly property real iconW: Style.space(14)

    function act(name) {
        if (name === "panel") { ux.tabName = "grid"; toggle() }
        else if (name === "refresh") refresh()
    }

    // Fixed width: does not depend on the Repeater having populated the Row yet.
    implicitWidth: (cfg.showIcon ? iconW + gap : 0) + cfg.days * square + (cfg.days - 1) * gap + Style.space(16)
    implicitHeight: Math.max(button.implicitHeight, square + Style.space(8))

    // The button supplies hover, tooltip and clicks; the squares are drawn on top
    // and take no mouse input. Only fixed strings go into the button.
    WidgetButton {
        id: button
        anchors.fill: parent
        bar: root.bar
        text: " "
        tooltipText: (root.current
            ? "Last " + root.cfg.days + " days · " + Model.providerLabel(root.current.provider)
            : "Contribution grid") + " (right click for settings)"
        onPressed: function(buttonCode) {
            if (buttonCode === Qt.RightButton || buttonCode === "right") root.showTab("settings")
            else if (buttonCode === Qt.MiddleButton || buttonCode === "middle") root.act(root.cfg.middleAction)
            else root.act(root.cfg.clickAction)
        }
    }

    Row {
        id: squares
        anchors.centerIn: parent
        height: root.height
        spacing: root.gap

        // Icon and squares share the row height and are centered on it, so the
        // whole group sits on the bar's vertical middle.
        Text {
            visible: root.cfg.showIcon
            width: root.iconW
            height: squares.height
            verticalAlignment: Text.AlignVCenter
            horizontalAlignment: Text.AlignHCenter
            text: Model.providerGlyph(root.current ? root.current.provider : "github")
            textFormat: Text.PlainText
            color: root.barFg
            font.family: root.bar && root.bar.fontFamily ? root.bar.fontFamily : Style.font.family
            font.pixelSize: Style.font.subtitle
        }

        Repeater {
            model: root.recent
            Item {
                required property var modelData
                width: root.square
                height: squares.height
                Rectangle {
                    anchors.centerIn: parent
                    width: root.square
                    height: root.square
                    radius: Math.min(root.square / 2, Style.space(root.cfg.squareRound))
                    color: modelData.level <= 0 ? Qt.alpha(root.barFg, 0.18) : root.palette[modelData.level - 1]
                }
            }
        }
    }
}

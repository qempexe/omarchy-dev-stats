import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import "Stats.js" as Model

// Floating settings panel for Dev Stats.
//
//   * Header card: the auto-refresh switch, a status line, Reset all, close.
//   * Four tabs: Grid (accounts, years, the contribution grid), Bar, Data, Look.
//   * Every setting is a SettingRow: plain numbers, friendly option names, a
//     one-line hint, and a reset arrow once it differs from the default.
//     Settings that currently have no effect are dimmed.
//   * Colors: the "Settings panel colors" setting picks the scheme. Follow theme
//     uses the Omarchy theme's accent and background, Custom uses a hex accent,
//     Monochrome is neutral grey. Text always follows the bar foreground.
PopupWindow {
    id: root

    property var store: null
    property var anchorItem: null
    property bool vertical: false             // bar is on the left / right edge
    property color fg: "white"
    property string fontFamily: ""
    property string panelMode: "theme"            // theme | custom | monochrome
    property string panelAccent: "#7aa2f7"        // used by custom
    property var readSetting: null
    property var stats: null                      // BarWidget.qml: accounts, results, refresh()

    property int tab: 0
    property bool confirmReset: false

    // ---- colors --------------------------------------------------------------
    // Look up a color the shell's theme may expose, trying several likely names.
    // Missing names just return undefined, so an unknown theme falls back to the
    // bar foreground instead of breaking.
    function themeColor(names) {
        for (var i = 0; i < names.length; i++) {
            var raw
            try { raw = Color[names[i]] } catch (e) { raw = undefined }
            if (raw === undefined || raw === null) continue
            try {
                var c = Qt.color(raw)
                if (c && c.valid !== false) return c
            } catch (e2) { }
        }
        return null
    }
    function hexColor(text) {
        var t = String(text)
        return /^#([0-9a-fA-F]{6}|[0-9a-fA-F]{8})$/.test(t) ? Qt.color(t) : null
    }
    function luma(c) { return 0.299 * c.r + 0.587 * c.g + 0.114 * c.b }

    readonly property bool lightText: luma(fg) > 0.5
    readonly property var themeAccentColor: themeColor(["accent", "primary", "highlight", "accentColor", "color4", "blue"])
    readonly property var themeBgColor: themeColor(["background", "surface", "base", "bg"])
    readonly property var customAccentColor: hexColor(panelAccent)

    readonly property bool useTheme: panelMode === "theme"
    readonly property bool useCustom: panelMode === "custom"

    // Neutral panel, used by monochrome and custom (and by theme when the shell
    // exposes no background).
    readonly property color neutralBg: lightText ? Qt.rgba(0.07, 0.07, 0.09, 0.97) : Qt.rgba(0.97, 0.97, 0.98, 0.97)
    readonly property color neutralInk: lightText ? Qt.rgba(0.95, 0.95, 0.96, 1) : Qt.rgba(0.10, 0.10, 0.12, 1)

    // ink: text and soft tints.  accent: filled / selected parts.
    readonly property color ink: useTheme ? fg : (useCustom ? fg : neutralInk)
    readonly property color accent: {
        if (useTheme && themeAccentColor) return themeAccentColor
        if (useCustom && customAccentColor) return customAccentColor
        return ink
    }
    readonly property color panelBg: (useTheme && themeBgColor)
        ? Qt.rgba(themeBgColor.r, themeBgColor.g, themeBgColor.b, 0.97) : neutralBg
    // Text on top of an accent fill.
    readonly property color inkOnFg: luma(accent) > 0.55 ? Qt.rgba(0.07, 0.07, 0.09, 1) : Qt.rgba(0.97, 0.97, 0.98, 1)
    readonly property color panelSolid: Qt.rgba(panelBg.r, panelBg.g, panelBg.b, 1)
    function tint(a) { return Qt.rgba(ink.r, ink.g, ink.b, a) }
    function accentTint(a) { return Qt.rgba(accent.r, accent.g, accent.b, a) }

    // ---- placement: never overlap the bar -----------------------------------------
    // Worked out each time the panel is about to open (see toggle()), because the
    // bar's position is not known yet when this file is first loaded.
    //
    // The panel is anchored to the outer edge of the bar's own window (not to the
    // widget, which sits inside the bar's padding), and the gap is transparent
    // padding inside the popup window, so it works whatever the compositor does
    // with anchor margins.
    property var barObject: null              // the shell's bar, used as a hint for its edge
    property bool barAtTop: true              // horizontal bar: top edge (else bottom)
    property bool barAtLeft: true             // vertical bar: left edge (else right)
    property bool useRect: false              // anchor to the bar window's edge
    property var anchorWin: null
    property real rectX: 0
    property real rectY: 0
    property real rectW: 1
    property real rectH: 1
    property real extra: 0                    // extra clearance when only the widget is known
    property real maxHeight: 620
    readonly property int gap: 0              // free space between the bar and the panel (0 = flush)
    readonly property real padTop: (!vertical && barAtTop) ? gap + extra : 0
    readonly property real padBottom: (!vertical && !barAtTop) ? gap + extra : 0
    readonly property real padLeft: (vertical && barAtLeft) ? gap + extra : 0
    readonly property real padRight: (vertical && !barAtLeft) ? gap + extra : 0

    function sideFromText(v) {
        var t = String(v === undefined || v === null ? "" : v).toLowerCase()
        if (t.indexOf("top") >= 0) return "top"
        if (t.indexOf("bottom") >= 0) return "bottom"
        if (t.indexOf("left") >= 0) return "left"
        if (t.indexOf("right") >= 0) return "right"
        return ""
    }

    function locate() {
        var item = root.anchorItem
        if (!item) return
        var scr = item.screen
        var sw = scr ? scr.width : 1920
        var sh = scr ? scr.height : 1080
        var side = ""
        var qsWin = null
        var win = null

        // 1. the bar window knows which edges it is attached to
        try { qsWin = item.QsWindow.window } catch (e0) { qsWin = null }
        try { win = qsWin ? qsWin : item.Window.window } catch (e1) { win = null }
        try {
            var an = win ? win.anchors : null
            if (an) {
                if (root.vertical) {
                    if (an.left && !an.right) side = "left"
                    else if (an.right && !an.left) side = "right"
                } else {
                    if (an.top && !an.bottom) side = "top"
                    else if (an.bottom && !an.top) side = "bottom"
                }
            }
        } catch (e2) { side = "" }

        // 2. the shell's bar object may say it outright
        if (side === "" && root.barObject) {
            var names = ["position", "barPosition", "edge", "side", "location", "placement", "barSide"]
            for (var i = 0; i < names.length && side === ""; i++) {
                var got = ""
                try { got = root.sideFromText(root.barObject[names[i]]) } catch (e3) { got = "" }
                if ((root.vertical && (got === "left" || got === "right"))
                        || (!root.vertical && (got === "top" || got === "bottom")))
                    side = got
            }
        }

        // 3. last resort: which half of the screen (only meaningful when the bar
        //    window is as big as the screen)
        var pos = item.mapToItem(null, 0, 0)
        if (side === "") {
            if (root.vertical) side = pos.x < sw / 2 ? "left" : "right"
            else side = pos.y < sh / 2 ? "top" : "bottom"
        }
        root.barAtTop = side === "top"
        root.barAtLeft = side === "left"

        // Anchor rectangle on the bar window's outer edge (window coordinates).
        var ww = (win && win.width > 0) ? win.width : 0
        var wh = (win && win.height > 0) ? win.height : 0
        var small = root.vertical ? (ww > 0 && ww < sw * 0.5) : (wh > 0 && wh < sh * 0.5)
        root.useRect = !!qsWin && small
        root.anchorWin = qsWin
        if (root.useRect) {
            if (root.vertical) {
                root.rectW = 1
                root.rectH = Math.max(1, item.height)
                root.rectY = pos.y
                root.rectX = side === "left" ? Math.max(0, ww - 1) : 0
            } else {
                root.rectW = Math.max(1, item.width)
                root.rectH = 1
                root.rectX = pos.x
                root.rectY = side === "top" ? Math.max(0, wh - 1) : 0
            }
            root.extra = 0
        } else {
            root.extra = 6                    // only the widget is known: allow a little for bar padding
        }

        // Tallest the panel may be and still fit between the bar and the far edge.
        var thick = (!root.vertical && wh > 0 && wh < sh * 0.5) ? wh : 40
        var room = root.vertical ? sh - 40 : sh - thick - root.gap - root.extra - 16
        root.maxHeight = Math.max(300, Math.min(680, room))
    }

    function toggle() {
        // A click on the widget while the panel is open first closes it as an
        // "outside click" (below); don't let the same click open it again.
        if (!root.visible && Date.now() - root.grabClosedAt < 500) return
        if (!root.visible) root.locate()
        root.visible = !root.visible
    }

    // ---- click outside to close -----------------------------------------------------
    // Hyprland's focus grab reports any click outside the panel. It is created at
    // runtime so a shell without that module simply keeps the X button and Esc.
    property var grab: null
    property double grabClosedAt: 0

    Component.onCompleted: {
        try {
            var g = Qt.createQmlObject(
                'import Quickshell.Hyprland\nHyprlandFocusGrab { }', root, "DevStatsFocusGrab")
            g.windows = [root]
            g.cleared.connect(function() {
                root.grabClosedAt = Date.now()
                root.visible = false
            })
            root.grab = g
        } catch (e) {
            root.grab = null
        }
    }

    // ---- settings --------------------------------------------------------------
    // Item: { key, label, kind, fallback, hint, options?, labels?, presets?,
    //         min?, max?, step?, divisor?, decimals?, maxLength?, when? }
    // `when` is a list of { key, is: [...] }; if any fails the row is dimmed.
    readonly property var tabs: [
        { title: "Grid", kind: "grid", items: [] },
        {
            title: "Bar",
            items: [
                { key: "showIcon", label: "Show platform icon", kind: "bool", fallback: true,
                  hint: "The GitHub, GitLab or Forgejo logo before the squares." },
                { key: "days", label: "Days on the bar", kind: "int", fallback: 7,
                  min: 3, max: 14, step: 1,
                  hint: "How many recent days show as squares." },
                { key: "clickAction", label: "Left click", kind: "enum", fallback: "panel",
                  options: ["panel", "refresh", "none"],
                  labels: { panel: "Open this panel", refresh: "Refresh", none: "Nothing" },
                  hint: "What a left click on the widget does. Right click always opens the settings." },
                { key: "middleAction", label: "Middle click", kind: "enum", fallback: "refresh",
                  options: ["refresh", "panel", "none"],
                  labels: { refresh: "Refresh", panel: "Open this panel", none: "Nothing" },
                  hint: "What a middle click on the widget does." }
            ]
        },
        {
            title: "Data",
            items: [
                { key: "autoRefresh", label: "Refresh automatically", kind: "bool", fallback: true,
                  hint: "Fetch new numbers in the background. Off means only when you ask." },
                { key: "refreshMinutes", label: "Refresh every", kind: "int", fallback: 30,
                  min: 5, max: 240, step: 5,
                  hint: "Minutes between updates. Each one runs your own gh, glab or curl.",
                  when: [{ key: "autoRefresh", is: [true] }] }
            ]
        },
        {
            title: "Look",
            items: [
                { key: "gridColor", label: "Grid color", kind: "color", fallback: "#39d353",
                  presets: ["#39d353", "#58a6ff", "#bc8cff", "#ff6b2c", "#f85149", "#e3b341"],
                  hint: "Color of the busiest days. Quieter days are darker shades of it." },
                { key: "panelColor", label: "Settings panel colors", kind: "scheme", fallback: "theme",
                  options: ["theme", "custom", "monochrome"],
                  labels: { theme: "Follow theme", custom: "Custom", monochrome: "Monochrome" },
                  hint: "Colors of this panel. Follow theme brings in your theme's accent." },
                { key: "panelCustomColor", label: "Panel accent color", kind: "color", fallback: "#7aa2f7",
                  presets: ["#7aa2f7", "#bb9af7", "#7dcfff", "#9ece6a", "#e0af68", "#ff9e64", "#f7768e", "#c0caf5"],
                  hint: "Pick one, or type a hex like #7aa2f7.",
                  when: [{ key: "panelColor", is: ["custom"] }] }
            ]
        }
    ]

    readonly property var defaults: {
        var d = ({})
        for (var t = 0; t < tabs.length; t++)
            for (var i = 0; i < tabs[t].items.length; i++)
                d[tabs[t].items[i].key] = tabs[t].items[i].fallback
        return d
    }

    // ---- what the Grid tab shows (state lives in BarWidget.qml, `stats`) -----------
    readonly property var accounts: stats ? stats.accounts : []
    readonly property var account: stats && accounts.length > stats.selected ? accounts[stats.selected] : null
    readonly property int year: stats ? stats.selectedYear : 0
    readonly property var rolling: stats && account ? stats.results[Model.accountKey(account)] : null
    readonly property var years: rolling && rolling.years ? rolling.years : []
    readonly property var result: stats && account ? stats.results[Model.resultKey(account, year)] : null
    readonly property bool hasData: result !== null && result !== undefined && result.error === undefined
    readonly property var grid: Model.buildGrid(hasData ? result.days : ({}), new Date(), year)
    readonly property var palette: stats ? stats.palette : Model.palette("")
    property string hoverText: ""

    function levelColor(level) {
        if (level <= 0) return root.tint(0.12)
        return root.palette[level - 1]
    }

    function updatedText() {
        if (!stats) return ""
        if (stats.busy) return "Updating\u2026"
        if (stats.updatedAt <= 0) return ""
        return "Updated " + Qt.formatTime(new Date(stats.updatedAt), "HH:mm")
    }

    // Current value: local override, then the shell's setting, then default.
    function val(key) {
        var fb = root.defaults[key]
        var raw = root.store ? root.store.values[key] : undefined
        if (raw !== undefined) return raw
        if (root.readSetting) {
            var s = root.readSetting(key, fb)
            if (s !== undefined && s !== null) return s
        }
        return fb
    }

    function dimmed(item) {
        if (!item.when) return false
        for (var i = 0; i < item.when.length; i++) {
            var c = item.when[i]
            var cur = String(root.val(c.key))
            if (c.is.map(String).indexOf(cur) < 0) return true
        }
        return false
    }

    function setValue(item, v) {
        if (root.store) root.store.set(item.key, v)
    }

    function resetAll() {
        if (!root.store) return
        if (!root.confirmReset) {
            root.confirmReset = true
            confirmTimer.restart()
            return
        }
        root.confirmReset = false
        root.store.resetAll(root.defaults)
    }

    // ---- clipboard paste for text fields ---------------------------------------
    // Native paste is disabled in SettingRow. A paste request runs a fixed command
    // that reads at most `pasteMaxBytes` from the clipboard, and the text is handed
    // back to the row that asked. One paste runs at a time; extra requests are dropped.
    readonly property int pasteMaxBytes: 1024
    property var pasteRow: null
    property var pasteTarget: null

    function requestPaste(row, target) {
        if (pasteProc.running) return
        pasteRow = row
        pasteTarget = target
        pasteProc.running = true
    }

    function finishPaste(raw) {
        var row = pasteRow
        var target = pasteTarget
        pasteRow = null
        pasteTarget = null
        if (!row || !target) return
        try { row.insertPasted(target, raw) } catch (e) { }   // row may have closed mid-paste
    }

    Process {
        id: pasteProc
        running: false
        // Fixed command, no user input. timeout ends a stalled clipboard read;
        // head -c stops wl-paste early, so a huge clipboard never gets fully read.
        command: ["sh", "-c", "timeout 2 wl-paste --no-newline 2>/dev/null | head -c 1024"]
        stdout: StdioCollector {
            id: pasteOut
            onStreamFinished: root.finishPaste(pasteOut.text)
        }
    }

    function stepTab(d) {
        root.tab = (root.tab + d + root.tabs.length) % root.tabs.length
    }

    // What the header says.
    readonly property string statusText: {
        var s = root.stats
        if (!s) return "Starting\u2026"
        if (s.busy) return "Updating\u2026"
        if (!root.account) return "No accounts found. Log in with gh, glab, tea or fj."
        var line = Model.providerLabel(root.account.provider) + " \u00B7 " + root.account.user
        if (s.updatedAt > 0) line += "  \u00B7  updated " + Qt.formatTime(new Date(s.updatedAt), "HH:mm")
        if (root.val("autoRefresh") !== true) line += "  \u00B7  auto-refresh off"
        return line
    }

    // Small switch, drawn from plain items. Colors come in as properties.
    component Sw: Rectangle {
        id: sw
        property bool on: false
        property color ink: "white"
        property color accent: "white"
        property color knob: "black"
        signal flipped()
        implicitWidth: 34
        implicitHeight: 18
        radius: 9
        color: on ? accent : Qt.rgba(ink.r, ink.g, ink.b, 0.18)
        Behavior on color { ColorAnimation { duration: 100 } }
        Rectangle {
            width: 12; height: 12; radius: 6
            y: 3
            x: sw.on ? sw.width - width - 3 : 3
            color: sw.on ? sw.knob : sw.ink
            opacity: sw.on ? 1 : 0.7
            Behavior on x { NumberAnimation { duration: 100 } }
        }
        MouseArea { anchors.fill: parent; cursorShape: Qt.PointingHandCursor; onClicked: sw.flipped() }
    }

    // ---- window geometry -------------------------------------------------------
    visible: false
    color: "transparent"
    implicitWidth: 640 + root.padLeft + root.padRight
    implicitHeight: Math.min(root.maxHeight, mainCol.implicitHeight + 28) + root.padTop + root.padBottom

    anchor.item: root.useRect ? null : root.anchorItem
    anchor.window: root.useRect ? root.anchorWin : null
    anchor.rect.x: root.rectX
    anchor.rect.y: root.rectY
    anchor.rect.width: root.rectW
    anchor.rect.height: root.rectH
    // The panel opens on the side of the anchor facing away from the bar.
    anchor.edges: root.vertical ? (root.barAtLeft ? Edges.Right : Edges.Left)
                                : (root.barAtTop ? Edges.Bottom : Edges.Top)
    anchor.gravity: root.vertical ? (root.barAtLeft ? Edges.Right : Edges.Left)
                                  : (root.barAtTop ? Edges.Bottom : Edges.Top)
    // Only slide along the bar, never across it, so the panel can't be pushed onto the bar.
    anchor.adjustment: root.vertical ? PopupAdjustment.SlideY : PopupAdjustment.SlideX

    onVisibleChanged: {
        if (!visible) root.confirmReset = false
        if (root.grab) Qt.callLater(function() { root.grab.active = root.visible })
    }

    Timer { id: confirmTimer; interval: 2500; onTriggered: root.confirmReset = false }

    Shortcut {
        sequence: "Escape"
        context: Qt.WindowShortcut
        onActivated: root.visible = false
    }
    Shortcut {
        sequence: "Alt+Right"
        context: Qt.WindowShortcut
        onActivated: root.stepTab(1)
    }
    Shortcut {
        sequence: "Alt+Left"
        context: Qt.WindowShortcut
        onActivated: root.stepTab(-1)
    }

    Rectangle {
        anchors.fill: parent
        anchors.topMargin: root.padTop
        anchors.bottomMargin: root.padBottom
        anchors.leftMargin: root.padLeft
        anchors.rightMargin: root.padRight
        color: root.panelBg
        border.color: root.tint(0.14)
        border.width: 1
        radius: 12
        clip: true

        ColumnLayout {
            id: mainCol
            anchors.fill: parent
            anchors.margins: 14
            spacing: 12

            // ---- header: status, master switch, reset, close -----------------------
            Rectangle {
                Layout.fillWidth: true
                implicitHeight: headerRow.implicitHeight + 24
                radius: 10
                color: root.tint(0.05)
                border.width: 1
                border.color: root.tint(0.08)

                RowLayout {
                    id: headerRow
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 12

                    Sw {
                        Layout.alignment: Qt.AlignVCenter
                        ink: root.ink
                        accent: root.accent
                        knob: root.inkOnFg
                        on: root.val("autoRefresh") === true
                        onFlipped: root.store.set("autoRefresh", !(root.val("autoRefresh") === true))
                    }

                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 2
                        Text {
                            textFormat: Text.PlainText  // names come from other programs: never auto-detect rich text
                            Layout.fillWidth: true
                            text: "Dev Stats"
                            color: root.ink
                            font.family: root.fontFamily
                            font.pixelSize: 11
                            font.weight: Font.DemiBold
                            elide: Text.ElideRight
                        }
                        Text {
                            textFormat: Text.PlainText  // names come from other programs: never auto-detect rich text
                            Layout.fillWidth: true
                            text: root.statusText
                            color: root.ink
                            opacity: 0.6
                            font.family: root.fontFamily
                            font.pixelSize: 9
                            elide: Text.ElideRight
                        }
                    }

                    // reset (asks twice) + close
                    Rectangle {
                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: resetLabel.implicitWidth + 16
                        implicitHeight: 24
                        radius: 6
                        color: root.confirmReset ? root.accent
                            : (resetArea.containsMouse ? root.tint(0.16) : root.tint(0.08))
                        Behavior on color { ColorAnimation { duration: 100 } }
                        Text {
                            textFormat: Text.PlainText
                            id: resetLabel
                            anchors.centerIn: parent
                            text: root.confirmReset ? "Really reset?" : "Reset all"
                            color: root.confirmReset ? root.inkOnFg : root.ink
                            font.family: root.fontFamily
                            font.pixelSize: 9
                        }
                        MouseArea {
                            id: resetArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.resetAll()
                        }
                    }
                    Rectangle {
                        Layout.alignment: Qt.AlignVCenter
                        implicitWidth: 24; implicitHeight: 24; radius: 6
                        color: closeArea.containsMouse ? root.tint(0.16) : root.tint(0.08)
                        Text {
                            textFormat: Text.PlainText
                            anchors.centerIn: parent
                            text: "\u00D7"
                            color: root.ink
                            font.pixelSize: 15
                        }
                        MouseArea {
                            id: closeArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.visible = false
                        }
                    }
                }
            }

            // ---- tabs --------------------------------------------------------------
            Item {
                Layout.fillWidth: true
                implicitHeight: 30

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 1
                    color: root.tint(0.10)
                }

                RowLayout {
                    anchors.fill: parent
                    spacing: 0

                    Repeater {
                        model: root.tabs
                        delegate: Item {
                            readonly property bool on: index === root.tab
                            Layout.fillWidth: true
                            Layout.preferredWidth: 1
                            Layout.fillHeight: true

                            Text {
                                textFormat: Text.PlainText
                                anchors.centerIn: parent
                                anchors.verticalCenterOffset: -1
                                text: modelData.title
                                color: root.ink
                                opacity: parent.on ? 1.0 : (tabArea.containsMouse ? 0.8 : 0.5)
                                font.family: root.fontFamily
                                font.pixelSize: 10
                                font.weight: parent.on ? Font.DemiBold : Font.Normal
                            }
                            Rectangle {
                                visible: parent.on
                                anchors.left: parent.left
                                anchors.right: parent.right
                                anchors.bottom: parent.bottom
                                height: 2
                                radius: 1
                                color: root.accent
                            }
                            MouseArea {
                                id: tabArea
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: root.tab = index
                            }
                        }
                    }
                }
            }

            // ---- settings of the active tab ------------------------------------------
            Flickable {
                id: flick
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.preferredHeight: card.implicitHeight
                contentWidth: width
                contentHeight: card.implicitHeight
                clip: true
                boundsBehavior: Flickable.StopAtBounds

                Rectangle {
                    id: card
                    width: flick.width
                    implicitHeight: rows.implicitHeight + 8
                    radius: 10
                    color: root.tint(0.035)
                    border.width: 1
                    border.color: root.tint(0.07)

                    ColumnLayout {
                        id: rows
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.leftMargin: 14
                        anchors.rightMargin: 14
                        anchors.topMargin: 4
                        spacing: 0

                        // ---- Grid tab ------------------------------------------------
                        ColumnLayout {
                            visible: root.tabs[root.tab].kind === "grid"
                            Layout.fillWidth: true
                            Layout.topMargin: 12
                            Layout.bottomMargin: 12
                            spacing: 10

                            Text {
                                textFormat: Text.PlainText
                                Layout.fillWidth: true
                                visible: root.accounts.length === 0
                                text: root.stats && root.stats.busy
                                    ? "Looking for logged-in accounts\u2026"
                                    : "No accounts found. Log in from a terminal, then middle-click the widget:\n\n"
                                      + "  gh auth login\n  glab auth login\n  tea login add     (or: fj auth login)\n\n"
                                      + "Or list accounts in ~/.config/dev-stats/accounts.json"
                                color: root.ink
                                opacity: 0.7
                                font.family: root.fontFamily
                                font.pixelSize: 9
                                wrapMode: Text.Wrap
                            }

                            // account tabs
                            Flow {
                                Layout.fillWidth: true
                                spacing: 6
                                visible: root.accounts.length > 0

                                Repeater {
                                    model: root.accounts
                                    delegate: Rectangle {
                                        id: acct
                                        required property var modelData
                                        required property int index
                                        readonly property bool on: root.stats && root.stats.selected === index
                                        implicitWidth: acctLabel.implicitWidth + 16
                                        implicitHeight: acctLabel.implicitHeight + 10
                                        radius: 6
                                        color: on ? root.accentTint(0.2) : root.tint(0.06)
                                        border.width: on ? 1 : 0
                                        border.color: root.accent
                                        Text {
                                            id: acctLabel
                                            anchors.centerIn: parent
                                            // Account names are remote data: plain text only, never markup.
                                            textFormat: Text.PlainText
                                            text: Model.providerLabel(acct.modelData.provider) + " \u00B7 " + acct.modelData.user
                                            color: root.ink
                                            font.family: root.fontFamily
                                            font.pixelSize: 9
                                            font.weight: acct.on ? Font.DemiBold : Font.Normal
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: if (root.stats) root.stats.selectAccount(acct.index)
                                        }
                                    }
                                }
                            }

                            // year chips
                            Flow {
                                Layout.fillWidth: true
                                spacing: 6
                                visible: root.years.length > 0

                                Repeater {
                                    model: [0].concat(root.years)
                                    delegate: Rectangle {
                                        id: chip
                                        required property var modelData
                                        readonly property bool on: root.year === modelData
                                        implicitWidth: chipLabel.implicitWidth + 14
                                        implicitHeight: chipLabel.implicitHeight + 8
                                        radius: 6
                                        color: on ? root.accentTint(0.2) : root.tint(0.06)
                                        border.width: on ? 1 : 0
                                        border.color: root.accent
                                        Text {
                                            id: chipLabel
                                            anchors.centerIn: parent
                                            textFormat: Text.PlainText
                                            text: chip.modelData === 0 ? "Last year" : String(chip.modelData)
                                            color: root.ink
                                            font.family: root.fontFamily
                                            font.pixelSize: 9
                                            font.weight: chip.on ? Font.DemiBold : Font.Normal
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            cursorShape: Qt.PointingHandCursor
                                            onClicked: if (root.stats) root.stats.selectYear(chip.modelData)
                                        }
                                    }
                                }
                            }

                            // summary or status
                            Text {
                                textFormat: Text.PlainText
                                Layout.fillWidth: true
                                visible: root.accounts.length > 0
                                text: root.hasData
                                    ? Model.summaryLine(root.grid)
                                    : (root.result ? Model.errorText(root.result.error) : "Loading\u2026")
                                color: root.ink
                                font.family: root.fontFamily
                                font.pixelSize: 10
                                font.weight: Font.DemiBold
                                wrapMode: Text.Wrap
                            }

                            // the grid: one column per week, Sunday on top
                            Item {
                                id: gridBox
                                Layout.fillWidth: true
                                Layout.preferredHeight: monthRow + 7 * (cell + gap)
                                visible: root.hasData

                                readonly property real lw: 28
                                readonly property real gap: 2
                                readonly property real monthRow: 14
                                readonly property real cell: Math.max(4, Math.min(11,
                                    (width - lw - (root.grid.cols.length - 1) * gap) / Math.max(1, root.grid.cols.length)))

                                Repeater {
                                    model: root.grid.months
                                    delegate: Text {
                                        required property var modelData
                                        x: gridBox.lw + modelData.col * (gridBox.cell + gridBox.gap)
                                        y: 0
                                        textFormat: Text.PlainText
                                        text: modelData.label
                                        color: root.ink
                                        opacity: 0.6
                                        font.family: root.fontFamily
                                        font.pixelSize: 8
                                    }
                                }

                                Repeater {
                                    model: [{ row: 1, label: "Mon" }, { row: 3, label: "Wed" }, { row: 5, label: "Fri" }]
                                    delegate: Text {
                                        required property var modelData
                                        y: gridBox.monthRow + modelData.row * (gridBox.cell + gridBox.gap) + (gridBox.cell - implicitHeight) / 2
                                        textFormat: Text.PlainText
                                        text: modelData.label
                                        color: root.ink
                                        opacity: 0.6
                                        font.family: root.fontFamily
                                        font.pixelSize: 8
                                    }
                                }

                                Row {
                                    x: gridBox.lw
                                    y: gridBox.monthRow
                                    spacing: gridBox.gap

                                    Repeater {
                                        model: root.grid.cols
                                        delegate: Column {
                                            id: week
                                            required property var modelData
                                            spacing: gridBox.gap

                                            Repeater {
                                                model: week.modelData
                                                delegate: Rectangle {
                                                    id: day
                                                    required property var modelData
                                                    width: gridBox.cell
                                                    height: gridBox.cell
                                                    radius: 2
                                                    color: root.levelColor(modelData.level)
                                                    opacity: modelData.skip ? 0 : 1

                                                    MouseArea {
                                                        anchors.fill: parent
                                                        hoverEnabled: !day.modelData.skip
                                                        onEntered: root.hoverText = Model.describe(day.modelData)
                                                        onExited: root.hoverText = ""
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }

                            // legend
                            Row {
                                Layout.leftMargin: gridBox.lw
                                spacing: 4
                                visible: root.hasData

                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    textFormat: Text.PlainText
                                    text: "Less"
                                    color: root.ink
                                    opacity: 0.6
                                    font.family: root.fontFamily
                                    font.pixelSize: 8
                                }
                                Repeater {
                                    model: 5
                                    delegate: Rectangle {
                                        required property int index
                                        anchors.verticalCenter: parent.verticalCenter
                                        width: gridBox.cell
                                        height: gridBox.cell
                                        radius: 2
                                        color: root.levelColor(index)
                                    }
                                }
                                Text {
                                    anchors.verticalCenter: parent.verticalCenter
                                    textFormat: Text.PlainText
                                    text: "More"
                                    color: root.ink
                                    opacity: 0.6
                                    font.family: root.fontFamily
                                    font.pixelSize: 8
                                }
                            }

                            // hover details or update time, and Refresh
                            RowLayout {
                                Layout.fillWidth: true
                                spacing: 8

                                Text {
                                    textFormat: Text.PlainText
                                    Layout.fillWidth: true
                                    text: root.hoverText !== "" ? root.hoverText : root.updatedText()
                                    elide: Text.ElideRight
                                    color: root.ink
                                    opacity: 0.6
                                    font.family: root.fontFamily
                                    font.pixelSize: 8
                                }
                                Text {
                                    textFormat: Text.PlainText
                                    text: "Refresh"
                                    color: root.ink
                                    font.family: root.fontFamily
                                    font.pixelSize: 8
                                    font.underline: true
                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: if (root.stats) root.stats.refresh()
                                    }
                                }
                            }
                        }

                        Repeater {
                            model: root.tabs[root.tab].items

                            delegate: ColumnLayout {
                                Layout.fillWidth: true
                                spacing: 0

                                Rectangle {
                                    visible: index > 0
                                    Layout.fillWidth: true
                                    implicitHeight: 1
                                    color: root.tint(0.07)
                                }

                                SettingRow {
                                    id: settingRow
                                    Layout.fillWidth: true
                                    Layout.topMargin: 12
                                    Layout.bottomMargin: 12

                                    label: modelData.label
                                    hint: modelData.hint || ""
                                    kind: modelData.kind
                                    options: modelData.options || []
                                    labels: modelData.labels || ({})
                                    presets: modelData.presets || []
                                    maxLength: modelData.maxLength !== undefined ? modelData.maxLength : 256
                                    min: modelData.min !== undefined ? modelData.min : 0
                                    max: modelData.max !== undefined ? modelData.max : 100
                                    step: modelData.step !== undefined ? modelData.step : 1
                                    divisor: modelData.divisor !== undefined ? modelData.divisor : 1
                                    decimals: modelData.decimals !== undefined ? modelData.decimals : 0
                                    defaultValue: modelData.fallback
                                    dimmed: root.dimmed(modelData)
                                    value: root.val(modelData.key)

                                    fg: root.ink
                                    accent: root.accent
                                    bg: root.inkOnFg
                                    panel: root.panelSolid
                                    barFg: root.fg
                                    fontFamily: root.fontFamily
                                    schemeAccent: root.themeAccentColor ? root.themeAccentColor : root.accent
                                    schemeBg: root.themeBgColor ? root.themeBgColor : root.panelSolid
                                    schemeCustom: root.customAccentColor ? root.customAccentColor : root.accent
                                    schemeNeutral: Qt.rgba(root.neutralBg.r, root.neutralBg.g, root.neutralBg.b, 1)
                                    schemeMono: root.neutralInk

                                    onEdited: function(v) { root.setValue(modelData, v) }
                                    onClipboardPaste: function(target, maxBytes) { root.requestPaste(settingRow, target) }
                                }
                            }
                        }
                    }
                }
            }

            // ---- footer ----------------------------------------------------------------
            RowLayout {
                Layout.fillWidth: true
                spacing: 6

                Rectangle {
                    implicitWidth: escLabel.implicitWidth + 10
                    implicitHeight: 16
                    radius: 4
                    color: root.tint(0.08)
                    Text {
                        textFormat: Text.PlainText
                        id: escLabel
                        anchors.centerIn: parent
                        text: "Esc"
                        color: root.ink
                        opacity: 0.75
                        font.family: root.fontFamily
                        font.pixelSize: 8
                    }
                }
                Text {
                    textFormat: Text.PlainText
                    text: "close"
                    color: root.ink
                    opacity: 0.45
                    font.family: root.fontFamily
                    font.pixelSize: 8
                }
                Item { Layout.fillWidth: true }
                Text {
                    textFormat: Text.PlainText
                    text: "Changes apply instantly"
                    color: root.ink
                    opacity: 0.45
                    font.family: root.fontFamily
                    font.pixelSize: 8
                }
            }
        }
    }
}

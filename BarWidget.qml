import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Stats.js" as Model

BarWidget {
  id: root
  moduleName: "io.github.qempexe.dev-stats"

  // ---- shared state (read by SettingsPopup.qml through `stats`) -----------
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
    String(Qt.resolvedUrl("bin/dev-stats.sh")).replace(/^file:\/\//, ""))

  readonly property var current: accounts.length > selected ? accounts[selected] : null

  // ---- settings: the popup's own edits (store) win over the shell's setting() ----
  SettingsStore { id: settingsStore }

  function v(key, fallback) {
    var o = settingsStore.values[key]
    return o !== undefined ? o : fallback
  }
  function clampInt(x, lo, hi, fb) {
    var n = Math.round(Number(x))
    return isFinite(n) ? Math.max(lo, Math.min(hi, n)) : fb
  }

  readonly property bool cfgShowIcon: v("showIcon", setting("showIcon", true)) !== false
  readonly property int cfgDays: clampInt(v("days", setting("days", 7)), 3, 14, 7)
  readonly property string cfgClick: String(v("clickAction", setting("clickAction", "panel")))
  readonly property string cfgMiddle: String(v("middleAction", setting("middleAction", "refresh")))
  readonly property bool cfgAuto: v("autoRefresh", setting("autoRefresh", true)) !== false
  readonly property int cfgMinutes: clampInt(v("refreshMinutes", setting("refreshMinutes", 30)), 5, 240, 30)
  readonly property string gridColor: Model.validColor(String(v("gridColor", setting("gridColor", Model.DEFAULT_COLOR))))
  readonly property string panelMode: String(v("panelColor", setting("panelColor", "theme")))
  readonly property string panelAccent: String(v("panelCustomColor", setting("panelCustomColor", "#7aa2f7")))
  readonly property var palette: Model.palette(gridColor)

  // Newest `n` visible cells of the grid, oldest first.
  function lastDays(grid, n) {
    var out = []
    for (var c = grid.cols.length - 1; c >= 0 && out.length < n; c--)
      for (var r = 6; r >= 0 && out.length < n; r--)
        if (!grid.cols[c][r].skip) out.unshift(grid.cols[c][r])
    return out
  }

  readonly property var dsRecent: {
    var res = current ? results[Model.accountKey(current)] : null
    var days = (res && !res.error) ? lastDays(Model.buildGrid(res.days, new Date()), cfgDays) : []
    while (days.length < cfgDays) days.unshift({ level: 0, count: 0 })
    return days
  }
  readonly property color dsFg: fgProbe.item ? fgProbe.item.barForeground : "#cccccc"
  readonly property real dsSquare: Style.space(9)
  readonly property real dsGap: Style.space(2)
  readonly property real dsIcon: Style.space(14)
  readonly property bool isVertical: {
    var b = root.bar
    if (!b) return false
    try { return b.vertical === true || b.isVertical === true } catch (e) { return false }
  }

  readonly property bool opened: popup.visible
  readonly property bool popoutSwitchClosing: false

  function open() { if (!popup.visible) popup.toggle() }
  function close() { popup.visible = false }
  function toggle() { popup.toggle() }
  function closeForPopoutSwitch() { popup.visible = false }

  function act(name) {
    if (name === "panel") toggle()
    else if (name === "refresh") refresh()
  }

  function openSettings() {
    popup.tab = 1                       // the Bar tab
    if (!popup.visible) popup.toggle()
  }

  function injectBar() {
    if (fgProbe.item) fgProbe.item.bar = root.bar
  }

  // ---- refresh pipeline: list accounts, then fetch each one in turn -------
  function refresh() {
    if (busy) return
    busy = true
    var keep = {}
    for (var k in results) if (k.split("|").length === 3) keep[k] = results[k]
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

  // ---- account / year selection (called from SettingsPopup.qml) ------------
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
    var a = yearRunning.account
    yearProc.command = ["bash", scriptPath, "fetch", a.provider, a.host, a.user, String(yearRunning.year)]
    yearProc.running = true
  }

  function onYearFetched(text) {
    var q = yearRunning
    yearRunning = null
    if (q) {
      var next = Object.assign({}, results)
      next[Model.resultKey(q.account, q.year)] = Model.parseResult(text)
      results = next
    }
    if (yearReq) yearTimer.restart()
  }

  function fetchNext() {
    if (fetchProc.running) { stepTimer.restart(); return }
    if (fetchIndex >= accounts.length) { finish(); return }
    var a = accounts[fetchIndex]
    fetchProc.command = ["bash", scriptPath, "fetch", a.provider, a.host, a.user]
    fetchProc.running = true
  }

  function onAccounts(text) {
    var list = Model.parseAccounts(text)
    accounts = list
    if (selected >= list.length) selected = 0
    fetchIndex = 0
    stepTimer.restart()
  }

  function onFetched(text) {
    var a = accounts[fetchIndex]
    if (a) {
      var next = Object.assign({}, results)
      next[Model.accountKey(a)] = Model.parseResult(text)
      results = next
    }
    fetchIndex++
    stepTimer.restart()
  }

  // ---- one-time move of the color saved by 1.1.x (~/.config/dev-stats/color) ----
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

  Process {
    id: loadColorProc
    command: ["bash", "-c", 'cat "${XDG_CONFIG_HOME:-$HOME/.config}/dev-stats/color" 2>/dev/null || true']
    stdout: StdioCollector {
      onStreamFinished: {
        var t = text.trim()
        if (/^#[0-9a-fA-F]{6}$/.test(t)) { root.legacyColor = t; root.migrateLegacyColor() }
      }
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
    interval: root.cfgMinutes * 60 * 1000
    repeat: true
    running: root.cfgAuto
    onTriggered: root.refresh()
  }

  Component.onCompleted: {
    loadColorProc.running = true
    root.refresh()
  }

  // Fixed width: does not depend on the Repeater having populated the Row yet.
  implicitWidth: (cfgShowIcon ? dsIcon + dsGap : 0) + cfgDays * dsSquare + (cfgDays - 1) * dsGap + Style.space(16)
  implicitHeight: Math.max(button.implicitHeight, dsSquare + Style.space(8))

  onBarChanged: injectBar()

  // Only supplies the bar's foreground color (see Foreground.qml).
  Loader {
    id: fgProbe
    active: true
    source: Qt.resolvedUrl("Foreground.qml")
    visible: false
    onLoaded: {
      root.injectBar()
      Qt.callLater(root.injectBar)
    }
  }

  SettingsPopup {
    id: popup
    store: settingsStore
    stats: root
    anchorItem: button
    barObject: root.bar
    vertical: root.isVertical
    fg: root.dsFg
    fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
    panelMode: root.panelMode
    panelAccent: root.panelAccent
    readSetting: function(key, fallback) { return root.setting(key, fallback) }
  }

  // The button supplies hover, tooltip and clicks; the squares are drawn on top
  // and take no mouse input. Only fixed strings go into the button.
  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: " "
    tooltipText: (root.current
      ? "Last " + root.cfgDays + " days \u00b7 " + Model.providerLabel(root.current.provider)
      : "Contribution grid") + " (right-click for settings)"
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton) root.act(root.cfgClick)
      else if (buttonCode === Qt.MiddleButton) root.act(root.cfgMiddle)
      else if (buttonCode === Qt.RightButton) root.openSettings()
    }
  }

  Row {
    id: squares
    anchors.centerIn: parent
    height: root.height
    spacing: root.dsGap

    // Icon and squares share the row height and are centered on it, so the
    // whole group sits on the bar's vertical middle.
    Text {
      visible: root.cfgShowIcon
      width: root.dsIcon
      height: squares.height
      verticalAlignment: Text.AlignVCenter
      horizontalAlignment: Text.AlignHCenter
      text: Model.providerGlyph(root.current ? root.current.provider : "github")
      textFormat: Text.PlainText
      color: root.dsFg
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Style.font.subtitle
    }

    Repeater {
      model: root.dsRecent

      Item {
        required property var modelData
        width: root.dsSquare
        height: squares.height

        Rectangle {
          anchors.centerIn: parent
          width: root.dsSquare
          height: root.dsSquare
          radius: Style.space(2)
          color: modelData.level <= 0
            ? Qt.alpha(root.dsFg, 0.18)
            : root.palette[modelData.level - 1]
        }
      }
    }
  }
}

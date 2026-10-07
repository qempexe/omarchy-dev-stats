import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Stats.js" as Model

BarWidget {
  id: root
  moduleName: "io.github.qempexe.dev-stats"

  // ---- shared state (read by Panel.qml through `store`) -------------------
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
  // Grid color, picked in the panel and saved to ~/.config/dev-stats/color.
  property string gridColor: Model.DEFAULT_COLOR
  readonly property var palette: Model.palette(gridColor)
  // Last 7 days (today last) for the bar squares; dim placeholders until data arrives.
  // Newest `n` visible cells of the grid, oldest first. Built here from
  // grid.cols only, so the bar does not depend on any newer helper in Stats.js.
  function lastDays(grid, n) {
    var out = []
    for (var c = grid.cols.length - 1; c >= 0 && out.length < n; c--)
      for (var r = 6; r >= 0 && out.length < n; r--)
        if (!grid.cols[c][r].skip) out.unshift(grid.cols[c][r])
    return out
  }

  readonly property var dsRecent: {
    var res = current ? results[Model.accountKey(current)] : null
    var days = (res && !res.error) ? lastDays(Model.buildGrid(res.days, new Date()), 7) : []
    while (days.length < 7) days.unshift({ level: 0, count: 0 })
    return days
  }
  readonly property color dsFg: panelLoader.item ? panelLoader.item.barForeground : "#cccccc"
  readonly property real dsSquare: Style.space(9)
  readonly property real dsGap: Style.space(2)
  readonly property real dsIcon: Style.space(14)

  readonly property bool opened: panelLoader.item
    ? panelLoader.item.opened === true
    : false
  readonly property bool popoutSwitchClosing: panelLoader.item
    ? panelLoader.item.popoutSwitchClosing === true
    : false

  function setGridColor(value) {
    var c = Model.validColor(value)
    gridColor = c
    saveColorProc.command = ["bash", "-c",
      'd="${XDG_CONFIG_HOME:-$HOME/.config}/dev-stats"; mkdir -p "$d" && printf "%s\\n" "$1" > "$d/color"',
      "_", c]
    saveColorProc.running = true
  }

  function open() {
    if (panelLoader.item) panelLoader.item.open()
  }

  function close() {
    if (panelLoader.item) panelLoader.item.close()
  }

  function toggle() {
    if (panelLoader.item) panelLoader.item.toggle()
  }

  function closeForPopoutSwitch() {
    if (panelLoader.item) panelLoader.item.closeForPopoutSwitch()
  }

  function injectPanel() {
    if (!panelLoader.item) return
    panelLoader.item.bar = root.bar
    panelLoader.item.anchorItem = button
    panelLoader.item.hostWidget = root
    panelLoader.item.store = root
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

  // ---- account / year selection (called from Panel.qml) --------------------
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

  Process { id: saveColorProc }

  Process {
    id: loadColorProc
    command: ["bash", "-c", 'cat "${XDG_CONFIG_HOME:-$HOME/.config}/dev-stats/color" 2>/dev/null || true']
    stdout: StdioCollector { onStreamFinished: root.gridColor = Model.validColor(text.trim()) }
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
    interval: 30 * 60 * 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Component.onCompleted: loadColorProc.running = true

  // Fixed width: does not depend on the Repeater having populated the Row yet.
  implicitWidth: dsIcon + 7 * dsSquare + 7 * dsGap + Style.space(16)
  implicitHeight: Math.max(button.implicitHeight, dsSquare + Style.space(8))

  onBarChanged: injectPanel()

  Loader {
    id: panelLoader
    active: true
    source: Qt.resolvedUrl("Panel.qml")
    visible: false
    onLoaded: {
      root.injectPanel()
      Qt.callLater(root.injectPanel)
    }
  }

  // The button supplies hover, tooltip and clicks; the squares are drawn on top
  // and take no mouse input. Only fixed strings go into the button.
  WidgetButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: " "
    tooltipText: root.current
      ? "Last 7 days \u00b7 " + Model.providerLabel(root.current.provider) + " (middle-click to refresh)"
      : "Contribution grid (middle-click to refresh)"
    onPressed: function(buttonCode) {
      if (buttonCode === Qt.LeftButton) root.toggle()
      else if (buttonCode === Qt.MiddleButton) root.refresh()
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

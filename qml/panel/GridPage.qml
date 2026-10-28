import QtQuick
import QtQuick.Layouts
import "../controls"
import "../js/Stats.js" as Model

// The Grid tab: the accounts, the years, and the contribution grid with its
// streaks. What it shows lives in BarWidget.qml (`ui.service`).
Flickable {
    id: root

    property var ui: null
    readonly property var stats: ui ? ui.service : null
    readonly property var cfg: ui.cfgSafe

    readonly property var accounts: stats ? stats.accounts : []
    readonly property var account: stats && accounts.length > stats.selected ? accounts[stats.selected] : null
    readonly property int year: stats ? stats.selectedYear : 0
    readonly property var rolling: stats && account ? stats.results[Model.accountKey(account)] : null
    readonly property var years: rolling && rolling.years ? rolling.years : []
    readonly property var result: stats && account ? stats.results[Model.resultKey(account, year)] : null
    readonly property bool hasData: result !== null && result !== undefined && result.error === undefined
    readonly property var grid: Model.buildGrid(hasData ? result.days : ({}), new Date(), year)
    readonly property var palette: Model.palette(cfg.gridColor)
    property string hoverText: ""
    readonly property int activeDays: {
        let n = 0
        for (const c of grid.flat) if (c.count > 0) n++
        return n
    }

    function levelColor(level) { return level <= 0 ? ui.tint(0.12) : root.palette[level - 1] }

    clip: true
    boundsBehavior: Flickable.StopAtBounds
    contentWidth: width
    contentHeight: col.implicitHeight + ui.px(8)

    ColumnLayout {
        id: col
        width: root.width
        spacing: ui.px(10)

        // nothing logged in yet
        Rectangle {
            Layout.fillWidth: true
            visible: root.accounts.length === 0
            implicitHeight: emptyCol.implicitHeight + ui.px(24)
            radius: ui.r(2.5)
            color: ui.cardFill(false)
            border.width: ui.cardBorder
            border.color: ui.tint(0.12)
            ColumnLayout {
                id: emptyCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: ui.px(12)
                spacing: ui.px(8)
                Txt {
                    ui: root.ui
                    Layout.fillWidth: true
                    text: root.stats && root.stats.busy ? "Looking for logged-in accounts…" : "No accounts found yet."
                    font.pixelSize: ui.fs(12)
                    font.weight: Font.DemiBold
                    wrapMode: Text.Wrap
                }
                Txt {
                    ui: root.ui
                    Layout.fillWidth: true
                    visible: !(root.stats && root.stats.busy)
                    text: "Log in from a terminal with the platform's own tool, then press Refresh:\n\n"
                        + "  gh auth login\n  glab auth login\n  tea login add     (or: fj auth login)\n\n"
                        + "Or list accounts in ~/.config/dev-stats/accounts.json."
                    opacity: 0.7
                    wrapMode: Text.Wrap
                }
            }
        }

        // the accounts
        Flow {
            Layout.fillWidth: true
            spacing: ui.px(6)
            visible: root.accounts.length > 1
            Repeater {
                model: root.accounts
                delegate: Chip {
                    required property var modelData
                    required property int index
                    ui: root.ui
                    // account names are remote data: Chip draws plain text only
                    label: Model.providerLabel(modelData.provider) + " · " + modelData.user
                    on: !!root.stats && root.stats.selected === index
                    onClicked: root.stats.selectAccount(index)
                }
            }
        }

        // the years
        Flow {
            Layout.fillWidth: true
            spacing: ui.px(6)
            visible: root.years.length > 0
            Repeater {
                model: [0].concat(root.years)
                delegate: Chip {
                    required property var modelData
                    ui: root.ui
                    label: modelData === 0 ? "Last year" : String(modelData)
                    on: root.year === modelData
                    onClicked: root.stats.selectYear(modelData)
                }
            }
        }

        // the grid card
        Rectangle {
            Layout.fillWidth: true
            visible: root.accounts.length > 0
            implicitHeight: gridCol.implicitHeight + ui.px(24)
            radius: ui.r(2.5)
            color: ui.cardFill(false)
            border.width: ui.cardBorder
            border.color: ui.tint(0.12)

            ColumnLayout {
                id: gridCol
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: ui.px(12)
                spacing: ui.px(10)

                // the total and the streaks, or what went wrong
                Txt {
                    ui: root.ui
                    Layout.fillWidth: true
                    text: root.hasData
                        ? Model.summaryLine(root.grid, root.cfg.showStreaks)
                        : (root.result ? Model.errorText(root.result.error) : "Loading…")
                    color: root.result && root.result.error !== undefined ? ui.bad : ui.fg
                    font.pixelSize: ui.fs(12)
                    font.weight: Font.DemiBold
                    wrapMode: Text.Wrap
                }

                // one column per week, Sunday on top
                Item {
                    id: gridBox
                    Layout.fillWidth: true
                    Layout.preferredHeight: monthRow + 7 * (cell + gap)
                    visible: root.hasData

                    readonly property real lw: ui.fs(10) * 3
                    readonly property real gap: Math.max(2, Math.round(cell / 5))
                    readonly property real monthRow: ui.fs(9) + ui.px(6)
                    readonly property int weeks: Math.max(1, root.grid.cols.length)
                    // the squares grow with the window, up to a point
                    readonly property real cell: Math.max(4, Math.min(18, Math.floor((width - lw) / weeks / 1.2)))
                    readonly property real radius: Math.min(cell / 2, root.ui.radius * cell / 24)

                    // month names, leaving out any that would run into the one before
                    TextMetrics { id: monthW; font.family: ui.fontName; font.pixelSize: ui.fs(9); text: "May" }
                    readonly property var months: {
                        const out = []
                        let last = -1e9
                        for (const m of root.grid.months) {
                            const x = m.col * (cell + gap)
                            if (x - last >= monthW.width + ui.px(6)) { out.push(m); last = x }
                        }
                        return out
                    }
                    Repeater {
                        model: gridBox.months
                        delegate: Txt {
                            required property var modelData
                            ui: root.ui
                            x: gridBox.lw + modelData.col * (gridBox.cell + gridBox.gap)
                            text: modelData.label
                            opacity: 0.6
                            font.pixelSize: ui.fs(9)
                        }
                    }
                    Repeater {
                        // left out when the rows are too small for them
                        model: 2 * (gridBox.cell + gridBox.gap) >= ui.fs(9) + 2
                            ? [{ row: 1, label: "Mon" }, { row: 3, label: "Wed" }, { row: 5, label: "Fri" }] : []
                        delegate: Txt {
                            required property var modelData
                            ui: root.ui
                            y: gridBox.monthRow + modelData.row * (gridBox.cell + gridBox.gap) + (gridBox.cell - implicitHeight) / 2
                            text: modelData.label
                            opacity: 0.6
                            font.pixelSize: ui.fs(9)
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
                                        radius: gridBox.radius
                                        color: root.levelColor(modelData.level)
                                        opacity: modelData.skip ? 0 : 1
                                        border.width: hover.containsMouse ? 1 : 0
                                        border.color: ui.fg
                                        MouseArea {
                                            id: hover
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

                // Less … More
                Row {
                    Layout.leftMargin: gridBox.lw
                    spacing: ui.px(4)
                    visible: root.hasData && root.cfg.showLegend
                    Txt { ui: root.ui; anchors.verticalCenter: parent.verticalCenter; text: "Less"; opacity: 0.6; font.pixelSize: ui.fs(9) }
                    Repeater {
                        model: 5
                        delegate: Rectangle {
                            required property int index
                            anchors.verticalCenter: parent.verticalCenter
                            width: gridBox.cell
                            height: gridBox.cell
                            radius: gridBox.radius
                            color: root.levelColor(index)
                        }
                    }
                    Txt { ui: root.ui; anchors.verticalCenter: parent.verticalCenter; text: "More"; opacity: 0.6; font.pixelSize: ui.fs(9) }
                }

                // the day under the mouse, or when the numbers were fetched
                Txt {
                    ui: root.ui
                    Layout.fillWidth: true
                    visible: root.hasData
                    text: root.hoverText !== "" ? root.hoverText : (root.stats ? root.stats.updatedText : "")
                    elide: Text.ElideRight
                    opacity: 0.6
                    font.pixelSize: ui.fs(10)
                }
            }
        }

        // a few numbers from the year
        GridLayout {
            Layout.fillWidth: true
            visible: root.hasData && root.cfg.showCards
            columns: root.width >= ui.px(520) ? 4 : 2
            columnSpacing: ui.px(8)
            rowSpacing: ui.px(8)
            Repeater {
                model: [
                    { label: "Contributions", value: String(root.grid.total) },
                    { label: "Active days", value: String(root.activeDays) },
                    { label: "Longest streak", value: root.grid.longest + (root.grid.longest === 1 ? " day" : " days") },
                    { label: "Busiest day", value: root.grid.busiest ? root.grid.busiest.count + " on " + Model.shortDay(root.grid.busiest) : "–" }
                ]
                delegate: Rectangle {
                    required property var modelData
                    Layout.fillWidth: true
                    Layout.preferredWidth: 1
                    implicitHeight: cardCol.implicitHeight + ui.px(20)
                    radius: ui.r(2)
                    color: ui.cardFill(false)
                    border.width: ui.cardBorder
                    border.color: ui.tint(0.12)
                    Column {
                        id: cardCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: ui.px(10)
                        anchors.rightMargin: ui.px(10)
                        spacing: ui.px(3)
                        Txt { ui: root.ui; width: parent.width; text: modelData.label; opacity: 0.6; font.pixelSize: ui.fs(10); elide: Text.ElideRight }
                        Txt { ui: root.ui; width: parent.width; text: modelData.value; font.pixelSize: ui.fs(14); font.weight: Font.DemiBold; elide: Text.ElideRight }
                    }
                }
            }
        }
    }
}

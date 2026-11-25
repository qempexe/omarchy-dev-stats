import QtQuick
import QtQuick.Layouts
import "../controls"
import "../js/Stats.js" as Model

// The day picked on the grid: the pull requests opened or merged that day and
// the commits pushed on any branch, grouped by repository. A click on a row
// opens it on the web. Everything shown here went through Model.parseDay.
Rectangle {
    id: root

    property var ui: null
    readonly property var stats: ui ? ui.service : null
    readonly property string date: stats ? stats.selectedDay : ""
    readonly property var day: stats ? stats.currentDay : null
    readonly property bool loading: stats ? stats.dayLoading : false
    readonly property bool ok: !!day && day.error === undefined
    readonly property var groups: ok ? Model.commitGroups(day.commits) : []

    implicitHeight: col.implicitHeight + ui.px(24)
    radius: ui.r(2.5)
    color: ui.cardFill(false)
    border.width: ui.cardBorder
    border.color: ui.tint(0.12)

    ColumnLayout {
        id: col
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.margins: ui.px(12)
        spacing: ui.px(8)

        // the day, what it holds, and a way to close it
        RowLayout {
            Layout.fillWidth: true
            spacing: ui.px(8)
            ColumnLayout {
                Layout.fillWidth: true
                spacing: ui.px(2)
                Txt {
                    ui: root.ui
                    Layout.fillWidth: true
                    text: Model.longDay(root.date)
                    font.pixelSize: ui.fs(12)
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
                Txt {
                    ui: root.ui
                    Layout.fillWidth: true
                    text: root.loading ? "Loading…"
                        : (root.ok ? Model.daySummary(root.day) : Model.errorText(root.day ? root.day.error : ""))
                    color: !root.loading && root.day && root.day.error !== undefined ? ui.bad : ui.fg
                    opacity: root.ok || root.loading ? 0.6 : 1
                    font.pixelSize: ui.fs(10)
                    wrapMode: Text.Wrap
                }
            }
            Btn {
                ui: root.ui
                Layout.alignment: Qt.AlignTop
                visible: !root.loading && root.day && root.day.error !== undefined && root.day.error !== "unsupported"
                text: "Retry"
                onClicked: root.stats.selectDay(root.date, true)
            }
            Btn {
                ui: root.ui
                Layout.alignment: Qt.AlignTop
                text: "Close"
                onClicked: root.stats.closeDay()
            }
        }

        Txt {
            ui: root.ui
            Layout.fillWidth: true
            visible: root.ok && !root.loading && root.day.commits.length === 0 && root.day.prs.length === 0
            text: "Nothing pushed and no pull requests on this day."
            opacity: 0.7
            wrapMode: Text.Wrap
        }

        // ---- pull requests ----
        Txt {
            ui: root.ui
            visible: root.ok && root.day.prs.length > 0
            text: "Pull requests"
            opacity: 0.6
            font.pixelSize: ui.fs(10)
            font.weight: Font.DemiBold
        }
        Repeater {
            model: root.ok ? root.day.prs : []
            delegate: DayRow {
                required property var modelData
                ui: root.ui
                Layout.fillWidth: true
                tag: "#" + modelData.number
                title: modelData.title
                detail: Model.prLine(modelData)
                url: modelData.url
            }
        }

        // ---- commits, one block per repository ----
        Repeater {
            model: root.groups
            delegate: ColumnLayout {
                id: group
                required property var modelData
                Layout.fillWidth: true
                Layout.topMargin: ui.px(4)
                spacing: ui.px(4)
                Txt {
                    ui: root.ui
                    Layout.fillWidth: true
                    text: group.modelData.repo + "  ·  " + group.modelData.commits.length
                        + (group.modelData.commits.length === 1 ? " commit" : " commits")
                    opacity: 0.6
                    font.pixelSize: ui.fs(10)
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
                Repeater {
                    model: group.modelData.commits
                    delegate: DayRow {
                        required property var modelData
                        ui: root.ui
                        Layout.fillWidth: true
                        tag: modelData.sha
                        mono: true
                        title: modelData.title
                        detail: modelData.branch + (modelData.at !== "" ? "  ·  " + modelData.at : "")
                        url: modelData.url
                    }
                }
            }
        }

        Txt {
            ui: root.ui
            Layout.fillWidth: true
            visible: root.ok && root.day.partial
            text: "Some repositories or branches weren't checked, so this list may be incomplete."
            opacity: 0.6
            font.pixelSize: ui.fs(10)
            wrapMode: Text.Wrap
        }
    }
}

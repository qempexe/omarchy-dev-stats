import QtQuick
import QtQuick.Layouts
import "../controls"

// One pull request or commit in the day card. Clicking opens `url` through the
// service's openUrl, which only accepts plain https links.
Rectangle {
    id: root

    property var ui: null
    property string tag: ""          // "#123" or a short sha
    property bool mono: false
    property string title: ""
    property string detail: ""
    property string url: ""

    implicitHeight: row.implicitHeight + ui.px(10)
    radius: ui.r(1.5)
    color: area.containsMouse && url !== "" ? ui.tint(0.08) : "transparent"

    RowLayout {
        id: row
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        anchors.leftMargin: ui.px(6)
        anchors.rightMargin: ui.px(6)
        spacing: ui.px(8)

        Txt {
            ui: root.ui
            Layout.alignment: Qt.AlignTop
            Layout.preferredWidth: ui.fs(11) * 4.6
            text: root.tag
            color: ui.accent
            font.family: root.mono ? "monospace" : ui.fontName
            font.pixelSize: ui.fs(11)
        }
        ColumnLayout {
            Layout.fillWidth: true
            spacing: ui.px(1)
            Txt {
                ui: root.ui
                Layout.fillWidth: true
                text: root.title
                elide: Text.ElideRight
            }
            Txt {
                ui: root.ui
                Layout.fillWidth: true
                text: root.detail
                opacity: 0.55
                font.pixelSize: ui.fs(9)
                elide: Text.ElideRight
            }
        }
    }

    MouseArea {
        id: area
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: root.url !== "" ? Qt.PointingHandCursor : Qt.ArrowCursor
        onClicked: if (root.url !== "" && root.ui && root.ui.service) root.ui.service.openUrl(root.url)
    }
}

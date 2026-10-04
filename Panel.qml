import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "Stats.js" as Model

Panel {
  id: root
  moduleName: "io.github.qempexe.dev-stats"
  manageIpc: false

  property var anchorItem: null
  property var hostWidget: null
  property var store: null   // BarWidget.qml, injected

  readonly property var accounts: store ? store.accounts : []
  readonly property var account: store && accounts.length > store.selected ? accounts[store.selected] : null
  readonly property int year: store ? store.selectedYear : 0
  readonly property var rolling: store && account ? store.results[Model.accountKey(account)] : null
  readonly property var years: rolling && rolling.years ? rolling.years : []
  readonly property var result: store && account ? store.results[Model.resultKey(account, year)] : null
  readonly property bool hasData: result !== null && result !== undefined && result.error === undefined
  readonly property var grid: Model.buildGrid(hasData ? result.days : ({}), new Date(), year)

  readonly property real prefCell: Style.space(10)
  readonly property real gap: Style.space(3)
  readonly property real labelWidth: Style.space(30)
  readonly property real monthRow: Style.space(16)
  readonly property real gridWidth: labelWidth + 54 * (prefCell + gap)
  // Cell size follows the width the panel really gives us (it adds padding),
  // so the grid always fits instead of spilling past the right edge.
  readonly property real cell: Math.max(Style.space(5), Math.min(prefCell * 1.2,
    (content.width - labelWidth - (grid.cols.length - 1) * gap) / grid.cols.length))
  readonly property real smallFont: Math.round(Style.font.subtitle * 0.8)
  readonly property color dim: Qt.alpha(root.barForeground, 0.65)

  property string hoverText: ""

  function levelColor(level) {
    if (level <= 0) return Qt.alpha(root.barForeground, 0.12)
    return ["#0e4429", "#006d32", "#26a641", "#39d353"][level - 1]
  }

  function updatedText() {
    if (!store) return ""
    if (store.busy) return "Updating\u2026"
    if (store.updatedAt <= 0) return ""
    return "Updated " + Qt.formatTime(new Date(store.updatedAt), "HH:mm")
  }

  function open() {
    root.controller.show()
  }

  function close() {
    root.controller.hide()
  }

  function switchPanel(direction) {
    if (root.bar && typeof root.bar.switchPanelFrom === "function")
      return root.bar.switchPanelFrom(root.hostWidget || root, direction)
    return false
  }

  KeyboardPanel {
    id: panel
    anchorItem: root.anchorItem
    owner: root.hostWidget || root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Math.max(Style.space(380), root.gridWidth + Style.space(32)))
    contentHeight: panel.fittedContentHeight(content.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: content
        width: parent.width
        spacing: Style.space(10)

        // ---- account tabs ------------------------------------------------
        Flow {
          width: parent.width
          spacing: Style.space(6)
          visible: root.accounts.length > 0

          Repeater {
            model: root.accounts

            Rectangle {
              id: tab
              required property var modelData
              required property int index
              readonly property bool active: root.store && root.store.selected === index

              implicitWidth: tabLabel.implicitWidth + Style.space(16)
              implicitHeight: tabLabel.implicitHeight + Style.space(8)
              radius: Style.space(6)
              color: active ? Qt.alpha(root.barForeground, 0.18) : Qt.alpha(root.barForeground, 0.06)

              Text {
                id: tabLabel
                anchors.centerIn: parent
                // Account names are remote data: plain text only, never markup.
                text: Model.providerLabel(tab.modelData.provider) + " \u00b7 " + tab.modelData.user
                textFormat: Text.PlainText
                elide: Text.ElideRight
                color: root.barForeground
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: root.smallFont
                font.bold: tab.active
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: if (root.store) root.store.selectAccount(tab.index)
              }
            }
          }
        }

        // ---- year selector ----------------------------------------------
        Flow {
          width: parent.width
          spacing: Style.space(6)
          visible: root.years.length > 0

          Repeater {
            model: [0].concat(root.years)

            Rectangle {
              id: chip
              required property var modelData
              readonly property bool active: root.year === modelData

              implicitWidth: chipLabel.implicitWidth + Style.space(14)
              implicitHeight: chipLabel.implicitHeight + Style.space(6)
              radius: Style.space(6)
              color: active ? Qt.alpha(root.barForeground, 0.18) : Qt.alpha(root.barForeground, 0.06)

              Text {
                id: chipLabel
                anchors.centerIn: parent
                text: chip.modelData === 0 ? "Last year" : String(chip.modelData)
                textFormat: Text.PlainText
                color: root.barForeground
                font.family: root.bar ? root.bar.fontFamily : Style.font.family
                font.pixelSize: root.smallFont
                font.bold: chip.active
              }

              MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: if (root.store) root.store.selectYear(chip.modelData)
              }
            }
          }
        }

        // ---- summary / status -------------------------------------------
        Text {
          width: parent.width
          visible: root.accounts.length > 0
          text: root.hasData
            ? Model.summaryLine(root.grid)
            : (root.result ? Model.errorText(root.result.error) : "Loading\u2026")
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          color: root.barForeground
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.subtitle
          font.bold: true
        }

        // ---- empty state --------------------------------------------------
        Text {
          width: parent.width
          visible: root.accounts.length === 0
          text: root.store && root.store.busy
            ? "Looking for logged-in accounts\u2026"
            : "No accounts found. Log in from a terminal, then middle-click the widget:\n\n"
              + "  gh auth login\n  glab auth login\n  tea login add     (or: fj auth login)\n\n"
              + "Or list accounts in ~/.config/dev-stats/accounts.json"
          textFormat: Text.PlainText
          wrapMode: Text.WordWrap
          color: root.barForeground
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: root.smallFont
        }

        // ---- the grid -----------------------------------------------------
        Item {
          width: parent.width
          height: root.monthRow + 7 * (root.cell + root.gap)
          visible: root.hasData

          Repeater {
            model: root.grid.months

            Text {
              required property var modelData
              x: root.labelWidth + modelData.col * (root.cell + root.gap)
              y: 0
              text: modelData.label
              textFormat: Text.PlainText
              color: root.dim
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: root.smallFont
            }
          }

          Repeater {
            model: [{ row: 1, label: "Mon" }, { row: 3, label: "Wed" }, { row: 5, label: "Fri" }]

            Text {
              required property var modelData
              y: root.monthRow + modelData.row * (root.cell + root.gap) + (root.cell - implicitHeight) / 2
              text: modelData.label
              textFormat: Text.PlainText
              color: root.dim
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: root.smallFont
            }
          }

          Row {
            x: root.labelWidth
            y: root.monthRow
            spacing: root.gap

            Repeater {
              model: root.grid.cols

              Column {
                id: week
                required property var modelData
                spacing: root.gap

                Repeater {
                  model: week.modelData

                  Rectangle {
                    id: day
                    required property var modelData
                    width: root.cell
                    height: root.cell
                    radius: Style.space(2)
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

        // ---- legend + footer ---------------------------------------------
        Item {
          width: parent.width
          height: legend.implicitHeight
          visible: root.hasData

          Row {
            id: legend
            x: root.labelWidth
            spacing: Style.space(4)

            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: "Less"
              textFormat: Text.PlainText
              color: root.dim
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: root.smallFont
            }
            Repeater {
              model: 5
              Rectangle {
                required property int index
                anchors.verticalCenter: parent.verticalCenter
                width: root.cell
                height: root.cell
                radius: Style.space(2)
                color: root.levelColor(index)
              }
            }
            Text {
              anchors.verticalCenter: parent.verticalCenter
              text: "More"
              textFormat: Text.PlainText
              color: root.dim
              font.family: root.bar ? root.bar.fontFamily : Style.font.family
              font.pixelSize: root.smallFont
            }
          }
        }

        Item {
          width: parent.width
          height: footer.implicitHeight

          Text {
            id: footer
            anchors.left: parent.left
            anchors.right: refreshLabel.left
            anchors.rightMargin: Style.space(8)
            text: root.hoverText !== "" ? root.hoverText : root.updatedText()
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: root.dim
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: root.smallFont
          }

          Text {
            id: refreshLabel
            anchors.right: parent.right
            text: "Refresh"
            textFormat: Text.PlainText
            color: root.barForeground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            font.pixelSize: root.smallFont
            font.underline: true

            MouseArea {
              anchors.fill: parent
              cursorShape: Qt.PointingHandCursor
              onClicked: if (root.store) root.store.refresh()
            }
          }
        }
      }
    }
  }
}

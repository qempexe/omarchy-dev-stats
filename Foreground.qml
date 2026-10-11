import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// Not a visible panel any more. The settings popup is SettingsPopup.qml; this
// item only exists because the shell's Panel type is what exposes the bar's
// foreground color (barForeground), which the squares and the popup text use.
Panel {
  id: root
  moduleName: "io.github.qempexe.dev-stats"
  manageIpc: false
}

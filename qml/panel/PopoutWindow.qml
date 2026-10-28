import QtQuick
import Quickshell

// The same Dev Stats, as a normal window you can move, resize and tile.
// BarWidget.qml creates it on "Pop out" and destroys it on "Dock".
//
// To make Hyprland float and center it (it tiles by default), add window rules
// that match the title "Dev Stats"; see the README.
FloatingWindow {
    id: win

    property var ui: null

    title: "Dev Stats"
    visible: false
    color: "transparent"
    implicitWidth: ui ? ui.cfgSafe.windowWidth : 640
    implicitHeight: ui ? ui.cfgSafe.windowHeight : 520

    Loader {
        anchors.fill: parent
        active: win.ui !== null
        sourceComponent: Component { StatsView { ui: win.ui; focus: true } }
    }
}

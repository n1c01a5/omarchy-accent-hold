pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import "Accents.js" as Accents

// Full-screen transparent layer on one monitor. It takes the keyboard while
// open, which also stops the application from auto-repeating the held
// letter, and turns every key press or click into a decision for the service.
PanelWindow {
  id: window

  // Global logical point to center on, and whether to sit above it instead.
  property point anchorPoint: Qt.point(0, 0)
  property bool above: false
  property var variants: []
  property int highlighted: -1

  signal decided(var decision)

  // Qt key codes the popup reacts to; everything else is plain text.
  readonly property var keyRoles: {
    var roles = {}
    for (var modifier of [Qt.Key_Shift, Qt.Key_Control, Qt.Key_Alt, Qt.Key_Meta, Qt.Key_Super_L,
                          Qt.Key_Super_R, Qt.Key_AltGr, Qt.Key_CapsLock, Qt.Key_Multi_key])
      roles[modifier] = { key: "Modifier" }
    roles[Qt.Key_Escape] = { key: "Escape" }
    roles[Qt.Key_Left] = { key: "Left" }
    roles[Qt.Key_Right] = { key: "Right" }
    roles[Qt.Key_Tab] = { key: "Tab" }
    roles[Qt.Key_Backtab] = { key: "Backtab" }
    roles[Qt.Key_Return] = { key: "Return" }
    roles[Qt.Key_Enter] = { key: "Return" }
    roles[Qt.Key_Space] = { key: "Space" }
    roles[Qt.Key_Backspace] = { key: "Named", name: "BackSpace" }
    roles[Qt.Key_Delete] = { key: "Named", name: "Delete" }
    roles[Qt.Key_Up] = { key: "Named", name: "Up" }
    roles[Qt.Key_Down] = { key: "Named", name: "Down" }
    roles[Qt.Key_Home] = { key: "Named", name: "Home" }
    roles[Qt.Key_End] = { key: "Named", name: "End" }
    return roles
  }

  function open() {
    row.reset()
    window.visible = true
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    window.visible = false
  }

  visible: false
  anchors { top: true; bottom: true; left: true; right: true }
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: "accent-hold"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

  MouseArea {
    anchors.fill: parent
    onClicked: window.decided({ action: "cancel" })
  }

  AccentRow {
    id: row
    variants: window.variants
    highlighted: window.highlighted
    onPicked: function(index) { window.decided({ action: "commit", index: index }) }
    onHovered: function(index) { window.decided({ action: "highlight", index: index }) }

    readonly property real localX: window.anchorPoint.x - (window.screen ? window.screen.x : 0)
    readonly property real localY: window.anchorPoint.y - (window.screen ? window.screen.y : 0)
    readonly property real margin: Style.gapsOut * 2

    x: Math.max(margin, Math.min(window.width - width - margin, localX - width / 2))
    y: Math.max(margin, Math.min(window.height - height - margin,
      window.above ? localY - height - Style.space(16) : localY - height / 2))
  }

  Item {
    id: keyCatcher
    focus: true
    Keys.onPressed: function(event) {
      event.accepted = true
      var input = Accents.keyInput(event.key, event.text, window.keyRoles)
      window.decided(Accents.decideKey(input, { count: window.variants.length, highlighted: window.highlighted }))
    }
  }
}

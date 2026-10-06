pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import "Accents.js" as Accents

// Layer surface the size of the accent row. Taking the keyboard is what stops
// auto-repeat of the held letter (fcitx5 repeats keys until the focus moves),
// so opening must beat input.repeat_delay. Creating a layer surface takes
// 45-70 ms, so the surface stays mapped between holds as an invisible,
// click-through 1x1 pixel without keyboard focus; opening only resizes it and
// takes the keyboard. While a fullscreen window is active it is unmapped
// instead, so it never sits above games or video.
// No HyprlandFocusGrab: it hands the still-held letter to the popup as a
// fresh key press.
PanelWindow {
  id: window

  // "screen" centers the row on this monitor. "window" centers it on
  // anchorPoint (global logical coordinates); "pointer" sits above it.
  property string placement: "screen"
  property point anchorPoint: Qt.point(0, 0)
  property var variants: []
  property int highlighted: -1

  property bool shown: false
  property bool parked: false

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

  // Keypad keys without NumLock, mapped back to the digit printed on them.
  readonly property var keypadDigits: {
    var digits = {}
    digits[Qt.Key_Insert] = "0"
    digits[Qt.Key_End] = "1"
    digits[Qt.Key_Down] = "2"
    digits[Qt.Key_PageDown] = "3"
    digits[Qt.Key_Left] = "4"
    digits[Qt.Key_Clear] = "5"
    digits[Qt.Key_Right] = "6"
    digits[Qt.Key_Home] = "7"
    digits[Qt.Key_Up] = "8"
    digits[Qt.Key_PageUp] = "9"
    return digits
  }

  // A key's decision is taken when it goes down but applied when it comes up.
  // The service then types with wtype, whose virtual keyboard reuses low
  // keycodes (its second key has the keycode of "1"); typing while the
  // physical key is still down makes Hyprland drop that character.
  property var pendingDecision: null
  property int pendingScanCode: -1

  function flushPending() {
    var decision = window.pendingDecision
    window.pendingDecision = null
    window.pendingScanCode = -1
    releaseFallback.stop()
    if (decision) window.decided(decision)
  }

  function open() {
    row.reset()
    window.pendingDecision = null
    window.pendingScanCode = -1
    window.shown = true
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    window.shown = false
  }

  readonly property Region clickThrough: Region {}

  readonly property real screenWidth: window.screen ? window.screen.width : 0
  readonly property real screenHeight: window.screen ? window.screen.height : 0
  readonly property real localX: window.anchorPoint.x - (window.screen ? window.screen.x : 0)
  readonly property real localY: window.anchorPoint.y - (window.screen ? window.screen.y : 0)
  readonly property real targetX: window.placement === "screen" ? window.screenWidth / 2 : window.localX
  readonly property real targetY: window.placement === "screen" ? window.screenHeight / 2 : window.localY
  readonly property real edge: Style.gapsOut * 2

  function clamp(value, low, high) {
    return Math.max(low, Math.min(high, value))
  }

  visible: window.shown || !window.parked
  color: "transparent"
  anchors { top: true; left: true }
  margins {
    left: window.clamp(window.targetX - row.width / 2, window.edge, window.screenWidth - row.width - window.edge)
    top: window.clamp(window.placement === "pointer" ? window.targetY - row.height - Style.space(16)
                                                     : window.targetY - row.height / 2,
                      window.edge, window.screenHeight - row.height - window.edge)
  }
  implicitWidth: window.shown ? row.width : 1
  implicitHeight: window.shown ? row.height : 1
  mask: window.shown ? null : window.clickThrough
  exclusionMode: ExclusionMode.Ignore
  WlrLayershell.namespace: "accent-hold"
  WlrLayershell.layer: WlrLayer.Overlay
  WlrLayershell.keyboardFocus: window.shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

  AccentRow {
    id: row
    visible: window.shown
    variants: window.variants
    highlighted: window.highlighted
    onPicked: function(index) { window.decided({ action: "commit", index: index }) }
    onHovered: function(index) { window.decided({ action: "highlight", index: index }) }
  }

  Item {
    id: keyCatcher
    focus: true
    Keys.onPressed: function(event) {
      event.accepted = true
      if (event.isAutoRepeat) return
      window.flushPending()
      var input = Accents.keyInput({
        code: event.key,
        text: event.text,
        keypad: (event.modifiers & Qt.KeypadModifier) !== 0,
        scanCode: event.nativeScanCode
      }, { roles: window.keyRoles, keypadDigits: window.keypadDigits })
      var decision = Accents.decideKey(input, { count: window.variants.length, highlighted: window.highlighted })
      if (decision.action === "highlight" || decision.action === "ignore") {
        window.decided(decision)
        return
      }
      window.pendingDecision = decision
      window.pendingScanCode = event.nativeScanCode
      releaseFallback.restart()
    }
    Keys.onReleased: function(event) {
      event.accepted = true
      if (!event.isAutoRepeat && event.nativeScanCode === window.pendingScanCode) window.flushPending()
    }
  }

  // Applies the decision anyway if the release never reaches the popup.
  Timer {
    id: releaseFallback
    interval: 1000
    onTriggered: window.flushPending()
  }
}

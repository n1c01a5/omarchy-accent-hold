pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons
import qs.Ui
import "Accents.js" as Accents

// Accent Hold service. Loads hypr/accent-hold.lua into Hyprland, listens for
// its "hold" events, and shows the accent popup on the focused monitor.
Item {
  id: root

  property string omarchyPath: ""
  property var shell: null
  property var manifest: null

  readonly property string configPath: Quickshell.env("HOME") + "/.config/omarchy/accent-hold.json"
  readonly property string luaPath: decodeURIComponent(Qt.resolvedUrl("hypr/accent-hold.lua").toString().replace(/^file:\/\//, ""))
  property var config: Accents.parseConfig("")

  // Popup state.
  property bool opened: false
  property var hold: null
  property bool upper: false
  property var variants: []
  property int highlighted: -1
  property var pendingCommand: null

  readonly property var targetScreen: {
    var name = root.hold ? root.hold.monitor : ""
    var screens = Quickshell.screens
    for (var i = 0; i < screens.length; i++)
      if (screens[i].name === name) return screens[i]
    var focused = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
    for (var j = 0; j < screens.length; j++)
      if (screens[j].name === focused) return screens[j]
    return screens.length > 0 ? screens[0] : null
  }

  function applyConfig(text) {
    root.config = Accents.parseConfig(text)
    root.inject()
  }

  function inject() {
    var lua = "__accent_hold_config = " + Accents.luaConfig(root.config)
      + "\nreturn dofile(" + Accents.luaString(root.luaPath) + ")"
    injectProc.running = false
    injectProc.command = ["hyprctl", "eval", lua]
    injectProc.running = true
  }

  function show(hold) {
    if (root.opened || !hold) return
    root.hold = hold
    root.upper = hold.shift
    root.variants = Accents.variantsFor(root.config.accents, hold.letter, root.upper)
    if (root.variants.length === 0) return
    root.highlighted = -1
    popup.reset()
    root.opened = true
    capsProc.running = true
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  function close() {
    root.opened = false
  }

  function run(command) {
    root.close()
    // Let the application get keyboard focus back before typing into it.
    root.pendingCommand = command
    typeTimer.restart()
  }

  function apply(decision) {
    switch (decision.action) {
    case "commit":
      root.run(Accents.commitCommand(root.variants[decision.index]))
      break
    case "pass":
      root.run(Accents.passCommand(decision))
      break
    case "highlight":
      root.highlighted = decision.index
      break
    case "cancel":
      root.close()
      break
    }
  }

  function keyInput(event) {
    switch (event.key) {
    case Qt.Key_Shift: case Qt.Key_Control: case Qt.Key_Alt: case Qt.Key_Meta:
    case Qt.Key_Super_L: case Qt.Key_Super_R: case Qt.Key_AltGr: case Qt.Key_CapsLock:
    case Qt.Key_Multi_key:
      return { key: "Modifier" }
    case Qt.Key_Escape: return { key: "Escape" }
    case Qt.Key_Left: return { key: "Left" }
    case Qt.Key_Right: return { key: "Right" }
    case Qt.Key_Tab: return { key: "Tab" }
    case Qt.Key_Backtab: return { key: "Backtab" }
    case Qt.Key_Return: case Qt.Key_Enter: return { key: "Return" }
    case Qt.Key_Space: return { key: "Space" }
    case Qt.Key_Backspace: return { key: "Named", name: "BackSpace" }
    case Qt.Key_Delete: return { key: "Named", name: "Delete" }
    case Qt.Key_Up: return { key: "Named", name: "Up" }
    case Qt.Key_Down: return { key: "Named", name: "Down" }
    case Qt.Key_Home: return { key: "Named", name: "Home" }
    case Qt.Key_End: return { key: "Named", name: "End" }
    }
    var text = event.text || ""
    var printable = text.length > 0 && text.charCodeAt(0) >= 32 && text.charCodeAt(0) !== 127
    return printable ? { key: "Text", text: text } : { key: "Named" }
  }

  Component.onCompleted: root.inject()

  Component.onDestruction: {
    Quickshell.execDetached(["hyprctl", "eval",
      "local s = rawget(_G, '__accent_hold'); if s then s.stop() end"])
  }

  FileView {
    path: root.configPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.applyConfig(text())
    onLoadFailed: root.applyConfig("")
  }

  Process {
    id: injectProc
    stdout: StdioCollector {
      onStreamFinished: {
        var out = text.trim()
        if (out !== "ok") console.warn("accent-hold: hyprctl eval:", out)
      }
    }
  }

  Process {
    id: capsProc
    command: ["hyprctl", "devices", "-j"]
    stdout: StdioCollector {
      onStreamFinished: {
        try {
          var keyboards = JSON.parse(text).keyboards || []
          var caps = keyboards.some(function(k) { return k.main && k.capsLock })
          if (!caps || !root.opened) return
          root.upper = !root.hold.shift
          root.variants = Accents.variantsFor(root.config.accents, root.hold.letter, root.upper)
          if (root.highlighted >= root.variants.length) root.highlighted = -1
        } catch (e) {}
      }
    }
  }

  Timer {
    id: typeTimer
    interval: 40
    onTriggered: {
      if (root.pendingCommand) Quickshell.execDetached(root.pendingCommand)
      root.pendingCommand = null
    }
  }

  Connections {
    target: Hyprland
    function onRawEvent(event) {
      switch (event.name) {
      case "custom":
        root.show(Accents.parseEvent(event.data))
        break
      case "configreloaded":
        root.inject()
        break
      case "workspace":
      case "focusedmon":
        root.close()
        break
      }
    }
  }

  PanelWindow {
    id: panel
    visible: root.opened
    screen: root.targetScreen
    anchors { top: true; bottom: true; left: true; right: true }
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "accent-hold"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

    MouseArea {
      anchors.fill: parent
      onClicked: root.close()
    }

    AccentPopup {
      id: popup
      variants: root.variants
      highlighted: root.highlighted
      onPicked: function(index) { root.apply({ action: "commit", index: index }) }
      onHovered: function(index) { root.highlighted = index }

      readonly property real localX: (root.hold ? root.hold.x : 0) - (panel.screen ? panel.screen.x : 0)
      readonly property real localY: (root.hold ? root.hold.y : 0) - (panel.screen ? panel.screen.y : 0)
      readonly property real margin: Style.gapsOut * 2
      x: Math.max(margin, Math.min(panel.width - width - margin, localX - width / 2))
      y: Math.max(margin, Math.min(panel.height - height - margin,
        root.config.position === "pointer" ? localY - height - Style.space(16) : localY - height / 2))
    }

    Item {
      id: keyCatcher
      focus: true
      Keys.onPressed: function(event) {
        event.accepted = true
        root.apply(Accents.decideKey(root.keyInput(event),
          { count: root.variants.length, highlighted: root.highlighted }))
      }
    }
  }
}

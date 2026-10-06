pragma ComponentBehavior: Bound
import QtQuick
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import "Accents.js" as Accents

// Accent Hold service. Loads hypr/accent-hold.lua into Hyprland, opens the
// popup when the Lua side reports a held letter, and types the outcome back
// into the application.
Item {
  id: root

  readonly property string configPath: Quickshell.env("HOME") + "/.config/omarchy/accent-hold.json"
  readonly property string luaPath: decodeURIComponent(Qt.resolvedUrl("hypr/accent-hold.lua").toString().replace(/^file:\/\//, ""))
  property var config: Accents.parseConfig("")
  property var hold: null

  function applyConfig(text) {
    root.config = Accents.parseConfig(text)
    root.inject()
  }

  // Loading the Lua twice is safe: it tears down its previous instance.
  function inject() {
    injectProc.running = false
    injectProc.command = ["hyprctl", "eval", "__accent_hold_config = " + Accents.luaConfig(root.config)
      + "\ndofile(" + Accents.luaString(root.luaPath) + ")"]
    injectProc.running = true
  }

  function screenFor(name) {
    var screens = Array.from(Quickshell.screens)
    var focused = Hyprland.focusedMonitor ? Hyprland.focusedMonitor.name : ""
    return screens.find(function(s) { return s.name === name })
      || screens.find(function(s) { return s.name === focused })
      || screens[0] || null
  }

  function showVariants(upper) {
    popup.variants = Accents.variantsFor(root.config.accents, root.hold.letter, upper)
    if (popup.highlighted >= popup.variants.length) popup.highlighted = -1
  }

  function show(hold) {
    if (!hold || popup.visible) return
    root.hold = hold
    root.showVariants(hold.shift)
    if (popup.variants.length === 0) return
    popup.screen = root.screenFor(hold.monitor)
    popup.anchorPoint = Qt.point(hold.x, hold.y)
    popup.placement = root.config.position
    popup.highlighted = -1
    popup.open()
    capsProc.running = true
  }

  // Close first so the application has the keyboard back before typing.
  function typeAfterClose(command) {
    popup.close()
    typeTimer.command = command
    typeTimer.restart()
  }

  function apply(decision) {
    switch (decision.action) {
    case "commit":
      root.typeAfterClose(Accents.commitCommand(popup.variants[decision.index]))
      break
    case "pass":
      root.typeAfterClose(Accents.passCommand(decision))
      break
    case "highlight":
      popup.highlighted = decision.index
      break
    case "cancel":
      popup.close()
      break
    }
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
      onStreamFinished: if (text.trim() !== "ok") console.warn("accent-hold: hyprctl eval:", text.trim())
    }
  }

  // Caps Lock flips the case shown for this hold.
  Process {
    id: capsProc
    command: ["hyprctl", "devices", "-j"]
    stdout: StdioCollector {
      onStreamFinished: {
        if (!popup.visible) return
        try {
          var keyboards = JSON.parse(text).keyboards || []
          if (keyboards.some(function(k) { return k.main && k.capsLock }))
            root.showVariants(!root.hold.shift)
        } catch (e) {}
      }
    }
  }

  Timer {
    id: typeTimer
    property var command: null
    interval: 40
    onTriggered: if (command) Quickshell.execDetached(command)
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
        popup.close()
        break
      }
    }
  }

  AccentPopup {
    id: popup
    onDecided: function(decision) { root.apply(decision) }
  }
}

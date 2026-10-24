import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons

// Tablet Lite — the simplified tablet experience: virtual keyboard + voice
// input only. No laptop/tablet state machine, no rotation, no handwriting, no
// window manager, no bar declutter.
//
// Voice input: the bar's mic icon opens a bottom hold-to-talk button.
// Press & hold -> `voxtype record start` (SIGUSR1), release -> `voxtype record
// stop` (SIGUSR2); voxtype transcribes locally and types the text at the
// cursor with wtype (CJK works everywhere). Delete / Clear / Enter fix or
// submit the dictated line, the left-side caret pad moves through it, and the
// expandable "CLI keys" grid sends esc / / / tab / ⇧tab / ⌃C / ⌃D / ⌃J / ⌃T
// for pi / codex CLI on a touch-only screen. The overlay follows voxtype's own
// state file, so the visuals agree with the F9 / SUPER+CTRL+X hotkeys too.
//
// Virtual keyboard: `texp-vk` drives wvkbd-deskintl (a wlroots-native build
// with Ctrl/Super/Alt, F-keys, a number row and arrows). Controllable from
// the bar icon, SUPER+U, or `omarchy-shell maxt.tablet-lite keyboardToggle`.
// Visibility is read from `hyprctl layers`, so the keyboard's own ▼ collapse
// key is reflected immediately.
//
// Voice input and the keyboard are mutually exclusive: opening one closes the
// other.
//
// IPC (omarchy-shell maxt.tablet-lite <method>):
//   getState | voiceInputToggle | voiceInputShow | voiceInputHide
//   keyboardToggle | keyboardShow | keyboardHide
//   cliKeysToggle | clearNow
Item {
  id: root

  Component.onCompleted: console.log("tablet-lite Service LOADED v" + root.pluginVersion)

  property var shell: null
  readonly property string pluginVersion: "1.0.1"

  // Voice input (voxtype hold-to-talk overlay).
  //   voiceInputOpen  the bottom hold-to-talk overlay is showing
  //   holding         our button is pressed (authority for start/stop)
  //   recording       voxtype state file says recording/streaming
  //   transcribing    voxtype state file says transcribing/outputting
  //   voxtypeUp       voxtype state file readable => daemon running
  property bool voiceInputOpen: false
  property bool cliKeysOpen: false
  property bool holding: false
  property bool recording: false
  property bool transcribing: false
  property bool voxtypeUp: false

  // On-screen keyboard visibility + the geometry of the real wvkbd surface
  // (the CLI/caret pad parks just above it).
  property bool vkVisible: false
  property string vkOutput: ""
  property real vkHeight: 0

  property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || ""
  readonly property string voxtypeStateDir: root.runtimeDir + "/voxtype"
  readonly property string voxtypeStateFile: root.voxtypeStateDir + "/state"

  // Hyprland window classes of terminal emulators (compared case-insensitively,
  // anchored): Clear must send readline Ctrl+A + Ctrl+K there, not a GUI
  // select-all + BackSpace. Anchored on purpose — a substring test would let
  // `st` catch `systemsettings`.
  readonly property var terminalClasses: [
    "foot", "alacritty", "kitty", "ghostty", "com.mitchellh.ghostty",
    "wezterm", "org.wezfurlong.wezterm", "konsole", "gnome-terminal",
    "gnome-terminal-server", "kgx", "org.gnome.console", "ptyxis",
    "xterm", "urxvt", "rxvt", "termite", "tilix", "xfce4-terminal",
    "mate-terminal", "lxterminal", "qterminal", "sakura", "st",
    "st-256color", "warp-terminal", "dev.warp.warp", "tabby", "hyper",
    "contour", "rio", "blackbox", "com.raggesilver.blackbox"
  ]

  // Extra control keys for the pad — what a TUI agent (pi / codex CLI) or a
  // shell prompt needs from touch, which the 4 caret arrows cannot provide.
  // `label` is the literal key sent; `argv` is appended to `wtype`.
  readonly property var cliKeys: [
    { label: "esc",  argv: ["-k", "Escape"] },
    { label: "/",    argv: ["-k", "slash"] },
    { label: "tab",  argv: ["-k", "Tab"] },
    { label: "\u21E7tab", argv: ["-M", "shift", "-k", "Tab", "-m", "shift"] },
    { label: "\u2303C",  argv: ["-M", "ctrl", "-k", "c", "-m", "ctrl"] },
    { label: "\u2303D",  argv: ["-M", "ctrl", "-k", "d", "-m", "ctrl"] },
    { label: "\u2303J",  argv: ["-M", "ctrl", "-k", "j", "-m", "ctrl"] },
    { label: "\u2303T",  argv: ["-M", "ctrl", "-k", "t", "-m", "ctrl"] }
  ]

  // ------------------------------------------------------------- actions

  BoundedProcess { id: vxCmd }
  BoundedProcess { id: enterCmd }
  BoundedProcess { id: delCmd }
  BoundedProcess { id: clrCmd }
  BoundedProcess { id: arrowCmd }
  BoundedProcess { id: cliCmd }
  BoundedProcess { id: vkCmd }
  BoundedProcess { id: mousehopCmd }

  // ---- voice input -------------------------------------------------------

  function toggleVoiceInput() {
    if (root.voiceInputOpen) root.hideVoiceInput()
    else root.showVoiceInput()
  }

  function showVoiceInput() {
    root.voiceInputOpen = true
    root.releaseMousehop()   // keys from this overlay must land here
    root.pollVoxtype()       // refresh daemon state the moment it appears
    // Voice input and the virtual keyboard are mutually exclusive.
    if (root.vkVisible) root.hideVk()
  }

  function hideVoiceInput() {
    // Never strand a recording when the button disappears — a lift-off event
    // can get lost with it.
    if (root.holding || root.recording) root.stopRecording()
    root.voiceInputOpen = false
    root.cliKeysOpen = false
  }

  // Press = `voxtype record start`; gated locally so a repeated press while
  // already holding cannot double-start the daemon.
  function startRecording() {
    if (root.holding || root.recording) return
    root.holding = true
    vxCmd.command = ["voxtype", "record", "start"]
    vxCmd.running = true
  }

  // Release = `voxtype record stop` -> transcribe + type at the cursor. Sent
  // unconditionally on our own release (harmless when idle) so a very fast tap
  // that the state poll never saw still ends its recording.
  function stopRecording() {
    root.holding = false
    vxCmd.command = ["voxtype", "record", "stop"]
    vxCmd.running = true
  }

  function sendEnter() {
    enterCmd.command = ["wtype", "-k", "Return"]
    enterCmd.running = true
  }

  function deleteLastChar() {
    delCmd.command = ["wtype", "-k", "BackSpace"]
    delCmd.running = true
  }

  function isTerminalClass(cls) {
    return root.terminalClasses.indexOf(String(cls || "").toLowerCase()) !== -1
  }

  // Clear the whole input. A terminal gets Ctrl+A + Ctrl+K (readline
  // beginning-of-line + kill-line); anything else gets Ctrl+A + BackSpace
  // (select-all + delete). Ask Hyprland which window owns the keyboard first;
  // on any probe failure the GUI sequence is the safe default (Ctrl+K in a
  // browser is the search bar, not kill-line).
  function clearInput() {
    if (clearWinProbe.running) return
    clearWinProbe.running = true
  }

  function sendArrow(dir) {
    arrowCmd.command = ["wtype", "-k", dir]
    arrowCmd.running = true
  }

  // Copy argv element by element (QML may hand a model's nested array back as
  // a QVariantList, which concat would splice in as one element).
  function sendCliKey(argv) {
    var cmd = ["wtype"]
    for (var i = 0; i < argv.length; i++) cmd.push(String(argv[i]))
    cliCmd.command = cmd
    cliCmd.running = true
  }

  // ---- virtual keyboard --------------------------------------------------

  function hideVk() {
    vkCmd.command = ["texp-vk", "hide"]
    vkCmd.running = true
  }

  function showVk() {
    // The voice overlay occupies the same bottom strip.
    if (root.voiceInputOpen) root.hideVoiceInput()
    root.releaseMousehop()   // the keyboard types into the focused app
    vkCmd.command = ["texp-vk", "show"]
    vkCmd.running = true
  }

  function toggleVk() {
    if (root.vkVisible) root.hideVk()
    else root.showVk()
  }

  // The voice pad's ⌨ half: bring the keyboard up/toggle it.
  function selectInputMode(mode) {
    if (mode === "keyboard") root.toggleVk()
  }

  function releaseMousehop() {
    if (mousehopCmd.running) return
    mousehopCmd.command = ["texp-mousehop", "release"]
    mousehopCmd.running = true
  }

  // ---- state pollers -----------------------------------------------------

  function onVkState(out) {
    var vis = /visible/.test(String(out || ""))
    var changed = vis !== root.vkVisible
    root.vkVisible = vis
    if (changed && vis && root.voiceInputOpen) root.hideVoiceInput()
    if (changed && !vis) root.cliKeysOpen = false
  }

  function pollVk() {
    if (!vkProbe.running) vkProbe.running = true
  }

  // Voxtype state names: idle / recording / transcribing / outputting /
  // streaming / eager-recording (written to the state file).
  function updateVoxtypeState(name) {
    var n = String(name || "").trim().toLowerCase()
    root.voxtypeUp = n !== ""
    root.recording = (n === "recording" || n === "streaming" || n === "eager-recording")
    root.transcribing = (n === "transcribing" || n === "outputting")
  }

  function pollVoxtype() {
    if (!vxStateProbe.running) vxStateProbe.running = true
  }

  // ---- probes ------------------------------------------------------------

  BoundedProcess {
    id: clearWinProbe
    command: ["hyprctl", "activewindow", "-j"]
    onStreamFinished: {
      var cls = ""
      try { cls = String((JSON.parse(output || "{}") || {}).class || "") } catch (e) {}
      var cmd = root.isTerminalClass(cls)
        ? ["wtype", "-M", "ctrl", "-k", "a", "-k", "k", "-m", "ctrl"]
        : ["wtype", "-M", "ctrl", "-k", "a", "-m", "ctrl", "-k", "BackSpace"]
      clrCmd.command = cmd
      console.log("clear: focused class=[" + cls + "] terminal=" + root.isTerminalClass(cls)
        + " -> " + cmd.join(" "))
      clrCmd.running = true
    }
  }

  // Visibility = the keyboard layer actually present in `hyprctl layers`
  // (wvkbd hides by unmapping, so a ▼-key collapse is seen too).
  BoundedProcess {
    id: vkProbe
    command: ["hyprctl", "layers", "-j"]
    onStreamFinished: {
      var vis = false
      var vkOut = ""
      var vkH = 0
      try {
        var d = JSON.parse(output || "{}")
        for (var out in d) {
          var levels = (d[out] || {}).levels || {}
          for (var lvl in levels) {
            var arr = levels[lvl] || []
            for (var i = 0; i < arr.length; i++) {
              var ns = String(arr[i].namespace || "")
              if (ns.indexOf("wvkbd") !== -1) {
                vis = true
                vkOut = String(out)
                vkH = Math.max(vkH, Number(arr[i].h) || 0)
              }
            }
          }
        }
      } catch (e) {}
      root.vkOutput = vis ? vkOut : ""
      root.vkHeight = vis ? vkH : 0
      root.onVkState(vis ? "visible" : "hidden")
    }
  }

  // Voxtype live state — same state file `voxtype status` reads, so the
  // hold-to-talk visuals agree with the F9 / SUPER+CTRL+X hotkeys as well.
  // The daemon removes the file on exit, so an empty read = daemon down.
  BoundedProcess {
    id: vxStateProbe
    command: ["bash", "-c", "cat \"$XDG_RUNTIME_DIR/voxtype/state\" 2>/dev/null; echo; true"]
    onStreamFinished: root.updateVoxtypeState(String(output || "").trim())
  }

  FileView {
    path: root.voxtypeStateDir
    watchChanges: true
    printErrors: false
    onFileChanged: if (!vxStateProbe.running) vxStateProbe.running = true
  }

  Timer {
    id: poller
    interval: 1500
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      root.pollVoxtype()
      root.pollVk()
    }
  }

  // ------------------------------------------------- voice overlay (bottom-right)
  Variants {
    model: Quickshell.screens
    delegate: Component {
      PanelWindow {
        id: voiceBar
        required property var modelData
        screen: modelData
        visible: root.voiceInputOpen
        color: "transparent"
        WlrLayershell.namespace: "maxt-tablet-voicebar"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore

        anchors { bottom: true; right: true }
        margins { bottom: 28; right: 28 }
        implicitWidth: 240
        implicitHeight: 230

        Column {
          anchors.centerIn: parent
          spacing: 12

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            text: {
              if (!root.voxtypeUp) return "Voxtype not running"
              if (root.transcribing) return "Transcribing…"
              if (root.holding || root.recording) return "Release to finish"
              return "Hold to talk"
            }
            color: Color.foreground
            font.family: Style.font.family
            font.pixelSize: Style.font.body
            opacity: 0.85
          }

          Rectangle {
            id: micCircle
            width: 120
            height: 120
            radius: width / 2
            anchors.horizontalCenter: parent.horizontalCenter
            color: (root.holding || root.recording)
              ? Util.alpha(Color.urgent, 0.9)
              : Util.alpha(Color.accent, 0.14)
            border.width: 2
            border.color: (root.holding || root.recording)
              ? Color.urgent : Util.alpha(Color.foreground, 0.35)

            Text {
              anchors.centerIn: parent
              text: "\uF130"          // fa-microphone
              color: (root.holding || root.recording) ? "#ffffff" : Color.foreground
              font.family: Style.font.family
              font.pixelSize: 44
            }

            // Expanding pulse ring while recording.
            Rectangle {
              anchors.fill: parent
              radius: width / 2
              color: "transparent"
              border.width: 3
              border.color: Util.alpha(Color.urgent, 0.6)
              visible: root.holding || root.recording
              opacity: 0.7
              SequentialAnimation on scale {
                running: root.holding || root.recording
                loops: Animation.Infinite
                NumberAnimation { from: 1.0; to: 1.35; duration: 700; easing.type: Easing.InOutQuad }
                NumberAnimation { from: 1.35; to: 1.0; duration: 700; easing.type: Easing.InOutQuad }
              }
            }

            // Press & hold = record, release = transcribe. mouseEnabled keeps
            // mouse presses working too; the area captures the touch, so
            // sliding off and releasing still fires onReleased.
            MultiPointTouchArea {
              anchors.fill: parent
              mouseEnabled: true
              onPressed: root.startRecording()
              onReleased: root.stopRecording()
              onCanceled: root.stopRecording()
            }
          }

          // Delete · Clear · Enter — fix or send the just-dictated text.
          Row {
            id: actionRow
            anchors.horizontalCenter: parent.horizontalCenter
            width: 232
            spacing: 8

            Rectangle {
              width: (actionRow.width - actionRow.spacing * 2) / 3
              height: 44
              radius: 12
              color: Util.alpha(Color.accent, 0.12)
              border.width: 1
              border.color: Util.alpha(Color.foreground, 0.3)
              Text {
                anchors.centerIn: parent
                text: "Delete"
                color: Color.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.body
              }
              TapHandler { onTapped: root.deleteLastChar() }
            }

            Rectangle {
              width: (actionRow.width - actionRow.spacing * 2) / 3
              height: 44
              radius: 12
              color: Util.alpha(Color.accent, 0.12)
              border.width: 1
              border.color: Util.alpha(Color.foreground, 0.3)
              Text {
                anchors.centerIn: parent
                text: "Clear"
                color: Color.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.body
              }
              TapHandler { onTapped: root.clearInput() }
            }

            Rectangle {
              width: (actionRow.width - actionRow.spacing * 2) / 3
              height: 44
              radius: 12
              color: Util.alpha(Color.accent, 0.12)
              border.width: 1
              border.color: Util.alpha(Color.foreground, 0.3)
              Text {
                anchors.centerIn: parent
                text: "Enter"
                color: Color.foreground
                font.family: Style.font.family
                font.pixelSize: Style.font.body
                font.bold: true
              }
              TapHandler { onTapped: root.sendEnter() }
            }
          }
        }

        // If the surface goes away mid-press (bar reload / shell reload),
        // never strand voxtype recording.
        Component.onDestruction: if (root.holding || root.recording) root.stopRecording()
      }
    }
  }

  // --------------------------------------- caret + CLI key pad (bottom-left)
  // Shown with voice input (bottom margin 40 == the voice bar's button row)
  // and with the on-screen keyboard (parked 12 px above the probed wvkbd
  // surface). Only the output that actually hosts the keyboard gets the pad.
  Variants {
    model: Quickshell.screens
    delegate: Component {
      PanelWindow {
        id: dirPad
        required property var modelData
        screen: modelData
        readonly property bool vkHere: root.vkVisible
          && String(root.vkOutput) === String(modelData.name || "")
        visible: root.voiceInputOpen || vkHere
        color: "transparent"
        WlrLayershell.namespace: "maxt-tablet-dirpad"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore

        anchors { bottom: true; left: true }
        margins {
          bottom: root.voiceInputOpen ? 40 : Math.max(root.vkHeight + 12, 40)
          left: 28
        }
        implicitWidth: 232
        // Collapsed = toggle bar + caret arrows (32 + 8 + 44 = 84).
        // Expanded adds the 4x2 CLI grid above the bar (96 + 8 + 32 + 8 + 44).
        implicitHeight: root.cliKeysOpen ? 188 : 84

        Column {
          anchors.centerIn: parent
          spacing: 8

          // Agent control keys (pi / codex CLI) — only while expanded.
          Grid {
            visible: root.cliKeysOpen
            columns: 4
            spacing: 8
            width: 232

            Repeater {
              model: root.cliKeys
              delegate: Rectangle {
                id: cliKey
                required property var modelData
                width: 52
                height: 44
                radius: 12
                color: Util.alpha(Color.accent, 0.12)
                border.width: 1
                border.color: Util.alpha(Color.foreground, 0.3)
                Text {
                  anchors.centerIn: parent
                  text: cliKey.modelData.label
                  color: Color.foreground
                  font.family: Style.font.family
                  font.pixelSize: Style.font.body
                }
                TapHandler { onTapped: root.sendCliKey(cliKey.modelData.argv) }
              }
            }
          }

          // Toggle bar. The chevron points the way the grid appears (up).
          Row {
            spacing: 8

            Rectangle {
              width: 232
              height: 32
              radius: 12
              color: Util.alpha(Color.accent, 0.08)
              border.width: 1
              border.color: Util.alpha(Color.foreground, 0.22)
              Text {
                anchors.centerIn: parent
                text: root.cliKeysOpen ? "CLI keys  \u25BC" : "CLI keys  \u25B2"
                color: Util.alpha(Color.foreground, 0.85)
                font.family: Style.font.family
                font.pixelSize: Style.font.bodySmall
              }
              TapHandler { onTapped: root.cliKeysOpen = !root.cliKeysOpen }
            }
          }

          Row {
            spacing: 8

            Rectangle {
              width: 52
              height: 44
              radius: 12
              color: Util.alpha(Color.accent, 0.12)
              border.width: 1
              border.color: Util.alpha(Color.foreground, 0.3)
              Text {
                anchors.centerIn: parent
                text: "\u2190"
                color: Color.foreground
                font.family: Style.font.family
                font.pixelSize: 22
              }
              TapHandler { onTapped: root.sendArrow("Left") }
            }
            Rectangle {
              width: 52
              height: 44
              radius: 12
              color: Util.alpha(Color.accent, 0.12)
              border.width: 1
              border.color: Util.alpha(Color.foreground, 0.3)
              Text {
                anchors.centerIn: parent
                text: "\u2192"
                color: Color.foreground
                font.family: Style.font.family
                font.pixelSize: 22
              }
              TapHandler { onTapped: root.sendArrow("Right") }
            }
            Rectangle {
              width: 52
              height: 44
              radius: 12
              color: Util.alpha(Color.accent, 0.12)
              border.width: 1
              border.color: Util.alpha(Color.foreground, 0.3)
              Text {
                anchors.centerIn: parent
                text: "\u2191"
                color: Color.foreground
                font.family: Style.font.family
                font.pixelSize: 22
              }
              TapHandler { onTapped: root.sendArrow("Up") }
            }
            Rectangle {
              width: 52
              height: 44
              radius: 12
              color: Util.alpha(Color.accent, 0.12)
              border.width: 1
              border.color: Util.alpha(Color.foreground, 0.3)
              Text {
                anchors.centerIn: parent
                text: "\u2193"
                color: Color.foreground
                font.family: Style.font.family
                font.pixelSize: 22
              }
              TapHandler { onTapped: root.sendArrow("Down") }
            }
          }
        }
      }
    }
  }

  // ---------------------------------------------------------------- IPC

  IpcHandler {
    target: "maxt.tablet-lite"

    function getState(): string {
      return JSON.stringify({
        voiceInputOpen: root.voiceInputOpen,
        cliKeysOpen: root.cliKeysOpen,
        voiceRecording: root.recording,
        voxtypeUp: root.voxtypeUp,
        vkVisible: root.vkVisible,
        vkOutput: root.vkOutput,
        vkHeight: root.vkHeight,
        version: root.pluginVersion
      })
    }

    function voiceInputToggle(): string {
      root.toggleVoiceInput()
      return root.voiceInputOpen ? "open" : "closed"
    }

    function voiceInputShow(): string {
      root.showVoiceInput()
      return "open"
    }

    function voiceInputHide(): string {
      root.hideVoiceInput()
      return "closed"
    }

    function keyboardToggle(): string {
      root.toggleVk()
      return root.vkVisible ? "visible" : "hidden"
    }

    function keyboardShow(): string {
      root.showVk()
      return "visible"
    }

    function keyboardHide(): string {
      root.hideVk()
      return "hidden"
    }

    function cliKeysToggle(): string {
      root.cliKeysOpen = !root.cliKeysOpen
      return root.cliKeysOpen ? "open" : "closed"
    }

    function clearNow(): string {
      root.clearInput()
      return "ok"
    }
  }
}

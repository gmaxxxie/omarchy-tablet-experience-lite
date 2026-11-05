import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons

// Tablet Lite — the simplified tablet experience: virtual keyboard, voice
// input and screen rotation. No laptop/tablet state machine, no handwriting,
// no window manager, no bar declutter.
//
// Rotation: the bar's rotate icon and SUPER+SHIFT+R step the display through
// 0° / 90° / 180° / 270°; right-clicking the icon (or the IPC method) turns on
// sensor-following auto-rotate via `tlit-orient` (sysfs accelerometer). Every
// rotation preserves the monitor scale and keeps the touch calibration matrix
// in step (tlit-rotate). The last angle is persisted, so a shell restart does
// not silently put the screen back to landscape.
//
// Voice input: the bar's mic icon opens a bottom hold-to-talk button.
// Press & hold -> `omarchy dictation start`, release -> `omarchy dictation
// stop` (falling back to `voxtype record ...` when no backend is configured):
// omarchy 4.5 owns the backend choice (voxtype, superwhisper, ...) and the
// same commands the ALT+SPACE / Alt_R / F9 hotkeys use, so the touch button
// and the keyboard cannot drift apart. The backend transcribes locally and
// types the text at the cursor with wtype (CJK works everywhere). Delete /
// Clear / Enter fix or submit the dictated line, the left-side caret pad
// moves through it, and the expandable "CLI keys" grid sends esc / / / tab /
// ⇧tab / ⌃C / ⌃D / ⌃J / ⌃T for pi / codex CLI on a touch-only screen. The pad
// is voice-mode only — with the keyboard up, the keyboard itself carries
// those keys. The overlay follows voxtype's state file when voxtype is the
// backend, so the visuals agree with the F9 / SUPER+CTRL+X hotkeys too.
//
// Virtual keyboard: `tlit-vk` drives wvkbd-deskintl (a wlroots-native build
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
//   rotationNext | rotateLeft | rotateRight | setRotation <auto|0|1|2|3>
//   autoRotateToggle | setAutoOrient <on|off>
Item {
  id: root

  Component.onCompleted: {
    console.log("tablet-lite Service LOADED v" + root.pluginVersion)
    root.probeDictation()
  }

  property var shell: null
  readonly property string pluginVersion: "1.8.0"

  // ---- labels -------------------------------------------------------------
  // The shell's language (~/.config/omarchy/language, which omarchy exposes as
  // I18n.language) picks the table; an unknown key falls back to English, so
  // a partial translation is safe. tf() fills a %1 hole.
  readonly property bool useZh: String(I18n.language || "").toLowerCase().indexOf("zh") === 0
  readonly property var enLabels: ({
    "vk.tip.up": "Keyboard is up — tap to close (Super+U)",
    "vk.tip.down": "Keyboard — tap to type on screen (Super+U)",
    "voice.tip.up": "Hide voice input button",
    "voice.tip.down": "Voice input — hold to talk",
    "rotate.tip.auto": "Rotation: auto (sensor) — tap to choose",
    "rotate.tip.angle": "Rotation: %1 — tap to choose",
    "tablet.tip": "Tablet controls — keyboard / voice / rotation",
    "tablet.header": "Tablet",
    "popup.keyboard": "Keyboard",
    "popup.keyboard.up": "Keyboard (up)",
    "popup.voice": "Voice input",
    "popup.voice.up": "Voice (open)",
    "rotate.header": "Rotation",
    "rotate.auto": "Auto (sensor)",
    "rotate.prev": "90° ⟲",
    "rotate.next": "90° ⟳",
    "osd.rotate": "Rotate: %1",
    "osd.auto.on": "Auto-rotate: on (sensor)",
    "osd.auto.off": "Auto-rotate: off",
    "voice.hold": "Hold to talk",
    "voice.release": "Release to finish",
    "voice.transcribing": "Transcribing…",
    "voice.down": "Dictation not running",
    "action.delete": "Delete",
    "action.clear": "Clear",
    "action.enter": "Enter",
    "cli.keys": "CLI keys"
  })
  readonly property var zhLabels: ({
    "vk.tip.up": "键盘已打开 — 点此收起 (Super+U)",
    "vk.tip.down": "屏幕键盘 — 点此输入 (Super+U)",
    "voice.tip.up": "收起语音输入",
    "voice.tip.down": "语音输入 — 按住说话",
    "rotate.tip.auto": "旋转：自动（传感器）— 点此选择",
    "rotate.tip.angle": "旋转：%1 — 点此选择",
    "tablet.tip": "平板控制 — 键盘 / 语音 / 旋转",
    "tablet.header": "平板",
    "popup.keyboard": "屏幕键盘",
    "popup.keyboard.up": "屏幕键盘（已打开）",
    "popup.voice": "语音输入",
    "popup.voice.up": "语音输入（已打开）",
    "rotate.header": "屏幕旋转",
    "rotate.auto": "自动（传感器）",
    "rotate.prev": "左转 90°",
    "rotate.next": "右转 90°",
    "osd.rotate": "旋转：%1",
    "osd.auto.on": "自动旋转：开启（传感器）",
    "osd.auto.off": "自动旋转：关闭",
    "voice.hold": "按住说话",
    "voice.release": "松开结束",
    "voice.transcribing": "转写中…",
    "voice.down": "听写服务未运行",
    "action.delete": "删除",
    "action.clear": "清空",
    "action.enter": "回车",
    "cli.keys": "CLI 按键"
  })

  function t(key) {
    if (root.useZh) {
      var zh = root.zhLabels[key]
      if (zh !== undefined) return zh
    }
    var en = root.enLabels[key]
    return en !== undefined ? en : String(key)
  }

  function tf(key, value) {
    return String(root.t(key)).replace("%1", String(value))
  }

  // Voice input (hold-to-talk overlay).
  //   voiceInputOpen  the bottom hold-to-talk overlay is showing
  //   holding         our button is pressed (authority for start/stop)
  //   recording       backend state file says recording/streaming
  //   transcribing    backend state file says transcribing/outputting
  //   voxtypeUp       backend usable (state file readable, or a non-voxtype
  //                   omarchy dictation backend is configured)
  //   dictationBackend  `omarchy-default-dictation` output; empty = use the
  //                   bare `voxtype record` path
  property bool voiceInputOpen: false
  property bool cliKeysOpen: false
  property bool holding: false
  property bool recording: false
  property bool transcribing: false
  property bool voxtypeUp: false
  property string dictationBackend: ""

  // On-screen keyboard visibility (the CLI/caret pad is voice-mode only and
  // deliberately does not float above the keyboard).
  property bool vkVisible: false

  // Lock-screen keyboard. The Omarchy lock view is a Quickshell
  // ext-session-lock surface; wvkbd and the floating invoke button are
  // rendered above it via the above_lock layer rules in tablet-lite.lua.
  // `locked` mirrors `omarchy-shell lock status`; lockVkShown remembers that
  // WE raised the keyboard so it can be put down again on unlock.
  property bool locked: false
  property bool lockVkShown: false

  // Rotation state. `rotation` is the last applied transform (0-3); "auto" is
  // a separate flag because the sensor keeps changing the live angle.
  // These two survive shell restarts in a plain file (see setPref below):
  // auto is the default, and picking an angle in the rotation picker turns it
  // off.
  property string rotation: ""
  property bool autoOrient: true
  property bool prefsLoaded: false
  property var pendingPrefs: ({})
  readonly property string statePath: (Quickshell.env("XDG_STATE_HOME")
    || (Quickshell.env("HOME") + "/.local/state")) + "/tablet-lite/state"
  property string orientation: "unknown"
  property string appliedFor: ""
  property bool pendingRelative: false
  property int liveTransform: 0
  // Live orientation from hyprctl (not the persisted preference), so the bar
  // folds in portrait even if the display was rotated outside this service.
  readonly property bool portrait: root.liveTransform === 1 || root.liveTransform === 3
  readonly property var rotationRing: ["0", "1", "2", "3"]

  // Preferences are kept in $XDG_STATE_HOME/tablet-lite/state by tlit-state:
  // Quickshell's PersistentProperties writes nothing in this shell build (no
  // state dir is ever created, so rotation and the auto flag silently reset on
  // every restart). A plain key=value file is boring and verifiable.
  FileView {
    id: prefsFile
    path: root.statePath
    printErrors: false
    onLoaded: root.applyPrefs(text())
  }

  // Writes are queued: two quick taps cannot drop one of them.
  BoundedProcess {
    id: prefsWriter
    command: ["tlit-state", "set", "rotation", "0"]
    onStreamFinished: root.flushPrefs()
  }

  function applyPrefs(raw) {
    var values = {}
    var lines = String(raw || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var eq = lines[i].indexOf("=")
      if (eq > 0) values[lines[i].slice(0, eq).trim()] = lines[i].slice(eq + 1).trim()
    }
    root.rotation = values.rotation || ""
    root.autoOrient = values.auto === undefined ? true : values.auto === "on"
    root.prefsLoaded = true
    root.initRotation()
  }

  function setPref(key, value) {
    var v = String(value)
    if (key === "rotation") root.rotation = v
    else if (key === "auto") root.autoOrient = (v === "on")
    root.pendingPrefs[key] = v
    root.flushPrefs()
  }

  function flushPrefs() {
    if (prefsWriter.running) return
    var keys = Object.keys(root.pendingPrefs)
    if (keys.length === 0) return
    var key = keys[0]
    var value = root.pendingPrefs[key]
    delete root.pendingPrefs[key]
    prefsWriter.command = ["tlit-state", "set", key, value]
    prefsWriter.running = true
  }


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
  BoundedProcess {
    id: rotateCmd
    deadlineMs: 8000
    onStreamFinished: {
      // Relative steps print the resulting transform; persist it so the next
      // shell start restores the angle the user actually ended up at.
      if (root.pendingRelative) {
        root.pendingRelative = false
        var m = /^([0-3])\s*$/.exec(String(output || "").trim())
        if (m) {
          root.setPref("rotation", m[1])
          root.liveTransform = Number(m[1])
          root.osd("rotate-cw", root.tf("osd.rotate", root.rotationLabel(m[1])))
        }
      }
    }
  }
  BoundedProcess { id: osdCmd }

  // ---- rotation ----------------------------------------------------------

  function rotationLabel(value) {
    var v = String(value || "")
    if (root.autoOrient || v === "auto") return "auto"
    if (v === "1") return "90°"
    if (v === "2") return "180°"
    if (v === "3") return "270°"
    return "0°"
  }

  // Sensor posture -> Hyprland transform (same convention as the full plugin).
  function rotationTransform(label) {
    if (label === "left-up") return "1"
    if (label === "right-up") return "3"
    if (label === "bottom-up") return "2"
    return "0"
  }

  function osd(icon, message) {
    if (osdCmd.running) return
    osdCmd.command = ["omarchy", "osd", "-i", icon, "-m", message]
    osdCmd.running = true
  }

  // Apply one absolute transform. `silent` suppresses the tlit-rotate OSD
  // (used for startup restore and sensor-following); manual actions show it.
  function applyRotation(value, silent) {
    if (rotateCmd.running) return false
    var target = String(value || "0")
    if (root.rotationRing.indexOf(target) === -1) target = "0"
    // Always -s: tlit-rotate's own OSD is English-only, so the text is shown
    // here instead, in the shell's language.
    rotateCmd.command = ["tlit-rotate", "-s", target]
    rotateCmd.running = true
    root.setPref("rotation", target)
    root.liveTransform = Number(target)
    if (!silent) root.osd("rotate-cw", root.tf("osd.rotate", root.rotationLabel(target)))
    return true
  }

  // One 90° step from the CURRENT transform: `next` counter-clockwise,
  // `prev` clockwise (same convention as the full plugin).
  function rotateStep(dir) {
    if (rotateCmd.running) return
    root.setPref("auto", "off")
    root.appliedFor = ""
    root.pendingRelative = true
    rotateCmd.command = ["tlit-rotate", "-s", dir]
    rotateCmd.running = true
  }

  function rotationNext() { root.rotateStep("next") }
  function rotationPrev() { root.rotateStep("prev") }

  // Bar right-click / IPC: sensor-following on/off. Turning it off keeps the
  // screen where the sensor last put it.
  function toggleAutoRotate() {
    root.setPref("auto", root.autoOrient ? "off" : "on")
    root.appliedFor = ""
    if (root.autoOrient) {
      root.osd("rotate-cw", root.t("osd.auto.on"))
      root.ensureOrientationWatch()
    } else {
      root.osd("rotate-cw", root.t("osd.auto.off"))
    }
  }

  function setRotationPreset(value) {
    var v = String(value || "").toLowerCase()
    if (v === "auto") {
      if (!root.autoOrient) root.toggleAutoRotate()
      else root.ensureOrientationWatch()
      return
    }
    if (root.rotationRing.indexOf(v) === -1) return
    root.setPref("auto", "off")
    root.appliedFor = ""
    root.applyRotation(v, false)
  }

  function applyOrientation() {
    if (!root.autoOrient) return
    if (root.orientation === "unknown") return
    if (root.appliedFor === root.orientation) return
    if (root.applyRotation(root.rotationTransform(root.orientation), true))
      root.appliedFor = root.orientation
  }

  // Auto-rotate keeps ONE long-lived sensor reader (`tlit-orient --watch`),
  // which prints a posture line only when it changes. That replaces a 380 ms
  // process spawn every 1.5 s with a reader that costs well under 1% of a
  // core, and turns the posture into an event instead of a poll.
  function ensureOrientationWatch() {
    if (!root.autoOrient) {
      if (orientationWatch.running) orientationWatch.running = false
      return
    }
    if (!orientationWatch.running) orientationWatch.running = true
  }

  onAutoOrientChanged: root.ensureOrientationWatch()

  // Runs once after the shell starts (PersistentProperties restore may be
  // asynchronous): restore the last angle, or adopt the current one on first
  // install. Auto mode starts the sensor reader instead.
  function initRotation() {
    if (root.autoOrient) { root.ensureOrientationWatch(); return }
    if (root.rotation) root.applyRotation(root.rotation, true)
    else if (!transformProbe.running) transformProbe.running = true
  }

  // ---- voice input -------------------------------------------------------

  function toggleVoiceInput() {
    if (root.voiceInputOpen) root.hideVoiceInput()
    else root.showVoiceInput()
  }

  function showVoiceInput() {
    root.voiceInputOpen = true
    root.releaseMousehop()   // keys from this overlay must land here
    root.probeDictation()    // a backend may have been configured since start
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

  // Press = start recording; gated locally so a repeated press while already
  // holding cannot double-start the backend. `omarchy dictation` when a
  // backend is configured (it respects the user's voxtype/superwhisper choice
  // and its lock), otherwise the voxtype-specific command.
  function startRecording() {
    if (root.holding || root.recording) return
    root.holding = true
    vxCmd.command = root.dictationBackend
      ? ["omarchy", "dictation", "start"]
      : ["voxtype", "record", "start"]
    vxCmd.running = true
  }

  // Release = stop -> transcribe + type at the cursor. Sent unconditionally on
  // our own release (harmless when idle) so a very fast tap that the state
  // poll never saw still ends its recording.
  function stopRecording() {
    root.holding = false
    vxCmd.command = root.dictationBackend
      ? ["omarchy", "dictation", "stop"]
      : ["voxtype", "record", "stop"]
    vxCmd.running = true
  }

  // Which dictation backend omarchy has selected: "" when none is configured
  // (then the raw voxtype path is the only thing that can work).
  function probeDictation() {
    if (!dictationProbe.running) dictationProbe.running = true
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
    vkCmd.command = ["tlit-vk", "hide"]
    vkCmd.running = true
  }

  function showVk() {
    // The voice overlay occupies the same bottom strip.
    if (root.voiceInputOpen) root.hideVoiceInput()
    root.releaseMousehop()   // the keyboard types into the focused app
    vkCmd.command = ["tlit-vk", "show"]
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

  // Pre-start the keyboard HIDDEN at shell start, so the lock screen can
  // raise it with a signal instead of connecting a new Wayland client while
  // the session is already locked (the flaky corner for ext-session-lock).
  function preStartVk() {
    if (vkCmd.running) return
    vkCmd.command = ["tlit-vk", "start-hidden"]
    vkCmd.running = true
  }

  function releaseMousehop() {
    if (mousehopCmd.running) return
    mousehopCmd.command = ["tlit-mousehop", "release"]
    mousehopCmd.running = true
  }

  // ---- state pollers -----------------------------------------------------

  function setVkVisible(vis) {
    var changed = vis !== root.vkVisible
    root.vkVisible = vis
    if (changed && vis && root.voiceInputOpen) root.hideVoiceInput()
    if (changed && !vis) root.cliKeysOpen = false
  }

  function onVkState(out) {
    root.setVkVisible(/visible/.test(String(out || "")))
  }

  function pollVk() {
    if (!vkProbe.running) vkProbe.running = true
  }

  // Hyprland's event socket: `openlayer` / `closelayer` is the keyboard's real
  // state, so folding it away with its own ▼ key is reflected the moment the
  // layer unmaps instead of up to 1.5 s later. Monitor events re-read the
  // transform, which has no event of its own.
  function onHyprEvent(line) {
    root.hyprEventCount++
    var m = /^(openlayer|closelayer)>>(.*)$/.exec(line)
    if (m) {
      if (String(m[2]).indexOf("wvkbd") !== -1)
        root.setVkVisible(m[1] === "openlayer")
      return
    }
    if (/^monitor(added|removed|layout)/.test(line)) root.pollTransform()
  }

  // Backend state names: idle / recording / transcribing / outputting /
  // streaming / eager-recording (written to voxtype's state file). A backend
  // without a state file (superwhisper) is driven by our own press events.
  function updateVoxtypeState(name) {
    var n = String(name || "").trim().toLowerCase()
    if (root.dictationBackend && root.dictationBackend !== "voxtype") {
      root.voxtypeUp = true
      root.recording = root.holding
      root.transcribing = false
      return
    }
    root.voxtypeUp = n !== ""
    root.recording = (n === "recording" || n === "streaming" || n === "eager-recording")
    root.transcribing = (n === "transcribing" || n === "outputting")
  }

  function pollVoxtype() {
    if (!vxStateProbe.running) vxStateProbe.running = true
  }

  // Lock state: locked -> raise the keyboard for the password field (typing
  // and fingerprint both stay available); unlocked -> put it back down. The
  // show is unconditional so a stale visibility state cannot skip the raise.
  function onLockState(next) {
    var changed = next !== root.locked
    root.locked = next
    if (!changed) return
    if (next) {
      root.lockVkShown = true
      root.showVk()
    } else if (root.lockVkShown) {
      root.lockVkShown = false
      root.hideVk()
    }
  }

  function pollLock() {
    if (!lockProbe.running) lockProbe.running = true
  }

  function pollTransform() {
    if (!transformProbe.running) transformProbe.running = true
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
      try {
        var d = JSON.parse(output || "{}")
        for (var out in d) {
          var levels = (d[out] || {}).levels || {}
          for (var lvl in levels) {
            var arr = levels[lvl] || []
            for (var i = 0; i < arr.length; i++) {
              if (String(arr[i].namespace || "").indexOf("wvkbd") !== -1) {
                vis = true
                break
              }
            }
            if (vis) break
          }
          if (vis) break
        }
      } catch (e) {}
      root.onVkState(vis ? "visible" : "hidden")
    }
  }

  // `omarchy-shell lock status` is the lock plugin's own authoritative JSON
  // and keeps answering IPC while the session is locked (the shell process IS
  // the ext-session-lock client).
  BoundedProcess {
    id: lockProbe
    command: ["omarchy-shell", "lock", "status"]
    onStreamFinished: {
      var locked = false
      try {
        var d = JSON.parse(output || "{}")
        locked = !!(d && d.locked)
      } catch (e) {}
      root.onLockState(locked)
    }
  }

  // The configured dictation backend (omarchy 4.5 owns that choice).
  BoundedProcess {
    id: dictationProbe
    command: ["omarchy-default-dictation"]
    onStreamFinished: root.dictationBackend = String(output || "").trim()
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

  // Auto-rotate sensor reader: one long-lived process, labels on change only.
  Process {
    id: orientationWatch
    command: ["tlit-orient", "--watch"]
    stdout: SplitParser {
      onRead: function(line) {
        var label = String(line || "").trim()
        if (!label) return
        root.orientation = label
        root.applyOrientation()
      }
    }
    onExited: {
      // Sensor vanished or could not be read: stop trusting the last posture
      // and retry while auto-rotate is still on.
      root.orientation = "unknown"
      if (root.autoOrient) orientationRetry.start()
    }
  }

  Timer {
    id: orientationRetry
    interval: 3000
    repeat: false
    onTriggered: root.ensureOrientationWatch()
  }

  BoundedProcess {
    id: transformProbe
    command: ["hyprctl", "monitors", "-j"]
    onStreamFinished: {
      try {
        var ms = JSON.parse(output || "[]")
        if (!Array.isArray(ms) || ms.length === 0) return
        var t = String(Number(ms[0].transform || 0))
        root.liveTransform = Number(t)
        // Adopt the live angle on first run, without writing a preference:
        // an angle the user never picked must not turn auto-mode into a
        // fixed one on the next start.
        if (!root.rotation) root.rotation = t
      } catch (e) {}
    }
  }

  // Hyprland's event socket — the keyboard's visibility and monitor changes
  // arrive here instead of being polled. `connected` follows whether the
  // session actually has a Hyprland instance signature.
  property int hyprEventCount: 0

  readonly property string hyprEventSocket: {
    var his = Quickshell.env("HYPRLAND_INSTANCE_SIGNATURE") || ""
    return his ? root.runtimeDir + "/hypr/" + his + "/.socket2.sock" : ""
  }

  Socket {
    id: hyprEventConn
    path: root.hyprEventSocket
    connected: root.hyprEventSocket !== ""
    parser: SplitParser {
      onRead: function(line) { root.onHyprEvent(String(line || "")) }
    }
    // A (re)connect can miss events that happened while it was down.
    onConnectedChanged: if (connected) {
      root.pollVk()
      root.pollTransform()
    }
  }

  // Lock state has no event source (ext-session-lock is not a layer), and the
  // keyboard must come up with the lock, so this one stays a cheap poll: the
  // lock plugin's IPC answers in ~7 ms.
  Timer {
    id: lockPoller
    interval: 1500
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.pollLock()
  }

  // Safety net for the event-driven state above: the keyboard layer, the
  // voxtype state file and the transform each have an event/watch already, so
  // this only catches one that was missed (socket down, file created late).
  Timer {
    id: slowPoller
    interval: 5000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      root.pollVk()
      root.pollVoxtype()
      root.pollTransform()
    }
  }

  // The shell may restore PersistentProperties asynchronously; wait before
  // applying the saved angle so a stale empty value cannot reset the screen.
  Timer {
    id: settleTimer
    interval: 2500
    running: true
    repeat: false
    triggeredOnStart: true
    onTriggered: {
      root.initRotation()
      root.preStartVk()
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
              if (!root.voxtypeUp) return root.t("voice.down")
              if (root.transcribing) return root.t("voice.transcribing")
              if (root.holding || root.recording) return root.t("voice.release")
              return root.t("voice.hold")
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
                text: root.t("action.delete")
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
                text: root.t("action.clear")
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
                text: root.t("action.enter")
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
  // Voice-mode only: with the on-screen keyboard up, the keyboard already
  // carries Esc / Tab / Ctrl / arrows, so the pad would just cover content
  // above it. Bottom margin 40 == the voice bar's button row.
  Variants {
    model: Quickshell.screens
    delegate: Component {
      PanelWindow {
        id: dirPad
        required property var modelData
        screen: modelData
        visible: !root.locked && root.voiceInputOpen
        color: "transparent"
        WlrLayershell.namespace: "maxt-tablet-dirpad"
        WlrLayershell.layer: WlrLayer.Top
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore

        anchors { bottom: true; left: true }
        margins { bottom: 40; left: 28 }
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
                text: root.t("cli.keys") + (root.cliKeysOpen ? "  \u25BC" : "  \u25B2")
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

  // ------------------------------------------- lock-screen keyboard button
  // A floating “keyboard” button on the LOCK screen, parked just right of the
  // centred password field. It re-invokes the keyboard after the ▼ key folds
  // it away; wvkbd itself is rendered above the lock by the above_lock rule.
  Variants {
    model: Quickshell.screens
    delegate: Component {
      PanelWindow {
        id: lockVkButton
        required property var modelData
        screen: modelData
        visible: root.locked
        color: "transparent"
        WlrLayershell.namespace: "maxt-tablet-vk-toggle"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
        exclusionMode: ExclusionMode.Ignore

        // Just right of the centred password field (381x67), on its centre line.
        anchors { right: true; bottom: true }
        margins {
          right: Math.max(0, modelData.width / 2 - 190 - 36 - 64)
          bottom: Math.max(0, modelData.height / 2 - 32)
        }
        implicitWidth: 64
        implicitHeight: 64

        Rectangle {
          anchors.fill: parent
          radius: 32
          color: Util.alpha(Color.accent, 0.85)
          border.width: 2
          border.color: root.vkVisible ? Color.foreground : Util.alpha(Color.foreground, 0.6)

          Text {
            anchors.centerIn: parent
            text: "\uF11C"        // fa-keyboard
            color: "#ffffff"
            font.family: Style.font.family
            font.pixelSize: 26
          }

          TapHandler {
            onTapped: {
              // Pure invoke: always show (idempotent), never toggle into a
              // stale-state double press. The ▼ key is the way to fold it.
              root.lockVkShown = true
              root.showVk()
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
        dictationBackend: root.dictationBackend,
        vkVisible: root.vkVisible,
        rotation: root.rotation,
        rotationLabel: root.rotationLabel(root.rotation),
        liveTransform: root.liveTransform,
        portrait: root.portrait,
        autoOrient: root.autoOrient,
        orientation: root.orientation,
        locked: root.locked,
        lockVkShown: root.lockVkShown,
        hyprEventSocket: root.hyprEventSocket,
        hyprEventConnected: hyprEventConn.connected,
        hyprEventsSeen: root.hyprEventCount,
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

    function rotationNext(): string {
      root.rotationNext()
      return root.rotationLabel(root.rotation)
    }

    function rotateLeft(): string {
      root.rotateStep("next")
      return root.rotationLabel(root.rotation)
    }

    function rotateRight(): string {
      root.rotateStep("prev")
      return root.rotationLabel(root.rotation)
    }

    function setRotation(value: string): string {
      root.setRotationPreset(String(value || "").toLowerCase())
      return root.rotationLabel(root.rotation)
    }

    function autoRotateToggle(): string {
      root.toggleAutoRotate()
      return root.autoOrient ? "on" : "off"
    }

    function setAutoOrient(value: string): string {
      var v = String(value || "").toLowerCase()
      var on = (v === "on" || v === "true" || v === "1" || v === "yes")
      if (on !== root.autoOrient) root.toggleAutoRotate()
      else if (on) root.ensureOrientationWatch()
      return root.autoOrient ? "on" : "off"
    }
  }
}

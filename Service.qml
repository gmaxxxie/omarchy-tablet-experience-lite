import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import qs.Commons

// Tablet Lite — only what a touch tablet needs and Omarchy does not already
// provide: an on-screen keyboard (including on the lock screen), a touch
// trigger for Omarchy's own dictation, and screen rotation.
//
// Everything Omarchy 4.5 already owns is used, not re-implemented:
//   * dictation is `omarchy dictation start|stop` — the same commands the
//     ALT+SPACE / Alt_R hotkeys run, so the backend (voxtype, superwhisper, …)
//     and its lock stay Omarchy's business. This plugin adds nothing but the
//     hold-to-talk button; the text is typed by the backend at the cursor.
//   * the rotation OSD is `omarchy osd`, the keyboard theme comes from
//     `omarchy theme color --all`, and the lock state is
//     `omarchy-shell lock status`.
// Removed on purpose (they were duplication): the voxtype state-file poller and
// dictation-backend probe (Omarchy owns the backend, its lock and the typing).
// The voice pad itself keeps its own keys — Delete / Clear / Enter, the caret
// arrows and the "CLI keys" grid — because they are what makes dictation
// usable on a touch-only screen without raising the keyboard.
//
// Rotation: the bar's ⟳ button opens a picker — auto (sensor, the default) and
// 0° / 90° / 180° / 270°; SUPER+SHIFT+R steps 90°. Every rotation preserves the
// monitor scale and keeps the touch calibration matrix in step
// (`tlit-rotate`), the sensor is read by one long-lived `tlit-orient --watch`,
// and the chosen angle / auto flag live in `tlit-state` so a shell restart
// keeps them.
//
// Virtual keyboard: `tlit-vk` drives wvkbd-deskintl (a wlroots-native build
// with Ctrl/Super/Alt, F-keys, a number row, arrows and a ▼ collapse key).
// Visibility is read from `hyprctl layers` and from Hyprland's openlayer /
// closelayer events, so the ▼ key is reflected immediately.
//
// Voice input and the keyboard are mutually exclusive: opening one closes the
// other.
//
// IPC (omarchy-shell maxt.tablet-lite <method>):
//   getState | voiceInputToggle | voiceInputShow | voiceInputHide
//   keyboardToggle | keyboardShow | keyboardHide
//   cliKeysToggle | clearNow
//   rotationNext | rotationPrev | setRotation <auto|0|1|2|3> | autoRotateToggle
Item {
  id: root

  Component.onCompleted: console.log("tablet-lite Service LOADED v" + root.pluginVersion)

  property var shell: null
  readonly property string pluginVersion: "2.0.1"

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
    "osd.rotate": "Rotate: %1",
    "osd.auto.on": "Auto-rotate: on (sensor)",
    "osd.auto.off": "Auto-rotate: off",
    "voice.hold": "Hold to talk",
    "voice.release": "Release to finish",
    "voice.transcribing": "Transcribing…",
    "voice.noBackend": "No dictation backend — Setup ▸ Defaults ▸ Dictation",
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
    "osd.rotate": "旋转：%1",
    "osd.auto.on": "自动旋转：开启（传感器）",
    "osd.auto.off": "自动旋转：关闭",
    "voice.hold": "按住说话",
    "voice.release": "松开结束",
    "voice.transcribing": "转写中…",
    "voice.noBackend": "没有听写后端 — 设置 ▸ 默认 ▸ Dictation",
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
  //   holding         our button is pressed; start/stop follow this
  //   busy            `omarchy dictation stop` is still running (the backend
  //                   transcribes and types while it does)
  property bool voiceInputOpen: false
  property bool holding: false
  property bool busy: false
  // The expandable "CLI keys" grid lives in the voice pad (bottom-left).
  property bool cliKeysOpen: false
  // One dictation command at a time: a release that arrives while `start` is
  // still running is queued instead of overwriting the command.
  property string vxAction: ""
  property string vxQueued: ""
  property bool vxRunning: false

  // On-screen keyboard visibility (wvkbd layer mapped).
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
  property var pendingPrefs: ({})
  // A user action that lands before the state file finishes loading must win:
  // the asynchronous onLoaded would otherwise overwrite it.
  property bool prefsDirty: false
  readonly property string statePath: (Quickshell.env("XDG_STATE_HOME")
    || (Quickshell.env("HOME") + "/.local/state")) + "/tablet-lite/state"
  property string orientation: "unknown"
  property string appliedFor: ""
  property bool pendingRelative: false
  // Our own in-flight flag: Process.running only turns true once the child has
  // started, so two taps in one turn would overwrite each other's command.
  property bool rotating: false
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

  // Writes are queued: two quick taps cannot drop one of them. `writerBusy` is
  // our own flag — Quickshell's Process reports `running` only once the child
  // has actually started, so it cannot gate a second write in the same turn.
  property bool writerBusy: false

  BoundedProcess {
    id: prefsWriter
    command: ["tlit-state", "set", "rotation", "0"]
    onStreamFinished: {
      root.writerBusy = false
      root.flushPrefs()
    }
  }

  function applyPrefs(raw) {
    var values = {}
    var lines = String(raw || "").split("\n")
    for (var i = 0; i < lines.length; i++) {
      var eq = lines[i].indexOf("=")
      if (eq > 0) values[lines[i].slice(0, eq).trim()] = lines[i].slice(eq + 1).trim()
    }
    if (!root.prefsDirty) {
      root.rotation = values.rotation || ""
      root.autoOrient = values.auto === undefined ? true : values.auto === "on"
    }
    root.initRotation()
  }

  function setPref(key, value) {
    var v = String(value)
    root.prefsDirty = true
    if (key === "rotation") root.rotation = v
    else if (key === "auto") root.autoOrient = (v === "on")
    root.pendingPrefs[key] = v
    root.flushPrefs()
  }

  function flushPrefs() {
    if (root.writerBusy) return
    var keys = Object.keys(root.pendingPrefs)
    if (keys.length === 0) return
    var key = keys[0]
    var value = root.pendingPrefs[key]
    delete root.pendingPrefs[key]
    root.writerBusy = true
    prefsWriter.command = ["tlit-state", "set", key, value]
    prefsWriter.running = true
  }

  property string runtimeDir: Quickshell.env("XDG_RUNTIME_DIR") || ""

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

  // Clear first asks Hyprland which window owns the keyboard, because the
  // sequence differs between a terminal and a GUI toolkit.
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
      clrCmd.running = true
    }
  }

  // Dictation, exactly as Omarchy runs it: the backend choice, its lock and
  // the typing (wtype via the backend) all belong to `omarchy dictation`.
  // A non-zero exit means no backend is selected/installed — say so once.
  BoundedProcess {
    id: vxCmd
    deadlineMs: 15000
    onStreamFinished: {
      if (root.vxAction === "start" && vxCmd.exitCode !== 0)
        root.osd("audio-input-microphone", root.t("voice.noBackend"))
      root.vxAction = ""
      root.busy = false
      root.vxRunning = false
      if (root.vxQueued !== "") {
        var next = root.vxQueued
        root.vxQueued = ""
        root.runDictation(next)
      }
    }
  }

  BoundedProcess { id: vkCmd }
  BoundedProcess { id: mousehopCmd }
  BoundedProcess { id: enterCmd }
  BoundedProcess { id: delCmd }
  BoundedProcess { id: clrCmd }
  BoundedProcess { id: arrowCmd }
  BoundedProcess { id: cliCmd }
  BoundedProcess {
    id: rotateCmd
    deadlineMs: 8000
    onStreamFinished: {
      root.rotating = false
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
    if (root.rotating) return false
    var target = String(value || "0")
    if (root.rotationRing.indexOf(target) === -1) target = "0"
    // Always -s: tlit-rotate's own OSD is English-only, so the text is shown
    // here instead, in the shell's language.
    root.rotating = true
    rotateCmd.command = ["tlit-rotate", "-s", target]
    rotateCmd.running = true
    root.setPref("rotation", target)
    root.liveTransform = Number(target)
    if (!silent) root.osd("rotate-cw", root.tf("osd.rotate", root.rotationLabel(target)))
    return true
  }

  // One 90° step from the CURRENT transform. `next` adds 1 (the content turns
  // clockwise, which is what you want when turning the device to the left);
  // `prev` subtracts 1.
  function rotateStep(dir) {
    if (root.rotating) return
    root.rotating = true
    root.setPref("auto", "off")
    root.appliedFor = ""
    root.pendingRelative = true
    rotateCmd.command = ["tlit-rotate", "-s", dir]
    rotateCmd.running = true
  }

  function rotationNext() { root.rotateStep("next") }
  function rotationPrev() { root.rotateStep("prev") }

  // Sensor-following on/off. Turning it off keeps the screen where the sensor
  // last put it.
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

  // Runs once after the shell starts: restore the last angle, or adopt the
  // current one on first install. Auto mode starts the sensor reader instead.
  function initRotation() {
    if (root.prefsDirty) return   // a user action already chose the angle
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
    // Voice input and the virtual keyboard are mutually exclusive.
    if (root.vkVisible) root.hideVk()
  }

  function hideVoiceInput() {
    // Never strand a recording when the button disappears — a lift-off event
    // can get lost with it.
    if (root.holding) root.stopRecording()
    root.voiceInputOpen = false
    root.cliKeysOpen = false
  }

  function runDictation(action) {
    // `vxRunning` is ours, not Process.running: Quickshell flips that only
    // once the child starts, so a press+release inside one turn would send
    // only the stop.
    if (root.vxRunning) { root.vxQueued = action; return }
    root.vxRunning = true
    root.vxAction = action
    root.busy = (action === "stop")
    vxCmd.command = ["omarchy", "dictation", action]
    vxCmd.running = true
  }

  // Press = start recording. Gated locally so a repeated press while already
  // holding cannot double-start `omarchy dictation`.
  function startRecording() {
    if (root.holding) return
    root.holding = true
    root.runDictation("start")
  }

  // Release = stop -> transcribe + type at the cursor. Sent on our own release
  // so a very fast tap that the backend never registered still ends cleanly
  // (`omarchy dictation` ignores a stop when nothing is recording).
  function stopRecording() {
    root.holding = false
    root.runDictation("stop")
  }

  // The voice pad's own keys: the text the backend typed lands at the cursor,
  // and on a touch-only screen these are how it is fixed or submitted without
  // raising the keyboard first.
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
  // layer unmaps instead of up to 5 s later. Monitor events re-read the
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

  function pollLock() {
    if (!lockProbe.running) lockProbe.running = true
  }

  function pollTransform() {
    if (!transformProbe.running) transformProbe.running = true
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

  // ---- probes ------------------------------------------------------------

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

  // Safety net for the event-driven state above: the keyboard layer and the
  // transform each have an event already, so this only catches one that was
  // missed (socket down).
  Timer {
    id: slowPoller
    interval: 5000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      root.pollVk()
      root.pollTransform()
    }
  }

  // Restore the saved angle once, and pre-start the keyboard hidden, 2.5 s in:
  // `prefsDirty` already protects an action that races the state-file load, and
  // lockProbe would start the keyboard on demand anyway.
  Timer {
    id: settleTimer
    interval: 2500
    running: true
    repeat: false
    onTriggered: {
      root.initRotation()
      // A session that is already locked raised the keyboard for the password
      // field; forcing it hidden here would fold it away under the lock.
      if (!root.locked) root.preStartVk()
    }
  }

  // ------------------------------------------------- voice overlay (bottom-right)
  // The one touch affordance Omarchy does not have: press & hold to talk.
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
              if (root.holding) return root.t("voice.release")
              if (root.busy) return root.t("voice.transcribing")
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
            color: root.holding
              ? Util.alpha(Color.urgent, 0.9)
              : Util.alpha(Color.accent, 0.14)
            border.width: 2
            border.color: root.holding
              ? Color.urgent : Util.alpha(Color.foreground, 0.35)

            Text {
              anchors.centerIn: parent
              text: "\uF130"          // fa-microphone
              color: root.holding ? "#ffffff" : Color.foreground
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
              visible: root.holding
              opacity: 0.7
              SequentialAnimation on scale {
                running: root.holding
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
        // never strand a recording.
        Component.onDestruction: if (root.holding) root.stopRecording()
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
        voiceHolding: root.holding,
        voiceBusy: root.busy,
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

    function cliKeysToggle(): string {
      root.cliKeysOpen = !root.cliKeysOpen
      return root.cliKeysOpen ? "open" : "closed"
    }

    function clearNow(): string {
      root.clearInput()
      return "ok"
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

    function rotationNext(): string {
      root.rotationNext()
      return root.rotationLabel(root.rotation)
    }

    function rotationPrev(): string {
      root.rotationPrev()
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
  }
}

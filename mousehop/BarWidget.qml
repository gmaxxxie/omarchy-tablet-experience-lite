import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Mousehop KVM — bar indicator + on/off switch.
//
// ON  the mousehop client is active: pushing the pointer into the peer's edge
//     captures it (InputCapture / libei) and hands the pointer and keyboard to
//     the other machine. While that session is live Hyprland forwards every
//     pointer and key event to the peer and drops it locally, which is why a
//     stray capture looks like "the touchpad stopped working".
// OFF the client is deactivated, so no capture can happen at all.
//
// The same action is on SUPER+SHIFT+K (`tlit-mousehop-toggle toggle`), so the
// icon has to follow state changes made elsewhere: it polls `mousehop cli
// list` — a ~5 ms Rust binary, no helper process, no shell — every 3 s and
// immediately after a click.
//
// `off` releases a live capture before deactivating the client (that is what
// tlit-mousehop-toggle does), so clicking here also rescues a pointer that is
// already stuck on the peer.
BarWidget {
  id: root
  moduleName: "maxt.mousehop"

  property bool active: false     // client armed → 指针可以跨到对端
  property bool known: false      // daemon answered at least once
  property bool busy: false       // a toggle is in flight
  property string peer: ""        // "max-mac-mini-4"
  property string edge: "left"    // peer edge the pointer crosses

  visible: true
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function refresh() {
    if (busy || poll.running) return
    poll.running = true
  }

  function toggle() {
    if (busy || toggleProc.running) return
    busy = true
    toggleProc.running = true
  }

  // "id 0: max-mac-mini-4:4252 (left) active: true, ips: {…}" — one line per
  // configured client; the widget is on when any client is armed.
  function applyListing(text) {
    var lines = String(text || "").split("\n")
    var any = false
    var found = false
    for (var i = 0; i < lines.length; i++) {
      var m = /^id\s+(\d+):\s+(\S+?)(?::\d+)?\s+\(([^)]+)\)\s+active:\s+(true|false)/.exec(lines[i].trim())
      if (!m) continue
      found = true
      if (i === 0 || root.peer === "") {
        root.peer = m[2]
        root.edge = m[3]
      }
      if (m[4] === "true") any = true
    }
    root.known = found
    root.active = any
  }

  readonly property string tip: {
    if (!root.known) return "mousehop 没在运行 — 点击尝试开启（SUPER+SHIFT+K）"
    if (root.busy) return "mousehop: 切换中…"
    if (root.active) return "mousehop 开 — 指针推到 " + root.edge + " 边缘就跨到 "
      + root.peer + "（点击关闭 / SUPER+SHIFT+K）"
    return "mousehop 关 — 指针和键盘都留在本机（点击开启 / SUPER+SHIFT+K）"
  }

  // Poll: one cheap `mousehop cli list` every few seconds.
  Process {
    id: poll
    command: ["mousehop", "cli", "list"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.applyListing(text)
    }
    onExited: function(exitCode) {
      if (exitCode !== 0) root.known = false
    }
  }

  Process {
    id: toggleProc
    command: ["tlit-mousehop-toggle", "toggle"]
    onExited: function(exitCode) {
      // mousehop writes the new client state to its config before the CLI
      // returns, but the daemon applies it a moment later; poll once it has.
      settle.start()
    }
  }

  Timer {
    id: settle
    interval: 350
    repeat: false
    onTriggered: {
      root.busy = false
      root.refresh()
    }
  }

  Timer {
    interval: 3000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.active ? "\uf0ec" : "\uf204"   // fa-arrows-left-right : fa-toggle-off
    active: root.active
    dimmed: !root.known
    slotSize: Style.bar.statusSlot
    tooltipText: root.tip
    onPressed: function(b) {
      if (b === Qt.MiddleButton) root.refresh()
      else root.toggle()
    }
  }
}

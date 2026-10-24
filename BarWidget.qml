import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// Tablet Lite — bar widget: the two entry points this plugin exists for.
//   ⌨  on-screen keyboard (same as SUPER+U / `texp-vk toggle`)
//   🎤 voice input overlay (voxtype hold-to-talk)
// The keyboard half highlights while the wvkbd layer is mapped; the mic half
// highlights while the hold-to-talk overlay is open. Voice input and the
// keyboard are mutually exclusive (Service.qml closes the other one).
Panel {
  id: root
  moduleName: "maxt.tablet-lite"
  ipcTarget: "maxt.tablet-lite-window"

  property var service: bar ? bar.shell.serviceFor("maxt.tablet-lite") : null

  implicitWidth: row.implicitWidth
  implicitHeight: row.implicitHeight

  function refresh() {
    if (root.service) root.service.pollVk()
  }

  Row {
    id: row
    anchors.centerIn: parent
    spacing: Style.spacing.xs

    WidgetButton {
      id: keyboardButton
      bar: root.bar
      text: "\uF11C"          // fa-keyboard
      active: root.service ? root.service.vkVisible : false
      tooltipText: root.service && root.service.vkVisible
        ? "Keyboard is up — tap to close (Super+U)"
        : "Keyboard — tap to type on screen (Super+U)"
      onPressed: function() {
        if (!root.service) return
        root.service.toggleVk()
        root.refresh()
      }
    }

    WidgetButton {
      id: voiceButton
      bar: root.bar
      text: "\uF130"          // fa-microphone
      active: root.service ? root.service.voiceInputOpen : false
      tooltipText: root.service && root.service.voiceInputOpen
        ? "Hide voice input button"
        : "Voice input — hold to talk (voxtype)"
      onPressed: function() {
        if (root.service) root.service.toggleVoiceInput()
      }
    }
  }

  // The plugin service re-instantiates after every shell.json mutation
  // (plugin reload); keep the reference pointing at the CURRENT instance.
  Timer {
    id: serviceTimer
    interval: 1500
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      var current = bar ? bar.shell.serviceFor("maxt.tablet-lite") : null
      if (current !== root.service) root.service = current
    }
  }

  Component.onCompleted: console.log("MAXT-TABLET-LITE-WIDGET-ONLINE")
}

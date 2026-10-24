import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// Tablet Lite — bar widget: the four entry points this plugin exists for.
//   ⌨  on-screen keyboard (same as SUPER+U / `texp-vk toggle`)
//   🎤 voice input overlay (voxtype hold-to-talk)
//   ⟳  rotation: click = next 90°
//   🧭  auto-rotate: click = sensor-following on/off
// The keyboard highlights while the wvkbd layer is mapped; the mic while the
// hold-to-talk overlay is open; the rotate icon while the screen is not at 0°;
// the compass while auto-rotate is on. Voice and keyboard are exclusive
// (Service.qml).
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

    WidgetButton {
      id: rotateButton
      bar: root.bar
      text: "\uF2F9"          // fa-rotate-right
      active: root.service
        ? (!root.service.autoOrient && root.service.rotation !== "0") : false
      tooltipText: root.service
        ? "Rotate " + root.service.rotationLabel(root.service.rotation)
          + " — click: next 90° (SUPER+SHIFT+R)"
        : "Rotate"
      onPressed: function() {
        if (root.service) root.service.rotationNext()
      }
    }

    WidgetButton {
      id: autoRotateButton
      bar: root.bar
      text: "\uF14E"          // fa-compass
      active: root.service ? root.service.autoOrient : false
      tooltipText: root.service && root.service.autoOrient
        ? "Auto-rotate on (sensor) — tap to turn off"
        : "Auto-rotate off — tap to follow the device's sensor"
      onPressed: function() {
        if (root.service) root.service.toggleAutoRotate()
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

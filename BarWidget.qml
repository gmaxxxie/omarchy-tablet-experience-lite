import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// Tablet Lite — bar widget: the four entry points this plugin exists for.
//   ⌨  on-screen keyboard (same as SUPER+U / `texp-vk toggle`)
//   🎤 voice input overlay (voxtype hold-to-talk)
//   ⟳  rotation: click = next 90°
//   🧭  auto-rotate: click = sensor-following on/off
//
// In PORTRAIT the bar is much narrower, and four icons collide with the
// clock/centre widgets. Portrait therefore folds all four into ONE tablet
// button whose popup offers the same four actions at touch size; landscape
// keeps the direct one-tap icons. The keyboard highlights while the wvkbd
// layer is mapped; the mic while the overlay is open; the rotate icon while
// the screen is not at 0°; the compass while auto-rotate is on.
Panel {
  id: root
  moduleName: "maxt.tablet-lite"
  ipcTarget: "maxt.tablet-lite-window"

  property var service: bar ? bar.shell.serviceFor("maxt.tablet-lite") : null

  // Live monitor transform from the service (1/3 = 90°/270° = portrait).
  // Reading the live transform, not the persisted preference, keeps the bar
  // folded even when the display was rotated outside the plugin.
  readonly property bool portrait: root.service ? root.service.portrait : false

  implicitWidth: row.implicitWidth
  implicitHeight: row.implicitHeight

  function refresh() {
    if (root.service) root.service.pollVk()
  }

  // Rotating back to landscape with the portrait popup open would leave a
  // popup anchored to a hidden button; close it on every such transition.
  onPortraitChanged: if (!root.portrait) root.close()

  Row {
    id: row
    anchors.centerIn: parent
    spacing: Style.spacing.xs

    WidgetButton {
      id: keyboardButton
      bar: root.bar
      visible: !root.portrait
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
      visible: !root.portrait
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
      visible: !root.portrait
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
      visible: !root.portrait
      text: "\uF14E"          // fa-compass
      active: root.service ? root.service.autoOrient : false
      tooltipText: root.service && root.service.autoOrient
        ? "Auto-rotate on (sensor) — tap to turn off"
        : "Auto-rotate off — tap to follow the device's sensor"
      onPressed: function() {
        if (root.service) root.service.toggleAutoRotate()
      }
    }

    // Portrait: one button instead of four, so the bar does not collide with
    // the centre clock. The popup carries the same four actions.
    WidgetButton {
      id: tabletButton
      bar: root.bar
      visible: root.portrait
      text: "\uF10A"          // fa-tablet
      active: root.opened || (root.service
        && (root.service.vkVisible || root.service.voiceInputOpen
            || root.service.autoOrient))
      tooltipText: "Tablet controls — keyboard / voice / rotation"
      onPressed: function() {
        root.toggle()
      }
    }
  }

  PopupCard {
    id: panel
    anchorItem: tabletButton
    owner: root
    bar: root.bar
    open: root.opened && root.portrait
    triggerMode: "click"
    contentWidth: panel.fittedContentWidth(Style.space(240))
    contentHeight: panel.fittedContentHeight(controlList.implicitHeight)

    Column {
      id: controlList
      anchors.fill: parent
      anchors.margins: Style.spacing.popupPadding
      spacing: Style.spacing.sm

      PanelSectionHeader {
        text: "Tablet"
      }

      Button {
        width: parent.width
        height: Style.space(44)
        iconText: "\uF11C"      // fa-keyboard
        text: root.service && root.service.vkVisible ? "Keyboard (up)" : "Keyboard"
        active: root.service ? root.service.vkVisible : false
        onClicked: {
          if (root.service) root.service.toggleVk()
          root.close()
        }
      }

      Button {
        width: parent.width
        height: Style.space(44)
        iconText: "\uF130"      // fa-microphone
        text: root.service && root.service.voiceInputOpen ? "Voice (open)" : "Voice input"
        active: root.service ? root.service.voiceInputOpen : false
        onClicked: {
          if (root.service) root.service.toggleVoiceInput()
          root.close()
        }
      }

      Button {
        width: parent.width
        height: Style.space(44)
        iconText: "\uF2F9"      // fa-rotate-right
        text: root.service
          ? "Rotate 90° (" + root.service.rotationLabel(root.service.rotation) + ")"
          : "Rotate 90°"
        onClicked: {
          if (root.service) root.service.rotationNext()
          root.close()
        }
      }

      Button {
        width: parent.width
        height: Style.space(44)
        iconText: "\uF14E"      // fa-compass
        text: root.service && root.service.autoOrient
          ? "Auto-rotate: on" : "Auto-rotate: off"
        active: root.service ? root.service.autoOrient : false
        onClicked: {
          if (root.service) root.service.toggleAutoRotate()
          root.close()
        }
      }

      Item {
        width: parent.width
        height: Style.space(8)
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

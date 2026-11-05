import QtQuick
import Quickshell
import qs.Commons
import qs.Ui

// Tablet Lite — bar widget: the three entry points this plugin exists for.
//   ⌨  on-screen keyboard (same as SUPER+U / `tlit-vk toggle`)
//   🎤 voice input overlay (hold to talk)
//   ⟳  rotation: opens ONE picker — auto (default) / 0° / 90° / 180° / 270°
//      plus ⟲ ⟳ 90° steps — instead of a separate auto-rotate icon
//
// In PORTRAIT the bar is much narrower and the icons would collide with the
// clock/centre widgets, so all three fold into one tablet button whose popup
// carries the same actions at touch size. The keyboard highlights while the
// wvkbd layer is mapped, the mic while the overlay is open, and the rotate
// icon whenever the screen is rotated or sensor-following is on.
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

  // Labels come from the service so the bar follows the shell's language;
  // the fallbacks keep the widget readable before the service exists.
  function label(key, fallback) {
    return root.service ? root.service.t(key) : fallback
  }

  function rotateTip() {
    if (!root.service) return "Rotation"
    return root.service.autoOrient
      ? root.label("rotate.tip.auto", "Rotation: auto (sensor) — tap to choose")
      : root.service.tf("rotate.tip.angle", root.service.rotationLabel(root.service.rotation),
                        "Rotation — tap to choose")
  }

  // Rotating back to landscape with the portrait popup open would leave a
  // popup anchored to a hidden button; close it on every such transition.
  onPortraitChanged: root.close()

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
        ? root.label("vk.tip.up", "Keyboard is up — tap to close (Super+U)")
        : root.label("vk.tip.down", "Keyboard — tap to type on screen (Super+U)")
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
        ? root.label("voice.tip.up", "Hide voice input button")
        : root.label("voice.tip.down", "Voice input — hold to talk")
      onPressed: function() {
        if (root.service) root.service.toggleVoiceInput()
      }
    }

    // One rotation button: the picker carries auto (the default) and every
    // angle, so there is no separate compass icon on the bar.
    WidgetButton {
      id: rotateButton
      bar: root.bar
      visible: !root.portrait
      text: "\uF2F9"          // fa-rotate-right
      active: root.service
        ? (root.service.autoOrient || root.service.rotation !== "0") : false
      tooltipText: root.rotateTip()
      onPressed: function() {
        root.toggle()
      }
    }

    // Portrait: one button instead of three, so the bar does not collide with
    // the centre clock. The popup carries the same actions.
    WidgetButton {
      id: tabletButton
      bar: root.bar
      visible: root.portrait
      text: "\uF10A"          // fa-tablet
      active: root.opened || (root.service
        && (root.service.vkVisible || root.service.voiceInputOpen
            || root.service.autoOrient || root.service.rotation !== "0"))
      tooltipText: root.label("tablet.tip", "Tablet controls — keyboard / voice / rotation")
      onPressed: function() {
        root.toggle()
      }
    }
  }

  // Landscape: the rotation picker under the rotate icon.
  PopupCard {
    id: rotatePanel
    anchorItem: rotateButton
    owner: root
    bar: root.bar
    open: root.opened && !root.portrait
    triggerMode: "click"
    contentWidth: rotatePanel.fittedContentWidth(Style.space(240))
    contentHeight: rotatePanel.fittedContentHeight(rotateContent.implicitHeight)

    Column {
      id: rotateContent
      anchors.fill: parent
      anchors.margins: Style.spacing.popupPadding
      spacing: Style.spacing.sm

      RotationChoices {
        tablet: root.service
        onPicked: root.close()
      }
    }
  }

  // Portrait: everything in one popup.
  PopupCard {
    id: tabletPanel
    anchorItem: tabletButton
    owner: root
    bar: root.bar
    open: root.opened && root.portrait
    triggerMode: "click"
    contentWidth: tabletPanel.fittedContentWidth(Style.space(240))
    contentHeight: tabletPanel.fittedContentHeight(controlList.implicitHeight)

    Column {
      id: controlList
      anchors.fill: parent
      anchors.margins: Style.spacing.popupPadding
      spacing: Style.spacing.sm

      PanelSectionHeader {
        text: root.label("tablet.header", "Tablet")
      }

      Button {
        width: parent.width
        height: Style.space(44)
        iconText: "\uF11C"      // fa-keyboard
        text: root.service && root.service.vkVisible
          ? root.label("popup.keyboard.up", "Keyboard (up)")
          : root.label("popup.keyboard", "Keyboard")
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
        text: root.service && root.service.voiceInputOpen
          ? root.label("popup.voice.up", "Voice (open)")
          : root.label("popup.voice", "Voice input")
        active: root.service ? root.service.voiceInputOpen : false
        onClicked: {
          if (root.service) root.service.toggleVoiceInput()
          root.close()
        }
      }

      RotationChoices {
        tablet: root.service
        onPicked: root.close()
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

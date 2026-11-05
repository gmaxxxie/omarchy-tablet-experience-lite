import QtQuick
import qs.Commons
import qs.Ui

// The rotation picker shared by both bar popups (landscape and portrait).
//
// Auto is the first row and the default: sensor-following, the mode a
// detachable tablet is normally used in. Picking an angle turns sensor
// following off and pins the screen there. The four angles are the four
// 90° steps, so the picker carries no separate ⟲/⟳ pair — SUPER+SHIFT+R and
// `rotationNext` / `rotationPrev` still step without opening it.
Column {
  id: root

  // The plugin service (maxt.tablet-lite). Null while the widget is being
  // created; every action is guarded so the picker can render either way.
  property var tablet: null

  signal picked()

  width: parent ? parent.width : 0
  spacing: Style.spacing.sm

  function label(key, fallback) {
    return root.tablet ? root.tablet.t(key) : fallback
  }

  PanelSectionHeader {
    text: root.label("rotate.header", "Rotation")
  }

  Button {
    width: parent.width
    height: Style.space(44)
    iconText: "\uF14E"        // fa-compass
    text: root.label("rotate.auto", "Auto (sensor)")
    active: root.tablet ? root.tablet.autoOrient : false
    onClicked: {
      if (root.tablet) root.tablet.setRotationPreset("auto")
      root.picked()
    }
  }

  Row {
    id: angleRow
    width: parent.width
    spacing: Style.spacing.sm

    Repeater {
      model: ["0", "1", "2", "3"]

      delegate: Button {
        required property string modelData
        width: (angleRow.width - angleRow.spacing * 3) / 4
        height: Style.space(40)
        // Fixed labels: root.rotationLabel() answers "auto" while sensor
        // following is on, which would make all four buttons read "auto".
        text: modelData + "\u00B0"
        active: root.tablet
          ? (!root.tablet.autoOrient && root.tablet.rotation === modelData) : false
        onClicked: {
          if (root.tablet) root.tablet.setRotationPreset(modelData)
          root.picked()
        }
      }
    }
  }
}

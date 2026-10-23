import QtQuick
import qs.Commons

// A rounded, animated pill used for tabs, selectors, and buttons.
Rectangle {
  id: root

  property string text: ""
  property bool selected: false
  property bool primary: false
  property bool danger: false
  property bool chip: false
  property color accent: "#89b4fa"
  property color fg: "#cdd6f4"
  property color dim: "#7f849c"
  property color dangerColor: "#f38ba8"
  property string fontFamily
  property int fontSize: Style.font.body
  property bool enabled: true

  signal clicked()

  readonly property bool hovered: mouse.containsMouse && root.enabled
  readonly property color baseColor: root.danger ? root.dangerColor
    : root.primary ? root.accent
    : root.selected ? root.accent
    : "transparent"

  implicitWidth: label.implicitWidth + (chip ? Style.space(18) : Style.space(26))
  implicitHeight: chip ? Style.space(24) : Style.space(30)
  radius: height / 2
  opacity: enabled ? 1 : 0.4

  color: {
    if (root.primary || root.danger || root.selected) return root.baseColor
    return root.hovered ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.09) : "transparent"
  }
  border.width: 1
  border.color: {
    if (root.primary || root.danger || root.selected) return root.baseColor
    return root.hovered ? Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.22) : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.10)
  }

  Behavior on color { ColorAnimation { duration: 130; easing.type: Easing.OutCubic } }
  Behavior on border.color { ColorAnimation { duration: 130; easing.type: Easing.OutCubic } }

  Text {
    id: label
    anchors.centerIn: parent
    text: root.text
    font.family: root.fontFamily
    font.pixelSize: root.fontSize
    font.bold: root.primary || root.danger || root.selected
    color: (root.primary || root.danger || root.selected) ? Color.menu.background
      : (root.hovered ? root.fg : root.dim)

    Behavior on color { ColorAnimation { duration: 130 } }
  }

  MouseArea {
    id: mouse
    anchors.fill: parent
    hoverEnabled: true
    enabled: root.enabled
    cursorShape: root.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: root.clicked()
  }
}

import QtQuick
import qs.Commons

// A single subject row: color swatch, name, optional right-aligned value, and
// an optional trailing action label (e.g. a trash glyph).
Rectangle {
  id: root

  property string tag: ""
  property color swatch: "#89b4fa"
  property bool selected: false
  property bool deleted: false
  property string rightText: ""
  property string actionText: ""
  property color actionColor: "#f38ba8"
  property string fontFamily
  property color fg: "#cdd6f4"
  property color dim: "#7f849c"
  property color accent: "#89b4fa"

  signal clicked()
  signal action()

  readonly property alias hovered: hover.hovered

  implicitHeight: Style.space(32)
  radius: Style.cornerRadius / 2
  opacity: deleted ? 0.5 : 1
  color: selected
    ? Qt.rgba(accent.r, accent.g, accent.b, 0.18)
    : (hovered ? Qt.rgba(fg.r, fg.g, fg.b, 0.06) : "transparent")

  Behavior on color { ColorAnimation { duration: 120; easing.type: Easing.OutCubic } }

  Rectangle {
    id: sw

    x: Style.space(10)
    anchors.verticalCenter: parent.verticalCenter
    width: Style.space(10)
    height: Style.space(10)
    radius: 3
    color: root.swatch
    border.color: Qt.rgba(0, 0, 0, 0.25)
    border.width: 1
  }

  MouseArea {
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: root.clicked()
  }

  Text {
    id: nameText

    anchors.left: sw.right
    anchors.leftMargin: Style.space(10)
    anchors.verticalCenter: parent.verticalCenter
    width: parent.width - Style.space(60) - (root.actionText ? Style.space(24) : 0)
    text: root.tag + (root.deleted ? "  ·  deleted" : "")
    color: root.deleted ? root.dim : root.fg
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
    elide: Text.ElideRight
  }

  Text {
    visible: root.rightText !== ""
    anchors.right: root.actionText ? actionTextItem.left : parent.right
    anchors.rightMargin: Style.space(8)
    anchors.verticalCenter: parent.verticalCenter
    text: root.rightText
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.body
  }

  Text {
    id: actionTextItem

    visible: root.actionText !== ""
    anchors.right: parent.right
    anchors.rightMargin: Style.space(8)
    anchors.verticalCenter: parent.verticalCenter
    text: root.actionText
    color: actionMouse.containsMouse ? root.fg : root.actionColor
    font.family: root.fontFamily
    font.pixelSize: Style.font.body

    MouseArea {
      id: actionMouse
      anchors.fill: parent
      anchors.margins: -Style.space(7)
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: root.action()
    }
  }

  HoverHandler { id: hover }
}

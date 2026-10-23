import QtQuick
import qs.Commons

// One headline number in the stats strip: a small caps label, the value, and
// a dim footnote that says exactly how the value was computed.
Rectangle {
  id: root

  property string label: ""
  property string value: "—"
  property string note: ""
  property color noteColor: dim
  property string fontFamily
  property color fg: "#cdd6f4"
  property color dim: "#7f849c"
  property color accent: "#89b4fa"
  property bool highlight: false

  implicitHeight: col.implicitHeight + Style.space(16)
  radius: Style.cornerRadius / 2
  color: highlight
    ? Qt.rgba(accent.r, accent.g, accent.b, 0.10)
    : Qt.rgba(fg.r, fg.g, fg.b, 0.04)
  border.width: 1
  border.color: highlight
    ? Qt.rgba(accent.r, accent.g, accent.b, 0.35)
    : Qt.rgba(fg.r, fg.g, fg.b, 0.07)

  Column {
    id: col

    x: Style.space(10)
    y: Style.space(8)
    width: root.width - Style.space(20)
    spacing: Style.space(1)

    Text {
      width: parent.width
      text: root.label.toUpperCase()
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      font.letterSpacing: 0.8
      elide: Text.ElideRight
    }

    Text {
      width: parent.width
      text: root.value
      color: root.highlight ? root.accent : root.fg
      font.family: root.fontFamily
      font.pixelSize: Style.font.heading + Style.space(2)
      font.bold: true
      elide: Text.ElideRight

      Behavior on color { ColorAnimation { duration: 150 } }
    }

    Text {
      width: parent.width
      text: root.note
      color: root.noteColor
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }
  }
}

import QtQuick
import qs.Commons

// Stacked study chart. Each bar is one day/week/month; segments are subjects
// colored by their subject color and sized by time spent.
//
// Hovering a bar lifts it, outlines it in black, and reveals a breakdown
// tooltip — the interaction is intentionally springy so the chart feels alive.
Item {
  id: root

  property var chartData: null
  property string fontFamily
  property color foreground: "#cdd6f4"
  property color dim: "#7f849c"
  property color axis: "#45475a"
  property color accent: "#89b4fa"
  property real averageSeconds: 0
  property string averageUnit: "day"

  property int hoverIndex: -1
  readonly property int selectedIndex: hoverIndex

  readonly property int axisWidth: Style.space(40)
  readonly property int labelHeight: Style.space(20)
  readonly property int plotHeight: Math.max(40, height - labelHeight - Style.space(6))
  readonly property int plotWidth: Math.max(10, width - axisWidth)
  readonly property var bars: chartData && chartData.bars ? chartData.bars : []
  readonly property real maxSeconds: Math.max(1, chartData && chartData.max_seconds > 0 ? chartData.max_seconds : 0, averageSeconds)
  readonly property int barCount: Math.max(1, bars.length)
  readonly property real barGap: barCount > 24 ? Style.space(2) : Style.space(5)
  readonly property real barSlot: plotWidth / barCount
  readonly property real barWidth: Math.max(3, barSlot - barGap)

  implicitHeight: Style.space(230)

  function fmt(seconds) {
    var s = Math.round(Number(seconds) || 0)
    if (s <= 0) return "0m"
    var h = Math.floor(s / 3600)
    var m = Math.round((s % 3600) / 60)
    if (h > 0) return m > 0 ? h + "h " + m + "m" : h + "h"
    if (m > 0) return m + "m"
    return s + "s"
  }

  function axisLabel(seconds) {
    var s = Number(seconds) || 0
    if (s <= 0) return "0"
    if (s >= 3600) return (Math.round(s / 360) / 10) + "h"
    return Math.round(s / 60) + "m"
  }

  // Y offset (within a bar of height totalH) for the top of segment index.
  function segmentY(segs, index, totalH) {
    var acc = 0
    for (var i = 0; i <= index; i++)
      acc += (segs[i].seconds / root.maxSeconds) * root.plotHeight
    return totalH - acc
  }

  // ------------------------------------------------------------------ grid
  Repeater {
    model: 3

    Item {
      required property int index

      readonly property real yPos: root.labelHeight + (index / 2) * root.plotHeight

      Rectangle {
        x: root.axisWidth
        y: parent.yPos
        width: root.plotWidth
        height: 1
        color: root.axis
        opacity: index === 2 ? 0.75 : 0.28
      }

      Text {
        x: 0
        y: parent.yPos - height / 2
        width: root.axisWidth - Style.space(6)
        horizontalAlignment: Text.AlignRight
        text: index === 0 ? root.axisLabel(root.maxSeconds)
          : index === 1 ? root.axisLabel(root.maxSeconds / 2)
          : "0"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }

  // --------------------------------------------------------- average line
  Item {
    id: avgLine

    visible: root.averageSeconds > 0
    x: root.axisWidth
    y: root.labelHeight + root.plotHeight - (root.averageSeconds / root.maxSeconds) * root.plotHeight
    width: root.plotWidth
    height: 1
    z: 5

    Behavior on y { NumberAnimation { duration: 260; easing.type: Easing.OutCubic } }

    Row {
      spacing: Style.space(3)
      Repeater {
        model: Math.ceil(avgLine.width / Style.space(7))
        Rectangle { width: Style.space(4); height: 1; color: root.accent; opacity: 0.85 }
      }
    }

    Rectangle {
      anchors.left: parent.left
      anchors.leftMargin: Style.space(4)
      anchors.bottom: parent.top
      anchors.bottomMargin: Style.space(2)
      width: avgText.implicitWidth + Style.space(8)
      height: avgText.implicitHeight + Style.space(2)
      radius: height / 2
      color: root.accent
      opacity: root.hoverIndex >= 0 ? 0 : 1

      Behavior on opacity { NumberAnimation { duration: 120 } }

      Text {
        id: avgText
        anchors.centerIn: parent
        text: "avg " + root.fmt(root.averageSeconds) + " / " + root.averageUnit
        color: Color.menu.background
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
      }
    }
  }

  // ------------------------------------------------------------------ bars
  Item {
    id: plot

    x: root.axisWidth
    y: root.labelHeight
    width: root.plotWidth
    height: root.plotHeight

    Repeater {
      model: root.bars

      Item {
        id: barItem

        required property var modelData
        required property int index

        readonly property bool hovered: root.hoverIndex === index
        readonly property real totalHeight:
          modelData.total_seconds > 0
            ? Math.max(3, (modelData.total_seconds / root.maxSeconds) * root.plotHeight)
            : 0
        readonly property var segments: modelData.segments || []

        x: index * root.barSlot + (root.barSlot - root.barWidth) / 2
        width: root.barWidth
        height: root.plotHeight

        // Very light track so empty days still read as a slot.
        Rectangle {
          anchors.fill: parent
          radius: Math.min(4, barItem.width / 2)
          color: root.foreground
          opacity: 0.045
        }

        Item {
          id: barStack

          anchors.bottom: parent.bottom
          anchors.horizontalCenter: parent.horizontalCenter
          width: barItem.width
          height: barItem.totalHeight
          transformOrigin: Item.Bottom
          scale: barItem.hovered ? 1.05 : 1.0

          Behavior on scale {
            NumberAnimation { duration: 130; easing.type: Easing.OutCubic }
          }

          Repeater {
            model: barItem.segments

            Rectangle {
              required property var modelData
              required property int index

              readonly property int last: barItem.segments.length - 1
              readonly property real r: Math.min(3, barItem.width / 2)

              x: 0
              y: root.segmentY(barItem.segments, index, barItem.totalHeight)
              width: barItem.width
              height: Math.max(0, (modelData.seconds / root.maxSeconds) * root.plotHeight)

              color: modelData.color
              opacity: barItem.hovered ? 1.0 : 0.92

              topLeftRadius: (index === last || barItem.segments.length === 1) ? r : 0
              topRightRadius: (index === last || barItem.segments.length === 1) ? r : 0
              bottomLeftRadius: index === 0 ? r : 0
              bottomRightRadius: index === 0 ? r : 0

              Behavior on opacity {
                NumberAnimation { duration: 120 }
              }
            }
          }

          // Hover outline: a crisp black boundary plus a soft accent halo.
          Rectangle {
            anchors.fill: parent
            radius: Math.min(4, barItem.width / 2)
            color: "transparent"
            border.color: "#000000"
            border.width: 2
            opacity: barItem.hovered ? 1 : 0
            visible: opacity > 0

            Behavior on opacity {
              NumberAnimation { duration: 120 }
            }
          }

          Rectangle {
            anchors.fill: parent
            anchors.margins: -2
            radius: Math.min(6, barItem.width / 2 + 2)
            color: "transparent"
            border.color: root.accent
            border.width: 1
            opacity: barItem.hovered ? 0.5 : 0
            visible: opacity > 0

            Behavior on opacity {
              NumberAnimation { duration: 120 }
            }
          }
        }

        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          onEntered: root.hoverIndex = barItem.index
          onExited: if (root.hoverIndex === barItem.index) root.hoverIndex = -1
          onClicked: root.hoverIndex = root.hoverIndex === barItem.index ? -1 : barItem.index
        }

        // x label (sparse)
        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          y: root.plotHeight + Style.space(3)
          text: {
            var n = root.bars.length
            var step = n <= 10 ? 1 : Math.ceil(n / 8)
            return (barItem.index % step === 0) ? barItem.modelData.label : ""
          }
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }

  // --------------------------------------------------------------- tooltip
  Rectangle {
    id: tooltip

    readonly property var bar: root.hoverIndex >= 0 && root.hoverIndex < root.bars.length
      ? root.bars[root.hoverIndex] : null
    readonly property var segs: bar ? (bar.segments || []) : []

    visible: !!bar
    opacity: visible ? 1 : 0
    radius: Style.cornerRadius * 0.6
    color: Color.popups.background
    border.color: root.axis
    border.width: 1
    implicitWidth: Math.min(Style.space(250), root.width)
    implicitHeight: tipCol.implicitHeight + Style.space(14)
    width: implicitWidth
    height: implicitHeight
    z: 20

    x: {
      var cx = root.axisWidth + (root.hoverIndex + 0.5) * root.barSlot
      return Math.max(0, Math.min(root.width - width, cx - width / 2))
    }
    y: Math.max(0, root.labelHeight - height - Style.space(4))

    Behavior on opacity { NumberAnimation { duration: 100 } }

    Column {
      id: tipCol

      x: Style.space(8)
      y: Style.space(7)
      width: tooltip.width - Style.space(16)
      spacing: Style.space(3)

      Row {
        width: parent.width
        spacing: Style.space(6)

        Text {
          text: tooltip.bar ? tooltip.bar.label : ""
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: true
        }

        Text {
          text: tooltip.bar ? root.fmt(tooltip.bar.total_seconds) : ""
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }

      Repeater {
        model: tooltip.segs

        Row {
          required property var modelData

          width: tipCol.width
          height: Style.space(15)
          spacing: Style.space(6)

          Rectangle {
            width: Style.space(8)
            height: Style.space(8)
            radius: 2
            color: modelData.color
            anchors.verticalCenter: parent.verticalCenter
          }

          Text {
            width: tipCol.width - Style.space(64)
            text: modelData.tag + (modelData.deleted ? "  (deleted)" : "")
            color: modelData.deleted ? root.dim : root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }

          Text {
            text: root.fmt(modelData.seconds)
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
          }
        }
      }

      Text {
        visible: tooltip.segs.length === 0
        text: "No study"
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }
}

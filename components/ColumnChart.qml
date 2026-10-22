import QtQuick
import qs.Commons
import qs.Ui

// Vertical columns, optionally stacked by model. Shades follow each model's
// rank in `models`; tooltips carry the numbers so shade is never the only cue.
Column {
  id: chart
  property var buckets: []
  property var models: []
  property bool stacked: true
  property bool useCost: false
  property real chartHeight: Style.space(64)
  property var tooltipFor: function(bucket) { return "" }
  property string leftLabel: buckets.length ? buckets[0].label : ""
  property string rightLabel: buckets.length ? buckets[buckets.length - 1].label : ""
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property real peak: {
    var p = 0
    for (var i = 0; i < buckets.length; i++) p = Math.max(p, useCost ? buckets[i].cost : buckets[i].tokens)
    return p
  }
  readonly property var shades: [0.9, 0.6, 0.38, 0.2]

  spacing: Style.space(3)

  function shadeFor(model) {
    var index = models.indexOf(model)
    return shades[index < 0 ? shades.length - 1 : Math.min(index, shades.length - 1)]
  }

  Row {
    id: columns
    width: parent.width
    height: chart.chartHeight
    spacing: Math.max(1, Math.min(Style.space(4), Math.floor(width / Math.max(1, chart.buckets.length) * 0.2)))

    Repeater {
      model: chart.buckets
      Item {
        id: column
        required property var modelData
        width: (columns.width - columns.spacing * (chart.buckets.length - 1)) / Math.max(1, chart.buckets.length)
        height: columns.height
        readonly property real value: chart.useCost ? modelData.cost : modelData.tokens

        Rectangle {
          anchors.fill: parent
          radius: Style.space(2)
          color: Qt.rgba(chart.foreground.r, chart.foreground.g, chart.foreground.b, columnArea.containsMouse ? 0.08 : 0.03)
        }

        Column {
          anchors.bottom: parent.bottom
          width: parent.width
          height: chart.peak > 0 ? parent.height * column.value / chart.peak : 0
          // The first model sits at the bottom of the stack.
          rotation: 180
          Repeater {
            model: chart.stacked ? column.modelData.segments : [{ model: "", tokens: column.modelData.tokens, cost: column.modelData.cost }]
            Rectangle {
              required property var modelData
              width: column.width
              height: column.value > 0 ? parent.height * (chart.useCost ? modelData.cost : modelData.tokens) / column.value : 0
              color: chart.stacked
                ? Qt.rgba(chart.foreground.r, chart.foreground.g, chart.foreground.b, chart.shadeFor(modelData.model))
                : Qt.rgba(chart.foreground.r, chart.foreground.g, chart.foreground.b, column.modelData.isToday ? 0.95 : 0.45)
            }
          }
        }

        MouseArea { id: columnArea; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
        PanelToolTip { visible: columnArea.containsMouse; text: chart.tooltipFor(column.modelData); fontFamily: chart.fontFamily }
      }
    }
  }

  Item {
    width: parent.width
    implicitHeight: leftText.implicitHeight
    Text { id: leftText; text: chart.leftLabel; color: chart.dim; font.family: chart.fontFamily; font.pixelSize: Style.font.caption }
    Text { text: chart.rightLabel; color: chart.dim; font.family: chart.fontFamily; font.pixelSize: Style.font.caption; anchors.right: parent.right }
  }
}

import QtQuick
import qs.Commons
import qs.Ui

// A limit window: title and percentage, meter, and the reset/pace line.
Column {
  id: row
  property var window: null
  property real pace: -1
  property string detail: ""
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  readonly property color dim: Qt.darker(foreground, 1.55)

  spacing: Style.space(6)

  Item {
    width: parent.width
    implicitHeight: title.implicitHeight

    Text {
      id: title
      text: row.window ? row.window.title : ""
      color: row.foreground
      font.family: row.fontFamily
      font.pixelSize: Style.font.body
      elide: Text.ElideRight
      anchors.left: parent.left
      width: Math.min(implicitWidth, percent.x - Style.spacing.sm)
    }
    // A pooled window says what it pools ("3 Plus pooled").
    Text {
      visible: text !== ""
      text: row.window && row.window.subtitle ? row.window.subtitle : ""
      color: row.dim
      font.family: row.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
      anchors.left: title.right
      anchors.leftMargin: Style.space(8)
      anchors.right: percent.left
      anchors.rightMargin: Style.spacing.sm
      anchors.baseline: title.baseline
    }
    Text {
      id: percent
      text: row.window && row.window.percent >= 0 ? Math.round(row.window.percent * 100) + "%" : "—"
      color: meter.usageColor(row.window ? row.window.percent : -1)
      font.family: row.fontFamily
      font.pixelSize: Style.font.caption
      anchors.right: parent.right
      anchors.verticalCenter: title.verticalCenter
    }
  }

  Meter {
    id: meter
    width: parent.width
    value: row.window ? row.window.percent : -1
    pace: row.pace
    graded: true
    alarming: row.window && row.window.percent >= 0.9
    foreground: row.foreground
  }

  Text {
    visible: text !== ""
    width: parent.width
    text: row.detail
    color: row.dim
    font.family: row.fontFamily
    font.pixelSize: Style.font.caption
    elide: Text.ElideRight
  }
}

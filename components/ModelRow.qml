import QtQuick
import qs.Commons
import qs.Ui

import "../Analytics.js" as A

// name · cost · tokens, with a thin share bar underneath.
Column {
  id: model
  property var row: null
  property string name: ""
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  readonly property color dim: Qt.darker(foreground, 1.55)

  spacing: Style.space(3)

  Item {
    width: parent.width
    implicitHeight: label.implicitHeight
    Text {
      id: label
      text: model.name
      color: model.foreground
      font.family: model.fontFamily
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideRight
      anchors.left: parent.left
      anchors.right: cost.left
      anchors.rightMargin: Style.space(8)
    }
    Text {
      id: cost
      text: model.row ? A.formatMoney(model.row.cost) : ""
      color: model.foreground
      font.family: model.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: true
      anchors.right: tokens.left
      anchors.rightMargin: Style.space(10)
    }
    Text {
      id: tokens
      text: model.row ? A.formatTokens(model.row.tokens) : ""
      color: model.dim
      font.family: model.fontFamily
      font.pixelSize: Style.font.bodySmall
      horizontalAlignment: Text.AlignRight
      width: Style.space(44)
      anchors.right: parent.right
    }
  }
  Rectangle {
    width: parent.width
    height: Style.space(3)
    radius: height / 2
    color: Style.selectedFillFor(model.foreground, Color.accent)
    Rectangle {
      width: parent.width * (model.row ? model.row.share : 0)
      height: parent.height
      radius: parent.radius
      color: Qt.rgba(model.foreground.r, model.foreground.g, model.foreground.b, 0.55)
    }
  }

  MouseArea { id: hover; anchors.fill: parent; hoverEnabled: true; acceptedButtons: Qt.NoButton }
  PanelToolTip {
    visible: hover.containsMouse && !!model.row
    fontFamily: model.fontFamily
    text: model.row ? "In " + A.formatTokens(model.row.input) + " · out " + A.formatTokens(model.row.output)
      + " · cache read " + A.formatTokens(model.row.cacheRead) + " · cache write " + A.formatTokens(model.row.cacheWrite) : ""
  }
}

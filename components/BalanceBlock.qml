import QtQuick
import qs.Commons
import qs.Ui

// A prepaid credit ledger: what is left drains toward empty.
Column {
  id: block
  property var balance: null
  property string amountText: ""
  property string detail: ""
  property bool alarming: false
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property real ratio: balance && balance.funded > 0
    ? Math.max(0, Math.min(1, balance.remaining / balance.funded)) : -1

  spacing: Style.space(6)

  Item {
    width: parent.width
    implicitHeight: label.implicitHeight
    Text {
      id: label
      text: "Prepaid credits"
      color: block.foreground
      font.family: block.fontFamily
      font.pixelSize: Style.font.body
    }
    Text {
      text: block.amountText
      color: block.alarming ? Color.urgent : block.foreground
      font.family: block.fontFamily
      font.pixelSize: Style.font.caption
      anchors.right: parent.right
      anchors.verticalCenter: label.verticalCenter
    }
  }
  Meter {
    visible: block.ratio >= 0
    width: parent.width
    value: block.ratio
    alarming: block.alarming
    foreground: block.foreground
  }
  Text {
    visible: text !== ""
    width: parent.width
    text: block.detail
    color: block.dim
    font.family: block.fontFamily
    font.pixelSize: Style.font.caption
  }
}

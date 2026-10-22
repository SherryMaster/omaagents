import QtQuick
import qs.Commons
import qs.Ui

import "../Analytics.js" as A

// A 100% stacked bar of the four token kinds plus a two-column legend that
// names each slice with its value and share.
Column {
  id: mix
  property var rows: []
  property bool priced: false
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property var shades: [0.9, 0.62, 0.4, 0.22]

  spacing: Style.space(8)

  Item {
    width: parent.width
    height: Style.space(8)
    Rectangle { anchors.fill: parent; radius: Style.space(3); color: Style.selectedFillFor(mix.foreground, Color.accent) }
    Row {
      anchors.fill: parent
      spacing: 1
      Repeater {
        model: mix.rows
        Rectangle {
          required property var modelData
          required property int index
          visible: modelData.share > 0
          width: Math.max(0, (mix.width - (mix.rows.length - 1)) * modelData.share)
          height: parent.height
          radius: Style.space(2)
          color: Qt.rgba(mix.foreground.r, mix.foreground.g, mix.foreground.b, mix.shades[index])
        }
      }
    }
  }

  Grid {
    id: legend
    width: parent.width
    columns: 2
    columnSpacing: Style.spacing.lg
    rowSpacing: Style.space(4)
    Repeater {
      model: mix.rows
      Item {
        required property var modelData
        required property int index
        width: (legend.width - legend.columnSpacing) / 2
        implicitHeight: name.implicitHeight
        Rectangle {
          id: swatch
          width: Style.space(8); height: Style.space(8); radius: Style.space(2)
          anchors.verticalCenter: parent.verticalCenter
          color: Qt.rgba(mix.foreground.r, mix.foreground.g, mix.foreground.b, mix.shades[index])
        }
        Text {
          id: name
          text: modelData.label
          color: mix.foreground
          font.family: mix.fontFamily
          font.pixelSize: Style.font.caption
          anchors.left: swatch.right
          anchors.leftMargin: Style.space(6)
        }
        Text {
          text: (mix.priced ? A.formatMoney(modelData.cost) : A.formatTokens(modelData.tokens))
            + "  " + Math.round(modelData.share * 100) + "%"
          color: mix.dim
          font.family: mix.fontFamily
          font.pixelSize: Style.font.caption
          anchors.right: parent.right
        }
      }
    }
  }
}

import QtQuick
import qs.Commons
import qs.Ui

// A labelled figure: what it is, the number, and the context it needs.
Rectangle {
  id: tile
  property string label: ""
  property string value: ""
  property string detail: ""
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  readonly property color dim: Qt.darker(foreground, 1.55)

  implicitHeight: column.implicitHeight + Style.space(12)
  radius: Style.cornerRadius
  color: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.05)
  border.color: Qt.rgba(foreground.r, foreground.g, foreground.b, 0.10)

  Column {
    id: column
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.verticalCenter: parent.verticalCenter
    anchors.leftMargin: Style.space(10)
    anchors.rightMargin: Style.space(10)
    Text { width: parent.width; text: tile.label; color: tile.dim; font.family: tile.fontFamily; font.pixelSize: Style.font.caption; elide: Text.ElideRight }
    Text { width: parent.width; text: tile.value; color: tile.foreground; font.family: tile.fontFamily; font.pixelSize: Style.font.body; font.bold: true; elide: Text.ElideRight }
    Text { visible: text !== ""; width: parent.width; text: tile.detail; color: tile.dim; font.family: tile.fontFamily; font.pixelSize: Style.font.caption; elide: Text.ElideRight }
  }
}

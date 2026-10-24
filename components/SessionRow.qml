import QtQuick
import qs.Commons
import qs.Ui

import "../Analytics.js" as A

// A session: title · cost · tokens. Expanded, it lists each model with its
// tokens, cost and effort, plus cache hit rate and last activity.
Column {
  id: session
  property var row: null
  property bool expanded: false
  property var nameFor: function(id) { return id }
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  readonly property color dim: Qt.darker(foreground, 1.55)
  signal toggled()

  spacing: Style.space(4)

  Item {
    width: parent.width
    implicitHeight: title.implicitHeight + Style.space(6)
    Rectangle {
      anchors.fill: parent
      anchors.margins: -Style.space(4)
      radius: Style.cornerRadius
      color: Qt.rgba(session.foreground.r, session.foreground.g, session.foreground.b,
        area.containsMouse || session.expanded ? 0.06 : 0)
    }
    Text {
      id: chevron
      text: session.expanded ? "▾" : "▸"
      color: session.dim
      font.family: session.fontFamily
      font.pixelSize: Style.font.caption
      anchors.verticalCenter: parent.verticalCenter
    }
    Text {
      id: title
      text: session.row ? session.row.title : ""
      color: session.foreground
      font.family: session.fontFamily
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideRight
      anchors.left: chevron.right
      anchors.leftMargin: Style.space(6)
      anchors.right: cost.left
      anchors.rightMargin: Style.space(8)
      anchors.verticalCenter: parent.verticalCenter
    }
    Text {
      id: cost
      text: session.row ? A.formatMoney(session.row.cost) : ""
      color: session.foreground
      font.family: session.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: true
      anchors.right: tokens.left
      anchors.rightMargin: Style.space(10)
      anchors.verticalCenter: parent.verticalCenter
    }
    Text {
      id: tokens
      text: session.row ? A.formatTokens(session.row.tokens) : ""
      color: session.dim
      font.family: session.fontFamily
      font.pixelSize: Style.font.bodySmall
      horizontalAlignment: Text.AlignRight
      width: Style.space(44)
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
    }
    MouseArea {
      id: area
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: session.toggled()
    }
  }

  Column {
    visible: session.expanded && !!session.row
    width: parent.width
    leftPadding: Style.space(14)
    spacing: Style.space(2)
    Repeater {
      // Counted, not the array itself: a new array would rebuild every row.
      model: (session.row && session.row.models || []).length
      Text {
        required property int index
        // The row stays put across refreshes; only what it shows changes.
        readonly property var modelData: (session.row && session.row.models || [])[index] || ({})
        width: session.width - Style.space(14)
        text: session.nameFor(modelData.id) + " — " + A.formatTokens(modelData.tokens)
          + (modelData.cost >= 0 ? " · " + A.formatMoney(modelData.cost) : "")
          + (modelData.effort.length ? " · " + modelData.effort.join("/") : "")
        color: session.dim
        font.family: session.fontFamily
        font.pixelSize: Style.font.caption
        elide: Text.ElideRight
      }
    }
    Text {
      width: session.width - Style.space(14)
      text: {
        if (!session.row) return ""
        var parts = []
        if (session.row.hitRate >= 0) parts.push("cache hit " + Math.round(session.row.hitRate * 100) + "%")
        var when = new Date(session.row.updatedAt)
        if (!isNaN(when.getTime())) parts.push("last active " + when.toLocaleString(Qt.locale(), "MMM d · h:mm AP"))
        return parts.join(" · ")
      }
      color: session.dim
      font.family: session.fontFamily
      font.pixelSize: Style.font.caption
      elide: Text.ElideRight
    }
  }
}

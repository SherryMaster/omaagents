import QtQuick
import qs.Commons
import qs.Ui

// One small square per agent in the header; hidden with a single agent.
Row {
  id: chips
  property var providers: []
  property int selectedIndex: 0
  property color surface: Color.background
  property string fallbackText: ""
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  signal picked(int index)

  visible: providers.length > 1
  spacing: Style.space(4)

  Repeater {
    // Counted, not the array itself: a new array would rebuild every row.
    model: chips.providers.length
    CursorSurface {
      id: chip
      // The row stays put across refreshes; only what it shows changes.
      readonly property var modelData: chips.providers[index] || ({})
      required property int index
      width: Style.space(28)
      height: Style.space(28)
      bordered: true
      current: index === chips.selectedIndex
      hasCursor: chipArea.containsMouse
      foreground: chips.foreground

      ProviderMark {
        anchors.centerIn: parent
        size: Style.space(16)
        providerId: chip.modelData.providerId
        surface: chips.surface
        fallbackText: chips.fallbackText
        foreground: chips.foreground
        fontFamily: chips.fontFamily
      }
      MouseArea {
        id: chipArea
        anchors.fill: parent
        hoverEnabled: true
        cursorShape: Qt.PointingHandCursor
        onClicked: chips.picked(chip.index)
      }
      PanelToolTip {
        visible: chipArea.containsMouse
        text: chip.modelData.providerName
        fontFamily: chips.fontFamily
      }
    }
  }
}

import QtQuick
import qs.Commons
import qs.Ui
import "../Analytics.js" as A

// A month calendar for picking a date range: click the first day, then the
// last (in either order). While the end is pending, hovering previews the
// range. Days with usage carry a dot; days after today cannot be picked.
Column {
  id: calendar
  property string start: ""
  property string end: ""
  property string todayIso: ""
  property var activeDates: ({})
  property int weekStart: Qt.locale().firstDayOfWeek
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  signal picked(string start, string end)

  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property color accentFill: Style.selectedStateColor(foreground, Color.accent)
  readonly property var weekdays: ["Su", "Mo", "Tu", "We", "Th", "Fr", "Sa"]
  readonly property var monthNames: ["January", "February", "March", "April", "May", "June", "July",
    "August", "September", "October", "November", "December"]

  // The month on screen; opens on the month holding the current end date.
  property int viewYear: 2026
  property int viewMonth: 0
  property string pendingStart: ""
  property string hoverIso: ""

  readonly property var cells: A.monthGrid(viewYear, viewMonth, weekStart, todayIso)
  readonly property bool atCurrentMonth: todayIso !== ""
    && viewYear === +todayIso.slice(0, 4) && viewMonth === +todayIso.slice(5, 7) - 1
  // The range drawn: the committed one, or the one being picked.
  readonly property string lo: pendingStart === "" ? start
    : (hoverIso !== "" && hoverIso < pendingStart ? hoverIso : pendingStart)
  readonly property string hi: pendingStart === "" ? end
    : (hoverIso !== "" && hoverIso > pendingStart ? hoverIso : pendingStart)

  function showMonthOf(iso) {
    var text = iso !== "" ? iso : todayIso
    if (text === "") return
    viewYear = +text.slice(0, 4)
    viewMonth = +text.slice(5, 7) - 1
  }

  function moveMonth(delta) {
    if (delta > 0 && atCurrentMonth) return
    var index = viewYear * 12 + viewMonth + delta
    viewYear = Math.floor(index / 12)
    viewMonth = index % 12
  }

  function choose(iso) {
    if (pendingStart === "") {
      pendingStart = iso
      return
    }
    var a = pendingStart < iso ? pendingStart : iso
    var b = pendingStart < iso ? iso : pendingStart
    pendingStart = ""
    hoverIso = ""
    picked(a, b)
  }

  function applyPreset(kind) {
    var range = A.monthPreset(kind, todayIso)
    pendingStart = ""
    showMonthOf(range.end)
    picked(range.start, range.end)
  }

  Component.onCompleted: showMonthOf(end)
  onEndChanged: if (pendingStart === "") showMonthOf(end)

  spacing: Style.space(6)

  // ---- Quick ranges
  Row {
    id: presets
    width: parent.width
    spacing: Style.space(4)
    Repeater {
      model: [{ kind: "thisMonth", label: "This month" }, { kind: "lastMonth", label: "Last month" },
        { kind: "thisYear", label: "This year" }]
      Button {
        required property var modelData
        width: (presets.width - presets.spacing * 2) / 3
        text: modelData.label
        bordered: true
        foreground: calendar.foreground
        fontFamily: calendar.fontFamily
        fontSize: Style.font.caption
        verticalPadding: Style.space(3)
        onClicked: calendar.applyPreset(modelData.kind)
      }
    }
  }

  // ---- Month header
  Item {
    width: parent.width
    implicitHeight: Style.space(24)

    Text {
      text: "‹"
      color: calendar.foreground
      font.family: calendar.fontFamily
      font.pixelSize: Style.font.title
      anchors.left: parent.left
      anchors.leftMargin: Style.space(4)
      anchors.verticalCenter: parent.verticalCenter
      MouseArea { anchors.fill: parent; anchors.margins: -8; cursorShape: Qt.PointingHandCursor; onClicked: calendar.moveMonth(-1) }
    }
    Text {
      text: calendar.monthNames[calendar.viewMonth] + " " + calendar.viewYear
      color: calendar.foreground
      font.family: calendar.fontFamily
      font.pixelSize: Style.font.bodySmall
      font.bold: true
      anchors.centerIn: parent
    }
    Text {
      text: "›"
      opacity: calendar.atCurrentMonth ? 0.3 : 1
      color: calendar.foreground
      font.family: calendar.fontFamily
      font.pixelSize: Style.font.title
      anchors.right: parent.right
      anchors.rightMargin: Style.space(4)
      anchors.verticalCenter: parent.verticalCenter
      MouseArea { anchors.fill: parent; anchors.margins: -8; cursorShape: Qt.PointingHandCursor; onClicked: calendar.moveMonth(1) }
    }
  }

  // ---- Weekdays and days
  Grid {
    id: grid
    width: parent.width
    columns: 7
    readonly property real cell: width / 7

    Repeater {
      model: 7
      Text {
        required property int index
        width: grid.cell
        height: Style.space(18)
        text: calendar.weekdays[(calendar.weekStart + index) % 7]
        color: calendar.dim
        font.family: calendar.fontFamily
        font.pixelSize: Style.font.caption
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
      }
    }

    Repeater {
      // Counted, not the array itself: a new array would rebuild every row.
      model: calendar.cells.length
      Item {
        id: day
        required property int index
        // The row stays put across refreshes; only what it shows changes.
        readonly property var modelData: calendar.cells[index] || ({})
        width: grid.cell
        height: Style.space(26)
        readonly property bool edge: modelData.iso === calendar.lo || modelData.iso === calendar.hi
        readonly property bool inside: calendar.lo !== "" && calendar.hi !== ""
          && modelData.iso > calendar.lo && modelData.iso < calendar.hi

        // The band joining the range's ends, drawn edge to edge.
        Rectangle {
          visible: day.inside || (day.edge && calendar.lo !== calendar.hi && calendar.lo !== "" && calendar.hi !== "")
          anchors.verticalCenter: parent.verticalCenter
          height: Style.space(22)
          x: day.modelData.iso === calendar.lo ? parent.width / 2 : 0
          width: day.inside ? parent.width : parent.width / 2
          color: Qt.rgba(calendar.accentFill.r, calendar.accentFill.g, calendar.accentFill.b, 0.22)
        }
        Rectangle {
          anchors.centerIn: parent
          width: Style.space(22)
          height: Style.space(22)
          radius: Style.cornerRadius
          color: day.edge ? calendar.accentFill
            : (dayArea.containsMouse && !day.modelData.future
               ? Qt.rgba(calendar.foreground.r, calendar.foreground.g, calendar.foreground.b, 0.10) : "transparent")
          border.width: day.modelData.isToday && !day.edge ? 1 : 0
          border.color: Qt.rgba(calendar.foreground.r, calendar.foreground.g, calendar.foreground.b, 0.5)
        }
        Text {
          anchors.centerIn: parent
          text: day.modelData.day
          color: day.edge ? Color.popups.background : calendar.foreground
          opacity: day.modelData.future ? 0.25 : (day.modelData.inMonth ? 1 : 0.4)
          font.family: calendar.fontFamily
          font.pixelSize: Style.font.caption
          font.bold: day.edge
        }
        // A day with recorded usage.
        Rectangle {
          visible: !!calendar.activeDates[day.modelData.iso]
          width: Style.space(3)
          height: Style.space(3)
          radius: width / 2
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.bottom: parent.bottom
          anchors.bottomMargin: Style.space(1)
          color: day.edge ? calendar.foreground : calendar.dim
        }
        MouseArea {
          id: dayArea
          anchors.fill: parent
          enabled: !day.modelData.future
          hoverEnabled: true
          cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
          onContainsMouseChanged: if (containsMouse) calendar.hoverIso = day.modelData.iso
          onClicked: calendar.choose(day.modelData.iso)
        }
      }
    }

    WheelHandler {
      onWheel: function(event) {
        if (event.angleDelta.y !== 0) calendar.moveMonth(event.angleDelta.y > 0 ? -1 : 1)
      }
    }
  }

  Text {
    width: parent.width
    text: calendar.pendingStart !== "" ? "Now pick the last day" : "Pick the first day, then the last"
    color: calendar.dim
    font.family: calendar.fontFamily
    font.pixelSize: Style.font.caption
    horizontalAlignment: Text.AlignHCenter
  }
}

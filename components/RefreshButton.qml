import QtQuick
import qs.Commons
import qs.Ui

// A circular-arrow refresh control that spins while a refresh runs.
CursorSurface {
  id: control
  property bool busy: false
  property string fontFamily: Style.font.family
  signal triggered()

  width: Style.space(28)
  height: Style.space(28)
  enabled: !busy
  opacity: enabled ? 1.0 : 0.65
  bordered: true
  hasCursor: area.containsMouse

  Canvas {
    id: arrow
    width: Style.space(16)
    height: Style.space(16)
    anchors.centerIn: parent
    antialiasing: true
    property color strokeColor: control.foreground
    onStrokeColorChanged: requestPaint()

    onPaint: {
      var ctx = getContext("2d")
      ctx.clearRect(0, 0, width, height)
      ctx.strokeStyle = strokeColor
      ctx.lineWidth = 1.7
      ctx.lineCap = "round"
      ctx.lineJoin = "round"
      var cx = width / 2, cy = height / 2
      var radius = Math.min(width, height) * 0.29
      var start = -Math.PI * 0.78, end = Math.PI * 0.58
      ctx.beginPath()
      ctx.arc(cx, cy, radius, start, end, false)
      ctx.stroke()
      var tipX = cx + radius * Math.cos(end), tipY = cy + radius * Math.sin(end)
      var tangent = end + Math.PI / 2, wing = 3.1
      ctx.beginPath()
      ctx.moveTo(tipX, tipY)
      ctx.lineTo(tipX - wing * Math.cos(tangent - 0.62), tipY - wing * Math.sin(tangent - 0.62))
      ctx.moveTo(tipX, tipY)
      ctx.lineTo(tipX - wing * Math.cos(tangent + 0.62), tipY - wing * Math.sin(tangent + 0.62))
      ctx.stroke()
    }

    RotationAnimator on rotation {
      running: control.busy
      from: 0
      to: 360
      duration: 850
      loops: Animation.Infinite
    }
  }

  MouseArea {
    id: area
    anchors.fill: parent
    enabled: !control.busy
    hoverEnabled: true
    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
    onClicked: control.triggered()
  }

  PanelToolTip {
    visible: area.containsMouse
    text: control.busy ? "Refreshing usage…" : "Refresh usage (r)"
    fontFamily: control.fontFamily
  }
}

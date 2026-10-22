import QtQuick
import qs.Commons
import qs.Ui

// Rounded track showing how much of an allowance is used. The pace tick
// marks where usage would sit if spread evenly over the window.
Item {
  id: meter
  property real value: -1
  property real pace: -1
  property bool graded: false
  property bool alarming: false
  property color foreground: Color.foreground
  property color urgent: Color.urgent
  property real thickness: Math.max(Style.space(4), Math.round(Style.spacing.controlHeight * 0.14))

  implicitHeight: thickness

  function usageColor(v) {
    if (!isFinite(v) || v < 0) return foreground
    if (v >= 0.95) return "#f7768e"
    if (v >= 0.90) return "#ff9e64"
    if (v >= 0.75) return "#e0af68"
    if (v >= 0.50) return "#c0ca75"
    if (v >= 0.25) return "#73daca"
    return "#9ece6a"
  }

  Rectangle {
    id: track
    anchors.fill: parent
    radius: height / 2
    color: Style.selectedFillFor(meter.foreground, Color.accent)
  }

  Rectangle {
    anchors.left: track.left
    anchors.verticalCenter: track.verticalCenter
    height: track.height
    radius: track.radius
    width: track.width * Math.max(0, Math.min(1, meter.value))
    color: meter.graded ? meter.usageColor(meter.value) : (meter.alarming ? meter.urgent : meter.foreground)
    Behavior on width { NumberAnimation { duration: 160; easing.type: Easing.OutCubic } }
  }

  Rectangle {
    visible: meter.pace >= 0
    width: Math.max(2, Math.round(meter.thickness * 0.45))
    height: meter.thickness + Style.space(6)
    radius: width / 2
    anchors.verticalCenter: track.verticalCenter
    x: Math.max(0, Math.min(track.width - width, track.width * meter.pace - width / 2))
    color: Qt.rgba(meter.foreground.r, meter.foreground.g, meter.foreground.b, 0.8)
  }
}

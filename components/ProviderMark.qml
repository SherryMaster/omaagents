import QtQuick
import qs.Commons
import qs.Ui

// An agent's mark: assets/<id>-light.svg on light surfaces, assets/<id>.svg,
// else the fallback glyph. Walks the candidates as each fails to load. Only
// marks listed in lightVariants have a light twin; asking for one that does
// not exist costs a failed load and a warning on every draw.
Item {
  id: mark
  property string providerId: ""
  property color surface: Color.background
  property string fallbackText: ""
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property real size: Style.font.display

  readonly property var lightVariants: ["codex"]
  readonly property bool lightSurface: 0.2126 * surface.r + 0.7152 * surface.g + 0.0722 * surface.b >= 0.5
  readonly property var candidates: providerId === "" ? [] : (lightSurface && lightVariants.indexOf(providerId) >= 0
    ? [Qt.resolvedUrl("../assets/" + providerId + "-light.svg"), Qt.resolvedUrl("../assets/" + providerId + ".svg")]
    : [Qt.resolvedUrl("../assets/" + providerId + ".svg")])
  property string candidatesKey: candidates.join("\n")
  property int candidateIndex: 0
  onCandidatesKeyChanged: candidateIndex = 0

  width: size
  height: size

  Image {
    id: image
    anchors.fill: parent
    source: mark.candidateIndex < mark.candidates.length ? mark.candidates[mark.candidateIndex] : ""
    sourceSize.width: mark.size * 2
    sourceSize.height: mark.size * 2
    fillMode: Image.PreserveAspectFit
    // Advancing source inside its own status change trips the binding-loop
    // detector, so the step waits a tick.
    onStatusChanged: if (status === Image.Error && mark.candidateIndex < mark.candidates.length)
      Qt.callLater(function() { mark.candidateIndex++ })
  }
  Text {
    anchors.centerIn: parent
    visible: image.status !== Image.Ready
    text: mark.fallbackText
    color: mark.foreground
    font.family: mark.fontFamily
    font.pixelSize: mark.size * 0.8
  }
}

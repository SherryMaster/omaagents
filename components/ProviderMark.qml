import QtQuick
import qs.Commons
import qs.Ui

// An agent's mark: assets/<id>-light.svg on light surfaces, assets/<id>.svg,
// else the fallback glyph. Walks the candidates as each fails to load. Marks
// this plugin doesn't ship come from Omarchy's own agents panel, which has
// one for every collector it adds. Only marks listed in a light list have a
// light twin; asking for one that does not exist costs a failed load and a
// warning on every draw.
Item {
  id: mark
  property string providerId: ""
  property color surface: Color.background
  property string fallbackText: ""
  property color foreground: Color.foreground
  property string fontFamily: Style.font.family
  property real size: Style.font.display

  readonly property var ownMarks: ["claude", "codex", "fireworks"]
  readonly property var lightVariants: ["codex"]
  readonly property string omarchyAssets: "file:///usr/share/omarchy/shell/plugins/agents/assets/"
  // Omarchy 4.5's marks; an id outside both lists draws the fallback glyph.
  readonly property var omarchyMarks: ["agy", "copilot", "cursor", "deepseek", "devin", "grok", "grokbot", "hermes",
    "kimchi", "kimi", "minimax", "muse", "ollama", "opencode", "openrouter", "qwen", "synthetic", "vibe", "zai"]
  readonly property var omarchyLightVariants: ["agy", "copilot", "cursor", "devin", "grok", "grokbot", "hermes",
    "kimi", "minimax", "muse", "ollama", "opencode", "openrouter", "synthetic", "zai"]
  readonly property bool lightSurface: 0.2126 * surface.r + 0.7152 * surface.g + 0.0722 * surface.b >= 0.5
  // One expression, so no half-updated intermediate ever names "<dir>/.svg".
  readonly property var candidates: {
    var id = providerId, base, light
    if (ownMarks.indexOf(id) >= 0) { base = Qt.resolvedUrl("../assets/" + id); light = lightVariants.indexOf(id) >= 0 }
    else if (omarchyMarks.indexOf(id) >= 0) { base = omarchyAssets + id; light = omarchyLightVariants.indexOf(id) >= 0 }
    else return []
    return lightSurface && light ? [base + "-light.svg", base + ".svg"] : [base + ".svg"]
  }
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

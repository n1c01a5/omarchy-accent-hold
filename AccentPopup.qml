pragma ComponentBehavior: Bound
import QtQuick
import qs.Commons
import qs.Ui
import "Accents.js" as Accents

// One row of accent variants, each with its number underneath, styled with
// the Omarchy menu tokens so themes that style the menu also style this.
BorderSurface {
  id: card

  property var variants: []
  property int highlighted: -1

  signal picked(int index)
  signal hovered(int index)

  // The popup opens under a pointer that has not moved; only real pointer
  // movement may move the highlight.
  function reset() { pointerGate.reset() }

  PointerMoveGate { id: pointerGate; referenceItem: card }

  FontMetrics { id: glyphMetrics; font.family: Style.font.menuFamily; font.pixelSize: Style.font.display }
  FontMetrics { id: numberMetrics; font.family: Style.font.menuFamily; font.pixelSize: Style.font.caption }

  readonly property int cellWidth: Math.max(Style.space(40), Style.font.display + Style.spacing.lg * 2)
  readonly property int cellHeight: Math.ceil(glyphMetrics.height + numberMetrics.height) + Style.spacing.xs + Style.spacing.sm * 2

  width: row.implicitWidth + contentLeftInset + contentRightInset
  height: cellHeight + contentTopInset + contentBottomInset
  radius: Style.cornerRadius
  color: Color.menu.background
  borderSpec: Border.surfaceSpec("menu", "border", Color.menu.border, Math.max(1, Style.space(2)))
  padding: Style.spacing.sm

  // Swallow clicks so they do not reach the dismiss area behind the card.
  MouseArea { anchors.fill: parent }

  Row {
    id: row
    x: card.contentLeftInset
    y: card.contentTopInset

    Repeater {
      model: card.variants

      delegate: Rectangle {
        id: cell
        required property int index
        required property string modelData

        readonly property bool active: index === card.highlighted

        width: card.cellWidth
        height: card.cellHeight
        radius: Style.cornerRadius
        color: active ? Color.menu.selectedBackground : "transparent"

        Column {
          anchors.centerIn: parent
          spacing: Style.spacing.xs

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            height: glyphMetrics.height
            textFormat: Text.PlainText
            text: cell.modelData
            color: cell.active ? Color.menu.selectedText : Color.menu.text
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.display
          }

          Text {
            anchors.horizontalCenter: parent.horizontalCenter
            height: numberMetrics.height
            textFormat: Text.PlainText
            text: Accents.numberLabel(cell.index)
            color: cell.active ? Color.menu.selectedText : Color.menu.text
            opacity: cell.active ? 1 : 0.55
            font.family: Style.font.menuFamily
            font.pixelSize: Style.font.caption
          }
        }

        MouseArea {
          anchors.fill: parent
          hoverEnabled: true
          cursorShape: Qt.PointingHandCursor
          onPositionChanged: function(mouse) {
            if (pointerGate.moved(this, mouse)) card.hovered(cell.index)
          }
          onClicked: card.picked(cell.index)
        }
      }
    }
  }
}

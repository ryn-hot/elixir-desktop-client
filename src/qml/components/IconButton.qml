import QtQuick 6.5
import QtQuick.Controls 6.5

import "../"

Button {
    id: control
    property string label: ""

    text: label
    background: Rectangle {
        radius: Theme.radiusSmall
        color: control.down ? Theme.backgroundCardRaised : Theme.backgroundCard
        border.color: control.hovered ? Theme.accent : Theme.border
    }
    contentItem: Label {
        text: control.label
        color: Theme.textPrimary
        font.pixelSize: 13
        font.family: Theme.fontBody
        horizontalAlignment: Text.AlignHCenter
        verticalAlignment: Text.AlignVCenter
    }
}

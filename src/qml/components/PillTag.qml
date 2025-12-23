import QtQuick 6.5

import Elixir 1.0

Rectangle {
    id: root
    property string text: ""

    radius: Theme.radiusSmall
    color: Theme.backgroundCard
    border.color: Theme.border
    height: 24

    Text {
        anchors.centerIn: parent
        text: root.text
        color: Theme.textSecondary
        font.pixelSize: 11
        font.family: Theme.fontBody
    }

    implicitWidth: textItem.implicitWidth + 16

    Text {
        id: textItem
        text: root.text
        visible: false
    }
}

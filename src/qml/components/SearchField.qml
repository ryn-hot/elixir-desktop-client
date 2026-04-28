import QtQuick 6.5
import QtQuick.Controls 6.5
import QtQuick.Layouts 6.5
import Elixir 1.0

Rectangle {
    id: root
    property alias text: input.text
    property string placeholderText: "Search"
    property bool fieldActive: input.activeFocus
    signal textEdited(string text)

    implicitHeight: 38
    radius: Theme.radius8
    color: input.activeFocus ? Theme.surfaceRaised : Theme.surface
    border.color: input.activeFocus ? Theme.accent : Qt.rgba(1, 1, 1, 0.06)
    border.width: 1

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 12
        anchors.rightMargin: 10
        spacing: 8

        Image {
            source: "qrc:/icons/search.svg"
            sourceSize.width: 16
            sourceSize.height: 16
            Layout.preferredWidth: 16
            Layout.preferredHeight: 16
            opacity: 0.58
        }

        TextField {
            id: input
            Layout.fillWidth: true
            placeholderText: root.placeholderText
            color: Theme.textPrimary
            placeholderTextColor: Theme.textMuted
            font.family: Theme.fontBody
            font.pixelSize: 14
            selectByMouse: true
            verticalAlignment: Text.AlignVCenter
            background: null
            onTextChanged: root.textEdited(text)
        }

        Image {
            source: "qrc:/icons/close.svg"
            sourceSize.width: 12
            sourceSize.height: 12
            Layout.preferredWidth: 18
            Layout.preferredHeight: 18
            visible: input.text !== ""
            opacity: clearMouse.containsMouse ? 0.9 : 0.5
            MouseArea {
                id: clearMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: input.text = ""
            }
        }
    }
}

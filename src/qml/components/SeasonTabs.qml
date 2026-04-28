import QtQuick 6.5
import QtQuick.Controls 6.5
import QtQuick.Layouts 6.5
import Elixir 1.0

Item {
    id: root
    property var seasons: []
    property string activeSeasonId: ""
    signal seasonSelected(string seasonId)

    implicitHeight: 48

    ListView {
        anchors.fill: parent
        orientation: ListView.Horizontal
        spacing: Theme.space8
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        model: root.seasons || []

        delegate: Rectangle {
            height: 38
            width: Math.max(116, label.implicitWidth + countLabel.implicitWidth + 32)
            radius: Theme.radius6
            color: modelData.id === root.activeSeasonId ? Theme.surfaceHover : Theme.surface
            border.color: modelData.id === root.activeSeasonId ? Theme.accent : Theme.borderSubtle

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: root.seasonSelected(modelData.id)
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: Theme.space12
                anchors.rightMargin: Theme.space12
                spacing: Theme.space8

                Label {
                    id: label
                    text: modelData.title || ("Season " + modelData.season_number)
                    color: modelData.id === root.activeSeasonId ? Theme.textPrimary : Theme.textSecondary
                    font.family: Theme.fontBody
                    font.pixelSize: 13
                    font.weight: modelData.id === root.activeSeasonId ? Font.DemiBold : Font.Normal
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }

                Label {
                    id: countLabel
                    text: modelData.episode_count ? String(modelData.episode_count) : ""
                    color: Theme.textMuted
                    font.family: Theme.fontBody
                    font.pixelSize: 12
                    visible: text !== ""
                }
            }
        }
    }
}

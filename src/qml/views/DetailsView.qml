import QtQuick 6.5
import QtQuick.Controls 6.5
import QtQuick.Layouts 6.5

import "../components"
import Elixir 1.0

Item {
    id: root
    objectName: "detailsView"
    property StackView stackView: null
    property string mediaId: ""
    property var details: null
    property string statusText: ""
    property var libraryItem: {
        var idx = libraryModel.indexOfId(mediaId)
        return idx >= 0 ? libraryModel.get(idx) : null
    }

    Component.onCompleted: {
        if (mediaId !== "") {
            apiClient.fetchMediaDetails(mediaId)
        }
    }

    onMediaIdChanged: {
        if (mediaId !== "") {
            apiClient.fetchMediaDetails(mediaId)
        }
    }

    Flickable {
        anchors.fill: parent
        contentWidth: width
        contentHeight: contentColumn.implicitHeight + Theme.spacingXLarge
        clip: true

        ColumnLayout {
            id: contentColumn
            width: parent.width
            spacing: Theme.spacingXLarge
            anchors.margins: Theme.spacingXLarge

            RowLayout {
                spacing: Theme.spacingLarge
                Layout.fillWidth: true

                Rectangle {
                    Layout.preferredWidth: 220
                    Layout.preferredHeight: 320
                    radius: Theme.radiusMedium
                    color: Theme.backgroundCard
                    border.color: Theme.border
                    clip: true

                    Image {
                        anchors.fill: parent
                        source: libraryItem && (libraryItem.backdrop || libraryItem.poster) ? (libraryItem.backdrop || libraryItem.poster) : ""
                        fillMode: Image.PreserveAspectCrop
                        visible: source !== ""
                    }

                    Rectangle {
                        anchors.fill: parent
                        color: Theme.backgroundCard
                        visible: source === ""
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: Theme.spacingSmall

                    Label {
                        text: details ? details.title : "Loading..."
                        color: Theme.textPrimary
                        font.pixelSize: 24
                        font.family: Theme.fontDisplay
                        font.weight: Font.DemiBold
                    }

                    RowLayout {
                        spacing: Theme.spacingSmall
                        PillTag { text: details ? details.type : "" }
                        PillTag { text: details && details.year ? details.year : "" }
                        PillTag { text: details && details.runtime_seconds ? details.runtime_seconds + "s" : "" }
                    }

                    Label {
                        text: details && details.description ? details.description : ""
                        color: Theme.textSecondary
                        font.pixelSize: 13
                        font.family: Theme.fontBody
                        wrapMode: Text.Wrap
                    }

                    RowLayout {
                        spacing: Theme.spacingMedium
                        Button {
                            text: "Play"
                            enabled: details !== null
                            onClicked: apiClient.startPlayback(mediaId, "")
                            background: Rectangle {
                                radius: Theme.radiusSmall
                                color: Theme.accent
                            }
                            contentItem: Label {
                                text: parent.text
                                color: "#111111"
                                font.pixelSize: 13
                                font.family: Theme.fontBody
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                        }
                        Button {
                            text: "Back"
                            onClicked: {
                                if (root.stackView) {
                                    root.stackView.pop()
                                }
                            }
                            background: Rectangle {
                                radius: Theme.radiusSmall
                                color: Theme.backgroundCardRaised
                                border.color: Theme.border
                            }
                            contentItem: Label {
                                text: parent.text
                                color: Theme.textPrimary
                                font.pixelSize: 13
                                font.family: Theme.fontBody
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }
                        }
                    }

                    Label {
                        text: statusText
                        color: Theme.textSecondary
                        font.pixelSize: 12
                        font.family: Theme.fontBody
                        visible: statusText !== ""
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                radius: Theme.radiusLarge
                color: Theme.backgroundCard
                border.color: Theme.border

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: Theme.spacingLarge
                    spacing: Theme.spacingMedium

                    Label {
                        text: "Files"
                        color: Theme.textPrimary
                        font.pixelSize: 18
                        font.family: Theme.fontDisplay
                    }

                    Repeater {
                        model: details && details.files ? details.files : []
                        delegate: Rectangle {
                            Layout.fillWidth: true
                            height: 72
                            radius: Theme.radiusSmall
                            color: Theme.backgroundCardRaised
                            border.color: Theme.border

                            RowLayout {
                                anchors.fill: parent
                                anchors.margins: Theme.spacingMedium
                                spacing: Theme.spacingMedium

                                ColumnLayout {
                                    Layout.fillWidth: true
                                    Label {
                                        text: modelData.path
                                        color: Theme.textPrimary
                                        font.pixelSize: 12
                                        font.family: Theme.fontBody
                                        elide: Text.ElideRight
                                    }
                                    Label {
                                        text: (modelData.container || "") + " / " + (modelData.video_codec || "?") + " / " + (modelData.audio_codec || "?")
                                        color: Theme.textSecondary
                                        font.pixelSize: 11
                                        font.family: Theme.fontBody
                                        elide: Text.ElideRight
                                    }
                                }

                                Button {
                                    text: "Play file"
                                    enabled: modelData.scan_state !== "missing"
                                    onClicked: apiClient.startPlayback(mediaId, modelData.id)
                                    background: Rectangle {
                                        radius: Theme.radiusSmall
                                        color: Theme.backgroundCard
                                        border.color: Theme.border
                                    }
                                    contentItem: Label {
                                        text: parent.text
                                        color: Theme.textPrimary
                                        font.pixelSize: 12
                                        font.family: Theme.fontBody
                                        horizontalAlignment: Text.AlignHCenter
                                        verticalAlignment: Text.AlignVCenter
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    Connections {
        target: apiClient
        function onMediaDetailsReceived(obj) {
            if (obj.id === mediaId) {
                details = obj
                statusText = ""
            }
        }
        function onRequestFailed(endpoint, error) {
            statusText = "Request failed: " + error
        }
    }
}

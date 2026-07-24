import QtQuick 6.5
import QtQuick.Controls 6.5
import QtQuick.Layouts 6.5
import Elixir 1.0

AbstractButton {
    id: root
    objectName: "liveEventCard"
    property var itemData: ({})
    property string artworkSource: ""
    property string timeText: ""
    property string sourceText: ""
    readonly property bool contentFits: titleLabel.paintedWidth <= titleLabel.width + 1
                                        && subtitleLabel.paintedWidth <= subtitleLabel.width + 1
    signal activated(string providerId, string itemKey)

    implicitWidth: 300
    implicitHeight: 232
    hoverEnabled: true
    focusPolicy: Qt.StrongFocus
    Accessible.name: String(itemData.title || "Live event")
    Accessible.description: [
        String(itemData.status || "") === "unknown" ? "" : String(itemData.status || ""),
        root.timeText
    ].filter(Boolean).join(", ")
    Accessible.role: Accessible.Button
    onClicked: activated(String(itemData.providerId || ""), String(itemData.itemKey || ""))

    background: Rectangle {
        radius: Theme.radius6
        color: root.down ? Theme.surfaceHover : (root.hovered ? Theme.surfaceRaised : Theme.surface)
        border.width: root.activeFocus ? 2 : 1
        border.color: root.activeFocus ? Theme.accent : Theme.borderSubtle
    }

    contentItem: ColumnLayout {
        spacing: 0

        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: Math.max(116, Math.min(156, root.height * 0.62))
            clip: true

            Rectangle {
                anchors.fill: parent
                color: Theme.panelSoft
                radius: Theme.radius6
            }

            Image {
                id: artwork
                anchors.fill: parent
                source: root.artworkSource
                asynchronous: true
                cache: true
                fillMode: Image.PreserveAspectCrop
                visible: root.artworkSource !== "" && status !== Image.Error
                sourceSize.width: Math.max(320, width * Screen.devicePixelRatio)
                sourceSize.height: Math.max(180, height * Screen.devicePixelRatio)
            }

            Label {
                anchors.centerIn: parent
                visible: root.artworkSource === "" || artwork.status === Image.Error
                text: String(root.itemData.itemType || "event") === "channel" ? "CHANNEL" : "LIVE EVENT"
                color: Theme.textMuted
                font.family: Theme.fontBody
                font.pixelSize: 12
                font.weight: Font.Bold
                font.letterSpacing: 0
            }

            LiveStatusPill {
                anchors.left: parent.left
                anchors.top: parent.top
                anchors.margins: Theme.space10
                status: String(root.itemData.status || "unknown")
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.leftMargin: Theme.space12
            Layout.rightMargin: Theme.space12
            Layout.topMargin: Theme.space10
            Layout.bottomMargin: Theme.space10
            spacing: Theme.space4

            Label {
                id: titleLabel
                objectName: "liveEventTitle"
                Layout.fillWidth: true
                text: String(root.itemData.title || "Untitled live event")
                textFormat: Text.PlainText
                color: Theme.textPrimary
                font.family: Theme.fontBody
                font.pixelSize: 14
                font.weight: Font.DemiBold
                elide: Text.ElideRight
            }

            Label {
                id: subtitleLabel
                Layout.fillWidth: true
                text: String(root.itemData.subtitle || "")
                textFormat: Text.PlainText
                color: Theme.textSecondary
                font.family: Theme.fontBody
                font.pixelSize: 12
                elide: Text.ElideRight
                visible: text !== ""
            }

            Item { Layout.fillHeight: true }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.space8
                Label {
                    Layout.fillWidth: true
                    text: root.timeText
                    color: Theme.textMuted
                    font.family: Theme.fontBody
                    font.pixelSize: 11
                    elide: Text.ElideRight
                    visible: text !== ""
                }
                Label {
                    objectName: "liveEventSource"
                    Layout.maximumWidth: root.width * 0.42
                    text: root.sourceText
                    textFormat: Text.PlainText
                    color: Theme.textMuted
                    font.family: Theme.fontBody
                    font.pixelSize: 11
                    elide: Text.ElideRight
                    visible: text !== ""
                }
            }
        }
    }
}

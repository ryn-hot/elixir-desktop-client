import QtQuick 6.5
import QtQuick.Controls 6.5
import QtQuick.Layouts 6.5
import Qt5Compat.GraphicalEffects
import Elixir 1.0

Item {
    id: root

    property string title: ""
    property string subtitle: ""
    property string imageSource: ""
    property double progress: 0.0
    property string cardType: "portrait" // "portrait" | "landscape"
    property string badgeText: ""
    property string mediaId: ""
    property bool trackedByManager: false
    property bool canStopTracking: false
    property string managerLabel: ""
    property bool deleteBusy: false
    property bool pendingStopTracking: false
    property string deleteStatusText: ""

    signal clicked(string mediaId)

    function resolvedManagerLabel() {
        var label = String(root.managerLabel || "").trim()
        return label !== "" ? label : "manager"
    }

    width: cardType === "landscape" ? Theme.landscapeWidth : Theme.posterWidth
    height: cardType === "landscape" ? Theme.landscapeHeight + 40 : Theme.posterHeight + 40

    HoverHandler {
        id: hoverHandler
    }

    MouseArea {
        anchors.fill: parent
        acceptedButtons: Qt.LeftButton
        cursorShape: Qt.PointingHandCursor
        onClicked: root.clicked(root.mediaId)
    }

    scale: hoverHandler.hovered ? 1.05 : 1.0
    Behavior on scale { NumberAnimation { duration: 150 } }
    z: hoverHandler.hovered || actionMenu.visible ? 10 : 1

    ColumnLayout {
        anchors.fill: parent
        spacing: 8

        Item {
            id: imageContainer
            Layout.fillWidth: true
            Layout.preferredHeight: root.cardType === "landscape" ? Theme.landscapeHeight : Theme.posterHeight

            Image {
                id: posterImage
                anchors.fill: parent
                source: root.imageSource
                fillMode: Image.PreserveAspectCrop
                visible: false
                asynchronous: true
            }

            Rectangle {
                id: mask
                anchors.fill: parent
                radius: 4
                visible: false
            }

            OpacityMask {
                anchors.fill: posterImage
                source: posterImage
                maskSource: mask
            }

            Rectangle {
                anchors.fill: parent
                color: "transparent"
                border.color: "white"
                border.width: 3
                radius: 4
                visible: hoverHandler.hovered
            }

            Item {
                anchors.fill: parent
                visible: root.cardType === "landscape"

                Rectangle {
                    width: 48
                    height: 48
                    radius: 24
                    color: "#cc000000"
                    anchors.centerIn: parent
                    visible: hoverHandler.hovered

                    Rectangle {
                        width: 0
                        height: 0
                        color: "transparent"
                        border.color: "transparent"
                        anchors.centerIn: parent
                        anchors.horizontalCenterOffset: 2

                        Canvas {
                            anchors.fill: parent
                            onPaint: {
                                var ctx = getContext("2d")
                                ctx.fillStyle = Theme.accent
                                ctx.beginPath()
                                ctx.moveTo(-8, -10)
                                ctx.lineTo(12, 0)
                                ctx.lineTo(-8, 10)
                                ctx.closePath()
                                ctx.fill()
                            }
                        }
                    }
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 4
                    color: "#80000000"
                    visible: root.progress > 0

                    Rectangle {
                        height: parent.height
                        width: parent.width * root.progress
                        color: Theme.accent
                    }
                }

                Rectangle {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    anchors.margins: 8
                    anchors.bottomMargin: 12
                    width: timeLabel.width + 12
                    height: 20
                    radius: 10
                    color: "#cc000000"
                    visible: root.progress > 0 && root.progress < 0.9

                    Label {
                        id: timeLabel
                        anchors.centerIn: parent
                        text: Math.round((1.0 - root.progress) * 20) + " min"
                        color: "white"
                        font.pixelSize: 10
                        font.bold: true
                    }
                }
            }

            Item {
                anchors.fill: parent
                visible: root.cardType === "portrait" && root.badgeText !== ""

                Rectangle {
                    width: 24
                    height: 24
                    radius: 12
                    color: Theme.accent
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.margins: -8
                    z: 5

                    Label {
                        anchors.centerIn: parent
                        text: root.badgeText
                        color: "black"
                        font.pixelSize: 10
                        font.bold: true
                    }
                }
            }

            Button {
                id: actionButton
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.margins: 8
                z: 20
                visible: root.mediaId !== "" && (hoverHandler.hovered || actionMenu.visible)
                width: 30
                height: 30
                padding: 0
                onClicked: {
                    if (Overlay.overlay) {
                        var point = actionButton.mapToItem(
                                    Overlay.overlay,
                                    actionButton.width - actionMenu.width,
                                    actionButton.height + 6)
                        actionMenu.x = Math.max(8, point.x)
                        actionMenu.y = Math.max(8, point.y)
                    } else {
                        actionMenu.x = Math.max(0, imageContainer.width - actionMenu.width - 8)
                        actionMenu.y = actionButton.y + actionButton.height + 6
                    }
                    actionMenu.open()
                }
                background: Rectangle {
                    radius: 15
                    color: actionButton.hovered ? "#f02a2d33" : "#d91a1c1f"
                    border.color: "#4dffffff"
                }
                contentItem: Image {
                    source: "qrc:/icons/more_vert.svg"
                    sourceSize.width: 16
                    sourceSize.height: 16
                    anchors.centerIn: parent
                    opacity: 0.92
                }
            }

            Popup {
                id: actionMenu
                parent: Overlay.overlay
                width: 220
                modal: false
                focus: true
                padding: 6
                closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
                background: Rectangle {
                    radius: Theme.radiusSmall
                    color: Theme.backgroundCard
                    border.color: Theme.border
                }

                contentItem: ColumnLayout {
                    spacing: 4

                    Button {
                        id: manageButton
                        Layout.fillWidth: true
                        leftPadding: Theme.spacingSmall
                        text: "Manage"
                        onClicked: {
                            actionMenu.close()
                            root.clicked(root.mediaId)
                        }
                        background: Rectangle {
                            radius: Theme.radiusSmall
                            color: manageButton.hovered ? Theme.backgroundCardRaised : "transparent"
                        }
                        contentItem: Label {
                            text: manageButton.text
                            color: Theme.textPrimary
                            font.pixelSize: 12
                            font.family: Theme.fontBody
                            horizontalAlignment: Text.AlignLeft
                            verticalAlignment: Text.AlignVCenter
                        }
                    }

                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 1
                        color: Theme.border
                    }

                    Button {
                        id: deleteMenuButton
                        Layout.fillWidth: true
                        leftPadding: Theme.spacingSmall
                        text: "Delete from Elixir"
                        enabled: !root.deleteBusy
                        onClicked: {
                            root.pendingStopTracking = false
                            root.deleteStatusText = ""
                            actionMenu.close()
                            deleteDialog.open()
                        }
                        background: Rectangle {
                            radius: Theme.radiusSmall
                            color: deleteMenuButton.hovered ? "#3a2224" : "transparent"
                        }
                        contentItem: Label {
                            text: deleteMenuButton.text
                            color: Theme.textPrimary
                            font.pixelSize: 12
                            font.family: Theme.fontBody
                            horizontalAlignment: Text.AlignLeft
                            verticalAlignment: Text.AlignVCenter
                        }
                    }

                    Button {
                        id: stopDeleteMenuButton
                        Layout.fillWidth: true
                        leftPadding: Theme.spacingSmall
                        visible: root.canStopTracking
                        enabled: !root.deleteBusy
                        text: "Delete + Stop " + root.resolvedManagerLabel()
                        onClicked: {
                            root.pendingStopTracking = true
                            root.deleteStatusText = ""
                            actionMenu.close()
                            deleteDialog.open()
                        }
                        background: Rectangle {
                            radius: Theme.radiusSmall
                            color: stopDeleteMenuButton.hovered ? "#3a3220" : "transparent"
                        }
                        contentItem: Label {
                            text: stopDeleteMenuButton.text
                            color: Theme.textPrimary
                            font.pixelSize: 12
                            font.family: Theme.fontBody
                            horizontalAlignment: Text.AlignLeft
                            verticalAlignment: Text.AlignVCenter
                        }
                    }
                }
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            spacing: 2

            Label {
                text: root.title
                Layout.fillWidth: true
                color: Theme.textPrimary
                font.family: Theme.bodyFont.family
                font.pixelSize: root.cardType === "landscape" ? 14 : 13
                font.weight: Font.Bold
                elide: Text.ElideRight
            }

            Label {
                text: root.subtitle
                Layout.fillWidth: true
                color: Theme.textSecondary
                font.family: Theme.bodyFont.family
                font.pixelSize: 12
                elide: Text.ElideRight
                visible: text !== ""
            }
        }
    }

    Dialog {
        id: deleteDialog
        parent: Overlay.overlay
        modal: true
        width: Math.min(Overlay.overlay ? Overlay.overlay.width * 0.86 : 520, 520)
        x: Overlay.overlay ? Math.round((Overlay.overlay.width - width) / 2) : 0
        y: Overlay.overlay ? Math.max(24, Math.round((Overlay.overlay.height - height) / 2)) : 0
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

        background: Rectangle {
            color: Theme.backgroundCard
            radius: Theme.radiusLarge
            border.color: Theme.border
        }

        contentItem: ColumnLayout {
            spacing: Theme.spacingMedium

            Label {
                text: root.pendingStopTracking ? "Delete and stop tracking" : "Delete from Elixir"
                color: Theme.textPrimary
                font.pixelSize: 18
                font.family: Theme.fontDisplay
            }

            Label {
                Layout.fillWidth: true
                wrapMode: Text.Wrap
                color: Theme.textSecondary
                font.pixelSize: 13
                font.family: Theme.fontBody
                text: root.pendingStopTracking
                      ? ("Delete this item from Elixir and stop " + root.resolvedManagerLabel()
                         + " from tracking it.")
                      : "Delete this item from Elixir. This removes the local library entry and its files from disk."
            }

            Label {
                Layout.fillWidth: true
                visible: root.deleteStatusText !== ""
                wrapMode: Text.Wrap
                color: Theme.textSecondary
                font.pixelSize: 12
                font.family: Theme.fontBody
                text: root.deleteStatusText
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: Theme.spacingSmall

                Button {
                    text: "Cancel"
                    enabled: !root.deleteBusy
                    onClicked: deleteDialog.close()
                    background: Rectangle {
                        radius: Theme.radiusSmall
                        color: Theme.backgroundCardRaised
                        border.color: Theme.border
                    }
                    contentItem: Label {
                        text: "Cancel"
                        color: Theme.textPrimary
                        font.pixelSize: 12
                        font.family: Theme.fontBody
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }

                Item { Layout.fillWidth: true }

                Button {
                    text: root.deleteBusy
                          ? "Working..."
                          : (root.pendingStopTracking
                             ? "Delete + Stop " + root.resolvedManagerLabel()
                             : "Delete")
                    enabled: !root.deleteBusy
                    onClicked: {
                        root.deleteBusy = true
                        root.deleteStatusText = ""
                        apiClient.deleteLibraryItem(root.mediaId, root.pendingStopTracking)
                    }
                    background: Rectangle {
                        radius: Theme.radiusSmall
                        color: root.pendingStopTracking ? Theme.accent : "#5a2b2b"
                        border.color: root.pendingStopTracking ? Theme.accent : "#8d4a4a"
                    }
                    contentItem: Label {
                        text: root.deleteBusy
                              ? "Working..."
                              : (root.pendingStopTracking
                                 ? "Delete + Stop " + root.resolvedManagerLabel()
                                 : "Delete")
                        color: root.pendingStopTracking ? "#111111" : Theme.textPrimary
                        font.pixelSize: 12
                        font.family: Theme.fontBody
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                }
            }
        }
    }

    Connections {
        target: apiClient

        function onMediaItemDeleted(deletedId, result) {
            if (deletedId !== root.mediaId) {
                return
            }
            root.deleteBusy = false
            root.deleteStatusText = ""
            deleteDialog.close()
            actionMenu.close()
        }

        function onRequestFailed(endpoint, error) {
            if (endpoint !== "/api/v1/library/items/" + root.mediaId || !root.deleteBusy) {
                return
            }
            root.deleteBusy = false
            root.deleteStatusText = "Delete failed: " + error
        }
    }
}

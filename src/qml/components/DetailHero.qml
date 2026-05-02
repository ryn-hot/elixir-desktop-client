import QtQuick 6.5
import QtQuick.Controls 6.5
import QtQuick.Layouts 6.5
import Elixir 1.0

Item {
    id: root
    property string title: ""
    property string posterSource: ""
    property string backdropSource: ""
    property string description: ""
    property string typeLabel: ""
    property string yearLabel: ""
    property string runtimeLabel: ""
    property var genres: []
    property bool busy: false
    property bool showRestoreBlocked: false
    readonly property real backdropVerticalCropBias: 0.35
    signal playRequested()
    signal deleteRequested()
    signal restoreBlockedRequested()
    signal backRequested()

    implicitHeight: Math.max(460, Math.min(680, width * 0.44))

    Rectangle {
        anchors.fill: parent
        color: Theme.appBg
        clip: true

        Image {
            id: backdrop
            readonly property real sourceAspect: implicitWidth > 0 && implicitHeight > 0 ? implicitWidth / implicitHeight : 16 / 9
            readonly property real targetAspect: parent.width > 0 && parent.height > 0 ? parent.width / parent.height : 16 / 9
            readonly property bool cropsVertically: sourceAspect < targetAspect

            width: cropsVertically ? parent.width : parent.height * sourceAspect
            height: cropsVertically ? parent.width / sourceAspect : parent.height
            x: cropsVertically ? 0 : (parent.width - width) / 2
            y: cropsVertically ? -(height - parent.height) * root.backdropVerticalCropBias : 0
            source: root.backdropSource
            fillMode: Image.Stretch
            asynchronous: true
            visible: status === Image.Ready && source !== ""
        }

        Rectangle {
            anchors.fill: parent
            gradient: Gradient {
                GradientStop { position: 0.0; color: "#B8111317" }
                GradientStop { position: 0.48; color: "#A6111317" }
                GradientStop { position: 1.0; color: Theme.appBg }
            }
        }

        Rectangle {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.bottom: parent.bottom
            width: Math.min(parent.width * 0.70, 920)
            gradient: Gradient {
                orientation: Gradient.Horizontal
                GradientStop { position: 0.0; color: "#F8151515" }
                GradientStop { position: 0.70; color: "#B8151515" }
                GradientStop { position: 1.0; color: "#0017191D" }
            }
        }

        ActionButton {
            anchors.left: parent.left
            anchors.top: parent.top
            anchors.leftMargin: Theme.space32
            anchors.topMargin: Theme.space24
            text: "Back"
            variant: "ghost"
            compact: true
            onClicked: root.backRequested()
        }

        RowLayout {
            anchors.left: parent.left
            anchors.right: parent.right
            anchors.bottom: parent.bottom
            anchors.leftMargin: Theme.space32
            anchors.rightMargin: Theme.space32
            anchors.bottomMargin: Theme.space36
            spacing: Theme.space28

            Rectangle {
                Layout.preferredWidth: Theme.posterLargeWidth
                Layout.preferredHeight: Theme.posterLargeHeight
                radius: Theme.radius8
                color: Theme.surface
                border.color: Qt.rgba(1, 1, 1, 0.14)
                clip: true

                Image {
                    id: poster
                    anchors.fill: parent
                    source: root.posterSource
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    visible: status === Image.Ready && source !== ""
                }

                Label {
                    anchors.centerIn: parent
                    width: parent.width - Theme.space24
                    text: root.title
                    color: Theme.textSecondary
                    font.family: Theme.fontBody
                    font.pixelSize: 13
                    wrapMode: Text.Wrap
                    horizontalAlignment: Text.AlignHCenter
                    visible: !poster.visible
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.maximumWidth: 820
                spacing: Theme.space14

                Label {
                    text: root.title !== "" ? root.title : "Loading..."
                    color: Theme.textPrimary
                    font.family: Theme.fontDisplay
                    font.pixelSize: Math.max(30, Math.min(48, root.width / 31))
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                    maximumLineCount: 2
                    Layout.fillWidth: true
                }

                Flow {
                    Layout.fillWidth: true
                    spacing: Theme.space8
                    visible: children.length > 0
                    PillTag { text: root.typeLabel; visible: root.typeLabel !== "" }
                    PillTag { text: root.yearLabel; visible: root.yearLabel !== "" && root.yearLabel !== "0" }
                    PillTag { text: root.runtimeLabel; visible: root.runtimeLabel !== "" && root.runtimeLabel !== "0s" }
                    Repeater {
                        model: root.genres || []
                        delegate: PillTag { text: modelData }
                    }
                }

                Label {
                    text: root.description !== "" ? root.description : "No description available yet."
                    color: Theme.textSecondary
                    font.family: Theme.fontBody
                    font.pixelSize: 15
                    lineHeight: 1.2
                    wrapMode: Text.Wrap
                    maximumLineCount: 4
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }

                RowLayout {
                    spacing: Theme.space12
                    ActionButton {
                        text: "Play"
                        variant: "primary"
                        enabled: !root.busy
                        iconSource: "qrc:/icons/play.svg"
                        onClicked: root.playRequested()
                    }
                    ActionButton {
                        text: "More"
                        variant: "secondary"
                        onClicked: actionsMenu.open()
                    }
                }
            }
        }
    }

    Popup {
        id: actionsMenu
        width: 240
        x: Math.min(parent.width - width - Theme.space24, Theme.space32 + Theme.posterLargeWidth + Theme.space24 + 92)
        y: parent.height - Theme.space32 - 120
        modal: false
        focus: true
        padding: Theme.space8
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent
        background: Rectangle {
            color: Theme.surfaceRaised
            radius: Theme.radius6
            border.color: Theme.borderSubtle
        }
        contentItem: ColumnLayout {
            spacing: Theme.space4
            ActionButton {
                Layout.fillWidth: true
                text: "Delete"
                variant: "danger"
                compact: true
                enabled: !root.busy
                onClicked: {
                    actionsMenu.close()
                    root.deleteRequested()
                }
            }
            ActionButton {
                Layout.fillWidth: true
                text: "Restore blocked episodes"
                variant: "secondary"
                compact: true
                visible: root.showRestoreBlocked
                enabled: !root.busy
                onClicked: {
                    actionsMenu.close()
                    root.restoreBlockedRequested()
                }
            }
        }
    }
}

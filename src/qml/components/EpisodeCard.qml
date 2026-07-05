import QtQuick 6.5
import QtQuick.Controls 6.5
import QtQuick.Layouts 6.5
import Elixir 1.0

Rectangle {
    id: root
    property string title: ""
    property string description: ""
    property string thumbnail: ""
    property string statusText: ""
    property string statusMessage: ""
    property string recoveryState: ""
    property bool available: false
    property bool blocked: false
    property bool canDelete: false
    property bool canRestore: false
    property bool canAcquire: false
    property string watchStateText: ""
    property bool watchStateWatched: false
    property bool canMarkWatched: false
    property bool canMarkUnwatched: false
    property bool canResetProgress: false
    property bool selectionMode: false
    property bool selectable: false
    property bool selected: false
    property string acquireText: "Get episode"
    property bool busy: false
    property string busyAction: ""
    readonly property int verticalPadding: Theme.space10
    signal playRequested()
    signal deleteRequested()
    signal restoreRequested()
    signal acquireRequested()
    signal markWatchedRequested()
    signal markUnwatchedRequested()
    signal resetProgressRequested()
    signal selectionToggled(bool selected)

    function showStatusChrome() {
        return root.recoveryState !== "available" && root.statusText !== ""
    }

    function stateColor() {
        if (root.blocked || root.recoveryState === "blocked") return Theme.accentInfo
        if (root.available || root.recoveryState === "available") return Theme.accentSuccess
        if (root.recoveryState === "review_needed") return Theme.accent
        if (root.recoveryState === "no_results" || root.recoveryState === "failed") return Theme.accentDanger
        if (root.recoveryState === "queued" ||
                root.recoveryState === "searching" ||
                root.recoveryState === "downloading" ||
                root.recoveryState === "post_processing") return Theme.accentInfo
        return Theme.accent
    }

    function stateFill() {
        if (root.available || root.recoveryState === "available") return Theme.accentSuccessSoft
        if (root.recoveryState === "no_results" || root.recoveryState === "failed") return Theme.accentDangerSoft
        if (root.recoveryState === "queued" ||
                root.recoveryState === "searching" ||
                root.recoveryState === "downloading" ||
                root.recoveryState === "post_processing" ||
                root.recoveryState === "blocked") return Theme.accentInfoSoft
        return Theme.accentSoft
    }

    radius: Theme.radius4
    color: hover.hovered ? Qt.rgba(1, 1, 1, 0.055) : "transparent"
    border.color: "transparent"
    implicitHeight: Math.max(Theme.episodeThumbHeight, detailsColumn.implicitHeight) + verticalPadding * 2

    HoverHandler { id: hover }

    RowLayout {
        anchors.fill: parent
        anchors.leftMargin: 0
        anchors.rightMargin: 0
        anchors.topMargin: root.verticalPadding
        anchors.bottomMargin: root.verticalPadding
        spacing: Theme.space16

        Item {
            Layout.preferredWidth: root.selectionMode ? 32 : 0
            Layout.fillHeight: true
            visible: root.selectionMode

            CheckBox {
                anchors.centerIn: parent
                checked: root.selected
                enabled: root.selectable && !root.busy
                opacity: enabled ? 1.0 : 0.45
                onToggled: root.selectionToggled(checked)
            }
        }

        Rectangle {
            Layout.preferredWidth: Theme.episodeThumbWidth
            Layout.preferredHeight: Theme.episodeThumbHeight
            radius: Theme.radius8
            color: Theme.surfaceRaised
            clip: true

            Image {
                id: thumb
                anchors.fill: parent
                source: root.thumbnail
                fillMode: Image.PreserveAspectCrop
                asynchronous: true
                visible: status === Image.Ready && source !== ""
            }

            Rectangle {
                anchors.fill: parent
                color: "#55000000"
                visible: hover.hovered && root.available && !root.blocked
                Rectangle {
                    width: 40
                    height: 40
                    radius: 20
                    color: Theme.accent
                    anchors.centerIn: parent
                    Image {
                        source: "qrc:/icons/play.svg"
                        anchors.centerIn: parent
                        width: 16
                        height: 16
                    }
                }
            }
        }

        ColumnLayout {
            id: detailsColumn
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: Theme.space8

            Label {
                text: root.title
                color: root.available && !root.blocked ? Theme.textPrimary : Theme.textMuted
                font.family: Theme.fontBody
                font.pixelSize: 15
                font.weight: Font.DemiBold
                elide: Text.ElideRight
                Layout.fillWidth: true
            }

            Label {
                text: root.description !== "" ? root.description : "No description available."
                color: Theme.textSecondary
                font.family: Theme.fontBody
                font.pixelSize: 13
                wrapMode: Text.Wrap
                maximumLineCount: 2
                elide: Text.ElideRight
                Layout.fillWidth: true
                Layout.fillHeight: true
            }

            RowLayout {
                spacing: Theme.space8

                Rectangle {
                    Layout.preferredWidth: 132
                    Layout.preferredHeight: 24
                    visible: root.showStatusChrome()
                    radius: Theme.radiusSmall
                    color: root.stateFill()
                    border.color: root.stateColor()

                    Label {
                        id: statusLabel
                        anchors.centerIn: parent
                        text: root.statusText
                        color: Theme.textPrimary
                        font.family: Theme.fontBody
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }
                }

                Rectangle {
                    Layout.preferredWidth: 96
                    Layout.preferredHeight: 24
                    visible: root.watchStateText !== ""
                    radius: Theme.radiusSmall
                    color: root.watchStateWatched ? Theme.accentSuccessSoft : Theme.panelSoft
                    border.color: root.watchStateWatched ? Theme.accentSuccess : Theme.borderSubtle

                    Label {
                        anchors.centerIn: parent
                        text: root.watchStateText
                        color: Theme.textPrimary
                        font.family: Theme.fontBody
                        font.pixelSize: 11
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }
                }

                Label {
                    Layout.fillWidth: true
                    text: root.showStatusChrome() ? root.statusMessage : ""
                    color: Theme.textSecondary
                    font.family: Theme.fontBody
                    font.pixelSize: 12
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }

                ActionButton {
                    text: "Play"
                    compact: true
                    Layout.preferredWidth: 104
                    visible: root.available && !root.blocked
                    enabled: !root.busy
                    onClicked: root.playRequested()
                }
                ActionButton {
                    text: root.busy ? "Requesting..." : root.acquireText
                    compact: true
                    Layout.preferredWidth: 124
                    visible: root.canAcquire && !root.available && !root.blocked
                    enabled: !root.busy
                    onClicked: root.acquireRequested()
                }
                ActionButton {
                    text: root.busy ? "Working..." : "Delete"
                    compact: true
                    variant: "danger"
                    Layout.preferredWidth: 104
                    visible: root.canDelete && !root.blocked
                    enabled: !root.busy
                    onClicked: root.deleteRequested()
                }
                ActionButton {
                    text: root.busy ? "Working..." : "Allow again"
                    compact: true
                    Layout.preferredWidth: 124
                    visible: root.canRestore
                    enabled: !root.busy
                    onClicked: root.restoreRequested()
                }
            }

            RowLayout {
                visible: root.canMarkWatched || root.canMarkUnwatched || root.canResetProgress
                spacing: Theme.space8

                Item { Layout.fillWidth: true }

                ActionButton {
                    text: root.busy && root.busyAction === "watched" ? "Saving..." : "Watched"
                    compact: true
                    variant: "ghost"
                    Layout.preferredWidth: 104
                    visible: root.canMarkWatched
                    enabled: !root.busy
                    onClicked: root.markWatchedRequested()
                }

                ActionButton {
                    text: root.busy && root.busyAction === "unwatched" ? "Saving..." : "Unwatched"
                    compact: true
                    variant: "ghost"
                    Layout.preferredWidth: 112
                    visible: root.canMarkUnwatched
                    enabled: !root.busy
                    onClicked: root.markUnwatchedRequested()
                }

                ActionButton {
                    text: root.busy && root.busyAction === "reset" ? "Saving..." : "Reset"
                    compact: true
                    variant: "ghost"
                    Layout.preferredWidth: 92
                    visible: root.canResetProgress
                    enabled: !root.busy
                    onClicked: root.resetProgressRequested()
                }
            }
        }
    }

    Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: 1
        color: Qt.rgba(1, 1, 1, 0.07)
    }
}

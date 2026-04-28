import QtQuick 6.5
import QtQuick.Controls 6.5
import QtQuick.Layouts 6.5
import Elixir 1.0

Button {
    id: root
    property string variant: "secondary"
    property string iconSource: ""
    property bool compact: false

    implicitHeight: compact ? 32 : 38
    implicitWidth: Math.max(compact ? 80 : 104, contentRow.implicitWidth + leftPadding + rightPadding)
    leftPadding: compact ? 12 : 16
    rightPadding: compact ? 12 : 16
    topPadding: 0
    bottomPadding: 0

    function baseColor() {
        if (!enabled) return Theme.surface
        if (variant === "primary") return hovered ? Theme.accentHover : Theme.accent
        if (variant === "danger") return hovered ? "#7A3434" : "#5A292B"
        if (variant === "ghost") return hovered ? Theme.surfaceHover : "transparent"
        return hovered ? Theme.surfaceHover : Theme.surfaceRaised
    }

    background: Rectangle {
        radius: Theme.radius6
        color: root.baseColor()
        border.color: root.variant === "primary" ? "transparent" : (root.variant === "danger" ? "#A65353" : Theme.borderSubtle)
        opacity: root.enabled ? 1.0 : 0.55
    }

    contentItem: RowLayout {
        id: contentRow
        spacing: 8

        Image {
            source: root.iconSource
            sourceSize.width: 16
            sourceSize.height: 16
            Layout.preferredWidth: root.iconSource === "" ? 0 : 16
            Layout.preferredHeight: 16
            visible: root.iconSource !== ""
            opacity: root.enabled ? 0.95 : 0.45
        }

        Label {
            text: root.text
            color: root.variant === "primary" ? "#17120A" : Theme.textPrimary
            font.family: Theme.fontBody
            font.pixelSize: root.compact ? 12 : 13
            font.weight: root.variant === "primary" ? Font.DemiBold : Font.Normal
            horizontalAlignment: Text.AlignHCenter
            verticalAlignment: Text.AlignVCenter
            elide: Text.ElideRight
            Layout.fillWidth: true
        }
    }
}

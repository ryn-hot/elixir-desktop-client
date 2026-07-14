import QtQuick 6.5
import QtQuick.Controls 6.5
import Elixir 1.0

Rectangle {
    id: root
    property string status: "unknown"
    property string label: {
        if (status === "live") return "LIVE"
        if (status === "scheduled") return "UPCOMING"
        if (status === "ended") return "ENDED"
        if (status === "unavailable") return "UNAVAILABLE"
        return "STATUS UNKNOWN"
    }

    implicitWidth: statusLabel.implicitWidth + 14
    implicitHeight: 22
    radius: Theme.radius4
    color: {
        if (status === "live") return Theme.accentDanger
        if (status === "scheduled") return Theme.accentInfo
        if (status === "ended") return Theme.surfaceRaised
        return Theme.surface
    }
    border.color: status === "unknown" || status === "unavailable"
                  ? Theme.borderSubtle : "transparent"

    Label {
        id: statusLabel
        anchors.centerIn: parent
        text: root.label
        color: root.status === "scheduled" ? "#101820" : Theme.textPrimary
        font.family: Theme.fontBody
        font.pixelSize: 10
        font.weight: Font.Bold
        font.letterSpacing: 0
    }
}

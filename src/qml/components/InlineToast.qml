import QtQuick 6.5
import QtQuick.Controls 6.5

import Elixir 1.0

Label {
    id: root
    property int durationMs: Theme.toastDurationMs
    property int fadeMs: Theme.toastFadeMs
    property bool autoClear: true

    function show(message) {
        text = message || ""
        if (autoClear && text !== "") {
            clearTimer.restart()
        }
    }

    function clear() {
        text = ""
        clearTimer.stop()
    }

    color: Theme.textMuted
    font.pixelSize: 11
    font.family: Theme.fontBody

    opacity: text === "" ? 0 : 1
    visible: opacity > 0.01
    Behavior on opacity {
        NumberAnimation { duration: root.fadeMs }
    }

    Timer {
        id: clearTimer
        interval: root.durationMs
        repeat: false
        onTriggered: root.text = ""
    }
}

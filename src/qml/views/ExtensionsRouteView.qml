import QtQuick 6.5
import QtQuick.Controls 6.5

import "../components"

Item {
    id: root
    objectName: "extensionsView"
    property StackView stackView: null

    Loader {
        id: extensionsLoader
        anchors.fill: parent
        asynchronous: true
        source: Qt.resolvedUrl("ExtensionsView.qml")
        onLoaded: {
            if (!item) {
                return
            }
            if (item.stackView !== undefined) {
                item.stackView = root.stackView
            }
        }
    }

    BusyIndicator {
        anchors.centerIn: parent
        running: extensionsLoader.status === Loader.Loading
        visible: running
    }
}

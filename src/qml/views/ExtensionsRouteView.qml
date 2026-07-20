import QtQuick 6.5
import QtQuick.Controls 6.5

import "../components"

Item {
    id: root
    objectName: "extensionsView"
    property StackView stackView: null
    property string marketplaceKindFilter: ""
    property string marketplaceTargetCapabilityFilter: ""
    property string marketplaceFilterLabel: ""
    property bool focusMarketplace: false
    property var openLiveRequested: null

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
            if (item.marketplaceKindFilter !== undefined) {
                item.marketplaceKindFilter = root.marketplaceKindFilter
            }
            if (item.marketplaceTargetCapabilityFilter !== undefined) {
                item.marketplaceTargetCapabilityFilter = root.marketplaceTargetCapabilityFilter
            }
            if (item.marketplaceFilterLabel !== undefined) {
                item.marketplaceFilterLabel = root.marketplaceFilterLabel
            }
            if (item.focusMarketplace !== undefined) {
                item.focusMarketplace = root.focusMarketplace
            }
            if (item.openLiveRequested !== undefined) {
                item.openLiveRequested = root.openLiveRequested
            }
        }
    }

    BusyIndicator {
        anchors.centerIn: parent
        running: extensionsLoader.status === Loader.Loading
        visible: running
    }
}

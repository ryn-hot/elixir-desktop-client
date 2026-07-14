import QtQuick 6.5
import QtQuick.Controls 6.5
import QtQuick.Layouts 6.5

import "../components"
import Elixir 1.0

Item {
    id: root
    objectName: "liveView"
    required property var liveModel
    property var itemsModel: liveModel
    property StackView stackView: null
    property string serverBaseUrl: ""
    property var playerController: null
    property var activeFilters: ({})
    property bool initialized: false
    signal itemRequested(string providerId, string itemKey)

    readonly property int pageMargin: width < 700 ? Theme.space16 : Theme.space32
    readonly property var selectedCatalog: {
        var catalogs = liveModel.catalogs || []
        for (var i = 0; i < catalogs.length; ++i) {
            if (String(catalogs[i].providerId) === String(liveModel.selectedProviderId)
                    && String(catalogs[i].catalogId) === String(liveModel.selectedCatalogId)) {
                return catalogs[i]
            }
        }
        return null
    }
    readonly property int readyProviderCount: {
        var providers = liveModel.providers || []
        var count = 0
        for (var i = 0; i < providers.length; ++i) {
            if (providers[i].readiness === "ready" || providers[i].readiness === "degraded") ++count
        }
        return count
    }
    readonly property int gridColumns: Math.max(1, Math.floor((contentWidth + Theme.space16) / 292))
    readonly property real contentWidth: Math.max(0, width - pageMargin * 2)

    Rectangle {
        anchors.fill: parent
        color: Theme.appBg
        z: -1
    }

    function absoluteArtwork(artwork) {
        if (!artwork || !artwork.url || serverBaseUrl === "") return ""
        var base = String(serverBaseUrl)
        while (base.endsWith("/")) base = base.slice(0, -1)
        return base + String(artwork.url)
    }

    function formatEventTime(value, status) {
        if (!value) return status === "live" ? "Live now" : ""
        var date = new Date(value)
        if (isNaN(date.getTime())) return ""
        if (status === "live") return "Live now - " + Qt.formatTime(date, "h:mm AP")
        return Qt.formatDateTime(date, "ddd, MMM d - h:mm AP")
    }

    function providerName(providerId) {
        var providers = liveModel.providers || []
        for (var i = 0; i < providers.length; ++i) {
            if (String(providers[i].providerId) === String(providerId))
                return String(providers[i].name || "Live provider")
        }
        return "Live provider"
    }

    function noticeText() {
        if (liveModel.lastError && liveModel.lastError.message)
            return String(liveModel.lastError.message)
        var failures = liveModel.errors || []
        if (failures.length > 0) {
            var labels = []
            for (var i = 0; i < failures.length; ++i) {
                labels.push(providerName(failures[i].providerId) + ": " +
                            String(failures[i].message || "Unavailable"))
            }
            return labels.join(" / ")
        }
        if (liveModel.partial) return "Some Live providers could not be reached."
        return "Showing recently cached Live results."
    }

    function ensureSelection() {
        var catalogs = liveModel.catalogs || []
        if (catalogs.length === 0 || String(liveModel.selectedCatalogId || "") !== "") return
        activeFilters = ({})
        liveModel.selectCatalog(String(catalogs[0].providerId), String(catalogs[0].catalogId), activeFilters)
    }

    function selectCatalog(catalog) {
        activeFilters = ({})
        liveModel.selectCatalog(String(catalog.providerId), String(catalog.catalogId), activeFilters)
    }

    function openItem(providerId, itemKey) {
        root.itemRequested(providerId, itemKey)
        if (stackView) {
            stackView.push(Qt.resolvedUrl("LiveDetailsView.qml"), {
                stackView: stackView,
                liveModel: liveModel,
                playerController: playerController,
                serverBaseUrl: serverBaseUrl,
                providerId: providerId,
                itemKey: itemKey
            })
        }
    }

    Component.onCompleted: {
        initialized = true
        if ((liveModel.providers || []).length === 0 && !liveModel.catalogIndexLoading) {
            liveModel.refreshIndex()
        } else {
            ensureSelection()
        }
    }

    Connections {
        target: root.liveModel
        function onCatalogsChanged() { root.ensureSelection() }
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.leftMargin: root.pageMargin
        anchors.rightMargin: root.pageMargin
        anchors.topMargin: Theme.space24
        anchors.bottomMargin: Theme.space16
        spacing: Theme.space16

        RowLayout {
            Layout.fillWidth: true
            spacing: Theme.space16

            ColumnLayout {
                Layout.fillWidth: true
                spacing: Theme.space4
                Label {
                    text: "Live"
                    color: Theme.textPrimary
                    font.family: Theme.fontDisplay
                    font.pixelSize: 30
                    font.weight: Font.Bold
                }
                Label {
                    text: (root.liveModel.catalogs || []).length + " catalog" +
                          ((root.liveModel.catalogs || []).length === 1 ? "" : "s") + " / " +
                          (root.liveModel.providers || []).length + " provider" +
                          ((root.liveModel.providers || []).length === 1 ? "" : "s")
                    color: Theme.textSecondary
                    font.family: Theme.fontBody
                    font.pixelSize: 13
                    elide: Text.ElideRight
                    Layout.fillWidth: true
                }
            }

            ActionButton {
                objectName: "liveRefreshButton"
                text: "Refresh"
                iconSource: "qrc:/icons/activity.svg"
                compact: true
                enabled: !root.liveModel.catalogIndexLoading && !root.liveModel.pageLoading
                Accessible.name: "Refresh Live catalogs"
                onClicked: root.liveModel.refreshIndex()
            }
        }

        Rectangle {
            objectName: "liveNoticeBanner"
            Layout.fillWidth: true
            Layout.preferredHeight: noticeRow.implicitHeight + Theme.space16
            radius: Theme.radius6
            color: root.liveModel.lastError && root.liveModel.lastError.message
                   ? Theme.accentDangerSoft : (root.liveModel.stale ? Theme.accentInfoSoft : Theme.panelSoft)
            border.color: root.liveModel.lastError && root.liveModel.lastError.message
                          ? Theme.accentDanger : (root.liveModel.stale ? Theme.accentInfo : Theme.borderSubtle)
            visible: (root.liveModel.lastError && root.liveModel.lastError.message)
                     || root.liveModel.stale || root.liveModel.partial
                     || (root.liveModel.errors || []).length > 0

            RowLayout {
                id: noticeRow
                anchors.fill: parent
                anchors.margins: Theme.space8
                spacing: Theme.space10
                Label {
                    objectName: "liveNoticeText"
                    Layout.fillWidth: true
                    text: root.noticeText()
                    textFormat: Text.PlainText
                    color: Theme.textPrimary
                    wrapMode: Text.Wrap
                    font.pixelSize: 12
                }
                ActionButton {
                    text: "Retry"
                    compact: true
                    visible: Boolean(root.liveModel.lastError && root.liveModel.lastError.retryable)
                    onClicked: root.liveModel.selectedCatalogId ? root.liveModel.refreshPage()
                                                               : root.liveModel.refreshIndex()
                }
            }
        }

        Item {
            objectName: "liveIndexLoading"
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.liveModel.catalogIndexLoading && (root.liveModel.catalogs || []).length === 0
            BusyIndicator {
                anchors.centerIn: parent
                running: parent.visible
                Accessible.name: "Loading Live catalogs"
            }
        }

        EmptyState {
            objectName: "liveEmptyProviders"
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop
            title: "No Live providers"
            message: "No enabled Live-compatible extensions were found."
            actionText: "Refresh"
            visible: root.initialized && !root.liveModel.catalogIndexLoading
                     && (root.liveModel.providers || []).length === 0
            onActionRequested: root.liveModel.refreshIndex()
        }

        EmptyState {
            objectName: "liveProvidersUnavailable"
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop
            title: "Live providers unavailable"
            message: "Your installed Live providers are not ready."
            actionText: "Retry"
            visible: !root.liveModel.catalogIndexLoading
                     && (root.liveModel.providers || []).length > 0
                     && root.readyProviderCount === 0
            onActionRequested: root.liveModel.refreshIndex()
        }

        EmptyState {
            objectName: "liveEmptyCatalogs"
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop
            title: "No Live catalogs"
            message: "The active providers did not publish any catalogs."
            actionText: "Refresh"
            visible: !root.liveModel.catalogIndexLoading && root.readyProviderCount > 0
                     && (root.liveModel.catalogs || []).length === 0
            onActionRequested: root.liveModel.refreshIndex()
        }

        ListView {
            id: catalogTabs
            objectName: "liveCatalogTabs"
            Layout.fillWidth: true
            Layout.preferredHeight: 42
            orientation: ListView.Horizontal
            spacing: Theme.space8
            clip: true
            model: root.liveModel.catalogs || []
            visible: count > 0
            keyNavigationEnabled: true
            keyNavigationWraps: true

            delegate: Button {
                id: catalogTab
                objectName: "liveCatalogTab"
                required property var modelData
                height: 36
                implicitWidth: Math.max(112, tabLabel.implicitWidth + 28)
                text: String(modelData.name || "Catalog")
                checked: String(modelData.providerId) === String(root.liveModel.selectedProviderId)
                         && String(modelData.catalogId) === String(root.liveModel.selectedCatalogId)
                checkable: true
                focusPolicy: Qt.StrongFocus
                Accessible.name: text + " Live catalog"
                onClicked: root.selectCatalog(modelData)
                background: Rectangle {
                    radius: Theme.radius6
                    color: catalogTab.checked ? Theme.accent : (catalogTab.hovered ? Theme.surfaceHover : Theme.surface)
                    border.color: catalogTab.activeFocus ? Theme.textPrimary : Theme.borderSubtle
                }
                contentItem: Label {
                    id: tabLabel
                    text: catalogTab.text
                    textFormat: Text.PlainText
                    color: catalogTab.checked ? "#17120A" : Theme.textPrimary
                    font.pixelSize: 12
                    font.weight: catalogTab.checked ? Font.DemiBold : Font.Normal
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideRight
                }
            }
        }

        LiveFilterBar {
            Layout.fillWidth: true
            definitions: root.selectedCatalog ? root.selectedCatalog.filters || [] : []
            values: root.activeFilters
            onFiltersEdited: function(values) {
                root.activeFilters = values
                if (root.selectedCatalog) {
                    root.liveModel.selectCatalog(
                        String(root.selectedCatalog.providerId),
                        String(root.selectedCatalog.catalogId),
                        values)
                }
            }
        }

        Item {
            objectName: "livePageLoading"
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: root.liveModel.pageLoading && eventGrid.count === 0
            BusyIndicator {
                anchors.centerIn: parent
                running: parent.visible
                Accessible.name: "Loading Live events"
            }
        }

        EmptyState {
            objectName: "liveEmptyPage"
            Layout.fillWidth: true
            Layout.alignment: Qt.AlignTop
            title: "Nothing live here"
            message: "No events match the current catalog and filters."
            actionText: "Refresh"
            visible: root.liveModel.selectedCatalogId && !root.liveModel.pageLoading
                     && eventGrid.count === 0 && !root.liveModel.lastError.message
            onActionRequested: root.liveModel.refreshPage()
        }

        GridView {
            id: eventGrid
            objectName: "liveEventGrid"
            Layout.fillWidth: true
            Layout.fillHeight: true
            visible: count > 0
            clip: true
            model: root.itemsModel
            cellWidth: width / root.gridColumns
            cellHeight: 248
            keyNavigationEnabled: true
            keyNavigationWraps: true
            boundsBehavior: Flickable.StopAtBounds

            delegate: LiveEventCard {
                required property var model
                width: Math.max(0, eventGrid.cellWidth - Theme.space16)
                height: 232
                itemData: ({
                    "providerId": model.providerId,
                    "itemKey": model.itemKey,
                    "itemType": model.itemType,
                    "title": model.title,
                    "subtitle": model.subtitle,
                    "description": model.description,
                    "status": model.status,
                    "poster": model.poster,
                    "background": model.background,
                    "logo": model.logo,
                    "categories": model.categories,
                    "badges": model.badges,
                    "facts": model.facts
                })
                artworkSource: root.absoluteArtwork(model.background || model.poster)
                timeText: root.formatEventTime(model.startsAtLocal, model.status)
                sourceText: root.providerName(model.providerId)
                onActivated: function(provider, key) { root.openItem(provider, key) }
            }

            footer: Item {
                width: eventGrid.width
                height: root.liveModel.hasMore ? 58 : Theme.space16
                ActionButton {
                    objectName: "liveLoadMore"
                    anchors.centerIn: parent
                    text: root.liveModel.loadingMore ? "Loading" : "Load more"
                    enabled: !root.liveModel.loadingMore
                    visible: root.liveModel.hasMore
                    onClicked: root.liveModel.loadMoreItems()
                }
            }
        }
    }
}

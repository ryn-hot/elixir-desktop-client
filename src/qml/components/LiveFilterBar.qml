import QtQuick 6.5
import QtQuick.Controls 6.5
import QtQuick.Layouts 6.5
import Elixir 1.0

Item {
    id: root
    property var definitions: []
    property var values: ({})
    signal filtersEdited(var values)

    implicitHeight: filterFlow.implicitHeight + Theme.space16
    visible: definitions && definitions.length > 0

    function setValue(id, value) {
        var next = ({})
        var key
        for (key in values) next[key] = values[key]
        if (value === undefined || value === null || value === ""
                || (Array.isArray(value) && value.length === 0)) {
            delete next[id]
        } else {
            next[id] = value
        }
        values = next
        filtersEdited(next)
    }

    Flow {
        id: filterFlow
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: Theme.space12

        Repeater {
            model: root.definitions || []

            delegate: Loader {
                id: controlLoader
                required property var modelData
                property var definition: modelData
                width: Math.min(240, Math.max(152, filterFlow.width))
                sourceComponent: {
                    if (definition.type === "toggle") return toggleControl
                    if (definition.type === "single_select") return singleControl
                    if (definition.type === "multi_select") return multiControl
                    if (definition.type === "date") return dateControl
                    return searchControl
                }
                onLoaded: {
                    if (item) item.definition = definition
                }
            }
        }
    }

    Component {
        id: toggleControl
        CheckBox {
            objectName: "liveFilterToggle"
            property var definition: ({})
            text: String(definition.label || "Filter")
            checked: Boolean(root.values[definition.id])
            Accessible.name: text
            onToggled: root.setValue(definition.id, checked)
        }
    }

    Component {
        id: singleControl
        ColumnLayout {
            property var definition: ({})
            spacing: Theme.space4
            Label {
                text: String(parent.definition.label || "Filter")
                textFormat: Text.PlainText
                color: Theme.textSecondary
                font.pixelSize: 11
            }
            ComboBox {
                objectName: "liveFilterSingle"
                Layout.fillWidth: true
                textRole: "label"
                valueRole: "value"
                model: [{"label": "All", "value": ""}].concat(parent.definition.options || [])
                Accessible.name: String(parent.definition.label || "Filter")
                onActivated: root.setValue(parent.definition.id, currentValue)
            }
        }
    }

    Component {
        id: multiControl
        ColumnLayout {
            id: multiRoot
            property var definition: ({})
            property var selected: root.values[definition.id] || []
            spacing: Theme.space4

            Label {
                text: String(multiRoot.definition.label || "Filter")
                textFormat: Text.PlainText
                color: Theme.textSecondary
                font.pixelSize: 11
            }
            Button {
                id: menuButton
                objectName: "liveFilterMulti"
                Layout.fillWidth: true
                text: multiRoot.selected.length > 0
                      ? multiRoot.selected.length + " selected" : "All"
                Accessible.name: String(multiRoot.definition.label || "Filter")
                onClicked: optionMenu.open()

                Menu {
                    id: optionMenu
                    y: menuButton.height
                    Repeater {
                        model: multiRoot.definition.options || []
                        MenuItem {
                            required property var modelData
                            text: String(modelData.label || modelData.value || "Option")
                            checkable: true
                            checked: multiRoot.selected.indexOf(String(modelData.value)) >= 0
                            onTriggered: {
                                var next = multiRoot.selected.slice()
                                var value = String(modelData.value)
                                var index = next.indexOf(value)
                                if (index >= 0) next.splice(index, 1)
                                else next.push(value)
                                multiRoot.selected = next
                                root.setValue(multiRoot.definition.id, next)
                            }
                        }
                    }
                }
            }
        }
    }

    Component {
        id: searchControl
        ColumnLayout {
            property var definition: ({})
            spacing: Theme.space4
            Label {
                text: String(parent.definition.label || "Search")
                textFormat: Text.PlainText
                color: Theme.textSecondary
                font.pixelSize: 11
            }
            TextField {
                objectName: "liveFilterSearch"
                Layout.fillWidth: true
                placeholderText: "Search"
                text: String(root.values[parent.definition.id] || "")
                maximumLength: 512
                Accessible.name: String(parent.definition.label || "Search")
                onEditingFinished: root.setValue(parent.definition.id, text.trim())
            }
        }
    }

    Component {
        id: dateControl
        ColumnLayout {
            property var definition: ({})
            spacing: Theme.space4
            Label {
                text: String(parent.definition.label || "Date")
                textFormat: Text.PlainText
                color: Theme.textSecondary
                font.pixelSize: 11
            }
            TextField {
                objectName: "liveFilterDate"
                Layout.fillWidth: true
                placeholderText: "YYYY-MM-DD"
                text: String(root.values[parent.definition.id] || "")
                maximumLength: 10
                validator: RegularExpressionValidator { regularExpression: /^\d{4}-\d{2}-\d{2}$/ }
                Accessible.name: String(parent.definition.label || "Date")
                onEditingFinished: root.setValue(parent.definition.id, acceptableInput ? text : "")
            }
        }
    }
}

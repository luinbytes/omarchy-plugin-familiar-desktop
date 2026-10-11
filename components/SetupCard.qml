import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import qs.Commons as Commons

Rectangle {
    id: root
    required property var controller
    signal dismissed()
    implicitWidth: Commons.Style.space(540)
    implicitHeight: content.implicitHeight + Commons.Style.space(48)
    radius: Commons.Style.cornerRadius
    color: Commons.Color.popups.background
    border.color: Commons.Color.popups.border
    border.width: 1
    property bool showDetails: false
    MouseArea { anchors.fill: parent; acceptedButtons: Qt.AllButtons }

    ColumnLayout {
        id: content
        anchors { left: parent.left; right: parent.right; top: parent.top; margins: Commons.Style.space(24) }
        spacing: Commons.Style.space(16)
        RowLayout {
            Layout.fillWidth: true
            Text {
                text: "󰟀  Familiar"
                textFormat: Text.PlainText
                font.family: Commons.Style.font.family
                font.pixelSize: Commons.Style.space(16)
                font.bold: true
                color: Commons.Color.popups.text
                Layout.fillWidth: true
            }
            ActionButton {
                implicitWidth: 70
                text: "Close"
                Accessible.name: "Close setup; reopen from Familiar in the bar"
                onClicked: root.dismissed()
            }
        }
        Text {
            Layout.fillWidth: true
            text: root.controller.ready ? "Make yourself at home." : "Your desktop, a little more familiar."
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            font.family: Commons.Style.font.family
            font.pixelSize: Commons.Style.space(25)
            font.bold: true
            color: Commons.Color.popups.text
        }
        Text {
            Layout.fillWidth: true
            text: root.controller.officialTitlebars ? (root.controller.ready ? "Your dock is ready. Open Windows → Window controls and choose Use Familiar controls to use your Mac or Windows style with Omarchy’s renderer." : "Choose a layout. Familiar downloads its helper and uses Omarchy’s titlebar renderer. Connect your controls after setup in Windows → Window controls.") : (root.controller.ready ? "The dock and window controls are ready. You can change your layout and preferences in Familiar at any time." : "Set up your dock and window controls. Familiar will download and verify the files it needs, then activate them here.")
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            font.family: Commons.Style.font.family
            font.pixelSize: Commons.Style.space(13)
            color: Commons.Color.popups.text
        }
        RowLayout {
            visible: !root.controller.ready
            enabled: !root.controller.busy && root.controller.canStart
            Layout.fillWidth: true
            Repeater {
                model: [{key: "windows", label: "Windows\nRight-side controls"}, {key: "mac", label: "Mac\nLeft-side controls"}]
                delegate: ActionButton {
                    required property var modelData
                    Layout.fillWidth: true
                    implicitHeight: Commons.Style.space(64)
                    text: root.controller.officialTitlebars ? (modelData.key === "windows" ? "Windows\nDock layout" : "Mac\nDock layout") : modelData.label
                    selected: root.controller.style === modelData.key
                    onClicked: root.controller.style = modelData.key
                }
            }
        }
        ProgressBar {
            Layout.fillWidth: true
            visible: root.controller.busy
            indeterminate: true
            Accessible.name: "Setup progress"
        }
        Text {
            Layout.fillWidth: true
            text: root.controller.message
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            font.family: Commons.Style.font.family
            font.pixelSize: Commons.Style.space(12)
            color: Commons.Color.popups.text
        }
        ActionButton {
            Layout.fillWidth: true
            selected: true
            enabled: !root.controller.busy
            text: root.controller.ready ? "Start using Familiar" : root.controller.state === "failed" ? "Retry setup" : "Set up Familiar"
            onClicked: {
                if (root.controller.ready) root.dismissed()
                else root.controller.start()
            }
        }
        ActionButton {
            visible: root.controller.state === "failed"
            Layout.fillWidth: true
            text: root.showDetails ? "Hide details" : "Show details"
            onClicked: root.showDetails = !root.showDetails
        }
        ScrollView {
            visible: root.showDetails && root.controller.state === "failed"
            Layout.fillWidth: true
            Layout.preferredHeight: Commons.Style.space(100)
            clip: true
            TextArea {
                text: root.controller.details
                textFormat: TextEdit.PlainText
                wrapMode: TextEdit.Wrap
                readOnly: true
                selectByMouse: true
                color: Commons.Color.popups.text
                font.pixelSize: Commons.Style.space(11)
            }
        }
    }
}

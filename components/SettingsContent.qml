import QtQuick
import QtQuick.Layouts
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import ".."
import "../DockSettings.js" as DockSettings

ColumnLayout {
    id: content
    required property var service
    required property var navigation
    required property var workspaceOptions
    required property bool taskbarActive
    signal closeRequested
    signal copyRequested(string text)
    enabled: service !== null
    readonly property bool officialTitlebars: !!service && !!service.titlebarsManagedByOmarchy
    anchors.left: parent.left
    anchors.right: parent.right
    anchors.top: parent.top
    spacing: 10

    Text {
        visible: !!content.service.settingsError
        text: content.service.settingsError
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        Layout.fillWidth: true
        color: Commons.Color.popups.text
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
    }
    ColumnLayout {
        Layout.fillWidth: true
        visible: content.navigation.page === "general"
        spacing: Style.space(16)
        Text {
            text: "Choose a starting layout. You can adjust the controls below."
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            Layout.fillWidth: true
            font.family: Style.font.family
            font.pixelSize: 11
            color: Commons.Color.popups.text
            opacity: 0.8
        }

        RowLayout {
            Layout.fillWidth: true
            spacing: 6
            Repeater {
                model: [{
                        "key": "general",
                        "title": "General"
                    }, {
                        "key": "windows",
                        "title": "Windows"
                    }, {
                        "key": "mac",
                        "title": "Mac"
                    }]
                delegate: Rectangle {
                    required property var modelData
                    Layout.fillWidth: true
                    height: 35
                    radius: 7
                    color: content.service.profile === modelData.key ? Commons.Color.accent : (presetMouse.containsMouse ? Style.hoverFillFor(Commons.Color.popups.text, Commons.Color.accent) : "transparent")
                    border.width: content.service.profile === modelData.key ? 0 : 1
                    border.color: Commons.Color.popups.border
                    Text {
                        anchors.centerIn: parent
                        text: modelData.title
                        textFormat: Text.PlainText
                        font.family: Style.font.family
                        font.pixelSize: 12
                        font.bold: content.service.profile === modelData.key
                        color: content.service.profile === modelData.key ? Commons.Color.background : Commons.Color.popups.text
                    }
                    MouseArea {
                        id: presetMouse
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: content.service.setProfile(modelData.key)
                    }
                }
            }
        }

        RowLayout {
            Layout.fillWidth: true
            ActionButton {
                Layout.fillWidth: true
                text: "Show desktop"
                enabled: !!content.service.desktopTools && !content.service.desktopTools.busy
                onClicked: content.service.desktopTools.run(["show"])
            }
            ActionButton {
                Layout.fillWidth: true
                text: "Restore windows"
                enabled: !!content.service.desktopTools && !content.service.desktopTools.busy
                onClicked: content.service.desktopTools.run(["restore"])
            }
        }
        Text {
            Layout.fillWidth: true
            visible: text !== ""
            text: content.service.desktopTools ? (content.service.desktopTools.busy ? "Working…" : content.service.desktopTools.message) : "Familiar service is not available. Enable the plugin and reopen settings."
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            font.family: Style.font.family
            font.pixelSize: 12
            color: Commons.Color.popups.text
        }
    }
    Text {
        visible: content.navigation.page === "general" && !!content.service && !!content.service.taskbar
        Layout.fillWidth: true
        text: content.service && content.service.taskbar ? (content.service.taskbar.busy ? "Changing taskbar layout…" : content.service.taskbar.message) : ""
        textFormat: Text.PlainText
        wrapMode: Text.WordWrap
        font.family: Style.font.family
        font.pixelSize: Style.font.caption
        color: Commons.Color.popups.text
    }
    GettingStarted {
        visible: content.navigation.page === "help"
        Layout.fillWidth: true
        tools: content.service.desktopTools
        labelStyle: content.service.shortcutLabels
    }
    Repeater {
        model: [{
                "key": "dockSize",
                "label": "Dock and icons"
            }, {
                "key": "titlebarSize",
                "label": "Title bars and buttons"
            }]
        delegate: ColumnLayout {
            id: sizeRow
            objectName: modelData.key + "-choices"
            visible: modelData.key === "dockSize" ? content.navigation.shows("dock", "appearance") : content.navigation.shows("windows", "titlebars")
            required property var modelData
            Layout.fillWidth: true
            Text {
                text: sizeRow.modelData.label
                textFormat: Text.PlainText
                font.family: Style.font.family
                font.pixelSize: 12
                color: Commons.Color.popups.text
            }
            RowLayout {
                Layout.fillWidth: true
                Repeater {
                    model: [{
                            "key": "default",
                            "label": "Default"
                        }, {
                            "key": "large",
                            "label": "Large"
                        }, {
                            "key": "extra-large",
                            "label": "Extra large"
                        }]
                    delegate: ActionButton {
                        required property var modelData
                        Layout.fillWidth: true
                        objectName: sizeRow.modelData.key + "-" + modelData.key
                        text: modelData.label
                        selected: content.service[sizeRow.modelData.key] === modelData.key
                        onClicked: {
                            content.service.setPreference(sizeRow.modelData.key, modelData.key);
                        }
                    }
                }
            }
        }
    }

    DockDropdown {
        objectName: "dock-background-opacity"
        Layout.fillWidth: true
        visible: content.navigation.shows("dock", "appearance") && !content.taskbarActive
        label: "Dock background opacity"
        value: content.service.dockBackgroundOpacity
        options: [{
                "value": "theme",
                "label": "Follow theme"
            }, {
                "value": "0",
                "label": "0% — Transparent"
            }, {
                "value": "25",
                "label": "25%"
            }, {
                "value": "50",
                "label": "50%"
            }, {
                "value": "75",
                "label": "75%"
            }, {
                "value": "100",
                "label": "100% — Opaque"
            }]
        onChanged: function (value) {
            content.service.setPreference("dockBackgroundOpacity", DockSettings.normalizeBackgroundOpacity(value));
        }
    }

    InputPreferenceSettings {
        visible: content.navigation.shows("windows", "resizing")
        Layout.fillWidth: true
        controller: content.service ? content.service.borderResize : null
        title: "Resize with the mouse"
        explanation: "Drag a window edge or corner to resize, without holding a modifier key. Adds a 15-pixel grab area and resize cursor. Tiled resizing follows your Hyprland layout; floating windows resize freely. Use configuration restores your original settings."
        enableLabel: "Enable border dragging"
    }

    WindowModeSettings {
        visible: content.navigation.shows("windows", "layout")
        Layout.fillWidth: true
        controller: content.service ? content.service.windowMode : null
        labelStyle: content.service.shortcutLabels
    }

    ColumnLayout {
        visible: content.navigation.shows("keyboard", "shortcuts")
        Layout.fillWidth: true
        Text {
            text: "Shortcut labels"
            textFormat: Text.PlainText
            font.family: Style.font.family
            color: Commons.Color.popups.text
        }
        Repeater {
            model: [{
                    "key": "standard",
                    "label": "Super / Alt / Ctrl"
                }, {
                    "key": "mac",
                    "label": "Command / Option / Control"
                }]
            delegate: ActionButton {
                required property var modelData
                Layout.fillWidth: true
                text: modelData.label
                selected: content.service.shortcutLabels === modelData.key
                onClicked: {
                    content.service.setPreference("shortcutLabels", modelData.key);
                }
            }
        }
        Text {
            Layout.fillWidth: true
            text: "Changes the names shown in Familiar. Your keybindings and copyable configuration stay the same."
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            font.family: Style.font.family
            font.pixelSize: 12
            color: Commons.Color.popups.text
        }
    }

    InputPreferenceSettings {
        visible: content.navigation.shows("keyboard", "shortcuts")
        Layout.fillWidth: true
        controller: content.service ? content.service.commandShortcuts : null
        title: "Command editing shortcuts"
        explanation: "Opt-in: replaces Super+C/V/X/A/Z and Super+Shift+Z with copy, paste, cut, select all, undo and redo. Other desktop shortcuts stay as configured. Known terminals (including Kitty, Alacritty, Foot, WezTerm and Ghostty) use Ctrl+Shift+C/V; other editing aliases pass through there. Custom terminal classes may need support before enabling. This changes behaviour independently of the label preference. Use configuration restores the original bindings."
        enableLabel: "Enable Command editing shortcuts"
    }

    GesturesSettings {
        visible: content.navigation.shows("keyboard", "gestures")
        Layout.fillWidth: true
        controller: content.service ? content.service.gestures : null
    }

    CapsLockSettings {
        visible: content.navigation.shows("keyboard", "keys")
        Layout.fillWidth: true
        controller: content.service ? content.service.capsLock : null
    }

    ColumnLayout {
        visible: content.navigation.shows("windows", "titlebars")
        Layout.fillWidth: true
        spacing: 6
        Text {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            text: content.officialTitlebars ? "Mac/Windows controls on Omarchy’s floating workspaces (Super+L). Restore minimised windows from the dock. Choose Omarchy for its default controls." : "Title bars with close, minimise and maximise. Restore minimised windows from the dock."
            font.family: Style.font.family
            font.pixelSize: 11
            color: Commons.Color.popups.text
        }
        RowLayout {
            Layout.fillWidth: true
            Repeater {
                model: [{
                        "key": "theme",
                        "title": "Theme"
                    }, {
                        "key": "off",
                        "title": content.officialTitlebars ? "Omarchy" : "Off"
                    }, {
                        "key": "mac",
                        "title": "Mac"
                    }, {
                        "key": "windows",
                        "title": "Windows"
                    }]
                delegate: Rectangle {
                    required property var modelData
                    readonly property bool selected: content.service.titlebarMode === modelData.key
                    Layout.fillWidth: true
                    height: 32
                    radius: 7
                    color: selected ? Commons.Color.accent : "transparent"
                    border.width: selected ? 0 : 1
                    border.color: Commons.Color.popups.border
                    Text {
                        anchors.centerIn: parent
                        text: modelData.title
                        font.family: Style.font.family
                        font.pixelSize: 12
                        color: parent.selected ? Commons.Color.background : Commons.Color.popups.text
                    }
                    MouseArea {
                        anchors.fill: parent
                        cursorShape: Qt.PointingHandCursor
                        onClicked: {
                            if (content.service)
                                content.service.setTitlebarMode(modelData.key);
                        }
                    }
                }
            }
        }
        Text {
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            textFormat: Text.PlainText
            text: content.service ? content.service.titlebarMessage : "Window controls require the Familiar Desktop service."
            font.family: Style.font.family
            font.pixelSize: 10
            color: Commons.Color.muted
        }
        Rectangle {
            visible: !content.officialTitlebars || content.service.titlebarState === "migration-required" || content.service.titlebarState === "failed"
            Layout.fillWidth: true
            height: 32
            radius: 6
            color: titlebarSetupMouse.containsMouse ? Style.hoverFillFor(Commons.Color.popups.text, Commons.Color.accent) : "transparent"
            border.width: 1
            border.color: Commons.Color.popups.border
            Text {
                anchors.centerIn: parent
                text: content.officialTitlebars ? "Use Familiar controls" : "Set up or repair window controls"
                font.family: Style.font.family
                font.pixelSize: 11
                color: Commons.Color.popups.text
            }
            MouseArea {
                id: titlebarSetupMouse
                objectName: "titlebar-repair"
                anchors.fill: parent
                hoverEnabled: true
                enabled: content.service && !content.service.titlebarBusy
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    if (content.officialTitlebars) {
                        content.service.useOmarchyTitlebars();
                        return;
                    }
                    if (content.service && content.service.setup) {
                        content.closeRequested();
                        content.service.setup.repair(content.service.titlebarStyle);
                    }
                }
            }
        }
        PreferenceToggle {
            visible: content.service.titlebarMode !== "off"
            objectName: "skipBrowserTitlebars"
            Layout.fillWidth: true
            label: "Skip Chrome and Chromium title bars"
            checked: content.service.skipBrowserTitlebars
            onToggled: function(value) { content.service.setPreference("skipBrowserTitlebars", value); }
        }
        Text {
            visible: content.service.titlebarMode !== "off"
            text: "Skip other apps with their own title bars (window classes, comma-separated)"
            Layout.fillWidth: true
            wrapMode: Text.WordWrap
            font.family: Style.font.family
            font.pixelSize: 10
            color: Commons.Color.muted
        }
        Rectangle {
            visible: content.service.titlebarMode !== "off"
            Layout.fillWidth: true
            height: 32
            radius: 6
            color: "transparent"
            border.width: 1
            border.color: titlebarExclusionsInput.activeFocus ? Commons.Color.accent : Commons.Color.popups.border
            SafeTextInput {
                id: titlebarExclusionsInput
                anchors.fill: parent
                anchors.margins: 7
                text: content.service.titlebarExclusions
                maximumLength: 6400
                clip: true
                font.family: Style.font.family
                font.pixelSize: 11
                color: Commons.Color.popups.text
                selectByMouse: true
                onEditingFinished: {
                    content.service.setPreference("titlebarExclusions", text);
                }
            }
        }
        Rectangle {
            Layout.fillWidth: true
            height: 28
            radius: 6
            color: "transparent"
            Text {
                anchors.centerIn: parent
                text: content.service && content.service.titlebarBusy ? "Applying…" : "Refresh window controls"
                font.family: Style.font.family
                font.pixelSize: 11
                color: Commons.Color.popups.text
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                enabled: content.service && !content.service.titlebarBusy
                onClicked: content.service.refreshTitlebars()
            }
        }
    }

    ColumnLayout {
        Layout.fillWidth: true
        visible: content.navigation.page === "dock"
        spacing: Style.space(8)
        // 1. Enable dock toggle row
        PreferenceToggle {
            objectName: "dock-enabled"
            Layout.fillWidth: true
            visible: content.navigation.section === "appearance"
            label: "Enable dock"
            description: "Show dock panel on screen"
            checked: content.service.dockEnabled
            onToggled: function(value) { content.service.setDockEnabled(value) }
        }

        DockDropdown {
            Layout.fillWidth: true
            visible: content.navigation.section === "appearance" && !content.taskbarActive
            label: "Dock position"
            value: content.service.dockPosition
            options: [{
                    "value": "auto",
                    "label": "Automatic (layout default)"
                }, {
                    "value": "bottom",
                    "label": "Bottom"
                }, {
                    "value": "left",
                    "label": "Left"
                }, {
                    "value": "right",
                    "label": "Right"
                }]
            onChanged: function (value) {
                content.service.setPreference("dockPosition", DockSettings.normalizeDockPosition(value));
            }
        }

        Text {
            Layout.fillWidth: true
            visible: content.navigation.section === "appearance"
            text: content.taskbarActive ? "Windows uses the native bottom taskbar. Bar height, appearance and widgets follow Omarchy’s bar settings. Choose General or Mac to restore your previous bar." : content.service.dockPosition !== "auto" && content.service && content.service.dockScreenPosition !== content.service.dockPosition ? "Omarchy’s bar uses that edge. The dock uses the opposite edge until it is free." : "Your position choice is kept when you change layouts. Automatic follows the layout default."
            textFormat: Text.PlainText
            wrapMode: Text.WordWrap
            font.family: Style.font.family
            font.pixelSize: Style.font.caption
            color: Commons.Color.muted
        }

        // File shortcuts
        Rectangle {
            visible: content.navigation.section === "extras"
            Layout.fillWidth: true
            implicitHeight: 38
            radius: 8
            color: Commons.Color.composed("popups.text", "popups.text-alpha", Commons.Color.text, 0.08)
            Text {
                anchors.centerIn: parent
                text: (content.service.fileShortcutsEnabled ? "✓  " : "+  ") + "Home, Downloads and Bin shortcuts"
                color: Commons.Color.popups.text
                font.family: Style.font.family
                font.pixelSize: 11
            }
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    content.service.setPreference("fileShortcutsEnabled", !content.service.fileShortcutsEnabled);
                }
            }
        }

        DockDropdown {
            Layout.fillWidth: true
            visible: content.navigation.section === "visibility"
            label: "Show apps from"
            value: content.service.visibleWorkspace
            options: content.workspaceOptions
            onChanged: function (value) {
                content.service.setVisibleWorkspace(value);
            }
        }

        // 3. Autohide dock (edge hover)
        PreferenceToggle {
            objectName: "dock-autohide"
            Layout.fillWidth: true
            visible: content.navigation.section === "visibility"
            label: "Autohide dock"
            description: "Reveal on screen-edge hover"
            checked: content.service.dockEnabled && (content.service.visibilityMode === "hover" || content.service.visibilityMode === "hybrid")
            onToggled: function(value) { content.service.setAutohide(value) }
        }

        // 4. Keyboard shortcut toggle
        PreferenceToggle {
            objectName: "dock-keybind"
            Layout.fillWidth: true
            visible: content.navigation.section === "visibility"
            label: "Keyboard shortcut"
            description: "Summon dock on demand"
            checked: content.service.dockEnabled && (content.service.visibilityMode === "keybind" || content.service.visibilityMode === "hybrid")
            onToggled: function(value) { content.service.setKeybindMode(value) }
        }

        // 5. Shortcut Hint (smoothly appears ONLY when Keyboard shortcut is active)
        ColumnLayout {
            id: shortcutHintCard
            Layout.fillWidth: true
            Layout.leftMargin: 2
            Layout.rightMargin: 2
            Layout.preferredHeight: (content.service.dockEnabled && (content.service.visibilityMode === "keybind" || content.service.visibilityMode === "hybrid")) ? 64 : 0
            Layout.minimumHeight: 0
            clip: true
            visible: content.navigation.section === "visibility" && Layout.preferredHeight > 0
            opacity: (content.service.dockEnabled && (content.service.visibilityMode === "keybind" || content.service.visibilityMode === "hybrid")) ? 1.0 : 0.0
            spacing: 4
            Behavior on Layout.preferredHeight  {
                NumberAnimation {
                    duration: 160
                    easing.type: Easing.OutCubic
                }
            }
            Behavior on opacity  {
                NumberAnimation {
                    duration: 160
                    easing.type: Easing.OutCubic
                }
            }

            Text {
                Layout.fillWidth: true
                Layout.leftMargin: 6
                text: "Add to ~/.config/hypr/bindings.lua:"
                textFormat: Text.PlainText
                font.family: Style.font.family
                font.pixelSize: 10
                font.bold: true
                color: Commons.Color.popups.text
                elide: Text.ElideRight
            }

            Rectangle {
                id: cmdPill
                Layout.fillWidth: true
                Layout.preferredHeight: 44
                Layout.minimumHeight: 44
                Layout.maximumHeight: 44
                radius: 6
                color: cmdMouse.containsMouse ? Style.hoverFillFor(Commons.Color.popups.text, Commons.Color.accent) : Commons.Color.composed("popups.border", "popups.border-alpha", Commons.Color.border, 0.25)
                border.width: 1
                border.color: cmdMouse.containsMouse ? Commons.Color.accent : Commons.Color.composed("popups.border", "popups.border-alpha", Commons.Color.border, 0.4)
                Behavior on color  {
                    ColorAnimation {
                        duration: 120
                    }
                }

                property bool copied: false
                Timer {
                    id: copyTimer
                    interval: 1800
                    repeat: false
                    onTriggered: cmdPill.copied = false
                }

                RowLayout {
                    anchors.fill: parent
                    anchors.leftMargin: 10
                    anchors.rightMargin: 10
                    spacing: 8

                    Text {
                        id: cmdText
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        text: cmdPill.copied ? "✓ Copied to clipboard!" : "o.bind(\"SUPER + D\", \"Toggle Dock\",\n  \"omarchy-shell -q io.github.tcballard.familiar-desktop toggleReveal\")"
                        textFormat: Text.PlainText
                        font.family: !cmdPill.copied ? (Style.font.monospace || "monospace") : Style.font.family
                        font.pixelSize: !cmdPill.copied ? 9 : 10
                        lineHeight: 1.18
                        font.bold: cmdPill.copied
                        color: cmdPill.copied ? Commons.Color.accent : Commons.Color.popups.text
                        wrapMode: Text.Wrap
                        verticalAlignment: Text.AlignVCenter
                    }

                    DockGlyph {
                        width: 14
                        height: 14
                        text: cmdPill.copied ? "󰄬" : "󰆏"
                        fontFamily: Style.font.family
                        fontSize: 11
                        color: cmdPill.copied ? Commons.Color.accent : Commons.Color.muted
                    }
                }

                MouseArea {
                    id: cmdMouse
                    anchors.fill: parent
                    enabled: content.service.dockEnabled && (content.service.visibilityMode === "keybind" || content.service.visibilityMode === "hybrid")
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        var cmd = 'o.bind("SUPER + D", "Toggle Dock", "omarchy-shell -q io.github.tcballard.familiar-desktop toggleReveal")';
                        content.copyRequested(cmd);
                        cmdPill.copied = true;
                        copyTimer.restart();
                    }
                }
            }
        }

        // Toggle Overlay Mode Row
        PreferenceToggle {
            objectName: "dock-overlay"
            Layout.fillWidth: true
            visible: content.navigation.section === "visibility"
            label: "Overlay mode"
            description: "Float on top of application windows"
            checked: content.service.overlayMode
            onToggled: function(value) { content.service.setOverlayMode(value) }
        }

        ActionButton {
            Layout.fillWidth: true
            visible: content.navigation.section === "extras"
            text: "Window previews on hover: " + (content.service.windowPreviews ? "On" : "Off")
            selected: content.service.windowPreviews
            onClicked: {
                content.service.setPreference("windowPreviews", !content.service.windowPreviews);
            }
        }

        // Toggle Notification Badges Row
        PreferenceToggle {
            objectName: "dock-badges"
            Layout.fillWidth: true
            visible: content.navigation.section === "extras"
            label: "Notification badges"
            description: "Show unread counter on app icons"
            checked: content.service.showBadges
            onToggled: function(value) { content.service.setPreference("showBadges", value) }
        }

        // Toggle Widgets in Dock Row
        PreferenceToggle {
            objectName: "dock-widgets"
            Layout.fillWidth: true
            visible: content.navigation.section === "extras"
            label: "Dock widgets"
            description: "Integrate app menu and bar widgets"
            checked: content.service.widgetsEnabled
            onToggled: function(value) { content.service.setWidgetsEnabled(value) }
        }

        // Configure Widgets Action Button
        Rectangle {
            id: configureWidgetsRow
            visible: content.navigation.section === "extras"
            Layout.fillWidth: true
            Layout.preferredHeight: 40
            radius: 8
            opacity: content.service.widgetsEnabled ? 1.0 : 0.4
            enabled: content.service.widgetsEnabled
            color: configureWidgetsMouse.containsMouse ? Commons.Color.composed("accent", "accent-alpha", Commons.Color.accent, 0.2) : Commons.Color.composed("popups.text", "popups.text-alpha", Commons.Color.text, 0.08)
            border.width: 1
            border.color: configureWidgetsMouse.containsMouse ? Commons.Color.accent : "transparent"
            Behavior on color  {
                ColorAnimation {
                    duration: 120
                }
            }
            Behavior on border.color  {
                ColorAnimation {
                    duration: 120
                }
            }
            Behavior on opacity  {
                NumberAnimation {
                    duration: 150
                    easing.type: Easing.OutCubic
                }
            }

            Text {
                anchors.centerIn: parent
                text: "Configure dock widgets"
                textFormat: Text.PlainText
                font.family: Style.font.family
                font.pixelSize: 11
                font.bold: true
                color: configureWidgetsMouse.containsMouse ? Commons.Color.accent : Commons.Color.popups.text
                renderType: Text.CurveRendering
                font.hintingPreference: Font.PreferNoHinting
                Behavior on color  {
                    ColorAnimation {
                        duration: 120
                    }
                }
            }

            MouseArea {
                id: configureWidgetsMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    content.closeRequested();
                    if (content.service)
                        content.service.openWidgetPicker();
                }
            }
        }
    }
}

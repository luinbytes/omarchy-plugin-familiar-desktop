import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Hyprland
import qs.Commons
import qs.Commons as Commons
import qs.Ui
import "DockModel.js" as DockModel
import "IconResolver.js" as Icons
import "DockDrag.js" as Drag
import "components"

Item {
    id: root

    property var itemData: null
    property int itemIndex: 0
    property int totalCount: 1
    property string barPosition: "bottom"
    property var shell: null
    property var knownWindows: []
    property real slotSize: 42
    property real iconBaseSize: 24
    property int systemBorderSize: Style.normalBorderWidth > 0 ? Style.normalBorderWidth : 2
    property int systemRounding: Style.cornerRadius >= 0 ? Style.cornerRadius : 12
    property bool isSelected: false
    property bool isMergeTarget: false
    property bool isEditMode: false
    property int dockDragActiveIndex: -1
    readonly property bool isAnyDragging: dockDragActiveIndex >= 0 || isDragging
    property bool showBadges: true

    signal previewHoverChanged(var item, bool hovered)
    signal previewCancelled()
    // A rebuild swaps dockItems out from under an active drag. Destroying the
    // MouseArea does not emit released or canceled, so the panel never hears
    // dragEnded and the rail stays in drag mode (blank cursor, held slots).
    Component.onDestruction: {
        previewHoverChanged(root, false)
        if (isDragging)
            dragEnded()
    }
    signal itemLeftClicked(var itemData)
    signal itemRightClicked(var itemData, var itemItem)
    signal moveRequested(int fromIndex, int toIndex)
    signal mergeRequested(int fromIndex, int targetIndex)
    signal dragHoverChanged(int fromIndex, int targetIndex, bool isMergeIntent)
    signal editModeRequested()
    signal editModeExitRequested()
    signal togglePinRequested(string appId)
    signal dissolveRequested(string stackId)
    signal originalAppLaunched(string appId)
    signal restoreOrLaunchRequested(var itemData, int targetIndex)
    signal minimizeRequested(var itemData, int targetIndex)
    signal dragStarted(int fromIndex)
    signal dragEnded()

    readonly property int badgeCount: (root.itemData && typeof root.itemData.badgeCount === "number") ? root.itemData.badgeCount : 0

    readonly property bool isVertical: barPosition === "left" || barPosition === "right"

    width: slotSize
    height: slotSize
    z: isDragging ? 100 : (isSelected ? 60 : (mouseArea.containsMouse ? 50 : 1))

    property bool isDragging: false
    property bool isMergeActive: false
    property int iconRevision: 0
    property bool iconsReady: true

    // Dynamic Real-time Theme-aware Icon Resolution
    function resolveIcon(itemObj) {
        return Icons.resolve(itemObj, {
            candidates: DockModel.getCandidates,
            diskIcon: DockModel.getDiskIcon,
            library: shell ? shell.appLibrary : null,
            iconPath: function(name) { return Quickshell.iconPath(name, true) },
            friendlyFallback: true
        })
    }

    // Clear, steady Merge Target Halo (stays perfectly still while hovered)
    Rectangle {
        id: mergeTargetHalo
        anchors.centerIn: parent
        width: root.slotSize - 6
        height: root.slotSize - 6
        radius: root.systemRounding
        color: Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.22)
        border.width: root.systemBorderSize
        border.color: Commons.Color.accent
        visible: opacity > 0
        opacity: root.isMergeTarget ? 1.0 : 0.0
        scale: root.isMergeTarget ? 1.04 : 0.92
        Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        Behavior on scale { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        z: 0
    }

    property real clickScaleFactor: 1.0
    property real clickLiftY: 0

    // Bouncy macOS-style physical press response
    ParallelAnimation {
        id: clickEffectAnim
        running: false
        NumberAnimation {
            target: root
            property: "clickScaleFactor"
            from: 0.88
            to: 1.0
            duration: 220
            easing.type: Easing.OutBack
        }
        SequentialAnimation {
            NumberAnimation {
                target: root
                property: "clickLiftY"
                to: (root.isVertical ? 0 : (root.barPosition === "bottom" ? -4 : 4))
                duration: 90
                easing.type: Easing.OutQuad
            }
            NumberAnimation {
                target: root
                property: "clickLiftY"
                to: 0
                duration: 130
                easing.type: Easing.OutBounce
            }
        }
    }

    // Independent drag offset so root.x and root.y bindings are NEVER broken
    Item {
        id: dragOffset
        x: 0
        y: 0
    }

    // Clamped drag offset for visual rendering (strictly confined within dock surface boundaries)
    readonly property real clampedDragOffsetX: root.isVertical ? 0 : Math.max(-root.itemIndex * root.slotSize, Math.min((root.totalCount - 1 - root.itemIndex) * root.slotSize, dragOffset.x))
    readonly property real clampedDragOffsetY: root.isVertical ? Math.max(-root.itemIndex * root.slotSize, Math.min((root.totalCount - 1 - root.itemIndex) * root.slotSize, dragOffset.y)) : 0

    readonly property bool isPressVisualActive: {
        if (!mouseArea.pressed) return false
        if (mouseArea.pressedButtons & (Qt.LeftButton | Qt.MiddleButton)) return true
        if (root.isEditMode) return true
        if (root.itemData) {
            if (root.itemData.isStack) return true
            if (root.itemData.isRunning) return true
        }
        return false
    }

    // Main animated icon wrapper (smooth, buttery rail motion)
    Item {
        id: iconWrapper
        x: (parent.width - width) / 2 + root.clampedDragOffsetX
        y: Math.round((parent.height - height) / 2) - 1 + root.clampedDragOffsetY + root.clickLiftY
        width: root.iconBaseSize
        height: root.iconBaseSize
        z: 1

        scale: (root.isDragging ? 1.15 : (root.isEditMode ? 0.82 : (root.isMergeTarget ? 0.94 : (root.isPressVisualActive ? 0.92 : (mouseArea.containsMouse ? 1.10 : 1.0))))) * root.clickScaleFactor
        opacity: root.iconsReady ? (root.isDragging ? 0.92 : 1.0) : 0.0

        Behavior on scale {
            enabled: !clickEffectAnim.running
            NumberAnimation { duration: 180; easing.type: Easing.OutCubic }
        }
        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

        // Normal Single App Icon (Instantly react to rawIcon theme swaps, crisp HiDPI rasterization)
        AppIcon {
            id: appIcon
            visible: root.itemData && !root.itemData.isStack
            anchors.centerIn: parent
            width: root.iconBaseSize
            height: root.iconBaseSize
            glyph: root.itemData ? (root.itemData.iconGlyph || "") : ""
            source: (root.iconRevision, root.resolveIcon(root.itemData))
            fallbackSource: {
                if (root.itemData) {
                    var raw = root.itemData.rawIcon || root.itemData.icon || root.itemData.appId || root.itemData.id || ""
                    var dIcon = DockModel.getDiskIcon(raw)
                    if (dIcon) return dIcon
                    var dIconLow = DockModel.getDiskIcon(String(raw).toLowerCase())
                    if (dIconLow) return dIconLow
                }
                return "file:///usr/share/pixmaps/omarchy.png"
            }
        }

        // Folder Custom Symbol Icon (Optically centered vector glyph with smooth anti-aliased rotation)
        DockGlyph {
            id: stackSymbolText
            visible: root.itemData && root.itemData.isStack === true && root.itemData.icon && root.itemData.icon !== "grid" && root.itemData.icon !== "folder" && root.itemData.icon !== "󰕰"
            anchors.centerIn: parent
            width: root.iconBaseSize
            height: root.iconBaseSize
            text: (root.itemData && root.itemData.icon) ? root.itemData.icon : ""
            fontFamily: Style.font.family
            fontSize: 20
            color: Commons.Color.accent
        }

        // Folder Mini-Grid (Shown when icon is "grid", "folder", "󰕰" or not set)
        Grid {
            id: stackGrid
            visible: root.itemData && root.itemData.isStack === true && (!root.itemData.icon || root.itemData.icon === "grid" || root.itemData.icon === "folder" || root.itemData.icon === "󰕰")
            anchors.centerIn: parent
            readonly property int totalSubs: (root.itemData && root.itemData.subApps) ? root.itemData.subApps.length : 0
            readonly property bool is3x3: totalSubs > 4
            columns: is3x3 ? 3 : 2
            spacing: is3x3 ? 1.5 : 2

            readonly property int cellWidth: is3x3
                ? Math.max(6, Math.floor((root.iconBaseSize - 4) / 3))
                : Math.max(9, Math.floor((root.iconBaseSize - 3) / 2))

            Repeater {
                model: (root.itemData && root.itemData.subApps) ? root.itemData.subApps.slice(0, stackGrid.is3x3 ? 9 : 4) : []
                AppIcon {
                    width: stackGrid.cellWidth
                    height: stackGrid.cellWidth
                    glyph: modelData ? (modelData.iconGlyph || "") : ""
                    source: (root.iconRevision, root.resolveIcon(modelData))
                }
            }
        }

        // Silky smooth, organic wiggle animation
        SequentialAnimation {
            id: jiggleAnim
            running: root.isDragging || root.isEditMode
            loops: Animation.Infinite

            NumberAnimation {
                target: iconWrapper
                property: "rotation"
                to: -3.8
                duration: 105
                easing.type: Easing.InOutSine
            }
            NumberAnimation {
                target: iconWrapper
                property: "rotation"
                to: 3.8
                duration: 105
                easing.type: Easing.InOutSine
            }
        }

        NumberAnimation {
            id: resetRotation
            target: iconWrapper
            property: "rotation"
            to: 0.0
            duration: 150
            easing.type: Easing.OutCubic
            running: !root.isDragging && !root.isEditMode && iconWrapper.rotation !== 0.0
        }
    }

    // Long press timer for Edit Mode activation (450ms)
    Timer {
        id: longPressTimer
        interval: 450
        repeat: false
        onTriggered: {
            if (!root.isDragging) {
                mouseArea.didLongPress = true
                root.editModeRequested()
            }
        }
    }

    readonly property int previewTopIndex: appInteraction.previewIndex
    readonly property bool isWheelScrolling: appInteraction.cycling
    readonly property int realActiveTopIndex: appInteraction.activeIndex
    readonly property int effectiveTopIndex: appInteraction.effectiveIndex
    AppTileInteraction {
        id: appInteraction
        itemData: root.itemData
        hovered: mouseArea.containsMouse
        onFeedbackRequested: clickEffectAnim.restart()
        onLaunchRequested: function(item) {
            DockModel.setPendingCliHint(item.appId || item.desktopId || "", root.knownWindows)
            DockModel.launchApp(root.shell, item, Util)
        }
        onRestoreRequested: function(item, index) { root.restoreOrLaunchRequested(item, index) }
    }

    // 0. iOS / macOS-Style Theme Notification Badge with Count (Anchored to top-right of iconWrapper)
    NotificationBadge {
        anchors.top: iconWrapper.top
        anchors.topMargin: -2
        anchors.right: iconWrapper.right
        anchors.rightMargin: -2
        count: root.badgeCount
        hasUrgent: (root.itemData && !!root.itemData.hasUrgent)
        isSuppressed: root.isEditMode || root.isAnyDragging || !root.showBadges
    }

    // 1. Pin / Unpin Glyph (Centered directly above scaled iconWrapper, hidden while dragging)
    Item {
        id: pinBadge
        visible: root.isEditMode && !root.isAnyDragging && root.itemData && !root.itemData.isStack
        anchors.horizontalCenter: iconWrapper.horizontalCenter
        anchors.bottom: iconWrapper.top
        anchors.bottomMargin: -5
        width: 16
        height: 14
        z: 200

        DockGlyph {
            anchors.centerIn: parent
            width: parent.width
            height: parent.height
            text: "•"
            fontFamily: Style.font.family
            fontSize: 11
            color: (root.itemData && root.itemData.isPinned)
                ? Commons.Color.accent
                : (pinBadgeMouse.containsMouse ? Commons.Color.accent : Commons.Color.composed("popups.text", "popups.text-alpha", Commons.Color.text, 0.45))

            scale: pinBadgeMouse.containsMouse ? 1.35 : 1.0
            Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
            Behavior on color { ColorAnimation { duration: 120 } }
        }

        MouseArea {
            id: pinBadgeMouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: (root.isAnyDragging || root.isDragging || mouseArea.drag.active) ? Qt.BlankCursor : Qt.PointingHandCursor
            onClicked: function(mouse) {
                if (mouse.button === Qt.RightButton) {
                    root.editModeExitRequested()
                    return
                }
                if (root.itemData && !root.itemData.isStack) {
                    root.togglePinRequested(root.itemData.appId)
                }
            }
        }
    }

    // 2. Dissolve Folder Glyph (Centered directly above scaled iconWrapper, hidden while dragging)
    Item {
        id: dissolveBadge
        visible: root.isEditMode && !root.isAnyDragging && root.itemData && root.itemData.isStack
        anchors.horizontalCenter: iconWrapper.horizontalCenter
        anchors.bottom: iconWrapper.top
        anchors.bottomMargin: -5
        width: 16
        height: 14
        z: 200

        DockGlyph {
            anchors.centerIn: parent
            width: parent.width
            height: parent.height
            text: "-"
            fontFamily: Style.font.family
            fontSize: 16
            color: dissolveBadgeMouse.containsMouse ? Commons.Color.accent : Commons.Color.composed("popups.text", "popups.text-alpha", Commons.Color.text, 0.85)

            scale: dissolveBadgeMouse.containsMouse ? 1.25 : 1.0
            Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
            Behavior on color { ColorAnimation { duration: 120 } }
        }

        MouseArea {
            id: dissolveBadgeMouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: (root.isAnyDragging || root.isDragging || mouseArea.drag.active) ? Qt.BlankCursor : Qt.PointingHandCursor
            onClicked: function(mouse) {
                if (mouse.button === Qt.RightButton) {
                    root.editModeExitRequested()
                    return
                }
                if (root.itemData && root.itemData.isStack) {
                    root.dissolveRequested(root.itemData.id)
                }
            }
        }
    }

    // 3. Multi-instance Duplicate Status Capsule (Sliding window viewport)
    DockDuplicateCapsule {
        id: duplicateCapsule
        visible: root.iconsReady && !root.isEditMode && root.itemData && !root.itemData.isStack && root.itemData.isRunning && root.itemData.toplevels && root.itemData.toplevels.length >= 2
        opacity: visible ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { duration: 180 } }

        totalWindows: (root.itemData && root.itemData.toplevels) ? root.itemData.toplevels.length : 0
        effectiveTopIndex: root.effectiveTopIndex
        isAppActive: (root.itemData && root.itemData.isActive === true && !root.itemData.isMinimized)
        isPreviewing: (root.previewTopIndex >= 0)

        x: Math.round((parent.width - width) / 2 + root.clampedDragOffsetX)
        y: parent.height - height - 2 + root.clampedDragOffsetY
        z: root.isDragging ? 101 : 1
    }

    // 4. Running / Active Application Indicator (Single instance)
    Rectangle {
        id: runningDot
        visible: root.iconsReady && !root.isEditMode && root.itemData && root.itemData.isRunning && (!root.itemData.toplevels || root.itemData.toplevels.length <= 1)
        opacity: visible ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

        x: Math.round((parent.width - width) / 2 + root.clampedDragOffsetX)
        y: parent.height - height - 3 + root.clampedDragOffsetY
        z: root.isDragging ? 101 : 1

        height: 2
        width: (root.itemData && root.itemData.isActive && !root.itemData.isMinimized) ? 10 : 4
        radius: 1
        color: (root.itemData && root.itemData.isActive && !root.itemData.isMinimized) ? Commons.Color.accent : Commons.Color.composed("popups.text", "popups.text-alpha", Commons.Color.text, 0.6)
        antialiasing: true
        smooth: true

        Behavior on width { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
        Behavior on color { ColorAnimation { duration: 150 } }
    }

    // Native bar click routing and the floating dock share exactly one action path.
    function triggerPress(button) {
        root.previewCancelled()
        longPressTimer.stop()
        if (mouseArea.didDrag || mouseArea.didLongPress) {
            mouseArea.didLongPress = false
            return
        }
        if (button === Qt.MiddleButton) {
            appInteraction.launch()
        } else if (button === Qt.LeftButton) {
            clickEffectAnim.restart()
            if (root.itemData && root.itemData.isStack) {
                root.itemLeftClicked(root.itemData)
            } else if (root.itemData && !root.isEditMode) {
                root.itemLeftClicked(root.itemData)
                appInteraction.restore()
            }
        }
    }

    MouseArea {
        id: mouseArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        cursorShape: (root.isDragging || mouseArea.drag.active || root.dockDragActiveIndex >= 0 || root.isAnyDragging || root.isWheelScrolling) ? Qt.BlankCursor : (root.isEditMode ? Qt.PointingHandCursor : Qt.ArrowCursor)

        drag.target: dragOffset
        drag.axis: root.isVertical ? Drag.YAxis : Drag.XAxis
        // Allow free mouse movement across the full screen while dragging along the rail
        drag.minimumX: -99999
        drag.maximumX: 99999
        drag.minimumY: -99999
        drag.maximumY: 99999
        drag.threshold: 6

        property bool didDrag: false
        property bool didLongPress: false

        focus: containsMouse

        onContainsMouseChanged: root.previewHoverChanged(root, containsMouse)

        onEntered: {
            mouseArea.forceActiveFocus()
        }

        Keys.onRightPressed: function(event) { event.accepted = appInteraction.cycle(true) }
        Keys.onLeftPressed: function(event) { event.accepted = appInteraction.cycle(false) }
        Keys.onTabPressed: function(event) { event.accepted = appInteraction.launch() }
        Keys.onReturnPressed: function(event) { event.accepted = appInteraction.confirmPreview() }

        onPressed: function(mouse) {
            root.previewCancelled()
            if (mouse.button === Qt.LeftButton) {
                didDrag = false
                didLongPress = false
                longPressTimer.restart()
            } else if (mouse.button === Qt.RightButton) {
                if (root.isEditMode) {
                    clickEffectAnim.restart()
                    root.editModeExitRequested()
                    return
                }
                if (root.itemData) {
                    clickEffectAnim.restart()
                    root.itemRightClicked(root.itemData, root)
                }
            }
        }

        onPositionChanged: function(mouse) {
            appInteraction.pointerMoved()
            if (mouseArea.drag.active) {
                longPressTimer.stop()
                if (!root.isDragging) {
                    root.isDragging = true
                    root.dragStarted(root.itemIndex)
                }
                // Enforce strict 1D rail axis lock (zero orthogonal wobble)
                if (root.isVertical) {
                    dragOffset.x = 0
                } else {
                    dragOffset.y = 0
                }

                var target = Drag.railTarget(root.itemIndex, root.totalCount, root.slotSize,
                    root.isVertical ? dragOffset.y : dragOffset.x, root.itemData && !root.itemData.isStack)
                root.isMergeActive = target.merge
                root.dragHoverChanged(root.itemIndex, target.index, target.merge)
            }
        }

        onReleased: function(mouse) {
            longPressTimer.stop()
            if (root.isDragging) {
                root.isDragging = false
                var target = Drag.railTarget(root.itemIndex, root.totalCount, root.slotSize,
                    root.isVertical ? dragOffset.y : dragOffset.x, root.itemData && !root.itemData.isStack)

                root.isMergeActive = false
                dragOffset.x = 0
                dragOffset.y = 0

                if (target.index !== root.itemIndex) {
                    if (target.merge) {
                        root.mergeRequested(root.itemIndex, target.index)
                    } else {
                        root.moveRequested(root.itemIndex, target.index)
                    }
                } else {
                    root.dragEnded()
                }
            }
        }

        onExited: {
            longPressTimer.stop()
            appInteraction.leave()
        }

        onCanceled: {
            longPressTimer.stop()
            didLongPress = false
            if (root.isDragging) {
                root.isDragging = false
                root.isMergeActive = false
                dragOffset.x = 0
                dragOffset.y = 0
                root.dragEnded()
            }
        }

        onWheel: function(wheel) {
            wheel.accepted = appInteraction.wheel(wheel.pixelDelta.x, wheel.pixelDelta.y, wheel.angleDelta.x, wheel.angleDelta.y)
        }

        onClicked: function(mouse) { root.triggerPress(mouse.button) }

        onDoubleClicked: function(mouse) {
            if (mouse.button === Qt.LeftButton) {
                clickEffectAnim.restart()
                if (root.itemData && root.itemData.isStack) {
                    root.itemLeftClicked(root.itemData)
                }
            }
        }
    }
}

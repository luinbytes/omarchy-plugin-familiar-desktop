import QtQuick
import QtTest
import ".."

TestCase {
    id: testCase
    name: "DockItem"
    width: 300
    height: 300
    visible: true
    when: windowShown

    Component {
        id: factory
        DockItem { x: 100; y: 100; slotSize: 64 }
    }
    SignalSpy { id: restores; signalName: "restoreOrLaunchRequested" }
    SignalSpy { id: drags; signalName: "dragStarted" }
    SignalSpy { id: moves; signalName: "moveRequested" }

    function test_runningAppClick_data() {
        return [
            {tag: "bottom", position: "bottom"},
            {tag: "top", position: "top"},
            {tag: "left", position: "left"},
            {tag: "right", position: "right"}
        ]
    }
    function runningApp() {
        return {appId: "spotify", desktopId: "spotify.desktop", iconGlyph: "S",
            isRunning: true, isActive: false, activeTopIndex: 1,
            toplevels: [{address: "0x111"}, {address: "0x222"}]}
    }
    function prepare(data) {
        var item = runningApp()
        var tile = createTemporaryObject(factory, testCase,
            {barPosition: data.position, itemData: item})
        verify(tile !== null)
        restores.target = tile
        drags.target = tile
        moves.target = tile
        restores.clear()
        drags.clear()
        moves.clear()
        mouseMove(tile, 32, 32)
        return tile
    }
    function checkRestore(tile) {
        compare(restores.count, 1)
        compare(restores.signalArguments[0][0], tile.itemData)
        compare(restores.signalArguments[0][0].appId, "spotify")
        compare(restores.signalArguments[0][1], 1)
        compare(drags.count, 0)
    }
    function test_runningAppClick(data) {
        var tile = prepare(data)
        mouseClick(tile, 32, 32, Qt.LeftButton)
        checkRestore(tile)
    }
    function test_perpendicularMovementKeepsClick_data() {
        return test_runningAppClick_data()
    }
    function test_perpendicularMovementKeepsClick(data) {
        var tile = prepare(data)
        mousePress(tile, 32, 32, Qt.LeftButton)
        var x = tile.isVertical ? 44 : 32
        var y = tile.isVertical ? 32 : 44
        mouseMove(tile, x, y, 20)
        mouseMove(tile, tile.isVertical ? 48 : 32, tile.isVertical ? 32 : 48, 20)
        mouseRelease(tile, tile.isVertical ? 48 : 32, tile.isVertical ? 32 : 48, Qt.LeftButton)
        checkRestore(tile)
    }
    function test_railMovementReordersWithoutActivation_data() {
        return test_runningAppClick_data()
    }
    function test_railMovementReordersWithoutActivation(data) {
        var tile = prepare(data)
        tile.itemIndex = 1
        tile.totalCount = 3
        mousePress(tile, 32, 32, Qt.LeftButton)
        mouseMove(tile, tile.isVertical ? 32 : 48, tile.isVertical ? 48 : 32, 20)
        mouseMove(tile, tile.isVertical ? 32 : 56, tile.isVertical ? 56 : 32, 20)
        mouseMove(tile, tile.isVertical ? 32 : 120, tile.isVertical ? 120 : 32, 20)
        mouseRelease(tile, tile.isVertical ? 32 : 120, tile.isVertical ? 120 : 32, Qt.LeftButton)
        compare(drags.count, 1)
        compare(drags.signalArguments[0][0], 1)
        compare(moves.count, 1)
        compare(moves.signalArguments[0][0], 1)
        compare(moves.signalArguments[0][1], 2)
        compare(restores.count, 0)
    }
}

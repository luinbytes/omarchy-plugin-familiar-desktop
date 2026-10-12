import QtQuick
import QtTest
import "../components"

TestCase {
    id: root
    name: "DockItemDrag"
    visible: true
    when: windowShown
    width: 240
    height: 80

    property var rowModel: [0]
    property var tile: null
    property int ends: 0
    DockDragState { id: drag }

    Item {
        id: rail
        width: 240
        height: 48
        Repeater {
            model: root.rowModel
            delegate: Item {
                width: 48
                height: 48
                x: index * 48
                Component.onCompleted: {
                    var component = Qt.createComponent("../DockItem.qml")
                    if (component.status !== Component.Ready) {
                        console.log("PROBE component", component.errorString())
                        return
                    }
                    var created = component.createObject(this, {
                        width: 48,
                        height: 48,
                        itemData: ({id: "foot", name: "Foot", isStack: false, isRunning: false, isActive: false, isMinimized: false, toplevels: []}),
                        itemIndex: index,
                        totalCount: 1,
                        slotSize: 48,
                        iconBaseSize: 32
                    })
                    if (!created) {
                        console.log("PROBE create", component.errorString())
                        return
                    }
                    created.dragStarted.connect(function(fromIdx) { drag.startDock(fromIdx) })
                    created.dragEnded.connect(function() { root.ends++; drag.cancelDock() })
                    root.tile = created
                }
            }
        }
    }

    // DockPanel rebuilds dockItems on a 16ms window/badge tick. That destroys the
    // delegate that owns the gesture. The panel clears its drag index only from
    // dragEnded, which released/canceled no longer deliver.
    function test_modelRebuildWhileDraggingClearsDrag() {
        verify(tile !== null)
        mousePress(tile, 24, 24, Qt.LeftButton, Qt.NoModifier, 20)
        mouseMove(tile, 40, 24, 20, Qt.LeftButton)
        mouseMove(tile, 90, 24, 20, Qt.LeftButton)
        compare(tile.isDragging, true)
        compare(drag.dockIndex, 0)
        rowModel = [1]
        wait(0)
        compare(ends, 1)
        compare(drag.dockIndex, -1)
    }
}

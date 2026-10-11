// Render the actual settings body with an inert owner: no compositor or config writes.
const fs = require('node:fs');
const path = require('node:path');
const os = require('node:os');
const {spawnSync} = require('node:child_process');
const assert = require('node:assert/strict');
// Qt 6.12 exports QtQuick.Color; palette access must name the Commons module.
for (const folder of ['.', 'components']) {
    for (const name of fs.readdirSync(folder).filter(name => /\.(qml|js)$/.test(name))) {
        const file = path.join(folder, name);
        const code = fs.readFileSync(file, 'utf8').replace(/\/\*[\s\S]*?\*\/|\/\/[^\n]*|"(?:\\.|[^"\\])*"|'(?:\\.|[^'\\])*'/g, '');
        assert.doesNotMatch(code, /(?<![\w.])Color\b/, `${file}: qualify the Omarchy palette as Commons.Color`);
        if (code.includes('Commons.Color.')) assert.match(code, /import qs\.Commons as Commons/, file);
    }
}
const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'familiar-settings-'));
const quoted = value => JSON.stringify(require('node:url').pathToFileURL(path.resolve(value)).href);
const fixture = `
import QtQuick
import QtQuick.Layouts
import QtTest
import qs.Commons
import ${quoted('components')}
import ${quoted('.')}
import ${quoted('DockSettings.js')} as DockSettings
TestCase {
    id: root
    name: "SettingsLayout"
    width: 800; height: 560
    visible: true
    when: windowShown
    property int writes: 0
    property var lastPreference: null
    function recordPreference(key, value) { writes++; lastPreference = {key: key, value: value} }
    SettingsStore {
        id: owner
        path: "/fictional/settings.json"
        fileShortcutsEnabled: true
        overlayMode: true
        titlebarsEnabled: true
        titlebarMode: "mac"
        titlebarStyle: "mac"
        readonly property string settingsError: error
        property string dockScreenPosition: "bottom"
        property var desktopTools: null
        property var capsLock: null
        property var borderResize: null
        property var commandShortcuts: null
        property var gestures: null
        property var windowMode: null
        property var taskbar: null
        property var setup: null
        property bool taskbarSelected: false
        property bool dockAvailable: true
        property bool titlebarsManagedByOmarchy: false
        property string titlebarState: "configured"
        property bool titlebarBusy: false
        property string titlebarMessage: ""
        function setPreference(key, value) { root.recordPreference(key, value) }
        function setDockEnabled(value) { root.recordPreference("dockEnabled", value) }
        function setProfile(value) { root.writes++ }
        function setTitlebarMode(value) { root.writes++ }
        function setAutohide(value) { root.recordPreference("autohide", value) }
        function setKeybindMode(value) { root.recordPreference("keybindMode", value) }
        function setOverlayMode(value) { root.recordPreference("overlayMode", value) }
        function setVisibleWorkspace(value) { root.writes++ }
        function setWidgetsEnabled(value) { root.recordPreference("widgetsEnabled", value) }
        function refreshTitlebars() { root.writes++ }
        function openWidgetPicker() { root.writes++ }
    }
    QtObject {
        id: shellFixture
        function serviceFor(name) { return owner }
    }
    QtObject {
        id: barFixture
        property var shell: shellFixture
        property var activePopout: null
        function moduleWidgets(name) { return [firstBar, secondBar] }
        function requestPopout(widget) { activePopout = widget }
        function releasePopout(widget) { activePopout = null }
    }
    ProductionBarWidget { id: firstBar; bar: barFixture }
    ProductionBarWidget { id: secondBar; bar: barFixture }
    QtObject {
        id: setupFixture
        property var repairs: []
        function repair(style) { repairs = repairs.concat([style]) }
    }
    SignalSpy { id: closes; target: cardColumn; signalName: "closeRequested" }
    SettingsFrame {
        id: settingsWindow
        width: root.width; height: root.height
        contentHeight: cardColumn.implicitHeight
        SettingsContent {
            id: cardColumn
            service: owner
            navigation: settingsWindow
            workspaceOptions: [{value: "all", label: "All workspaces"}]
            taskbarActive: false
        }
    }
    function test_barInstancesShareSettingsAndLoadTheProductionContent() {
        compare(firstBar.desktopService, owner)
        compare(secondBar.desktopService, owner)
        var original = owner.snapshot()
        verify(owner.patch({showFolderTitles: false, dockWidgets: [], dockSize: "large"}))
        compare(firstBar.showFolderTitles, false)
        compare(secondBar.showFolderTitles, false)
        compare(firstBar.dockWidgets.length, 0)
        compare(secondBar.dockSize, "large")
        firstBar.open()
        compare(firstBar.settingsOpen, true)
        compare(secondBar.settingsOpen, false)
        var loader = findChild(firstBar, "settings-content")
        verify(loader.item !== null)
        compare(loader.item.service, owner)
        verify(loader.implicitHeight > 0)
        compare(loader.implicitHeight, loader.item.implicitHeight)
        firstBar.close()
        compare(firstBar.settingsOpen, false)
        verify(owner.patch(original))
    }
    function test_repairUsesTheSavedStyleOnlyWhenClicked() {
        compare(setupFixture.repairs.length, 0)
        owner.setup = setupFixture
        settingsWindow.page = "windows"
        settingsWindow.section = "titlebars"
        wait(30)
        mouseClick(findChild(cardColumn, "titlebar-repair"))
        compare(setupFixture.repairs, ["mac"])
        owner.titlebarStyle = "windows"
        mouseClick(findChild(cardColumn, "titlebar-repair"))
        compare(setupFixture.repairs, ["mac", "windows"])
        compare(closes.count, 2)
        compare(root.writes, 0)
        owner.setup = null
    }
    function test_officialControlsKeepSizeAndExclusions() {
        owner.titlebarsManagedByOmarchy = true
        settingsWindow.page = "windows"
        settingsWindow.section = "titlebars"
        wait(30)
        verify(findChild(cardColumn, "titlebarSize-choices").visible)
        verify(findChild(cardColumn, "skipBrowserTitlebars").visible)
        var large = findChild(cardColumn, "titlebarSize-large")
        root.writes = 0
        mouseClick(large)
        compare(root.writes, 1)
        compare(root.lastPreference.key, "titlebarSize")
        compare(root.lastPreference.value, "large")
        owner.titlebarsManagedByOmarchy = false
        root.writes = 0
    }
    function test_switchesUseTheirExistingSetters() {
        var cases = [
            {name: "dock-enabled", section: "appearance", key: "dockEnabled"},
            {name: "dock-autohide", section: "visibility", key: "autohide"},
            {name: "dock-keybind", section: "visibility", key: "keybindMode"},
            {name: "dock-overlay", section: "visibility", key: "overlayMode"},
            {name: "dock-badges", section: "extras", key: "showBadges"},
            {name: "dock-widgets", section: "extras", key: "widgetsEnabled"}
            ,{name: "skipBrowserTitlebars", page: "windows", section: "titlebars", key: "skipBrowserTitlebars"}
        ]
        settingsWindow.page = "dock"
        for (var test of cases) {
            settingsWindow.page = test.page || "dock"
            settingsWindow.section = test.section
            wait(20)
            var row = findChild(cardColumn, test.name)
            verify(row !== null && row.visible)
            compare(row.height, 42)
            var expected = !row.checked
            root.writes = 0
            mouseClick(row, 20, row.height / 2)
            compare(root.writes, 1)
            compare(root.lastPreference.key, test.key)
            compare(root.lastPreference.value, expected)
            row.forceActiveFocus()
            keyClick(Qt.Key_Space)
            compare(root.writes, 2, "one request per activation")
            compare(root.lastPreference.value, expected, "the service owns the value")
        }
        var saved = owner.snapshot()
        settingsWindow.page = "dock"
        for (var mode of ["always", "hover", "keybind", "hybrid"]) {
            owner.visibilityMode = mode
            compare(findChild(cardColumn, "dock-autohide").checked, mode === "hover" || mode === "hybrid")
            compare(findChild(cardColumn, "dock-keybind").checked, mode === "keybind" || mode === "hybrid")
        }
        owner.patch(saved)
        root.writes = 0
    }
    function test_pages() {
        for (var width of [800, 560]) {
            root.width = width
            for (var page of settingsWindow.pages) {
                settingsWindow.page = page.key
                var sections = settingsWindow.currentSections
                for (var section of sections.length ? sections : [{key: ""}]) {
                    settingsWindow.section = section.key
                    wait(30)
                    var scroll = findChild(settingsWindow, "settings-scroll")
                    verify(scroll.width > 250)
                    // Each preference section fits without scrolling at both supported widths.
                    if (page.key !== "help")
                        verify(settingsWindow.contentHeight <= scroll.height + 1, page.key + "/" + section.key + ": " + settingsWindow.contentHeight)
                    if (width === 800 && section.key === "layout")
                        grabImage(settingsWindow).save("/tmp/familiar-settings-layout.png")
                    console.log(width + " " + page.key + "/" + section.key + " height=" + Math.round(settingsWindow.contentHeight))
                }
            }
        }
        compare(writes, 0)
        compare(owner.profile, "general")
        compare(owner.dockEnabled, true)
        compare(owner.titlebarMode, "mac")
    }
}
`;
fs.writeFileSync(path.join(dir, 'tst_SettingsLayout.qml'), fixture);
// Load the complete production bar with only its shell/window boundaries inert.
// This catches component-load errors that rendering SettingsContent alone misses.
for (const name of fs.readdirSync('.').filter(name => /\.(qml|js)$/.test(name) && name !== 'BarWidget.qml'))
    fs.copyFileSync(name, path.join(dir, name));
fs.copyFileSync('BarWidget.qml', path.join(dir, 'ProductionBarWidget.qml'));
fs.cpSync('components', path.join(dir, 'components'), {recursive: true});
fs.writeFileSync(path.join(dir, 'components/SettingsModal.qml'), `import QtQuick
SettingsFrame {
    required property Item anchorItem
    required property var owner
    required property var bar
    property bool open: false
    property real contentWidth: 800
    width: contentWidth; height: 560
    visible: open
}`);
fs.writeFileSync(path.join(dir, 'components/TaskbarApps.qml'), 'import QtQuick\nItem { property var service; property var bar }\n');
fs.mkdirSync(path.join(dir, 'qs/Ui'), {recursive:true});
fs.writeFileSync(path.join(dir, 'qs/Ui/qmldir'), 'module qs.Ui\nBorderSurface 1.0 BorderSurface.qml\nBarWidget 1.0 BarWidget.qml\nWidgetButton 1.0 WidgetButton.qml\n');
fs.writeFileSync(path.join(dir, 'qs/Ui/BorderSurface.qml'), 'import QtQuick\nRectangle { property var borderSpec; property int borderLeft: 1; property int borderRight: 1 }\n');
fs.writeFileSync(path.join(dir, 'qs/Ui/BarWidget.qml'), 'import QtQuick\nItem { property string moduleName; property var bar; property bool vertical: false }\n');
fs.writeFileSync(path.join(dir, 'qs/Ui/WidgetButton.qml'), `import QtQuick
Item {
    property var bar
    property bool interactive: true
    property string text
    property int fixedWidth: -1
    property string tooltipText
    implicitWidth: fixedWidth > 0 ? fixedWidth : 40
    implicitHeight: 32
    signal pressed(int buttonCode)
}`);
const run = spawnSync(process.env.QMLTESTRUNNER || '/usr/lib/qt6/bin/qmltestrunner', ['-input',dir,'-import',path.resolve('tests/imports'),'-import',dir], {encoding: 'utf8'});
process.stdout.write(run.stdout || '');
process.stderr.write(run.stderr || '');
if (run.error) throw run.error;
fs.rmSync(dir, {recursive:true,force:true});
process.exitCode = run.status === null ? 1 : run.status;
if (/TypeError:|ReferenceError:/.test((run.stdout || '') + (run.stderr || ''))) {
    console.error('Production settings or bar bindings raised a JavaScript error.');
    process.exitCode = 1;
}

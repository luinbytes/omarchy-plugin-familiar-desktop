import QtQuick
import Quickshell
import Quickshell.Io

Item {
    id: root
    property bool available: true
    property bool enabled: false
    property string style: "mac"
    property string mode: "theme"
    property string fontFamily: "Sans"
    property int fontSize: 13
    property string exclusions: ""
    property bool skipBrowserTitlebars: true
    property string size: "default"
    property color background: "#202020"
    property color foreground: "#ffffff"
    property string state: "checking"
    property string backend: "familiar"
    property string message: "Checking window controls…"
    readonly property bool busy: adapter.running
    readonly property string helper: Qt.resolvedUrl("../bin/familiar-desktop").toString().replace(/^file:\/\//, "")
    readonly property string ownerToken: String(Date.now()) + "-" + String(Math.random()).slice(2)
    property int revision: 0
    property int requestedRevision: 0
    property bool disposed: false

    function hexColour(value) {
        return "#" + [value.r, value.g, value.b].map(function(channel) {
            return Math.round(channel * 255).toString(16).padStart(2, "0")
        }).join("")
    }

    function schedule() {
        revision += 1
        reconcileTimer.restart()
    }
    function refresh() { schedule() }
    function useOmarchy() {
        if (disposed || !available || adapter.running) return
        requestedRevision = revision
        adapter.command = [helper, "titlebars", "migrate"]
        adapter.running = true
    }
    function reconcile() {
        if (disposed || !available || adapter.running) return
        requestedRevision = revision
        adapter.command = [helper, "titlebars", enabled ? "apply" : "disable", "--owner", ownerToken,
                           "--style", style, "--background", hexColour(background),
                           "--foreground", hexColour(foreground), "--exclude", exclusions,
                           "--mode", mode, "--size", size, "--font-family", fontFamily, "--font-size", String(fontSize)]
        if (!skipBrowserTitlebars) adapter.command = adapter.command.concat(["--include-browsers"])
        adapter.running = true
    }
    onAvailableChanged: schedule()
    onEnabledChanged: schedule()
    onStyleChanged: schedule()
    onModeChanged: schedule()
    onFontFamilyChanged: schedule()
    onFontSizeChanged: schedule()
    onExclusionsChanged: schedule()
    onSkipBrowserTitlebarsChanged: schedule()
    onSizeChanged: schedule()
    onBackgroundChanged: schedule()
    onForegroundChanged: schedule()
    Component.onCompleted: schedule()
    FileView {
        id: themeOptions
        path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme/familiar-desktop.json"
        watchChanges: true
        preload: false
        printErrors: false
        onFileChanged: root.schedule()
    }
    FileView {
        path: Quickshell.env("HOME") + "/.local/state/omarchy/current/theme.name"
        watchChanges: true
        preload: false
        printErrors: false
        onFileChanged: root.schedule()
    }
    Component.onDestruction: {
        disposed = true
        // A session token prevents an old instance's teardown undoing a newer
        // instance after hot reload. The adapter serializes writes with flock.
        if (available) Quickshell.execDetached([helper, "titlebars", "disable", "--owner", ownerToken, "--if-owner"])
    }
    Timer {
        id: reconcileTimer
        objectName: "titlebarReconcileTimer"
        interval: 200
        onTriggered: root.reconcile()
    }
    Process {
        id: adapter
        objectName: "titlebarAdapter"
        stdout: StdioCollector { id: resultCollector; waitForEnd: true }
        onExited: (exitCode, exitStatus) => {
            watchdog.stop()
            if (root.disposed) return
            if (root.requestedRevision !== root.revision) {
                reconcileTimer.restart()
                return
            }
            try {
                var result = JSON.parse(resultCollector.text)
                root.state = exitCode === 0 ? (result.state || "failed") : "failed"
                if (exitCode === 0) root.backend = String(result.backend || "familiar")
                root.message = String(result.message || "Window-control update failed.").slice(0, 300)
                if (exitCode === 0 && adapter.command[2] === "migrate") root.schedule()
            } catch (error) {
                root.state = "failed"
                root.message = "Window-control helper failed. Build the Rust helper and check that hyprctl is installed."
            }
        }
        onRunningChanged: if (running) watchdog.restart()
    }
    Timer {
        id: watchdog
        objectName: "titlebarWatchdog"
        interval: 30000
        onTriggered: {
            adapter.running = false
            root.state = "failed"
            root.message = "Window-control update timed out. Retry when Hyprland is responding."
        }
    }
}

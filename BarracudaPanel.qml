import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Barracuda VPN tunnel toggle with live network speeds in the panel.
// Left click opens the panel with Connect / Disconnect; right click launches
// the interactive client in a terminal. The bar glyph reflects tunnel state
// (shield = up, globe = down).
Panel {
  id: root
  moduleName: "ignace.barracudavpn"
  ipcTarget: "ignace.barracudavpn"

  property bool connected: false
  property bool busy: false
  property int downBps: 0
  property int upBps: 0
  property string ifaceName: ""

  readonly property string helper: Qt.resolvedUrl("vpn-ctl").toString().replace("file://", "")

  // Where the client's passwords are read from. Goes through setting() because
  // the bar injects the shell.json entry as `settings` and never assigns plain
  // properties. The fallback mirrors manifest barWidget.defaults.credsPath and
  // must stay ~/creds.txt: nothing merges the manifest default in, so this
  // literal is what actually runs when the setting is unset.
  readonly property string credsPath: String(setting("credsPath", "~/creds.txt")).trim()

  // Config-carrying prefix for every helper call, so status and start always
  // agree about which file they are talking about.
  function helperArgs(rest) {
    var base = [root.helper]
    if (root.credsPath !== "") base = base.concat(["--creds", root.credsPath])
    return base.concat(rest)
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  function fmtRate(bps) {
    var units = ["B", "K", "M", "G"]
    var v = bps
    var i = 0
    while (v >= 1000 && i < units.length - 1) { v /= 1000; i++ }
    return (i === 0 ? Math.round(v) : v.toFixed(1)) + units[i]
  }

  function refresh() {
    if (!statusProc.running && !busy) statusProc.running = true
  }

  function pollSpeeds() {
    if (!speedProc.running) speedProc.running = true
  }

  function startVpn() {
    if (busy) return
    busy = true
    startProc.running = true
  }

  function stopVpn() {
    if (busy) return
    busy = true
    stopProc.running = true
  }

  function openClient() {
    if (root.bar) root.bar.run("omarchy-launch-terminal barracudavpn")
  }

  Process {
    id: statusProc
    // timeout guards against a hung client call wedging refresh() forever.
    command: ["timeout", "10"].concat(root.helperArgs(["status"]))
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.connected = text.trim() === "1" }
  }

  Process {
    id: speedProc
    command: ["timeout", "10"].concat(root.helperArgs(["speeds"]))
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var parts = text.trim().split(/\s+/)
        if (parts.length >= 3) {
          root.downBps = parseInt(parts[0]) || 0
          root.upBps = parseInt(parts[1]) || 0
          root.ifaceName = parts[2]
        }
      }
    }
  }

  Process {
    id: startProc
    command: ["timeout", "60"].concat(root.helperArgs(["start"]))
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
    onExited: {
      root.busy = false
      root.refresh()
      root.pollSpeeds()
    }
  }

  Process {
    id: stopProc
    command: ["timeout", "30"].concat(root.helperArgs(["stop"]))
    stdout: StdioCollector { waitForEnd: true }
    stderr: StdioCollector { waitForEnd: true }
    onExited: {
      root.busy = false
      root.refresh()
      root.pollSpeeds()
    }
  }

  // Live updates while the panel is open.
  Timer {
    interval: 2000
    running: root.opened
    repeat: true
    triggeredOnStart: true
    onTriggered: {
      root.refresh()
      root.pollSpeeds()
    }
  }

  // Slow background poll keeps the bar glyph truthful when closed.
  Timer {
    interval: 30000
    running: !root.opened
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    // Shield vs globe: tunnelled traffic vs traffic going out in the open.
    // Reads at a glance and leaves the padlock glyphs to the KeePass widget.
    text: root.connected ? "\uF132" : "\uF0AC"
    slotSize: Style.bar.iconSlot
    tooltipText: root.connected ? "Barracuda VPN — connected" : "Barracuda VPN"
    onPressed: function(b) {
      if (b === Qt.RightButton) root.openClient()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(260))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(8)

        PanelSectionHeader {
          text: "BARRACUDA VPN"
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
        }

        Text {
          width: column.width
          text: root.busy
                ? (root.connected ? "Disconnecting…" : "Connecting…")
                : (root.connected ? "Connected" : "Disconnected")
          color: root.bar.foreground
          opacity: 0.8
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        PanelSeparator {}

        Text {
          width: column.width
          text: "\u2193 " + root.fmtRate(root.downBps) + "/s      \u2191 " + root.fmtRate(root.upBps) + "/s"
          color: root.bar.foreground
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.body
        }

        Text {
          width: column.width
          text: "via " + (root.ifaceName || "—")
          color: root.bar.foreground
          opacity: 0.5
          font.family: root.bar.fontFamily
          font.pixelSize: Style.font.bodySmall
        }

        PanelSeparator {}

        Button {
          width: column.width
          text: "Connect"
          fontSize: Style.font.bodySmall
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
          horizontalPadding: Style.spacing.controlPaddingX
          verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
          leftAlign: true
          bordered: true
          enabled: !root.connected && !root.busy
          opacity: root.enabled ? 1 : 0.4
          onClicked: root.startVpn()
        }

        Button {
          width: column.width
          text: "Disconnect"
          fontSize: Style.font.bodySmall
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
          horizontalPadding: Style.spacing.controlPaddingX
          verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
          leftAlign: true
          bordered: true
          active: root.connected
          enabled: root.connected && !root.busy
          opacity: root.enabled ? 1 : 0.4
          onClicked: root.stopVpn()
        }

        PanelSeparator {}

        Button {
          width: column.width
          text: "Open interactive client"
          fontSize: Style.font.bodySmall
          foreground: root.bar.foreground
          fontFamily: root.bar.fontFamily
          horizontalPadding: Style.spacing.controlPaddingX
          verticalPadding: Style.spacing.controlPaddingY + Style.space(2)
          leftAlign: true
          bordered: true
          onClicked: {
            root.close()
            root.openClient()
          }
        }
      }
    }
  }
}

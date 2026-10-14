import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui

// Work connection — un icono en la barra para la VPN del trabajo: estado, IP del
// túnel y gateway, con los botones de conectar, desconectar, escritorio remoto y
// Teams. Todo el trabajo lo hace un CLI auxiliar (por defecto `conectar-trabajo`,
// ajustable en los ajustes del widget):
//
//   --status   estado (lo que este panel lee)
//   --vpn-only conectar la VPN
//   --down     desconectar
//   --rdp      abrir el cliente de escritorio remoto
//   --teams    abrir Teams
//
// Nada de la empresa está acá: el perfil, el host y las credenciales viven en el
// helper y en el almacén de credenciales del sistema.
Panel {
  id: root
  moduleName: "meperdonas.work-vpn"
  ipcTarget: "meperdonas.work-vpn"

  readonly property string helper: setting("helper", "conectar-trabajo")
  readonly property string label: setting("label", "Work connection")
  readonly property int refreshInterval: setting("refreshIntervalSec", 5)
  readonly property bool showRemmina: setting("showRemmina", "On") === "On"
  readonly property bool showTeams: setting("showTeams", "On") === "On"

  property bool connected: false
  property bool busy: false
  property string statusText: "Comprobando…"
  property string ipAddress: "—"
  property string gateway: "—"

  implicitWidth: 30
  implicitHeight: bar ? bar.barSize : 26

  function refresh() { if (!statusProbe.running) statusProbe.running = true }
  function runAction(argument) {
    busy = true
    close()
    // bar.run = bash -lc detachado: el helper maneja su propia elevación y avisa
    // por notificación, así que no hace falta una terminal para ver la salida.
    bar.run(helper + " " + argument)
    refreshTimer.restart()
  }

  Process {
    id: statusProbe
    command: ["/bin/bash", "-lc", root.helper + " --status"]
    stdout: StdioCollector { id: statusOutput }
    onExited: {
      var output = String(statusOutput.text || "")
      root.connected = output.indexOf("VPN conectada") !== -1
      // Ojo con el escapado: dentro de un literal de regex, `\\.` sería una
      // barra literal + cualquier carácter (nunca coincide con "10.81.x.x").
      var ipMatch = output.match(/\b\d{1,3}(?:\.\d{1,3}){3}\b/)
      var gatewayMatch = output.match(/via (\d{1,3}(?:\.\d{1,3}){3})/)
      root.ipAddress = ipMatch ? ipMatch[0] : "—"
      root.gateway = gatewayMatch ? gatewayMatch[1] : "—"
      root.statusText = root.connected ? "Connected" : "Disconnected"
      root.busy = false
    }
  }

  Timer {
    id: refreshTimer
    interval: root.refreshInterval * 1000
    repeat: true
    running: true
    onTriggered: root.refresh()
  }

  Component.onCompleted: refresh()

  Rectangle {
    id: iconButton
    anchors.fill: parent
    radius: height / 2
    color: mouse.containsMouse ? Qt.rgba(1, 1, 1, 0.10) : "transparent"

    Text {
      id: barGlyph
      anchors.centerIn: parent
      text: "󰖂"
      color: root.connected ? (bar ? bar.foreground : "white") : Qt.darker(bar ? bar.foreground : "white", 1.65)
      font.family: bar ? bar.fontFamily : "monospace"
      font.pixelSize: 16

      // Mientras una acción está en curso el icono respira.
      SequentialAnimation on opacity {
        running: root.busy
        loops: Animation.Infinite
        NumberAnimation { from: 0.45; to: 1; duration: 950; easing.type: Easing.InOutSine }
        NumberAnimation { from: 1; to: 0.45; duration: 950; easing.type: Easing.InOutSine }
      }
    }

    MouseArea {
      id: mouse
      anchors.fill: parent
      hoverEnabled: true
      onClicked: root.toggle()
      onEntered: if (bar) bar.showTooltip(mouse, root.label + " · " + root.statusText)
      onExited: if (bar) bar.hideTooltip(mouse)
    }
  }

  PopupCard {
    id: popup
    anchorItem: iconButton
    bar: root.bar
    owner: root
    open: root.opened
    // "hover": sin HyprlandFocusGrab, así el popup sobrevive al clic-arrastre de
    // slurp cuando estás encuadrando un screenshot.
    triggerMode: "hover"
    contentWidth: 300
    contentHeight: popup.fittedContentHeight(contentColumn.implicitHeight + 32)
    margin: 14

    Column {
      id: contentColumn
      anchors.fill: parent
      anchors.margins: 16
      spacing: 14

      Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 10
        Text {
          text: "󰖂"
          color: root.connected ? (bar ? bar.foreground : "white") : Qt.darker(bar ? bar.foreground : "white", 1.65)
          font.family: bar ? bar.fontFamily : "monospace"
          font.pixelSize: 19
        }
        Text {
          text: root.label
          color: bar ? bar.foreground : "white"
          font.family: bar ? bar.fontFamily : "monospace"
          font.pixelSize: 15
          font.bold: true
          anchors.verticalCenter: parent.verticalCenter
        }
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        text: root.busy ? "Working…" : root.statusText
        color: root.connected ? (bar ? bar.foreground : "white") : (bar ? bar.urgent : "#e5a")
        font.family: bar ? bar.fontFamily : "monospace"
        font.pixelSize: 12
      }

      Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 24
        Text {
          text: "IP Address  " + root.ipAddress
          color: bar ? bar.foreground : "white"
          font.family: bar ? bar.fontFamily : "monospace"
          font.pixelSize: 11
        }
        Text {
          text: "Gateway  " + root.gateway
          color: bar ? bar.foreground : "white"
          font.family: bar ? bar.fontFamily : "monospace"
          font.pixelSize: 11
        }
      }

      Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 8
        ActionButton { label: "Connect"; icon: "󰐕"; enabled: !root.connected && !root.busy; onTriggered: root.runAction("--vpn-only") }
        ActionButton { label: "Disconnect"; icon: "󰜺"; enabled: root.connected && !root.busy; onTriggered: root.runAction("--down") }
      }

      Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 8
        visible: root.showRemmina || root.showTeams
        ActionButton { label: "Remmina"; icon: "󰆍"; visible: root.showRemmina; enabled: root.connected; onTriggered: root.runAction("--rdp") }
        ActionButton { label: "Teams"; icon: "󰊻"; visible: root.showTeams; enabled: true; onTriggered: root.runAction("--teams") }
      }
    }
  }

  component ActionButton: Rectangle {
    id: buttonRoot
    property string label
    property string icon: ""
    property bool enabled: true
    signal triggered()
    width: 116
    height: 54
    radius: 2
    color: enabled ? (buttonMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(1, 1, 1, 0.10)) : Qt.rgba(1, 1, 1, 0.04)
    border.color: enabled ? Qt.rgba(1, 1, 1, 0.28) : Qt.rgba(1, 1, 1, 0.10)
    border.width: 1
    opacity: enabled ? 1 : 0.45

    Column {
      anchors.centerIn: parent
      spacing: 2
      Text {
        width: buttonRoot.width - 12
        horizontalAlignment: Text.AlignHCenter
        text: buttonRoot.icon
        color: bar ? bar.foreground : "white"
        font.family: bar ? bar.fontFamily : "monospace"
        font.pixelSize: 17
      }
      Text {
        width: buttonRoot.width - 12
        horizontalAlignment: Text.AlignHCenter
        text: buttonRoot.label
        color: bar ? bar.foreground : "white"
        font.family: bar ? bar.fontFamily : "monospace"
        font.pixelSize: 10
        wrapMode: Text.NoWrap
        elide: Text.ElideRight
      }
    }

    MouseArea {
      id: buttonMouse
      anchors.fill: parent
      enabled: parent.enabled
      hoverEnabled: true
      onClicked: parent.triggered()
    }
  }
}

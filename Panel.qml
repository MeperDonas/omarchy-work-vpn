import QtQuick
import Quickshell
import Quickshell.Io
import qs.Ui
import "i18n.js" as I18n

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
//   lang [en|es] idioma del widget (~/.config/work-vpn/lang; por defecto en)
//
// El idioma del panel y del helper es el mismo archivo, y se cambia con el
// botoncito del encabezado del popup.
//
// Nada de la empresa está acá: el perfil, el host y las credenciales viven en el
// helper y en el almacén de credenciales del sistema.
Panel {
  id: root
  moduleName: "meperdonas.work-vpn"
  ipcTarget: "meperdonas.work-vpn"

  // El helper es la base de todo comando. Si está vacío se usa el que viaja
  // dentro del plugin (bin/work-vpn), como hace el resto de los widgets.
  readonly property string bundledHelper: Quickshell.env("HOME") + "/.config/omarchy/plugins/meperdonas.work-vpn/bin/work-vpn"
  readonly property string configuredHelper: setting("helper", "")
  readonly property string helper: configuredHelper !== ""
    ? configuredHelper
    : "$( [ -x " + bundledHelper + " ] && printf %s " + bundledHelper + " || printf %s conectar-trabajo )"
  // Contrato nuevo: `--status --json` y `apps --json`. Los valores por defecto
  // son los de los helpers viejos, así nada se rompe; el widget prueba json y
  // si el helper no lo entiende se queda con el texto para el resto de la sesión.
  readonly property string statusJsonArgs: setting("statusJsonArgs", "--status --json")
  readonly property string statusTextArgs: setting("statusTextArgs", "--status")
  readonly property string connectArgs: setting("connectArgs", "--vpn-only")
  readonly property string disconnectArgs: setting("disconnectArgs", "--down")
  readonly property string appsArgs: setting("appsArgs", "apps --json")
  readonly property string appOpenArgs: setting("appOpenArgs", "open")
  readonly property string label: setting("label", "Work connection")
  readonly property int refreshInterval: setting("refreshIntervalSec", 5)
  readonly property bool showRemmina: setting("showRemmina", "On") === "On"
  readonly property bool showTeams: setting("showTeams", "On") === "On"
  // Idioma del widget (en | es). Vive en ~/.config/work-vpn/lang, el mismo
  // archivo que usa el helper, así la UI y la terminal nunca se contradicen:
  // se cambia con el botoncito del popup o con `work-vpn lang es`.
  property string lang: "en"
  readonly property string langFile: Quickshell.env("HOME") + "/.config/work-vpn/lang"

  property bool connected: false
  // Apps que declara el helper (`apps --json`): id, etiqueta e ícono.
  property var apps: []
  property bool appsFromHelper: false
  // El helper viejo no entiende json: se prueba una vez y se recuerda.
  property bool jsonStatus: true
  property string backend: ""
  property string connection: ""
  property bool busy: false
  property string statusText: t("checking")
  property string ipAddress: "—"
  property string gateway: "—"

  implicitWidth: 30
  implicitHeight: bar ? bar.barSize : 26

  // Traducción: t("clave") o t("clave", { n: 7 })
  function t(key, subs) { return I18n.t(root.lang, key, subs) }

  // El idioma lo escribe el helper (`work-vpn lang en|es`); acá se refleja ya
  // mismo y se refresca el estado, que viene con su propio idioma.
  function toggleLang() {
    var next = root.lang === "en" ? "es" : "en"
    // Escribe el archivo del widget y le avisa al helper (si no lo entiende, no
    // pasa nada: el archivo ya quedó).
    bar.run("mkdir -p \"$(dirname " + root.langFile + ")\" && printf %s " + next + " > " + root.langFile
      + "; " + root.helper + " lang " + next + " >/dev/null 2>&1 || true")
    root.lang = next
    refresh()
  }

  function refresh() { if (!statusProbe.running) statusProbe.running = true }
  function refreshApps() { if (!appsProbe.running) appsProbe.running = true }
  function runAction(argument) {
    busy = true
    close()
    // bar.run = bash -lc detachado: el helper maneja su propia elevación y avisa
    // por notificación, así que no hace falta una terminal para ver la salida.
    bar.run(helper + " " + argument)
    refreshTimer.restart()
  }

  function applyTextStatus(output) {
    // Helper viejo: se lee el texto (contrato original). El marcador puede venir
    // en inglés (helper nuevo) o en español (helper de siempre): los dos valen.
    root.connected = output.indexOf("VPN conectada") !== -1 || output.indexOf("VPN connected") !== -1
    var ipMatch = output.match(/\b\d{1,3}(?:\.\d{1,3}){3}\b/)
    var gatewayMatch = output.match(/via (\d{1,3}(?:\.\d{1,3}){3})/)
    root.connection = ""
    root.ipAddress = ipMatch ? ipMatch[0] : "—"
    root.gateway = gatewayMatch ? gatewayMatch[1] : "—"
    root.statusText = t(root.connected ? "connected" : "disconnected")
  }

  function applyJsonStatus(data) {
    root.connected = data.connected === true
    root.connection = data.connection || ""
    root.ipAddress = data.ip && data.ip !== "" ? data.ip : "—"
    root.gateway = data.gateway && data.gateway !== "" ? data.gateway : ""
    root.backend = data.backend || ""
    root.statusText = data.detail && data.detail !== ""
      ? data.detail
      : t(root.connected ? "connected" : "disconnected")
  }

  Process {
    id: statusProbe
    // json: la primera pasada usa el contrato nuevo; si el helper no lo
    // entiende, esta bandera queda en false y se sigue con texto.
    property bool json: root.jsonStatus
    command: ["/bin/bash", "-lc", root.helper + " " + (json ? root.statusJsonArgs : root.statusTextArgs)]
    stdout: StdioCollector { id: statusOutput }
    onExited: {
      var output = String(statusOutput.text || "")
      if (json) {
        var data = null
        try {
          data = JSON.parse(output)
        } catch (error) {
          data = null
        }
        if (data && typeof data === "object" && data.connected !== undefined) {
          root.applyJsonStatus(data)
        } else {
          root.jsonStatus = false
          statusProbe.json = false
          statusProbe.running = true
          return
        }
      } else {
        root.applyTextStatus(output)
      }
      root.busy = false
    }
  }

  // Apps: si el helper las declara, se dibujan ésas; si no, quedan los botones
  // de siempre (Remmina y Teams).
  Process {
    id: appsProbe
    command: ["/bin/bash", "-lc", root.helper + " " + root.appsArgs]
    stdout: StdioCollector { id: appsOutput }
    onExited: {
      var data = null
      try {
        data = JSON.parse(String(appsOutput.text || ""))
      } catch (error) {
        data = null
      }
      if (data instanceof Array && data.length > 0) {
        root.apps = data
        root.appsFromHelper = true
      } else {
        root.apps = []
        root.appsFromHelper = false
      }
    }
  }

  // Idioma: se le pregunta al helper al arrancar (el archivo de lang manda). Si
  // no contesta —helper viejo— queda el inglés, que es el idioma de publicación.
  Process {
    id: langProbe
    // El archivo ~/.config/work-vpn/lang manda (lo escribe el botón): así el
    // idioma funciona aunque el helper sea un script viejo que no lo entiende.
    command: ["/bin/bash", "-lc",
      "cat " + root.langFile + " 2>/dev/null || " + root.helper + " lang 2>/dev/null || echo en"]
    stdout: StdioCollector { id: langOutput }
    onExited: {
      var value = String(langOutput.text || "").trim()
      root.lang = value === "es" ? "es" : "en"
    }
  }

  // Cita para el shell: el id viene del json del helper, no se interpola crudo.
  function shq(value) {
    return "'" + String(value).replace(/'/g, "'\\''") + "'"
  }

  function openApp(id) {
    if (id === "") return
    bar.run(root.helper + " " + root.appOpenArgs + " " + shq(id))
  }

  Timer {
    id: refreshTimer
    interval: root.refreshInterval * 1000
    repeat: true
    running: true
    onTriggered: {
      root.refresh()
      root.refreshApps()
    }
  }

  Component.onCompleted: {
    langProbe.running = true
    refresh()
    refreshApps()
  }

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

      // Encabezado: ícono y nombre centrados y, a la derecha, el botón de idioma
      // (alterna en/es; no es un dropdown).
      Item {
        width: contentColumn.width
        height: headerRow.implicitHeight > 0 ? headerRow.implicitHeight : 26

        Row {
          id: headerRow
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

        ActionButton {
          compact: true
          anchors.right: parent.right
          anchors.verticalCenter: parent.verticalCenter
          icon: root.lang.toUpperCase()
          onTriggered: root.toggleLang()
        }
      }

      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        width: contentColumn.width
        horizontalAlignment: Text.AlignHCenter
        text: root.busy ? root.t("working") : root.statusText
        color: root.connected ? (bar ? bar.foreground : "white") : (bar ? bar.urgent : "#e5a")
        font.family: bar ? bar.fontFamily : "monospace"
        font.pixelSize: 12
        elide: Text.ElideRight
      }

      // Qué conexión está resolviendo (el nombre largo no cabe: se recorta).
      Text {
        anchors.horizontalCenter: parent.horizontalCenter
        width: contentColumn.width
        horizontalAlignment: Text.AlignHCenter
        visible: root.connection !== ""
        text: root.connection
        color: bar ? bar.foreground : "white"
        opacity: 0.6
        font.family: bar ? bar.fontFamily : "monospace"
        font.pixelSize: 10
        elide: Text.ElideMiddle
      }

      // IP y gateway en dos columnas con etiqueta chica: entra sin pegarse al
      // borde (en una sola línea, con los dos valores, no entraba).
      Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 32

        Column {
          spacing: 2
          visible: root.connected
          Text {
            text: root.t("tunnelIp")
            anchors.horizontalCenter: parent.horizontalCenter
            color: bar ? bar.foreground : "white"
            opacity: 0.6
            font.family: bar ? bar.fontFamily : "monospace"
            font.pixelSize: 9
          }
          Text {
            text: root.ipAddress
            anchors.horizontalCenter: parent.horizontalCenter
            color: bar ? bar.foreground : "white"
            font.family: bar ? bar.fontFamily : "monospace"
            font.pixelSize: 12
          }
        }

        Column {
          spacing: 2
          visible: root.connected && root.gateway !== "" && root.gateway !== "—"
          Text {
            text: root.t("gateway")
            anchors.horizontalCenter: parent.horizontalCenter
            color: bar ? bar.foreground : "white"
            opacity: 0.6
            font.family: bar ? bar.fontFamily : "monospace"
            font.pixelSize: 9
          }
          Text {
            text: root.gateway
            anchors.horizontalCenter: parent.horizontalCenter
            color: bar ? bar.foreground : "white"
            font.family: bar ? bar.fontFamily : "monospace"
            font.pixelSize: 12
          }
        }
      }

      Row {
        anchors.horizontalCenter: parent.horizontalCenter
        spacing: 8
        ActionButton { label: root.t("connect"); icon: "󰐕"; enabled: !root.connected && !root.busy; onTriggered: root.runAction(root.connectArgs) }
        ActionButton { label: root.t("disconnect"); icon: "󰜺"; enabled: root.connected && !root.busy; onTriggered: root.runAction(root.disconnectArgs) }
      }

      // Un botón por app: las que declara el helper, o las de siempre si el
      // helper no las declara (Remmina y Teams, con sus ajustes de visibilidad).
      Grid {
        anchors.horizontalCenter: parent.horizontalCenter
        columns: 2
        spacing: 8
        visible: root.appsFromHelper || root.showRemmina || root.showTeams

        Repeater {
          model: root.appsFromHelper
            ? root.apps
            : [{ id: "remmina", label: root.t("remmina"), icon: "󰆍", only: "remmina" }, { id: "teams", label: root.t("teams"), icon: "󰊻", only: "teams" }]

          ActionButton {
            label: modelData.label
            icon: modelData.icon !== undefined ? modelData.icon : "󰖟"
            visible: root.appsFromHelper
              ? true
              : (modelData.only === "remmina" ? root.showRemmina : root.showTeams)
            enabled: root.appsFromHelper ? true : (modelData.only === "remmina" ? root.connected : true)
            onTriggered: {
              if (root.appsFromHelper) root.openApp(modelData.id)
              else root.runAction(modelData.only === "remmina" ? "--rdp" : "--teams")
            }
          }
        }
      }
    }
  }

  component ActionButton: Rectangle {
    id: buttonRoot
    property string label
    property string icon: ""
    property bool enabled: true
    property bool compact: false
    signal triggered()
    width: compact ? 26 : 116
    height: compact ? 22 : 54
    radius: 2
    color: enabled ? (buttonMouse.containsMouse ? Qt.rgba(1, 1, 1, 0.18) : Qt.rgba(1, 1, 1, 0.10)) : Qt.rgba(1, 1, 1, 0.04)
    border.color: enabled ? Qt.rgba(1, 1, 1, 0.28) : Qt.rgba(1, 1, 1, 0.10)
    border.width: 1
    opacity: enabled ? 1 : 0.45

    Column {
      anchors.centerIn: parent
      spacing: 2
      Text {
        width: buttonRoot.compact ? buttonRoot.width : buttonRoot.width - 12
        horizontalAlignment: Text.AlignHCenter
        text: buttonRoot.icon
        color: bar ? bar.foreground : "white"
        font.family: bar ? bar.fontFamily : "monospace"
        font.pixelSize: buttonRoot.compact ? 13 : 17
      }
      Text {
        visible: !buttonRoot.compact
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

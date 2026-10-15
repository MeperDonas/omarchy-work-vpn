.pragma library

// Diccionario del widget. `en` es el idioma de publicación (mercado, README,
// capturas) y `es` el de uso diario; el idioma activo vive en
// ~/.config/work-vpn/lang —el mismo archivo que lee el helper— y se cambia con
// el botoncito del popup o con `work-vpn lang es`.
//
// Uso desde Panel.qml:  I18n.t("connect")  ·  I18n.t("row", { n: 7 })

var strings = {
    en: {
        // estado
        checking: "Checking…",
        working: "Working…",
        connected: "Connected",
        disconnected: "Disconnected",
        // acciones
        connect: "Connect",
        disconnect: "Disconnect",
        // datos de la conexión
        tunnelIp: "Tunnel IP",
        gateway: "Gateway",
        // apps de siempre, si el helper no declara las suyas: en inglés van por su
        // nombre y en español por lo que hacen (igual que en el helper)
        remmina: "Remmina",
        teams: "Teams"
    },
    es: {
        checking: "Comprobando…",
        working: "Trabajando…",
        connected: "Conectada",
        disconnected: "Desconectada",
        connect: "Conectar",
        disconnect: "Desconectar",
        tunnelIp: "IP del túnel",
        gateway: "Gateway",
        remmina: "Escritorio remoto",
        teams: "Teams"
    }
}

// t("connect") o t("row", { n: 7 }): los {nombre} se reemplazan.
function t(lang, key, subs) {
    var table = strings[lang] || strings.en
    var text = table[key]
    if (text === undefined) text = strings.en[key]
    if (text === undefined) return key
    if (subs) {
        for (var name in subs) {
            text = text.split("{" + name + "}").join(String(subs[name]))
        }
    }
    return text
}

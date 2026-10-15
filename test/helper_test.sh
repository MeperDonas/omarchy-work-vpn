#!/usr/bin/env bash
# Prueba de `bin/work-vpn` (el helper del widget) con un NetworkManager y unas
# apps falsas: no toca la VPN real ni abre nada de la máquina que lo corre.
#
# El helper se invoca con un PATH cerrado (sólo los fakes + las herramientas que
# necesita), así la detección de apps depende del test y no del sistema.

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."
HELPER="$PWD/bin/work-vpn"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

fakebin="$tmp/bin"
mkdir -p "$fakebin" "$tmp/xdg/work-vpn"
export XDG_CONFIG_HOME="$tmp/xdg"

# --- NetworkManager de mentira ----------------------------------------------
printf 'VPN uno:vpn\nWired:802-3-ethernet\n' >"$tmp/connections"
: >"$tmp/active"

cat >"$fakebin/nmcli" <<EOF
#!/usr/bin/env bash
# nmcli de mentira: el estado de "activo" vive en un archivo del test.
state=$tmp
case "\$*" in
    *"connection show --active"*) cat "\$state/active" ;;
    *"-f NAME,TYPE connection show"*) cat "\$state/connections" ;;
    *"-f GENERAL.DEVICES connection show"*) printf 'GENERAL.DEVICES:tun0\n' ;;
    *"-f IP4.ADDRESS device show"*) printf 'IP4.ADDRESS[1]:10.81.0.6/24\n' ;;
    *"-f IP4.GATEWAY device show"*) printf 'IP4.GATEWAY:10.81.0.1\n' ;;
    *"connection up"*) printf 'VPN uno\n' >>"\$state/active"; printf 'ok\n' ;;
    *"connection down"*) : >"\$state/active"; printf 'ok\n' ;;
    *) printf '' ;;
esac
EOF
chmod +x "$fakebin/nmcli"

# apps de mentira: Teams y Remmina "instalados" (tocan un archivo al abrirse)
# sin herramientas externas: sólo redirección del shell
printf '#!/bin/sh\n: > %s/teams-opened\n' "$tmp" >"$fakebin/teams-for-linux"
printf '#!/bin/sh\n: > %s/remmina-opened\n' "$tmp" >"$fakebin/remmina"
chmod +x "$fakebin/teams-for-linux" "$fakebin/remmina"

# PATH del helper: los fakes primero y las herramientas justas.
for tool in bash sh jq awk sed cut head grep basename cat ls env setsid nohup sort uniq tr mkdir; do
    real=$(command -v "$tool" 2>/dev/null) || continue
    ln -sf "$real" "$fakebin/$tool"
done

fail=0
ok() { printf '\033[1;32m[ok]\033[0m   %s\n' "$1"; }
bad() {
    printf '\033[1;31m[fail]\033[0m %s\n' "$1" >&2
    fail=1
}
run() { env PATH="$fakebin" "$HELPER" "$@" 2>&1; }

printf 'work-vpn (helper del widget)\n'

[[ $(run list) == "VPN uno" ]] && ok "lista las VPN que conoce NetworkManager" || bad "lista las VPN"

[[ $(run status --json | jq -r .backend) == "nmcli" ]] && ok "el estado sale en json" || bad "el estado sale en json"
[[ $(run status --json | jq -r .connected) == "false" ]] && ok "sin VPN activa dice desconectado" || bad "dice desconectado"
run status | grep -q "VPN disconnected" && ok "y también en texto (compatibilidad)" || bad "y también en texto"

run up >/dev/null
[[ $(run status --json | jq -r .connected) == "true" ]] && ok "up conecta (y el estado lo refleja)" || bad "up conecta"
[[ $(run status --json | jq -r .ip) == "10.81.0.6" ]] && ok "lee la IP del túnel" || bad "lee la IP del túnel"
[[ $(run status --json | jq -r .gateway) == "10.81.0.1" ]] && ok "lee el gateway" || bad "lee el gateway"
[[ $(run status | head -1) == "VPN connected (VPN uno)" ]] && ok "el texto también cambia" || bad "el texto cambia"

run down >/dev/null
[[ $(run status --json | jq -r .connected) == "false" ]] && ok "down desconecta" || bad "down desconecta"
run toggle >/dev/null
[[ $(run status --json | jq -r .connected) == "true" ]] && ok "toggle conecta si estaba abajo" || bad "toggle conecta"
run toggle >/dev/null
[[ $(run status --json | jq -r .connected) == "false" ]] && ok "y baja si estaba arriba" || bad "y baja"

# Apps: las de mentira están, y el filtro de la config manda.
apps=$(run apps)
printf '%s\n' "$apps" | grep -qx teams && printf '%s\n' "$apps" | grep -qx remmina \
    && ok "detecta las apps instaladas (Teams y Remmina)" || {
    bad "detecta las apps instaladas"
    printf '       %s\n' "$apps" >&2
}
[[ $(run apps --json | jq -r '.[0].icon | length > 0') == true ]] && ok "cada app trae su ícono" || bad "cada app trae su ícono"

printf 'apps=remmina\n' >"$XDG_CONFIG_HOME/work-vpn/config"
[[ $(run apps | tr '\n' ',') == "remmina," ]] && ok "la config filtra las apps" || bad "la config filtra las apps"
printf 'connection=VPN uno\n' >>"$XDG_CONFIG_HOME/work-vpn/config"

# Idioma: inglés por defecto (es el idioma de publicación) y cambiable desde el
# helper, que es lo mismo que hace el botoncito del encabezado del widget.
[[ $(run status --json | jq -r .detail) == "Disconnected" ]] && ok "el detalle del estado sale en inglés" || bad "el detalle del estado en inglés"
[[ $(run lang) == "en" ]] && ok "sin archivo de idioma, inglés" || bad "el idioma por defecto"
[[ $(run apps --json | jq -r '.[0].label') == "Remote desktop" ]] && ok "y las apps también" || bad "las apps en inglés"
run lang es >/dev/null
[[ $(run lang) == "es" ]] && ok "lang es lo cambia" || bad "lang es lo cambia"
[[ $(cat "$XDG_CONFIG_HOME/work-vpn/lang") == "es" ]] && ok "y lo deja escrito en ~/.config/work-vpn/lang" || bad "el archivo de idioma"
[[ $(run status | head -1) == "VPN desconectada" ]] && ok "el texto del estado sale en español" || bad "el texto del estado en español"
[[ $(run status --json | jq -r .detail) == "Desconectada" ]] && ok "el json también" || bad "el json en español"
[[ $(run apps --json | jq -r '.[0].label') == "Escritorio remoto" ]] && ok "y las etiquetas de las apps" || bad "las etiquetas de las apps"
run up >/dev/null
[[ $(run status | head -1) == "VPN conectada (VPN uno)" ]] && ok "conectada, en español" || bad "conectada en español"
run down >/dev/null
run lang en >/dev/null
[[ $(run status | head -1) == "VPN disconnected" ]] && ok "lang en vuelve al inglés" || bad "lang en vuelve al inglés"
[[ $(run apps --json | jq -r '.[0].label') == "Remote desktop" ]] && ok "las apps también vuelven" || bad "las apps vuelven"
run lang fr >/dev/null 2>&1 && bad "un idioma que no existe falla" || ok "un idioma que no existe falla"

# el lanzamiento es en segundo plano a propósito: se espera un momento
wait_for() { # wait_for <archivo>
    local i
    for ((i = 0; i < 30; i++)); do
        [[ -e $1 ]] && return 0
        sleep 0.1
    done
    return 1
}

run open teams >/dev/null
wait_for "$tmp/teams-opened" && ok "open lanza la app" || bad "open lanza la app"
rm -f "$tmp/teams-opened"
run --teams >/dev/null
wait_for "$tmp/teams-opened" && ok "el alias viejo --teams también" || bad "el alias viejo --teams"
run --vpn-only >/dev/null
[[ $(run status --json | jq -r .connected) == "true" ]] && ok "el alias viejo --vpn-only conecta" || bad "el alias --vpn-only"
run --down >/dev/null
[[ $(run status --json | jq -r .connected) == "false" ]] && ok "y --down desconecta" || bad "y --down"

run open inventada >/dev/null 2>&1 && bad "una app que no existe falla" || ok "una app que no existe falla"
run inventado >/dev/null 2>&1 && bad "un comando desconocido falla" || ok "un comando desconocido falla"

if ((fail)); then
    printf '\033[1;31mhelper: hay fallos\033[0m\n' >&2
    exit 1
fi
printf '\033[1;32mhelper: todo bien\033[0m\n'

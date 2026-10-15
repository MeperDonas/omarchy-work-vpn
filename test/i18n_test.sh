#!/usr/bin/env bash
# El diccionario tiene que estar completo en los dos idiomas, el inglés tiene que
# ser el idioma por defecto (es el de publicación) y el widget no puede quedarse
# con textos crudos: si algo no pasa por i18n.js, no se traduce.
# Corre en CI, sin Omarchy.

set -euo pipefail
cd "$(dirname "${BASH_SOURCE[0]}")/.."

fail=0
ok() { printf '\033[1;32m[ok]\033[0m   %s\n' "$1"; }
bad() {
    printf '\033[1;31m[fail]\033[0m %s\n' "$1" >&2
    fail=1
}

printf 'i18n (inglés y español)\n'

# 1) mismas claves en los dos idiomas
python3 - <<'PY' && ok "en y es tienen las mismas claves" || bad "faltan claves en algún idioma"
import re, sys, pathlib
src = pathlib.Path("i18n.js").read_text()
blocks = {}
for lang in ("en", "es"):
    m = re.search(rf"\n    {lang}: \{{(.*?)\n    \}}", src, re.S)
    if not m:
        print(f"no encontré el bloque de {lang}", file=sys.stderr); sys.exit(1)
    blocks[lang] = set(re.findall(r"^\s*([a-zA-Z][A-Za-z0-9_]*):", m.group(1), re.M))
missing_en = blocks["es"] - blocks["en"]
missing_es = blocks["en"] - blocks["es"]
if missing_en or missing_es:
    print("faltan en en:", sorted(missing_en), "| en es:", sorted(missing_es), file=sys.stderr)
    sys.exit(1)
print(f"{len(blocks['en'])} claves")
PY

# 2) el idioma por defecto es inglés (mercado), se puede cambiar y el helper lo
#    expone igual que el botón
grep -q 'lang: "en"' Panel.qml && ok "el idioma por defecto es inglés" || bad "el idioma por defecto no es inglés"
grep -qE "onTriggered: root\.toggleLang\(\)" Panel.qml && ok "hay un botón para alternar (no dropdown)" || bad "no hay botón que alterne el idioma"
grep -qE 'langProbe' Panel.qml && grep -qE 'root\.helper \+ " lang"' Panel.qml \
    && ok "el panel le pregunta el idioma al helper al arrancar" || bad "el panel no le pregunta el idioma al helper"
grep -qE '^\s+lang\)' bin/work-vpn && ok "el helper expone el idioma (work-vpn lang)" || bad "el helper no expone el idioma"

# 3) nada de textos de UI crudos fuera del diccionario
hits=$(grep -nE '(label|text): *"[^"]*(Conectar|Desconectar|Comprobando|Trabajando|Conectada|Desconectada|Escritorio|IP del túnel)' Panel.qml || true)
if [[ -n $hits ]]; then
    bad "quedaron textos de UI sin traducir en Panel.qml"
    printf '%s\n' "$hits" | sed 's/^/       /' >&2
else
    ok "no quedan textos de UI sin pasar por el diccionario"
fi

if ((fail)); then
    printf '\033[1;31mi18n: hay fallos\033[0m\n' >&2
    exit 1
fi
printf '\033[1;32mi18n: todo bien\033[0m\n'

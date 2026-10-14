# Work connection — Omarchy bar widget

A bar icon for the workday: VPN state, tunnel IP and gateway, and the
connect / disconnect / remote desktop / Teams actions. Everything is done by a
helper CLI; the widget only reads its status and calls it.

```
┌─────────────────────────────┐
│         Work connection     │
│         Connected           │
│  IP Address 10.81.0.6   Gateway 10.81.0.1
│   [Connect]   [Disconnect]  │
│   [Remmina]   [Teams]       │
└─────────────────────────────┘
```

## It needs a helper

The widget is only the UI. The helper is the command that talks to your VPN and
opens your apps; the widget runs it and draws the answer. Any helper works, and
two contracts are supported:

**New (preferred): JSON**

| Command | What it must print |
|---|---|
| `<helper> --status --json` | `{"backend":"…","connected":true,"ip":"10.81.0.6","gateway":"10.81.0.1","detail":"…"}` (only `connected` is required; `gateway` can be empty, WireGuard has none) |
| `<helper> apps --json` | `[{"id":"slack","label":"Slack","icon":"…"}]`, one button per app |
| `<helper> open <id>` | open that app |
| `<helper> --vpn-only` / `<helper> --down` | connect / disconnect (configurable) |

**Old (still works): text.** `<helper> --status` printing the line `VPN conectada`
and the tunnel IP, plus `--vpn-only`, `--down`, `--rdp` and `--teams`. If the JSON
call does not answer, the widget falls back to this for the rest of the session.

## The helper that ships with it

`bin/work-vpn` is included and uses **NetworkManager**, so it covers whatever your
system already knows: OpenVPN, WireGuard, Fortinet, StrongSwan… It also detects the
work apps you have installed (`Slack`, `Microsoft Teams`, `Discord`, `Signal`,
`Remmina`) and gives each one a button.

```bash
work-vpn list           # VPN connections NetworkManager knows
work-vpn status --json  # backend, connected, ip, gateway
work-vpn up | down | toggle
work-vpn apps --json    # installed work apps, with their icon
work-vpn open slack     # open one of them
```

Optional config in `~/.config/work-vpn/config`:

```
connection=My work VPN      # if unset: the active one, or the first VPN found
apps=slack,teams,discord    # if unset: every app it detects
```

It keeps the old flags as aliases (`--status`, `--vpn-only`, `--down`, `--rdp`,
`--teams`), so switching helpers does not change how the widget calls them.

## Settings

`helper`, `label`, `refreshIntervalSec`, `showRemmina`, `showTeams` (from before)
plus: `statusJsonArgs`, `statusTextArgs`, `connectArgs`, `disconnectArgs`,
`appsArgs`, `appOpenArgs`. The defaults are the classic ones, so an existing setup
keeps working untouched; leave `helper` empty to use the bundled `bin/work-vpn`
(e.g. point `helper` at `nmcli connection` and `connectArgs` at `up "My VPN"` if you
prefer talking to NetworkManager yourself).

## Install

```bash
omarchy plugin add <this repo> --enable
omarchy plugin list          # meperdonas.work-vpn · third-party bar-widget
```

Settings (Omarchy settings UI, or inline keys in `~/.config/omarchy/shell.json`):
`helper`, `label`, `refreshIntervalSec`, `showRemmina`, `showTeams`.

## Remove

```bash
omarchy plugin remove meperdonas.work-vpn
```

That removes the plugin from the bar; its settings live in `~/.config/omarchy/shell.json`
(and the helper, its config and its credentials are yours and stay where they are).

## Keep it private

This widget is written for one company's setup. If you publish a copy, **remove
every internal detail first** — VPN profile names, hosts, usernames, subnets.
The defaults shipped here are generic: no host, no profile, no credentials. The
helper owns all of that, and its credential store stays in
`~/.config/openvpn-work/` (never in the plugin).

## License

MIT — see [LICENSE](LICENSE).

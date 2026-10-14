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

The widget is only the UI. The helper must expose:

| Argument | Meaning |
|---|---|
| `--status` | prints the current state (the widget looks for the line `VPN conectada` and the tunnel IP) |
| `--vpn-only` | connect the VPN |
| `--down` | disconnect |
| `--rdp` | open the remote desktop client |
| `--teams` | open Teams |

By default it calls `conectar-trabajo` from `PATH`; set **Helper command** in the
widget settings to point anywhere else.

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

# Chief plugin: bc (BindCaptain remote control)

This directory contains an **optional** Chief plugin that controls a **remote** BindCaptain installation over SSH.

Chief is a separate project. For more information: [https://github.com/randyoyarzabal/chief](https://github.com/randyoyarzabal/chief)

- **Script:** `bc_chief-plugin.sh` — source this from Chief as the `bc` plugin.
- **Full documentation:** [docs/chief-remote-plugin.md](../docs/chief-remote-plugin.md)

## Quick setup

1. Copy `bc_chief-plugin.sh` into your Chief user plugins directory (so Chief loads it as the `bc` plugin).
2. Set for your BindCaptain host:
   - `BC_HOST` — e.g. `root@wolfman.homelab.io`
   - `BC_MANAGER` — e.g. `/opt/bindcaptain/tools/bindcaptain_manager.sh`
3. Load the plugin and run `bc.help`.

See [docs/chief-remote-plugin.md](../docs/chief-remote-plugin.md) for prerequisites, all commands, and troubleshooting.

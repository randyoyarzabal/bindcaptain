# Chief plugin: bc (BindCaptain remote control)

This directory contains an **optional** Chief plugin for BindCaptain: use SSH to a **remote** DNS host when `BC_HOST` is set, or run **locally** on the BindCaptain machine when `BC_HOST` is unset.

Chief is a separate project. For more information: [https://github.com/randyoyarzabal/chief](https://github.com/randyoyarzabal/chief)

- **Script:** `bc_chief-plugin.sh` — source this from Chief as the `bc` plugin.
- **Full documentation:** [docs/chief-remote-plugin.md](../docs/chief-remote-plugin.md)

## Quick setup

1. Copy `bc_chief-plugin.sh` into your Chief user plugins directory (so Chief loads it as the `bc` plugin).
2. Optional: set `BC_HOST` only when Chief runs on a **different** machine than BindCaptain (e.g. `export BC_HOST=root@dns.example.com` for laptop → server over SSH). On the DNS host itself, leave `BC_HOST` unset so commands run locally (no SSH).
3. Set `BC_MANAGER` only if BindCaptain is not under `/opt/bindcaptain` (default: `/opt/bindcaptain/tools/bindcaptain_manager.sh`).
4. Load the plugin and run `bc.help` (after edits, `chief.reload` in an existing Chief shell).

**If `bc.status`, `bc.list`, or other `bc.*` commands are missing** in an already-open Chief shell (for example after you edited the plugin on disk, or Chief started before the plugin was installed), reload Chief’s plugins into memory:

```text
chief.reload
```

Then try `bc.help` again.

See [docs/chief-remote-plugin.md](../docs/chief-remote-plugin.md) for prerequisites, all commands, and troubleshooting.

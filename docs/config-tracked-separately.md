# Tracking `config/` separately from the BindCaptain repo

The BindCaptain repo intentionally **gitignores `config/`** so that
operator-specific zones, IPs, and secrets never land in the public
codebase. Most users will want to keep their config under version
control somewhere private. There are a few patterns that work well.

## Why decouple

- The public BindCaptain repo (this one) is generic; everything
  site-specific lives outside it.
- Your zone files change frequently (every record edit bumps the
  serial); the BindCaptain code itself changes rarely.
- Different teams may share BindCaptain code but maintain separate
  config repositories.

## Pattern: symlink `config/` to a directory in a separate repo

```bash
# Suppose you keep operational state in a private repo at /opt/ops
# (Gitea, GitLab, or anywhere — just not the public BindCaptain repo).
git clone <your-private-repo-url> /opt/ops

# Point BindCaptain's expected config path at a subdirectory of it:
ln -s /opt/ops/dns/bindcaptain /opt/bindcaptain/config

# Verify
readlink /opt/bindcaptain/config
```

After this, `bindcaptain.sh` and the manager continue to look at
`/opt/bindcaptain/config` (the script's default), but everything they
read or write actually lives in `/opt/ops/dns/bindcaptain` — which is
tracked in your private repo.

You can also point at the path directly without a symlink:

```bash
export BINDCAPTAIN_CONFIG_PATH=/opt/ops/dns/bindcaptain
sudo -E ./bindcaptain.sh run
```

## Symlink gotchas (handled in v1.2.0+)

If you use the symlink pattern, the BindCaptain manager has to follow
the symlink when walking zone files. Two places where this matters
have been fixed in v1.2.0:

1. **`__chown_zone_files_for_named` and `__refresh_dns`** use
   `find -L` so the recursive walk follows the top-level symlink.
   Without this, every chown on `/opt/bindcaptain/config/...` silently
   no-op'd, leaving newly-written zone files unreadable by `named`,
   which caused zones to silently fail to load on reload.
2. **`prepare_config` in `bindcaptain.sh`** resolves the path with
   `readlink -f` before chmod/chown, for the same reason.

If you're on v1.1.x or earlier and using a symlinked `config/`, you may
see "permission denied" errors from `named` at reload time and
secondaries that never advance their serial. Upgrade to v1.2.0 (or
manually `chown -R named:named` the real path after every edit).

## Pattern: pull config from a separate repo at deploy time

If you don't want a symlink, you can pull config in as part of your
deploy:

```bash
# Cron, systemd timer, or your CI:
cd /opt/ops && git pull
rsync -a --delete /opt/ops/dns/bindcaptain/ /opt/bindcaptain/config/
sudo systemctl reload bindcaptain
```

This avoids the symlink entirely; the trade-off is that you have two
copies of your config and need to remember to re-sync after edits.

## Pattern: BindCaptain inside a larger ops repo

If you already have a private "ops" or "common" repo that contains
many roles' config, you can clone BindCaptain into a subdirectory of
that repo:

```
<ops-repo>/
├── ansible/
├── chief_plugins/
├── dns/
│   └── bindcaptain/         # ← BindCaptain code as a submodule or subtree
│       ├── ...
│       └── config -> ../bindcaptain-config/   # config sym-linked alongside
├── bindcaptain-config/
│   ├── named.conf
│   └── example.com/
└── ...
```

Your private repo is the deploy target; BindCaptain itself stays a
clean upstream submodule/subtree.

## What goes where

| Lives in BindCaptain repo | Lives in your private config tree |
|---|---|
| `bindcaptain.sh`, `tools/`, `chief-plugin/` | `named.conf` |
| `Containerfile`, systemd unit | Zone files (`*.db`) |
| `docs/`, `config-examples/` | `data/`, `logs/` (runtime) |
| `VERSION`, `CHANGELOG.md` | `rndc.conf`, key files |

Anything that contains real IPs, hostnames, or secrets should be in
the private side.

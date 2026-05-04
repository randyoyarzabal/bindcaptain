# Changelog

All notable changes to BindCaptain are documented here. The format is based
on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.2.1] - 2026-05-03

### Fixed
- `bc.*` wildcard owner support across every command. Previously,
  `validate_relative_dns_name` rejected `*` and `_` labels outright, so
  `bc.delete *.apps.example.com` failed at the gate, and creating
  underscore-name TXT records (e.g. `_dmarc`, `_acme-challenge`) was
  blocked.
  - Validator now accepts a leftmost-only `*` (RFC 4592) and labels
    starting with `_` (RFC 8552); rejects illegal forms like `host*`,
    `*.*`, empty labels.
  - `bc.create_record` / `bc.create_cname` existence checks and
    in-place delete via `grep`/`sed` now escape `*` and `.` as
    literals (new `__regex_escape_owner` helper); a wildcard owner
    no longer accidentally matches sibling records.
  - PTR sync skips wildcard A records — reverse PTRs are not defined
    for wildcard owners.
- `bc.list` JSON: SOA-minimum TTL fallback so RRs with no explicit
  TTL and no `$TTL` directive surface a non-null TTL; CR characters
  in zone files are stripped before parsing.

## [1.2.0] - 2026-05-02

### Added
- `BINDCAPTAIN_NETWORK_MODE` env var (`bridge` default, `host`). Host mode
  required when this server NOTIFIES external secondaries. See
  `docs/networking.md`.
- `bc.update` command with `--json` input and output. Supports A, CNAME, TXT.
  Implemented as delete-then-create in one remote session so BIND reloads once.
- `bc.create`, `bc.delete`, `bc.refresh`, `bc.sync_ptr`: human-friendly summary
  output (status / host / record / reload) with `--json` for machine
  consumption.
- Explicit `rndc notify <zone>` after every successful reload (belt-and-
  suspenders for edge cases where automatic NOTIFY is suppressed).
- System-logger integration: every record action is sent to syslog/journald
  with tag `bindcaptain`. Reachable via `journalctl -t bindcaptain` or
  `/var/log/messages`. Shadow file at `${LOG_DIR}/bind_manager.log` is kept
  and rotated weekly via `config-examples/bindcaptain.logrotate`.
- `BINDCAPTAIN_PTR_NETWORKS` env override for managed reverse-zone subnets.
- `VERSION` file as single source of truth; surfaced in manager headers,
  `bc.help`, and the Chief plugin's load banner.
- `CHANGELOG.md` (this file).
- `docs/networking.md`.
- `docs/config-tracked-separately.md` — pattern for keeping zone/config
  in a private repo, symlinked into BindCaptain.
- `config-examples/bindcaptain.env.example`.
- `config-examples/bindcaptain.logrotate`.

### Changed
- `bc.create_cname` and `bc.create_txt` are now one-line shortcuts that
  forward to `bc.create CNAME …` / `bc.create TXT …` (single source of
  truth for create logic).
- `bc.sync_ptr_from_forwards` renamed to `bc.sync_ptr` at the plugin
  surface (manager-side function name unchanged).
- `__ptr_managed_network_lines` auto-discovers reverse zones from the
  user's `named.conf` instead of hardcoding subnets. Override via
  `BINDCAPTAIN_PTR_NETWORKS`.
- `log_message` no longer tee's to stdout; status messages go through
  `print_status` only. Eliminates double-print in captured-output paths.
- README: TL;DR install, version + license badges, GitHub repo link,
  documentation index updated.

### Fixed
- `__chown_zone_files_for_named` and the `__refresh_dns` chown path now
  use `find -L` so they follow `BIND_DIR` when it's a symlink. Prior
  behavior silently no-op'd, leaving newly-written zone files
  `0600 root:root` and unreadable by `named` — which caused zones to
  fail to load on reload, blocking secondaries from receiving updates.
- `prepare_config` resolves `BINDCAPTAIN_CONFIG_PATH` with `readlink -f`
  before `chown`. Same root cause as above; affected installs whose
  config path is a symlink.
- `bindcaptain.sh detect_bind_ip`: removed hardcoded fallback IP; now
  returns `any` when `listen-on` doesn't pin a specific address.
- `bc.update` exit code is the source of truth for status; intermediate
  warnings (e.g. pre-delete miss during upsert) no longer flip the
  rendered status to error when the operation actually succeeded.

### Security
- Repository scrubbed of site-specific addresses, hostnames, and
  domain names. All examples now use RFC 5737 (`192.0.2.0/24`) /
  RFC 1918 (`10.0.0.0/8`) per documentation convention.
- GitHub history rewritten to a single root commit (private Gitea
  mirror retains full history). New contributors see a clean tree.

## [1.0.0] - 2026-04-25

Initial public release. Containerized BIND 9.16+ DNS server with:
- Podman-based deployment, systemd service integration
- Manager script (`bindcaptain_manager.sh`) for zone CRUD
- Chief user-plugin (`bc.*`) for local and remote management
- Auto-generated PTR zones from forward A records
- Configuration wizard (`tools/config-setup.sh`)
- Containerfile, named.conf templates, example zones

[Unreleased]: https://github.com/randyoyarzabal/bindcaptain/compare/v1.2.1...HEAD
[1.2.1]: https://github.com/randyoyarzabal/bindcaptain/releases/tag/v1.2.1
[1.2.0]: https://github.com/randyoyarzabal/bindcaptain/releases/tag/v1.2.0
[1.0.0]: https://github.com/randyoyarzabal/bindcaptain/releases/tag/v1.0.0

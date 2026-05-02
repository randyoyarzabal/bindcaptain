# Secondaries, NOTIFY, and rndc

This page covers what BindCaptain does to keep authoritative secondaries
(slaves) in sync, and the gotchas you may hit if NOTIFY isn't reaching
them.

## Why secondaries may lag

Authoritative secondaries (BIND slaves, Synology DNS Server, PowerDNS,
etc.) need all of the following to update on time:

1. **Serial bump.** The primary's zone SOA serial must **increase** on
   each change. BindCaptain's `__increment_serial` does this; avoid
   hand-editing the serial to a lower or equal value.

2. **NOTIFY reaches the secondary.** The primary must successfully send
   NOTIFY (UDP/53) to each secondary. With `notify explicit;` and an
   `also-notify { ... };` list, only the listed addresses are notified
   (not every NS in the zone). This matches setups where the SOA/NS
   advertised name is only the primary.

3. **NOTIFY source IP is reachable from the secondary.** Some
   secondaries restrict `master` to a specific IP. If your NOTIFY is
   sourced from an unexpected address (e.g. a container bridge IP
   instead of your lab-facing IP), the secondary may silently drop it.
   See [networking.md](networking.md) for the container-side trade-offs
   and the `BINDCAPTAIN_NETWORK_MODE=host` switch.

4. **Firewall / routing.**
   - **NOTIFY**: UDP/53 from primary to secondaries.
   - **Zone transfer (AXFR/IXFR)**: TCP/53 from secondaries to primary
     and responses back. If TCP/53 is blocked or asymmetric, updates
     look "stuck" or intermittent.

5. **`allow-transfer`.** On the primary, `allow-transfer` must list the
   secondaries. On the secondary, the slave must allow the primary as a
   `master` / `allow-notify` (Synology DNS Server: "Allow zone transfer
   from" / master IP).

6. **`rndc` reload path.** If `rndc reload` never worked (no `controls`
   in `named.conf`, or `/etc/rndc.key` not readable by `named`),
   operations fall back to SIGHUP. That reloads zone data, but enabling
   a proper `rndc` control channel is recommended for predictable
   NOTIFY behavior. Use:
   - `config-examples/named-fragment-rndc.conf`
   - `tools/ensure-rndc-controls.sh` (and rebuild the image so
     `/etc/rndc.key` is `root:named` + `640`, or run the script to fix
     a running container).

## Belt-and-suspenders: explicit `rndc notify` after every change

After a successful reload, BindCaptain calls `rndc notify <zone>` for
every discovered forward zone. BIND already issues NOTIFY on serial
change automatically, but the explicit call covers edge cases (in-
container source-IP binding, NS/MNAME pairing quirks, reload races).
Failures are non-fatal: the reload itself already succeeded.

## "Instant" updates vs TTL

- **On the primary itself**: after a `bc` change, BindCaptain calls
  `sync` (flush disk) then `rndc reload` (full) so in-memory data
  matches the file on the primary host immediately.
- **On other clients (resolvers, your laptop's default DNS, public
  resolvers)**: those still honor the **TTL** from the last cached
  answer. That can be hours (e.g. 86400). For an end-to-end check,
  query the authoritative address directly:

  ```bash
  dig @<primary-ip> name.example.com A
  ```

## One-time: enable rndc (recommended)

```bash
sudo MERGE_NAMED=1 BINDCAPTAIN_CONFIG_PATH=/path/to/your/config \
     ./tools/ensure-rndc-controls.sh
sudo podman restart bindcaptain   # or: systemctl restart bindcaptain
podman exec bindcaptain /usr/sbin/rndc status   # should succeed
```

## Checking the SOA serial on each side

```bash
dig @<primary-ip>   example.com SOA +noall +answer
dig @<secondary-ip> example.com SOA +noall +answer
```

If a secondary's serial is older than the primary's, NOTIFY didn't get
through (or was ignored) and the secondary is on its retry timer. Force
the issue with `rndc notify <zone>` on the primary, or `rndc retransfer
<zone>` on the secondary if it has rndc.

## See also

- [networking.md](networking.md) — container network modes and the
  source-IP gotcha that causes silent NOTIFY drops.
- `dns-operations.md` — day-to-day record management with `bc.*`.

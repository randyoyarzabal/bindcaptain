# Secondaries (172.25.50.122 / 123) and rndc

## Why secondaries may lag

Authoritative secondaries (including Synology DNS Server) need:

1. **Surname / serial** The primary zone SOA serial must **increase** on each change. BindCaptain’s `__increment_serial` does this; avoid hand-editing the serial to a lower value.

2. **NOTIFY** The primary must send NOTIFY to the secondaries. With `notify explicit;` and `also-notify { 172.25.50.122; 172.25.50.123; };`, only those addresses are notified (not every NS in the zone). This matches a setup where the SOA/NS is only the primary name.

3. **Source address** In `options`, set `notify-source` and `transfer-source` to the **lab face** IP the secondaries expect (e.g. `172.25.50.156`). If NOTIFY or AXFR is sourced from a bridge/Podman address, the slave may **drop** it.

4. **Firewall / routing**
   - **NOTIFY** is typically **UDP 53** from primary to secondaries.
   - **Zone transfer (AXFR/IXFR)** uses **TCP 53** from secondaries to primary (and responses back). If TCP 53 is blocked or asymmetric, updates look “stuck” or intermittent.

5. **allow-transfer** On the primary, `allow-transfer` must list the secondaries. On the secondary, the slave must allow the primary as a master/allow-notify (Synology: check “Allow zone transfer from” / master IP).

6. **rndc / reload path** If `rndc reload` never worked (no `controls` in `named.conf`, or `/etc/rndc.key` not readable by `named`), operations relied on SIGHUP to reload zone files. That reloads data, but **enabling a proper `rndc` control channel** is still recommended for `rndc reload` / `rndc reconfig` and for predictable NOTIFY behavior. Use:
   - `config-examples/named-fragment-rndc.conf`
   - `tools/ensure-rndc-controls.sh` (and rebuild the image so `/etc/rndc.key` is `root:named` + `640`, or run the script to fix a running container).

## “Instant” updates vs TTL

- **This nameserver (172.25.50.156):** After `bc` changes a zone file, BindCaptain runs **`rndc reload <zone>`** for the affected zone(s) so in-memory data matches the file **immediately** on that host.
- **Other clients / 8.8.8.8 / your laptop’s “default” DNS:** Those still follow **TTL** from the last cached answer. That can be **hours** (e.g. 86400). For a true end-to-end check, query the authoritative address: `dig @172.25.50.156 name.example.com A`.

## One-time: enable rndc (recommended)

1. `sudo MERGE_NAMED=1 BINDCAPTAIN_CONFIG_PATH=/path/to/your/config ./tools/ensure-rndc-controls.sh`
2. `sudo podman restart bindcaptain` (or `systemctl restart bindcaptain`) so `named` loads the new `controls` block.
3. `podman exec bindcaptain /usr/sbin/rndc status` should succeed (connects to `127.0.0.1:953` **inside** the container).

## Verify secondaries

On each secondary, compare SOA serial to the primary, e.g.:

```bash
dig @172.25.50.156 reonetlabs.us SOA +noall +answer
dig @172.25.50.122 reonetlabs.us SOA +noall +answer
```

Serials should match after NOTIFY + transfer completes.

---

See also: comments in your production `named.conf` about `notify-source` and DSM `allow-notify`.

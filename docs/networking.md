# Container networking modes

BindCaptain runs `named` inside a Podman container. Two network modes
are supported, controlled by the `BINDCAPTAIN_NETWORK_MODE` environment
variable when invoking `bindcaptain.sh run` (or via the systemd unit's
`Environment=` directive):

| Mode    | What it does                                                                     | When to use it                                                                          |
|---------|----------------------------------------------------------------------------------|-----------------------------------------------------------------------------------------|
| `bridge` (default) | Container has a private CNI/bridge IP. Host:port is forwarded into the container with `-p <host-ip>:53:53`. | Single-host caching/recursive use; lab where this server doesn't NOTIFY external secondaries. |
| `host`             | Container shares the host's network namespace. `named` binds the host's interfaces directly. | **Any deployment where this server is a primary that NOTIFIES external secondaries.**  |

```bash
# One-shot
BINDCAPTAIN_NETWORK_MODE=host sudo ./bindcaptain.sh run

# Persistent: add to the systemd unit drop-in
sudo systemctl edit bindcaptain
# [Service]
# Environment=BINDCAPTAIN_NETWORK_MODE=host
```

## Why bridge mode breaks NOTIFY to external secondaries

In bridge mode the container only sees its private CNI IP (e.g.
`10.88.0.x`) and `lo`. The host's lab-facing IP — the one secondaries
have configured as `master` — is not present in the container's network
namespace.

When `named` prepares an outbound NOTIFY, it picks a source address
based on the zone's NS / SOA `MNAME` (and any `notify-source` you
configured in `options { }`). If that source address isn't in the
container's namespace, the kernel's `bind()` syscall fails with
`EADDRNOTAVAIL` and `named` **silently drops the packet** with only an
internal `dns_request_createvia: failed address not available` log
line at debug level 3.

Symptoms:
- `journalctl -t bindcaptain` shows `sending notify to <slave-ip>#53`
  but no follow-up "sent" line.
- `tcpdump` on the host shows zero NOTIFY packets to the secondaries.
- Secondaries stay on their old serial until their refresh timer
  expires (often hours).

Host mode eliminates the problem because `named` binds directly to a
real host interface; the source IP its socket uses is one the
secondaries already trust.

## Trade-offs

- **Isolation.** Bridge mode keeps `named` in its own namespace; host
  mode shares the host's. Most operators consider this acceptable for
  a DNS server (it's already an `inet` daemon binding port 53).
- **Port conflicts.** Host mode requires nothing else on the host to
  bind port 53. If you run `systemd-resolved` or `dnsmasq`, disable or
  reconfigure them first.
- **Multiple BindCaptain instances on one host.** Use bridge mode and
  forward different host IPs to each container. Host mode allows only
  one primary per host.

## Verifying NOTIFY actually reaches secondaries

```bash
# On the primary
podman exec bindcaptain rndc trace 3
podman exec bindcaptain rndc notify example.com
journalctl -t bindcaptain --since '10 sec ago' | grep -E 'notify|createvia'
```

If you see `sending notify to <ip>` followed by `sent notify to <ip>`
(at debug 3), and no `createvia: failed address not available`, NOTIFY
left the host. If only the first appears, you're hitting the
`EADDRNOTAVAIL` path described above — switch to host mode.

You can also `tcpdump` the secondary's interface to confirm packets
arrive:

```bash
sudo tcpdump -i any -nn 'src host <primary-ip> and port 53'
```

## Related

- [secondary-notify-and-rndc.md](secondary-notify-and-rndc.md) — the
  end-to-end NOTIFY / AXFR plumbing.
- [installation.md](installation.md) — first-time setup.
- [systemd-service.md](systemd-service.md) — running BindCaptain under
  systemd.

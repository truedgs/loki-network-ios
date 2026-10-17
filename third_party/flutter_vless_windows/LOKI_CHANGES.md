# LOKI Network Windows changes

This local copy of flutter_vless_windows 1.1.6 retains the upstream MIT license.
It is overridden for Windows only; Android and iOS use their own engines.

- Pass `--config` to tun2socks. The bundled pflag executable interprets the
  upstream `-config` argument as `-c onfig` and exits before creating Wintun.

- Set HTTP and HTTPS system proxies to the actual HTTP inbound port after port
  allocation, and SOCKS to the actual SOCKS inbound port.
- Restore the prior system proxy if Xray exits or startup fails.
- Persist a recovery snapshot before changing WinINet settings, and recover it
  on the next launch after an abnormal app exit.
- Do not create WFP blocking filters. The user explicitly requested fail-open
  networking during connect, disconnect, and failure. Clear only legacy filters
  belonging to the upstream plugin's exact provider GUID.
- Verify remote HTTPS forwarding through Xray before enabling proxy or capture
  routes. Use Windows' system curl with a private configuration file. A missing
  curl or unavailable probe fails startup before network settings change.
- Stop and remove capture routes when forwarding fails; do not loop behind a
  retained traffic barrier. Normal shutdown explicitly stops the tunnel.
- Migrate only this plugin's own persistent filters when starting the tunnel.
- Dispatch native method replies and status events through the root window on
  Flutter's platform thread, rather than posting replies to the child view or
  sending status directly from a worker thread. Join the old status timer before
  starting another one.

The app passes one SOCKS listener in Tunnel mode, as required by the upstream
protected tunnel implementation. Proxy mode receives HTTP and SOCKS listeners.

The tunnel is IPv4-only; without the old WFP kill switch, physical IPv6 can go
direct. This fork does not promise leak prevention or zero outage during route
transitions. Windows curl must be available in the system directory.

## Windows runtime verification (2026-10-08)

Reviewed upstream commit `032292aa006fcec4b5929af91274826931b09d37`:
Dart controller, Shadowsocks parser, method-channel adapter, Windows plugin,
manager, proxy/tunnel services, config preparation, protected runtime, process
launcher, packet-path probe, WFP policy, and Windows runtime smoke-test harness.
The `-config` bug is present in upstream `windows/vpn_service.cpp` too.

The opt-in `loki_tunnel_smoke` harness uses the production `VpnService`, existing
bundled Xray 26.3.27 and tun2socks, and the backend's available free config.
Two tunnel starts passed HTTPS bound to the TUN address and changed the public
IPv4 address. Both disconnects restored direct HTTPS and the original public
IPv4. An unreachable server failed startup without blocking direct HTTPS.
No runtime upgrade was necessary for this tested configuration.

These tests do not establish IPv6 protection, every server/protocol, or behavior
on every Windows installation. The harness requires explicit invocation and UAC;
ordinary CTest does not modify network settings.

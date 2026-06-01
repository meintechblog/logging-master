# Uptime-Monitor (Dual-Vantage) — meintechblog.de

Erkennt zuverlässig, ob meintechblog.de **wirklich down** ist oder nur die **Heim-IP gebannt**
wurde (netcup fail2ban). Anlass: Am 2026-06-01 sperrte ein zu aggressiver Blog-Scan die Haus-WAN-IP
→ die Seite wirkte aus dem LAN „down", lief extern aber normal (HTTP 200).

## Prinzip — zwei Sichtachsen

| Vantage | Pfad | misst |
|---|---|---|
| **internal** | direkter `curl` von CT143 (egresst über Haus-NAT) | Heim-Erreichbarkeit → fängt den IP-Ban |
| **external** | über Public-Proxy (codetabs primary, allorigins fallback) | globale Erreichbarkeit aus sauberer Off-Home-IP |

**Alert-Logik (debounced, 2 aufeinanderfolgende Fails ≈ 20min gegen Flapping):**
- `internal=fail` & `external=ok` → **`home_ip_banned`** (actionable: Plesk-Unban/Whitelist bzw. bantime abwarten)
- `external=fail` → **`outage`** (echter Ausfall)
- beide `ok` → still (löst aktiven Alert auf)
- alle Proxies proxy-level tot → `global=unknown`, **kein** Outage-Alert (False-Positive-Schutz)

„up" = HTTP 2xx/3xx **UND** Body enthält den Marker `Technik-Tipps` (fängt WSOD/Parking-Seiten,
die mit HTTP 200 trotzdem kaputt sind).

## Wo / wie

- **Host:** CT143 (Hallbude, `192.168.3.70`) — bewusst auf logging-master-Infra, nicht auf der Blog-App-Box.
- **Script:** `/opt/uptime-monitor/monitor.sh`
- **Schedule:** systemd-Timer `uptime-monitor.timer` → alle 10 min (1 Req/Vantage/10min, triggert kein fail2ban).
- **Frequenz/UA:** low-freq, eigener User-Agent `logging-master-uptime/1.0`.
- **State:** `/opt/uptime-monitor/state/` (Debounce-Counter, aktiver Alert, `monitor.log`).
- **Token:** scoped read+write nur auf Bucket `uptime`, `secrets/.influx-uptime` (chmod 600).

## Datenmodell (InfluxDB, Org `hallbude`, Bucket `uptime`, infinite Retention)

```
uptime_check,target=meintechblog.de,vantage=internal              reachable,status_code,latency_ms,marker_ok
uptime_check,target=meintechblog.de,vantage=external,proxy=<name> reachable,status_code,latency_ms,marker_ok,proxy_ok
uptime_alert,target=meintechblog.de,kind=home_ip_banned|outage    active,consecutive
```
(`proxy_ok=0` = externe Vantage „unknown", nicht „down".)

## Alert-Routing

Kein Auto-WhatsApp/Telegram-Push (Policy: Pushes sind opt-in). Alerts landen in InfluxDB + Log;
ein „Heim-IP gebannt"-Push an Jörg ist eine opt-in-Frage, die der Hub (agent-master) bündelt.

## Roadmap

- **v2 — eigene Off-Home-Sonde statt Dritt-Proxy:** externe Vantage auf `curl`-over-SSH von einem
  echt-remote Host umstellen (Kandidat CT111/wgsrv6, falls Off-Home-Egress ≠ Haus-WAN-IP bestätigt ist).
  Killt die Public-Proxy-Abhängigkeit. Non-urgent; v1 (codetabs) ist voll tragfähig.

# Stolperfalle: UniFi-Suricata-IPS blockt SSH zu VPN-Hosts

Relevant, wenn ein Proxmox-Host **über einen Site-to-Site-WireGuard-Tunnel**
hinter einer UniFi Dream Machine erreicht wird (z. B. der Host `172.25.0.2`).

## Symptom

- Nach mehreren schnellen SSH-Connects bricht SSH zum VPN-Host ab
- Reconnects laufen in Timeout (`port 22 closed`)
- ICMP-Ping geht weiter, PVE-Web (`:8006`) bleibt erreichbar
- Nur **Port 22** ist betroffen

## Ursache

Die UniFi-UDM (`192.168.3.1`, „Hallbude") hat Suricata IDS/IPS aktiv. Mehrere
schnelle TCP-Connects auf Port 22 werden als Brute-Force-Verdacht klassifiziert;
die Verbindungs-Tupel landen im Kernel-ipset `ips` und werden gedroppt. Suricata
unterscheidet dabei nicht zwischen Internet-Traffic und vertrauenswürdigem
VPN-Verkehr.

## Sofort-Fix

```bash
ssh root@192.168.3.1 'ipset flush ips'
```

## Persistenter Fix

Auf der UDM läuft ein Boot-Hook `/data/on_boot.d/15-allow-vpn-subnets.sh`, der
einen Watchdog `/usr/local/bin/vpn-ips-cleaner.sh` startet. Dieser entfernt alle
20 Sekunden alle `ips`-Einträge, deren Quell- oder Ziel-IP in einem bekannten
VPN-Subnetz liegt.

Aktiver Regex (Stand 2026-05-21):

```
VPN_REGEX="(192\.168\.(2|4|11|13|20|41|42|178)|172\.25\.0)\."
```

Das Subnetz `172.25.0.0/24` (Proxmox-Host `172.25.0.2`, wgsrv6) wurde am
2026-05-21 während der InfluxDB-Einrichtung ergänzt.

### Neues VPN-Subnetz hinzufügen

`/data/on_boot.d/15-allow-vpn-subnets.sh` editieren → `VPN_REGEX` erweitern →
Hook neu ausführen (`/data/on_boot.d/15-allow-vpn-subnets.sh`).

## Hinweis

Der Hallbude-Host `proxi1` (`192.168.3.2`) ist **nicht** betroffen — er liegt im
selben LAN wie die UDM, kein VPN-Tunnel, kein IPS-Drop.

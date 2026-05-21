# Setup-Historie

Chronologische Dokumentation der eingerichteten InfluxDB-Instanzen.

---

## 2026-05-21 — Instanz 1: 172.25.0.2 (wgsrv6)

**Proxmox-Host:** `172.25.0.2` (PVE 9.0.3, erreichbar über WireGuard-Tunnel `wgsrv6`)

| Parameter | Wert |
|---|---|
| CT-ID | 111 |
| Hostname | `influxdb-master` (urspr. `influxdb`, umbenannt 2026-05-21) |
| Template | Debian 12 (`debian-12-standard_12.7-1`) |
| Specs | 2 cores / 4096 MB RAM / 1024 MB Swap / 32 GB Disk |
| Storage | `local-lvm` |
| Netzwerk | statisch `172.25.0.111/24`, GW `172.25.0.1`, vmbr0 |
| InfluxDB | v2.9.1 OSS (apt-repo `repos.influxdata.com/debian stable`) |
| Org | `meintechblog` |
| Bucket | `default` (Retention unbegrenzt) |

**Stolperfalle:** Das Template `debian-13-standard_13.1-2` wurde von der
`pve-container`-Version auf PVE 9.0.3 nicht akzeptiert
(`unsupported debian version '13.1'`) → Fallback auf Debian 12.

**Stolperfalle 2:** Während der Einrichtung brach SSH zum Host wiederholt ab.
Ursache: Suricata-IPS auf der UniFi-UDM. Siehe
[`suricata-ssh-block.md`](suricata-ssh-block.md).

---

## 2026-05-21 — Instanz 2: proxi1 (Hallbude)

**Proxmox-Host:** `proxi1` = `192.168.3.2` (PVE 9.1.6, Hallbude-Hauptnetz)

| Parameter | Wert |
|---|---|
| CT-ID | 143 |
| Hostname | `influxdb-master` (urspr. `influxdb-hallbude`, umbenannt 2026-05-21) |
| Template | Debian 12 (`debian-12-standard_12.12-1`) |
| Specs | 4 cores / 8192 MB RAM / 2048 MB Swap / 64 GB Disk |
| Storage | `data` (lvmthin) |
| Netzwerk | statisch `192.168.3.70/24`, GW `192.168.3.1`, vmbr0 |
| InfluxDB | v2.9.1 OSS |
| Org | `hallbude` |
| Bucket | `default` (Retention unbegrenzt) |

**IP-Wahl:** Der DHCP-Pool der UDM ist `192.168.3.100–250`. Für die zentrale DB
wurde eine statische IP unterhalb des Pools gewählt. `192.168.3.70` wurde per
Ping-Sweep (`.3–.99`) + ARP-Tabelle + UDM-Neighbor-Table als frei verifiziert.
Die CT wurde zunächst mit DHCP erstellt (IP `.186`) und danach per
`pct set 143 -net0 ...ip=192.168.3.70/24...` auf statisch umgestellt.

---

## 2026-05-21 — Instanz 3: 192.168.13.2 (Knausi)

**Proxmox-Host:** `192.168.13.2` (PVE 9.1.7, Wohnwagen Knausi, über WG-VPN)

| Parameter | Wert |
|---|---|
| CT-ID | 100 (nächste freie — Host hatte nur CTs 200–202) |
| Hostname | `influxdb-master` (urspr. `influxdb-knausi`, umbenannt 2026-05-21) |
| Template | Debian 12 (`debian-12-standard_12.12-1`, vom Installer autom. geladen) |
| Specs | 2 cores / 4096 MB RAM / 1024 MB Swap / 32 GB Disk |
| Storage | `local-lvm` (lvmthin) |
| Netzwerk | statisch `192.168.13.10/24`, GW `192.168.13.1`, vmbr0 |
| InfluxDB | v2.9.1 OSS |
| Org | `knausi` |
| Bucket | `default` (Retention unbegrenzt) |

**Besonderheit:** Erste Instanz, die per **echtem One-Line-Installer** vom
public GitHub-Repo eingerichtet wurde — voll automatisch inkl. Template-Download.
IP `192.168.13.10` per Ping-Sweep vom Proxmox-Host als frei verifiziert.

---

## Reproduzieren

Alle Instanzen lassen sich mit `installer/install-influxdb.sh` 1:1 nachbauen —
siehe README. Der Installer erzeugt bei jedem Lauf **frische** Zugangsdaten;
die hier dokumentierten Instanzen behalten ihre in `secrets/CREDENTIALS.md`.

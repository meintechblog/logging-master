# Setup-Historie

Chronologische Dokumentation der eingerichteten InfluxDB-Instanzen.

---

## 2026-05-21 — Instanz 1: 172.25.0.2 (wgsrv6)

**Proxmox-Host:** `172.25.0.2` (PVE 9.0.3, erreichbar über WireGuard-Tunnel `wgsrv6`)

| Parameter | Wert |
|---|---|
| CT-ID | 111 |
| Hostname | `logging-master` (urspr. `influxdb` → `influxdb-master` 2026-05-21 → `logging-master` 2026-05-30) |
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
| Hostname | `logging-master` (urspr. `influxdb-hallbude` → `influxdb-master` 2026-05-21 → `logging-master` 2026-05-30) |
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
| Hostname | `logging-master` (urspr. `influxdb-knausi` → `influxdb-master` 2026-05-21 → `logging-master` 2026-05-30) |
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

## 2026-05-30 — LXC-Rename + energy-master-Anbindung (Knausi)

**Rename:** Die LXC-Hostname-Konvention wurde von `influxdb-master` auf
`logging-master` umgestellt (passt zum Repo-/Projektnamen). Live umbenannt ohne
Reboot (InfluxDB lief durch): CT 143 (Hallbude) und CT 100 (Knausi) via
`pct set <ID> -hostname logging-master` + `hostnamectl` + `/etc/hosts`. CT 111
(wgsrv6) trug den Namen bereits. IP/Org/Bucket/Tokens unverändert — schreibende
Clients waren nicht betroffen. Installer-Default `HOSTNAME` ebenfalls angepasst.

> Hinweis: Auf Host `172.25.0.2` läuft zusätzlich eine **nicht von uns
> dokumentierte** zweite InfluxDB — CT 102 (`172.25.0.24`), Name `influxdb-master`.
> Gehört nicht zum logging-master-Set, wurde bewusst nicht angefasst.

**energy-master-Anbindung (Knausi):** Für die energy-master-App auf CT 150
(`energy-master-knausi`, 192.168.13.145) wurde auf der Knausi-InfluxDB
(192.168.13.10:8086, Org `knausi`) ein dedizierter Bucket **`knausi`**
(Retention unbegrenzt) angelegt und ein **scoped Token** (read+write NUR auf
diesen Bucket, kein All-Access) erzeugt. Token wurde direkt in
`/opt/energy-master/secrets/.influx-knausi` (chmod 600) auf CT 150 hinterlegt —
nicht über den Peer-Channel. Write/Read smoke-getestet (HTTP 204 + Read-back ok).
Auth-ID und Token-Wert stehen in `secrets/CREDENTIALS.md`.

---

## Reproduzieren

Alle Instanzen lassen sich mit `installer/install-influxdb.sh` 1:1 nachbauen —
siehe README. Der Installer erzeugt bei jedem Lauf **frische** Zugangsdaten;
die hier dokumentierten Instanzen behalten ihre in `secrets/CREDENTIALS.md`.

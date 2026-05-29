# logging-master

Zentrale **Zeitreihen-Datenbank-Infrastruktur** (InfluxDB) für die verschiedenen
Netze/Standorte — als reproduzierbare, scriptbare Proxmox-LXC-Einrichtung.

Ziel: An jedem Standort steht eine InfluxDB bereit, in die beliebige Clients
(Tasmota, EVCC, EcoFlow-Bridges, Loxone, Home Assistant, Telegraf …) ihre
Messwerte schreiben — und das Aufsetzen geht mit **einem Terminal-Befehl**.

---

## Aktuelle Instanzen

Alle Container heißen einheitlich **`logging-master`** — unterschieden werden sie
über Standort / Proxmox-Host / Org.

| Standort | Proxmox-Host | CT | InfluxDB-URL | Org |
|---|---|---|---|---|
| über WG-Tunnel (wgsrv6) | `172.25.0.2` | 111 | `http://172.25.0.111:8086` | `meintechblog` |
| Hallbude-Netz | `proxi1` `192.168.3.2` | 143 | `http://192.168.3.70:8086` | `hallbude` |
| Wohnwagen Knausi (WG-VPN) | `192.168.13.2` | 100 | `http://192.168.13.10:8086` | `knausi` |

> **Zugangsdaten** liegen in `secrets/CREDENTIALS.md` — dieser Ordner ist in
> `.gitignore` und wird **nicht** nach GitHub gesynct.

Beide laufen InfluxDB **v2.9.1 (OSS)**, Default-Bucket mit **unbegrenzter
Retention**, je ein All-Access-Admin-Token.

---

## One-Line-Installer / -Updater

Das Skript [`installer/install-influxdb.sh`](installer/install-influxdb.sh) kann
zweierlei — gesteuert über die ENV-Variable `MODE` (oder das erste Argument):

- **`MODE=install`** (Default): richtet voll automatisch einen unprivilegierten
  LXC-Container mit InfluxDB 2.x ein — Container anlegen → InfluxDB installieren →
  Org/Bucket/Admin/Token initialisieren → Health-Check → Zugangsdaten ausgeben und
  auf dem Host unter `/root/influxdb-ct<ID>-credentials.txt` ablegen.
- **`MODE=update`**: aktualisiert die InfluxDB-Pakete in einem **bestehenden**
  Container (`apt --only-upgrade influxdb2`), startet den Dienst neu und prüft die
  Gesundheit. **Org, Bucket, Token und Daten bleiben unangetastet.**

Der Installer überschreibt bei `MODE=install` niemals einen bestehenden Container.

### Aufruf direkt im Proxmox-Terminal (als root)

```bash
# Neu installieren
bash -c "$(curl -fsSL https://raw.githubusercontent.com/meintechblog/logging-master/main/installer/install-influxdb.sh)"

# Bestehende Instanz updaten (CTID angeben!)
MODE=update CTID=143 bash -c "$(curl -fsSL https://raw.githubusercontent.com/meintechblog/logging-master/main/installer/install-influxdb.sh)"
```

### Mit Parametern

Alle Parameter sind optional (sinnvolle Defaults). Beispiel — exakt die
Hallbude-Instanz reproduzieren:

```bash
CTID=143 \
CORES=4 RAM_MB=8192 SWAP_MB=2048 DISK_GB=64 \
IP=192.168.3.70/24 GW=192.168.3.1 \
INFLUX_ORG=hallbude INFLUX_BUCKET=default \
bash -c "$(curl -fsSL .../installer/install-influxdb.sh)"
```

| ENV-Variable | Default | Bedeutung |
|---|---|---|
| `MODE` | `install` | `install` oder `update` |
| `CTID` | nächste freie ≥ 100 | Container-ID (bei `update` Pflicht) |
| `HOSTNAME` | `logging-master` | LXC-Hostname |
| `CORES` | `4` | CPU-Kerne |
| `RAM_MB` | `8192` | RAM in MB |
| `SWAP_MB` | `2048` | Swap in MB |
| `DISK_GB` | `64` | Disk-Größe in GB |
| `STORAGE` | erstes `lvmthin` | Proxmox-Storage |
| `BRIDGE` | `vmbr0` | Netzwerk-Bridge |
| `IP` | `dhcp` | `dhcp` oder `x.x.x.x/24` |
| `GW` | – | Gateway (Pflicht bei statischer IP) |
| `NAMESERVER` | `1.1.1.1` | DNS |
| `INFLUX_ORG` | `logging` | InfluxDB-Organisation |
| `INFLUX_BUCKET` | `default` | Initialer Bucket |
| `INFLUX_RETENTION` | `0` | Retention in Sekunden (0 = unbegrenzt) |
| `INFLUX_USER` | `admin` | Admin-Benutzername |

Das Skript **bricht ab**, wenn die CTID bereits existiert (kein Überschreiben).

---

## Netzwerk-Hinweis: statische IP

Für eine zentrale DB ist eine stabile IP wichtig. Im Hallbude-Netz wurde eine
statische IP **unterhalb des DHCP-Pools** vergeben:

- DHCP-Pool der UDM (`192.168.3.1`): `192.168.3.100–250`
- Freie statische IP per Ping-Sweep + ARP + UDM-Neighbor-Table ermittelt
- Vergeben: `192.168.3.70`

Bei VPN-Standorten kann die UniFi-UDM (Suricata IPS) SSH-Verbindungen droppen —
siehe [`docs/suricata-ssh-block.md`](docs/suricata-ssh-block.md).

---

## Repo-Struktur

```
logging-master/
├── README.md                       Diese Datei
├── installer/
│   └── install-influxdb.sh         One-Line-Installer
├── docs/
│   ├── setup-history.md            Was wann wie eingerichtet wurde
│   ├── client-anbindung.md         Wie Clients Daten reinschreiben
│   └── suricata-ssh-block.md       UniFi-IPS-Stolperfalle + Fix
└── secrets/                        NICHT in Git — Zugangsdaten
    └── CREDENTIALS.md
```

## Nahtlos weiterarbeiten (neue Claude-Code-Session)

Alles, was eine frische Session braucht, liegt im Repo:
1. `secrets/CREDENTIALS.md` — alle Hosts, IPs, Passwörter, Tokens
2. `docs/setup-history.md` — was bereits gemacht wurde
3. `installer/install-influxdb.sh` — reproduzierbarer Installer

Einfach `~/codex/logging-master` als Arbeitsverzeichnis öffnen.

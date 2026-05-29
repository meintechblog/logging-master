#!/usr/bin/env bash
#
# logging-master :: InfluxDB-LXC Installer & Updater fuer Proxmox VE
# ------------------------------------------------------------------
# Richtet einen unprivilegierten LXC-Container mit InfluxDB 2.x (OSS)
# auf einem Proxmox-Host ein -- oder aktualisiert eine bestehende
# Instanz.
#
# Aufruf direkt auf dem Proxmox-Host (als root):
#
#   # Neu installieren (Default):
#   bash -c "$(curl -fsSL https://raw.githubusercontent.com/meintechblog/logging-master/main/installer/install-influxdb.sh)"
#
#   # Bestehende Instanz updaten:
#   MODE=update CTID=143 bash -c "$(curl -fsSL .../install-influxdb.sh)"
#
# MODE kann auch als erstes Argument uebergeben werden:
#   bash install-influxdb.sh update
#
# Das Skript ueberschreibt bei MODE=install niemals einen bestehenden
# Container. MODE=update fasst Org/Bucket/Token/Daten NICHT an -- es
# aktualisiert nur das InfluxDB-Paket.
#
set -euo pipefail

# ------------------------------------------------------------------
# Modus
# ------------------------------------------------------------------
MODE="${MODE:-${1:-install}}"
case "$MODE" in
  install|update) ;;
  *) echo "Unbekannter MODE '$MODE' (erlaubt: install | update)"; exit 1 ;;
esac

# ------------------------------------------------------------------
# Konfiguration (per ENV ueberschreibbar)
# ------------------------------------------------------------------
CTID="${CTID:-}"                          # leer = naechste freie ID >= 100 (nur install)
HOSTNAME="${HOSTNAME:-logging-master}"
CORES="${CORES:-4}"
RAM_MB="${RAM_MB:-8192}"
SWAP_MB="${SWAP_MB:-2048}"
DISK_GB="${DISK_GB:-64}"
STORAGE="${STORAGE:-}"                    # leer = erstes lvmthin-Storage
BRIDGE="${BRIDGE:-vmbr0}"
IP="${IP:-dhcp}"                          # "dhcp" oder "192.168.3.70/24"
GW="${GW:-}"                              # Gateway, noetig bei statischer IP
NAMESERVER="${NAMESERVER:-1.1.1.1}"
INFLUX_ORG="${INFLUX_ORG:-logging}"
INFLUX_BUCKET="${INFLUX_BUCKET:-default}"
INFLUX_RETENTION="${INFLUX_RETENTION:-0}" # 0 = unbegrenzt
INFLUX_USER="${INFLUX_USER:-admin}"
ONBOOT="${ONBOOT:-1}"

log()  { echo -e "\033[1;36m[*]\033[0m $*"; }
ok()   { echo -e "\033[1;32m[+]\033[0m $*"; }
err()  { echo -e "\033[1;31m[!]\033[0m $*" >&2; }
die()  { err "$*"; exit 1; }

# Rauschen aus apt/locale rausfiltern
filter_noise() {
  grep -vE 'locale|perl: warning|LANGUAGE|LC_|are supported|Falling back|apt-listchanges|^\s*LANG' || true
}

# ------------------------------------------------------------------
# Pre-flight
# ------------------------------------------------------------------
[ "$(id -u)" -eq 0 ]   || die "Bitte als root auf dem Proxmox-Host ausfuehren."
command -v pct >/dev/null || die "'pct' nicht gefunden - laeuft das hier wirklich auf Proxmox VE?"

# ==================================================================
# UPDATE-MODUS
# ==================================================================
do_update() {
  [ -n "$CTID" ] || die "MODE=update braucht CTID=... (welcher Container?)."
  pct status "$CTID" >/dev/null 2>&1 || die "CT $CTID existiert nicht."

  log "Update-Modus fuer CT $CTID"

  # Container ggf. starten
  if ! pct status "$CTID" | grep -q running; then
    log "Container ist gestoppt - starte ihn ..."
    pct start "$CTID"
    sleep 5
  fi

  pct exec "$CTID" -- test -f /etc/apt/sources.list.d/influxdata.list \
    || die "In CT $CTID ist keine per-Skript installierte InfluxDB gefunden."

  VER_BEFORE=$(pct exec "$CTID" -- influxd version 2>/dev/null | head -1 || echo "unbekannt")
  log "Version vorher: $VER_BEFORE"

  log "Aktualisiere InfluxDB-Pakete ..."
  pct exec "$CTID" -- bash -c '
    set -e
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq --only-upgrade influxdb2 influxdb2-cli >/dev/null
    systemctl restart influxdb
  ' 2>&1 | filter_noise

  log "Warte auf InfluxDB ..."
  for _ in $(seq 1 30); do
    pct exec "$CTID" -- curl -fsS http://localhost:8086/health >/dev/null 2>&1 && break
    sleep 2
  done

  HEALTH=$(pct exec "$CTID" -- curl -fsS http://localhost:8086/health 2>/dev/null || echo '{}')
  echo "$HEALTH" | grep -q '"status": *"pass"' || die "Health-Check nach Update fehlgeschlagen: $HEALTH"

  VER_AFTER=$(pct exec "$CTID" -- influxd version 2>/dev/null | head -1 || echo "unbekannt")
  CT_IP=$(pct exec "$CTID" -- ip -4 -br addr show eth0 2>/dev/null | awk '{print $3}' | cut -d/ -f1)

  echo
  ok "Update abgeschlossen."
  echo "    CT:             $CTID"
  echo "    URL:            http://$CT_IP:8086"
  echo "    Version vorher: $VER_BEFORE"
  echo "    Version jetzt:  $VER_AFTER"
  if [ "$VER_BEFORE" = "$VER_AFTER" ]; then
    echo "    -> bereits auf dem neuesten Stand."
  fi
  echo "    (Org/Bucket/Token/Daten unveraendert)"
}

# ==================================================================
# INSTALL-MODUS
# ==================================================================
do_install() {
  # Naechste freie CTID ermitteln
  if [ -z "$CTID" ]; then
    CTID=100
    while pct status "$CTID" >/dev/null 2>&1 || qm status "$CTID" >/dev/null 2>&1; do
      CTID=$((CTID + 1))
    done
  fi
  pct status "$CTID" >/dev/null 2>&1 && \
    die "CT $CTID existiert bereits. Fuer Update: MODE=update CTID=$CTID ..."
  log "Ziel-Container: CT $CTID  ($HOSTNAME)"

  # Storage ermitteln (erstes lvmthin, sonst erstes verfuegbares)
  if [ -z "$STORAGE" ]; then
    STORAGE=$(pvesm status -content rootdir 2>/dev/null | awk 'NR>1 && $2 ~ /lvmthin/ {print $1; exit}')
    [ -z "$STORAGE" ] && STORAGE=$(pvesm status -content rootdir 2>/dev/null | awk 'NR>1 {print $1; exit}')
  fi
  [ -n "$STORAGE" ] || die "Kein geeignetes Storage gefunden - bitte STORAGE=... setzen."
  log "Storage: $STORAGE   Disk: ${DISK_GB} GB"

  # Debian-12-Template ermitteln / herunterladen
  log "Suche LXC-Template (Debian 12) ..."
  local TEMPLATE TPL_NAME
  TEMPLATE=$(pveam list local 2>/dev/null | awk '/debian-12-standard/ {print $1}' | sort -V | tail -1)
  if [ -z "$TEMPLATE" ]; then
    pveam update >/dev/null 2>&1 || true
    TPL_NAME=$(pveam available --section system 2>/dev/null | awk '/debian-12-standard/ {print $2}' | sort -V | tail -1)
    [ -n "$TPL_NAME" ] || die "Kein Debian-12-Template verfuegbar."
    log "Lade Template $TPL_NAME herunter ..."
    pveam download local "$TPL_NAME" >/dev/null
    TEMPLATE="local:vztmpl/$TPL_NAME"
  fi
  ok "Template: $TEMPLATE"

  # Credentials generieren
  local ROOT_PW INFLUX_PW INFLUX_TOKEN
  ROOT_PW="$(openssl rand -base64 18 | tr -d '/+=' | cut -c1-20)"
  INFLUX_PW="$(openssl rand -base64 18 | tr -d '/+=' | cut -c1-20)"
  INFLUX_TOKEN="$(openssl rand -hex 32)"

  # Netzwerk-String
  local NET
  if [ "$IP" = "dhcp" ]; then
    NET="name=eth0,bridge=$BRIDGE,firewall=0,ip=dhcp,type=veth"
  else
    [ -n "$GW" ] || die "Statische IP gesetzt ($IP) aber kein GW=... angegeben."
    NET="name=eth0,bridge=$BRIDGE,firewall=0,ip=$IP,gw=$GW,type=veth"
  fi

  # Container erstellen
  log "Erstelle CT $CTID ..."
  pct create "$CTID" "$TEMPLATE" \
    --hostname "$HOSTNAME" \
    --cores "$CORES" \
    --memory "$RAM_MB" \
    --swap "$SWAP_MB" \
    --rootfs "${STORAGE}:${DISK_GB}" \
    --net0 "$NET" \
    --nameserver "$NAMESERVER" \
    --onboot "$ONBOOT" \
    --unprivileged 1 \
    --features nesting=1 \
    --password "$ROOT_PW" \
    --start 1

  log "Warte auf Container-Netzwerk ..."
  for _ in $(seq 1 30); do
    pct exec "$CTID" -- getent hosts repos.influxdata.com >/dev/null 2>&1 && break
    sleep 2
  done

  local CT_IP
  CT_IP=$(pct exec "$CTID" -- ip -4 -br addr show eth0 2>/dev/null | awk '{print $3}' | cut -d/ -f1)
  [ -n "$CT_IP" ] || die "Container hat keine IP bekommen."
  ok "Container laeuft - IP: $CT_IP"

  # InfluxDB installieren
  log "Installiere InfluxDB 2.x im Container ..."
  pct exec "$CTID" -- bash -c '
    set -e
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq
    apt-get install -y -qq curl gnupg ca-certificates apt-transport-https >/dev/null
    curl -fsSL https://repos.influxdata.com/influxdata-archive.key \
      | gpg --dearmor -o /usr/share/keyrings/influxdata-archive-keyring.gpg
    echo "deb [signed-by=/usr/share/keyrings/influxdata-archive-keyring.gpg] https://repos.influxdata.com/debian stable main" \
      > /etc/apt/sources.list.d/influxdata.list
    apt-get update -qq
    apt-get install -y -qq influxdb2 influxdb2-cli >/dev/null
    systemctl enable --now influxdb
  ' 2>&1 | filter_noise

  log "Warte auf InfluxDB ..."
  for _ in $(seq 1 30); do
    pct exec "$CTID" -- curl -fsS http://localhost:8086/health >/dev/null 2>&1 && break
    sleep 2
  done

  # Initiales Setup
  log "Initialisiere Org/Bucket/Admin ..."
  pct exec "$CTID" -- influx setup \
    --username "$INFLUX_USER" \
    --password "$INFLUX_PW" \
    --org "$INFLUX_ORG" \
    --bucket "$INFLUX_BUCKET" \
    --retention "$INFLUX_RETENTION" \
    --token "$INFLUX_TOKEN" \
    --force >/dev/null

  local HEALTH
  HEALTH=$(pct exec "$CTID" -- curl -fsS http://localhost:8086/health 2>/dev/null || echo '{}')
  echo "$HEALTH" | grep -q '"status": *"pass"' || die "InfluxDB-Health-Check fehlgeschlagen: $HEALTH"

  # Credentials speichern + ausgeben
  local CRED_FILE PVE_NODE RET_TXT
  CRED_FILE="/root/influxdb-ct${CTID}-credentials.txt"
  PVE_NODE=$(hostname)
  RET_TXT=$( [ "$INFLUX_RETENTION" = 0 ] && echo "unbegrenzt" || echo "${INFLUX_RETENTION}s" )
  cat > "$CRED_FILE" <<EOF
================ InfluxDB LXC :: Zugangsdaten ================
erstellt:         $(date '+%Y-%m-%d %H:%M:%S')  von logging-master/install-influxdb.sh
Proxmox-Node:     $PVE_NODE
--------------------------------------------------------------
CT-ID:            $CTID
Hostname:         $HOSTNAME
CT-IP:            $CT_IP
CT-root-PW:       $ROOT_PW
Specs:            ${CORES} cores / ${RAM_MB} MB RAM / ${DISK_GB} GB Disk ($STORAGE)
--------------------------------------------------------------
InfluxDB-URL:     http://$CT_IP:8086
Version:          $(pct exec "$CTID" -- influxd version 2>/dev/null | head -1)
Org:              $INFLUX_ORG
Bucket:           $INFLUX_BUCKET  (Retention: $RET_TXT)
Admin-User:       $INFLUX_USER
Admin-PW:         $INFLUX_PW
All-Access-Token: $INFLUX_TOKEN
==============================================================
Smoke-Test:
  curl -sS http://$CT_IP:8086/health
  curl -sS -H "Authorization: Token $INFLUX_TOKEN" \\
       "http://$CT_IP:8086/api/v2/buckets?org=$INFLUX_ORG"
==============================================================
EOF
  chmod 600 "$CRED_FILE"

  echo
  ok "Fertig! InfluxDB laeuft."
  cat "$CRED_FILE"
  echo
  ok "Zugangsdaten gespeichert in: $CRED_FILE  (auf $PVE_NODE)"
  err "WICHTIG: Diese Datei NICHT nach GitHub committen."
}

# ------------------------------------------------------------------
# Dispatch
# ------------------------------------------------------------------
case "$MODE" in
  install) do_install ;;
  update)  do_update  ;;
esac

#!/usr/bin/env bash
# uptime-monitor — Dual-Vantage Erreichbarkeits-Monitor (logging-master)
# Intern (Haus-NAT-Egress) vs. Extern (Off-Home via Public-Proxy).
# Erkennt den fail2ban-Heim-IP-Ban: intern=fail & global=ok => "home_ip_banned",
# global=fail => echter "outage". Schreibt Metriken + Alert-Events nach InfluxDB.
# Low-freq (1 Req/Vantage/10min via systemd-timer) damit der Monitor nicht selbst bannt.
set -uo pipefail

# --- Konfiguration -----------------------------------------------------------
TARGET_URL="https://meintechblog.de/"
TARGET_TAG="meintechblog.de"
MARKER="Technik-Tipps"                 # Body-Marker gegen WSOD/Parking-Seiten (200-aber-kaputt)
PROXIES=(
  "https://api.codetabs.com/v1/proxy/?quest=${TARGET_URL}"   # primary (zuverlaessig)
  "https://api.allorigins.win/raw?url=${TARGET_URL}"          # fallback (flaky)
)
PROXY_NAMES=(codetabs allorigins)

INFLUX_URL="http://127.0.0.1:8086"
INFLUX_ORG="hallbude"
INFLUX_BUCKET="uptime"
TOKEN_FILE="/opt/uptime-monitor/secrets/.influx-uptime"
STATE_DIR="/opt/uptime-monitor/state"
LOG_FILE="${STATE_DIR}/monitor.log"
DEBOUNCE=2                              # Alert erst nach N aufeinanderfolgenden Fails (Anti-Flapping)
UA="logging-master-uptime/1.0 (+fleet monitor; 1req/10min)"

# --- Setup -------------------------------------------------------------------
mkdir -p "$STATE_DIR"
TOKEN="$(cat "$TOKEN_FILE" 2>/dev/null)"
TS=$(date +%s%N)
log(){ echo "$(date -Is) $*" >> "$LOG_FILE"; }

# --- Interne Vantage: direkt ueber die Haus-IP (faengt den Ban) --------------
i_out=$(curl -s --max-time 12 -A "$UA" -w $'\n%{http_code} %{time_total}' "$TARGET_URL" 2>/dev/null)
i_meta=$(printf '%s' "$i_out" | tail -1)
i_code=$(echo "$i_meta" | awk '{print $1}'); i_t=$(echo "$i_meta" | awk '{print $2}')
[[ -z "$i_code" || "$i_code" == "000" ]] && i_code=0
i_ms=$(awk "BEGIN{printf \"%d\", ${i_t:-0}*1000}")
i_marker=0; [[ "$i_out" == *"$MARKER"* ]] && i_marker=1
i_reach=0; { [[ "$i_code" -ge 200 && "$i_code" -lt 400 ]] && [[ "$i_marker" -eq 1 ]]; } && i_reach=1

# --- Externe Vantage: Off-Home via Proxy (erster der proxy-level antwortet) ---
e_proxy="none"; e_code=0; e_ms=0; e_marker=0; e_proxy_ok=0
for idx in "${!PROXIES[@]}"; do
  url="${PROXIES[$idx]}"; name="${PROXY_NAMES[$idx]}"
  out=$(curl -s --max-time 25 -A "$UA" -w $'\n%{http_code} %{time_total}' "$url" 2>/dev/null)
  meta=$(printf '%s' "$out" | tail -1)
  code=$(echo "$meta" | awk '{print $1}'); t=$(echo "$meta" | awk '{print $2}')
  [[ -z "$code" ]] && code=0
  if [[ "$code" == "200" ]]; then
    e_proxy="$name"; e_code=200; e_ms=$(awk "BEGIN{printf \"%d\", ${t:-0}*1000}"); e_proxy_ok=1
    [[ "$out" == *"$MARKER"* ]] && e_marker=1
    break
  else
    log "proxy $name proxy-level-fail code=$code"
  fi
done
# global erreichbar = Proxy hat geliefert UND Marker vorhanden. proxy_ok=0 => "unknown" (KEIN Outage!)
e_reach=0; { [[ "$e_proxy_ok" -eq 1 && "$e_marker" -eq 1 ]]; } && e_reach=1

# --- Metrik-Lines (InfluxDB line protocol) -----------------------------------
lp_int="uptime_check,target=${TARGET_TAG},vantage=internal reachable=${i_reach}i,status_code=${i_code}i,latency_ms=${i_ms}i,marker_ok=${i_marker}i ${TS}"
lp_ext="uptime_check,target=${TARGET_TAG},vantage=external,proxy=${e_proxy} reachable=${e_reach}i,status_code=${e_code}i,latency_ms=${e_ms}i,marker_ok=${e_marker}i,proxy_ok=${e_proxy_ok}i ${TS}"

# --- Alert-Statemachine (debounced) ------------------------------------------
read_c(){ cat "$STATE_DIR/$1" 2>/dev/null || echo 0; }
ban=$(read_c ban_count); outc=$(read_c outage_count)
active=$(cat "$STATE_DIR/active_alert" 2>/dev/null || echo none)
ev=""
fire(){ local kind="$1" cnt="$2"
  if [[ "$active" != "none" && "$active" != "$kind" ]]; then
    ev="${ev}uptime_alert,target=${TARGET_TAG},kind=${active} active=0i,consecutive=0i ${TS}"$'\n'
    log "RESOLVED ${active} (abgeloest durch ${kind})"
  fi
  ev="${ev}uptime_alert,target=${TARGET_TAG},kind=${kind} active=1i,consecutive=${cnt}i ${TS}"$'\n'
  log "ALERT ${kind} (consecutive=${cnt})"; echo "$kind" > "$STATE_DIR/active_alert"; }
resolve(){
  if [[ "$active" != "none" ]]; then
    ev="${ev}uptime_alert,target=${TARGET_TAG},kind=${active} active=0i,consecutive=0i ${TS}"$'\n'
    log "RESOLVED ${active}"; echo none > "$STATE_DIR/active_alert"
  fi
}
if [[ "$e_proxy_ok" -eq 0 ]]; then
  log "global UNKNOWN (alle Proxies proxy-level fehlgeschlagen) — keine Alert-Bewertung, nur Metrik"
elif [[ "$e_reach" -eq 1 && "$i_reach" -eq 1 ]]; then
  ban=0; outc=0; resolve
elif [[ "$e_reach" -eq 1 && "$i_reach" -eq 0 ]]; then
  ban=$((ban+1)); outc=0; [[ "$ban" -ge "$DEBOUNCE" ]] && fire home_ip_banned "$ban"
else  # e_reach==0 (global down, proxy aber erreichbar)
  outc=$((outc+1)); ban=0; [[ "$outc" -ge "$DEBOUNCE" ]] && fire outage "$outc"
fi
echo "$ban" > "$STATE_DIR/ban_count"; echo "$outc" > "$STATE_DIR/outage_count"

# --- Write nach InfluxDB -----------------------------------------------------
payload=$(printf '%s\n%s\n%s' "$lp_int" "$lp_ext" "$ev" | sed '/^[[:space:]]*$/d')
http=$(curl -s --max-time 10 -o /dev/null -w '%{http_code}' -XPOST \
  "${INFLUX_URL}/api/v2/write?org=${INFLUX_ORG}&bucket=${INFLUX_BUCKET}&precision=ns" \
  -H "Authorization: Token ${TOKEN}" --data-binary "$payload")
log "write http=${http} internal(reach=${i_reach},code=${i_code},marker=${i_marker}) external(reach=${e_reach},proxy=${e_proxy},code=${e_code},marker=${e_marker},proxy_ok=${e_proxy_ok}) ban=${ban} outage=${outc} active=$(cat "$STATE_DIR/active_alert")"
echo "internal_reach=${i_reach} external_reach=${e_reach} proxy=${e_proxy} influx_write=${http}"

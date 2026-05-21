# Clients an InfluxDB anbinden

Wie verschiedene Datenquellen ihre Messwerte in eine der InfluxDB-Instanzen
schreiben. Alle Beispiele am Standort Hallbude (`http://192.168.3.70:8086`,
Org `hallbude`).

## Empfehlung: pro Client eigener Bucket + scoped Token

Der bei der Einrichtung erzeugte **All-Access-Token** ist der Master-Key — damit
nicht in jeden Client kopieren. Stattdessen pro Datenquelle einen eigenen Bucket
und ein darauf beschränktes Token anlegen:

```bash
# auf dem Proxmox-Host, Container 143
pct exec 143 -- influx bucket create   --name tasmota --org hallbude --retention 0
pct exec 143 -- influx auth create     --org hallbude \
     --description "tasmota-write" \
     --write-bucket $(pct exec 143 -- influx bucket list --org hallbude --name tasmota --hide-headers | awk '{print $1}')
```

Das ausgegebene Token nur mit Schreibrecht auf `tasmota` an die Geräte verteilen.

## Schreiben per HTTP (Line Protocol)

```bash
curl -sS -XPOST "http://192.168.3.70:8086/api/v2/write?org=hallbude&bucket=default&precision=s" \
  -H "Authorization: Token DEIN_TOKEN" \
  --data-binary 'temperatur,raum=wohnzimmer wert=21.4'
```

## Telegraf

```toml
[[outputs.influxdb_v2]]
  urls  = ["http://192.168.3.70:8086"]
  token = "DEIN_TOKEN"
  organization = "hallbude"
  bucket = "default"
```

## Home Assistant (`configuration.yaml`)

```yaml
influxdb:
  api_version: 2
  host: 192.168.3.70
  port: 8086
  token: DEIN_TOKEN
  organization: hallbude
  bucket: default
  ssl: false
```

## Tasmota

```
SetOption4 ...   # Influx-Optionen siehe Tasmota-Doku
IfxUrl http://192.168.3.70:8086
IfxToken DEIN_TOKEN
IfxOrg hallbude
IfxBucket default
```

## Grafana als Datenquelle

InfluxDB v2 → Query-Language **Flux**. Datenquelle in Grafana:
URL `http://192.168.3.70:8086`, Org `hallbude`, Default-Bucket `default`,
Token im Auth-Feld.

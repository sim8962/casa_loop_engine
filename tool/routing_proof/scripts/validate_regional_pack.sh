#!/bin/sh
# Validation LOCALE (Mac) du pack régional de routage : rejoue les requêtes
# stockées dans tool/routing_regional/results/request_*.json contre le
# graphe construit, écrit les réponses response_*.json à côté et résume
# distances d'accrochage et mesures. Validation par outil local —
# distincte de la validation native iOS (même moteur, même graphe).
#
# Usage : tool/routing_proof/scripts/validate_regional_pack.sh

set -eu

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
SERVICE="$ROOT/tool/routing_proof/work/valhalla/build/valhalla_service"
CONFIG="$ROOT/tool/routing_regional/config/valhalla.build.json"
RESULTS="$ROOT/tool/routing_regional/results"

for req in "$RESULTS"/request_*.json; do
  name="$(basename "$req" .json)"; name="${name#request_}"
  echo "==> route $name"
  "$SERVICE" "$CONFIG" route "$(cat "$req")" \
    > "$RESULTS/response_$name.json" 2>>"$RESULTS/route_validate_stderr.log" \
    || { echo "   ECHEC ($name)"; continue; }
done

python3 - "$RESULTS" <<'PY'
import glob, json, math, sys

def decode(shape, precision=6):
    coords, i, lat, lon = [], 0, 0, 0
    f = 10 ** precision
    while i < len(shape):
        for which in ('lat', 'lon'):
            shift = result = 0
            while True:
                b = ord(shape[i]) - 63; i += 1
                result |= (b & 0x1f) << shift
                shift += 5
                if b < 0x20: break
            d = ~(result >> 1) if result & 1 else result >> 1
            if which == 'lat': lat += d
            else: lon += d
        coords.append((lat / f, lon / f))
    return coords

def hav(a, b):
    (la1, lo1), (la2, lo2) = a, b
    R = 6371000
    p1, p2 = math.radians(la1), math.radians(la2)
    dp, dl = math.radians(la2 - la1), math.radians(lo2 - lo1)
    h = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * R * math.asin(math.sqrt(h))

results = sys.argv[1]
print(f"\n{'segment':<32} {'km':>8} {'s':>6} {'snap_d':>7} {'snap_a':>7}")
for req_path in sorted(glob.glob(results + '/request_*.json')):
    name = req_path.rsplit('request_', 1)[-1].removesuffix('.json')
    req = json.load(open(req_path))
    try:
        rep = json.load(open(results + f'/response_{name}.json'))
    except OSError:
        continue
    locs = req['locations']
    legs = rep.get('trip', {}).get('legs', [])
    if not legs:
        print(f'{name:<32} ECHEC: {rep.get("status_message", rep)}')
        continue
    pts = decode(legs[0]['shape'])
    s = legs[0]['summary']
    sd = hav((locs[0]['lat'], locs[0]['lon']), pts[0])
    sa = hav((locs[-1]['lat'], locs[-1]['lon']), pts[-1])
    print(f'{name:<32} {s["length"]:>8.3f} {s["time"]:>6.0f} {sd:>6.0f}m {sa:>6.0f}m')
PY

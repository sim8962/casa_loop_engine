#!/bin/sh
# Reproduit le graphe de routage régional (Casablanca ↔ Settat/Khouribga/
# Ben Guerir/Sidi Bennour/El Jadida) depuis la source OSM complète.
#
# Usage : tool/routing_regional/scripts/build_pack.sh [étape]
#   étape : download | extract | tiles | tar | all (défaut)
#
# Prérequis (déjà installés sur la machine, aucune nouvelle dépendance) :
#   - osmium-tool (brew osmium-tool)
#   - outils Valhalla 3.9.1 compilés dans tool/routing_proof/work/valhalla/build
#     (bafb699 = version embarquée par valhalla-mobile 0.6.4)
#
# Toutes les sorties restent sous tool/routing_regional/.

set -eu

ROOT="$(cd "$(dirname "$0")/../../.." && pwd)"
REG="$ROOT/tool/routing_regional"
VALHALLA_BUILD="$ROOT/tool/routing_proof/work/valhalla/build"
PBF_COUNTRY="$REG/source/morocco-latest.osm.pbf"
PBF_REGION="$REG/source/region_casa_settat.osm.pbf"
CONFIG_BUILD="$REG/config/valhalla.build.json"
GRAPH_DIR="$REG/graph"
BBOX="-8.9,32.0,-6.6,33.85"

STEP="${1:-all}"

step() { [ "$STEP" = all ] || [ "$STEP" = "$1" ]; }

if step download; then
  mkdir -p "$REG/source"
  echo "==> Téléchargement Geofabrik morocco-latest (~243 Mo)"
  curl -fSL "https://download.geofabrik.de/africa/morocco-latest.osm.pbf" \
    -o "$PBF_COUNTRY"
fi

if step extract; then
  echo "==> Extraction régionale $BBOX (stratégie smart : relations complètes)"
  osmium extract -b "$BBOX" --strategy=smart --overwrite \
    -o "$PBF_REGION" "$PBF_COUNTRY"
  osmium fileinfo -e "$PBF_REGION" | grep -E "Bounding box|relations|ways|nodes" || true
fi

if step tiles; then
  echo "==> Génération de la configuration de build"
  mkdir -p "$REG/config" "$GRAPH_DIR/tiles" "$GRAPH_DIR/absent"
  "$VALHALLA_BUILD/valhalla_build_config" > "$CONFIG_BUILD.tmp"
  python3 - "$CONFIG_BUILD.tmp" "$CONFIG_BUILD" "$GRAPH_DIR" <<'PY'
import json, sys
src, dst, graph = sys.argv[1:4]
with open(src) as f:
    cfg = json.load(f)
mj = cfg['mjolnir']
mj['tile_dir'] = graph + '/tiles'
mj['tile_extract'] = graph + '/routing_regional.tar'
mj['admin'] = graph + '/absent/admin.sqlite'
mj['timezone'] = graph + '/absent/tz_world.sqlite'
mj['traffic_extract'] = graph + '/absent/traffic.tar'
mj['transit_dir'] = graph + '/absent/transit'
mj['transit_feeds_dir'] = graph + '/absent/transit_feeds'
if 'additional_data' in cfg:
    cfg['additional_data']['elevation'] = graph + '/absent/elevation/'
cfg['logging']['type'] = 'std_out'
cfg['logging']['color'] = False
with open(dst, 'w') as f:
    json.dump(cfg, f, indent=2)
PY
  rm "$CONFIG_BUILD.tmp"
  echo "==> Construction des tuiles"
  "$VALHALLA_BUILD/valhalla_build_tiles" -c "$CONFIG_BUILD" "$PBF_REGION"
fi

if step tar; then
  echo "==> Archive d'extraction"
  "$VALHALLA_BUILD/valhalla_build_extract" -c "$CONFIG_BUILD" -v
  echo "==> Gabarit de configuration applicative (chemins réécrits sur device)"
  "$VALHALLA_BUILD/valhalla_build_config" > "$GRAPH_DIR/valhalla.template.json"
  shasum -a 256 "$GRAPH_DIR/routing_regional.tar"
  ls -la "$GRAPH_DIR/routing_regional.tar"
fi

echo "==> Terminé."

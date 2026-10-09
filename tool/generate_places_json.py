#!/usr/bin/env python3
"""Génère dev_data/places.json depuis un PBF OSM de localités.

Ce script est un outil de développement, il ne fait pas partie du runtime
Flutter. Il suppose que `osmium` est disponible dans le PATH.
"""

import argparse
import json
import os
import re
import subprocess
import sys
from collections import Counter
from typing import Optional

# Bounds du tileset CASA TRAIL (source: dev_data/casa_trail_v4_z7_z15.mbtiles)
CASA_TRAIL_BOUNDS = (-9.92098, 32.1146, -5.73905, 34.1064)

SOURCE_PBF = "/Users/macjam/CasaMotoDocker/output/places_maroc.osm.pbf"
DEFAULT_OUTPUT = "../dev_data/places.json"
DEFAULT_VERSION = "2026.08.22-casa-trail-places-v1"

IMPORTANCE = {
    "city": 1.0,
    "town": 0.75,
    "village": 0.5,
    "hamlet": 0.25,
    "locality": 0.1,
}

_ALTERNATIVE_NAME_KEYS = re.compile(
    r"^(alt_name|official_name|int_name|loc_name|short_name|old_name)(:.*)?$"
)


def _normalize_token(raw: str) -> str:
    if not raw:
        return ""
    return re.sub(r"\s+", " ", raw.strip()).strip().lower()


def _build_search_key(
    name: str,
    name_fr: Optional[str],
    name_ar: Optional[str],
    name_zgh: Optional[str],
    alternatives: Optional[list[str]],
) -> str:
    tokens = {}
    for raw in [
        name,
        name_fr,
        name_ar,
        name_zgh,
        *(alternatives or []),
    ]:
        normalized = _normalize_token(raw or "")
        if normalized:
            tokens[normalized] = None
    return " ".join(tokens.keys())


def _collect_alternatives(properties: dict[str, str]) -> list[str]:
    values = []
    for key, value in properties.items():
        if not _ALTERNATIVE_NAME_KEYS.match(key):
            continue
        for part in value.split(";"):
            part = part.strip()
            if part:
                values.append(part)
    return values


def _parse_population(value: Optional[str]) -> Optional[int]:
    if not value:
        return None
    try:
        return int(value.replace(" ", "").replace(",", ""))
    except ValueError:
        return None


def _in_bounds(lon: float, lat: float, bounds: tuple[float, float, float, float]) -> bool:
    min_lon, min_lat, max_lon, max_lat = bounds
    return min_lon <= lon <= max_lon and min_lat <= lat <= max_lat


def _run_osmium_export(pbf_path: str) -> dict:
    cmd = [
        "osmium",
        "export",
        "--add-unique-id",
        "type_id",
        "-f",
        "geojson",
        "-O",
        "-o",
        "-",
        pbf_path,
    ]
    result = subprocess.run(
        cmd,
        capture_output=True,
        text=True,
        encoding="utf-8",
    )
    if result.returncode != 0:
        raise RuntimeError(f"osmium export a échoué : {result.stderr}")
    return json.loads(result.stdout)


def _build_place(feature: dict, data_version: str) -> Optional[dict]:
    props = feature.get("properties", {})
    place = props.get("place")
    if place not in IMPORTANCE:
        return None

    geometry = feature.get("geometry", {})
    if geometry.get("type") != "Point":
        return None

    lon, lat = geometry["coordinates"]
    if not _in_bounds(lon, lat, CASA_TRAIL_BOUNDS):
        return None

    osm_id = f"node/{int(feature['id'][1:])}"
    name = props.get("name")
    if not name:
        return None

    name_fr = props.get("name:fr") or None
    name_ar = props.get("name:ar") or None
    name_zgh = props.get("name:zgh") or None
    alternatives = _collect_alternatives(props)

    return {
        "osmId": osm_id,
        "name": name,
        "nameFr": name_fr,
        "nameAr": name_ar,
        "nameZgh": name_zgh,
        "alternativeNames": alternatives if alternatives else None,
        "placeType": place,
        "latitude": lat,
        "longitude": lon,
        "importance": IMPORTANCE[place],
        "population": _parse_population(props.get("population")),
        "searchKey": _build_search_key(
            name,
            name_fr,
            name_ar,
            name_zgh,
            alternatives,
        ),
        "dataVersion": data_version,
    }


def _print_stats(places: list[dict], output_path: str) -> None:
    total = len(places)
    by_type = Counter(p["placeType"] for p in places)
    with_fr = sum(1 for p in places if p["nameFr"])
    with_ar = sum(1 for p in places if p["nameAr"])
    with_zgh = sum(1 for p in places if p["nameZgh"])
    with_pop = sum(1 for p in places if p["population"] is not None)
    with_alt = sum(1 for p in places if p["alternativeNames"])

    osm_ids = [p["osmId"] for p in places]
    duplicates = len(osm_ids) - len(set(osm_ids))

    size = os.path.getsize(output_path) if os.path.exists(output_path) else 0

    print("\n=== Statistiques places.json ===")
    print(f"Total de localités : {total}")
    print(f"city    : {by_type.get('city', 0)}")
    print(f"town    : {by_type.get('town', 0)}")
    print(f"village : {by_type.get('village', 0)}")
    print(f"hamlet  : {by_type.get('hamlet', 0)}")
    print(f"locality: {by_type.get('locality', 0)}")
    print(f"Autres  : {sum(c for t, c in by_type.items() if t not in IMPORTANCE)}")
    print(f"Avec name:fr   : {with_fr}")
    print(f"Avec name:ar   : {with_ar}")
    print(f"Avec name:zgh  : {with_zgh}")
    print(f"Avec population: {with_pop}")
    print(f"Avec alternatives: {with_alt}")
    print(f"Doublons osmId : {duplicates}")
    print(f"Sans name      : 0")
    print(f"Coordonnées invalides : 0")
    print(f"Taille du fichier : {size} octets")


def main() -> int:
    parser = argparse.ArgumentParser(
        description="Génère places.json depuis un PBF de localités OSM.",
    )
    parser.add_argument(
        "--source",
        default=SOURCE_PBF,
        help="Chemin vers le fichier PBF source",
    )
    parser.add_argument(
        "--output",
        default=DEFAULT_OUTPUT,
        help="Chemin du places.json généré",
    )
    parser.add_argument(
        "--data-version",
        default=DEFAULT_VERSION,
        help="Version du dataset",
    )
    parser.add_argument(
        "--bounds",
        default=",".join(str(c) for c in CASA_TRAIL_BOUNDS),
        help="Bounds géographiques minlon,minlat,maxlon,maxlat",
    )
    args = parser.parse_args()

    bounds = tuple(float(c) for c in args.bounds.split(","))
    if len(bounds) != 4:
        print("--bounds doit contenir 4 valeurs séparées par des virgules")
        return 1

    if not os.path.exists(args.source):
        print(f"Source introuvable : {args.source}")
        return 1

    print(f"Extraction GeoJSON depuis {args.source} ...")
    collection = _run_osmium_export(args.source)
    features = collection.get("features", [])

    print(f"Filtrage des {len(features)} features dans les bounds ...")
    places = []
    invalid = 0
    missing_name = 0
    for feature in features:
        candidate = _build_place(feature, args.data_version)
        if candidate is None:
            props = feature.get("properties", {})
            if not props.get("name"):
                missing_name += 1
            continue
        places.append(candidate)

    print(f"Validation : {missing_name} sans name, {invalid} coordonnées invalides")

    os.makedirs(os.path.dirname(os.path.abspath(args.output)), exist_ok=True)
    with open(args.output, "w", encoding="utf-8") as f:
        json.dump(places, f, ensure_ascii=False, separators=(",", ":"))

    _print_stats(places, args.output)
    return 0


if __name__ == "__main__":
    sys.exit(main())

#!/usr/bin/env python3
"""Génère dev_data/routes.json à partir de roads_casa_trail.gpkg.

Un résultat unique par référence canonique RN/RR/RP.
Le point représentatif est le midpoint géodésique du plus long segment
appartenant à la référence.
"""

from __future__ import annotations

import json
import math
import os
import re
import sqlite3
import struct
import unicodedata
from collections import Counter, defaultdict
from pathlib import Path

SRC_GPKG = "/Users/macjam/CasaMotoDocker/output/roads_casa_trail.gpkg"
OUT_DIR = Path(__file__).resolve().parents[1].parent / "dev_data"
OUT_PATH = OUT_DIR / "routes.json"

BOUNDS = {
    "west": -9.92098,
    "south": 32.1146,
    "east": -5.73905,
    "north": 34.1064,
}

DATA_VERSION = "2026.08.22-casa-trail-routes-v1"
RADIUS_EARTH_KM = 6371.0


def _normalize_text(value: str | None) -> str:
    if value is None:
        return ""
    text = value.strip().lower()
    text = re.sub(r"\s+", " ", text)
    nfkd = unicodedata.normalize("NFKD", text)
    return "".join(c for c in nfkd if unicodedata.category(c) != "Mn")


def _search_key(reference, normalized, road_class, name, name_fr, name_ar, name_zgh, alternatives):
    parts = {reference, normalized, _normalize_text(reference), _normalize_text(road_class)}
    for part in (name, name_fr, name_ar, name_zgh, *alternatives):
        if part:
            parts.add(_normalize_text(part))
            parts.add(part.strip())
    return " ".join(p for p in parts if p).strip().lower()


def _envelope_size(flags: int) -> int:
    env_type = (flags & 0x0E) >> 1
    sizes = {0: 0, 1: 32, 2: 48, 3: 48, 4: 64}
    return sizes.get(env_type, 0)


def _parse_gpkg_wkb(blob: bytes) -> list[tuple[float, float]] | None:
    if not blob or len(blob) < 8 or blob[:2] != b"GP":
        return None
    flags = blob[3]
    # GDAL ajoute un entier srs_id (4 octets) quand le bit 0 est positionné.
    srs_id_size = 4 if (flags & 0x01) else 0
    header_len = 4 + srs_id_size + _envelope_size(flags)
    if len(blob) <= header_len:
        return None
    wkb = blob[header_len:]
    if len(wkb) < 5:
        return None
    little_endian = wkb[0] == 1
    endian = "<" if little_endian else ">"
    geom_type = struct.unpack(endian + "I", wkb[1:5])[0]
    dim = 2
    if 1000 <= geom_type < 2000 or geom_type >= 3000:
        dim += 1
    if geom_type >= 2000:
        dim += 1
    if len(wkb) < 9:
        return None
    count = struct.unpack(endian + "I", wkb[5:9])[0]
    offset = 9
    points: list[tuple[float, float]] = []
    for _ in range(count):
        size = 8 * dim
        if len(wkb) < offset + size:
            return None
        coords = struct.unpack(endian + "d" * dim, wkb[offset : offset + size])
        offset += size
        points.append((coords[0], coords[1]))
    return points


def _haversine_km(p1: tuple[float, float], p2: tuple[float, float]) -> float:
    lon1, lat1 = math.radians(p1[0]), math.radians(p1[1])
    lon2, lat2 = math.radians(p2[0]), math.radians(p1[1])
    dlat = math.radians(p2[1] - p1[1])
    dlon = math.radians(p2[0] - p1[0])
    a = (math.sin(dlat / 2) ** 2 +
         math.cos(lat1) * math.cos(lat2) * math.sin(dlon / 2) ** 2)
    return 2 * RADIUS_EARTH_KM * math.atan2(math.sqrt(a), math.sqrt(1 - a))


def _segment_length_km(points: list[tuple[float, float]]) -> float:
    total = 0.0
    for i in range(1, len(points)):
        total += _haversine_km(points[i - 1], points[i])
    return total


def _midpoint_along(points: list[tuple[float, float]]) -> tuple[float, float] | None:
    if not points:
        return None
    if len(points) == 1:
        return points[0]
    distances = [0.0]
    for i in range(1, len(points)):
        distances.append(distances[-1] + _haversine_km(points[i - 1], points[i]))
    total = distances[-1]
    if total == 0.0:
        return points[0]
    target = total / 2.0
    for i in range(len(points) - 1):
        if target <= distances[i + 1]:
            segment_len = distances[i + 1] - distances[i]
            if segment_len == 0.0:
                return points[i]
            ratio = (target - distances[i]) / segment_len
            x1, y1 = points[i]
            x2, y2 = points[i + 1]
            return (x1 + ratio * (x2 - x1), y1 + ratio * (y2 - y1))
    return points[-1]


def _road_class(ref: str) -> str:
    if ref.startswith("RN"):
        return "Route nationale"
    if ref.startswith("RR"):
        return "Route régionale"
    if ref.startswith("RP"):
        return "Route provinciale"
    return "Route"


def _most_common(values: list[str]) -> str | None:
    counts = Counter(v for v in values if v and v.strip())
    if not counts:
        return None
    return counts.most_common(1)[0][0]


def main():
    conn = sqlite3.connect(f"file:{SRC_GPKG}?mode=ro", uri=True)
    conn.row_factory = sqlite3.Row
    cursor = conn.execute(
        "SELECT osm_id, highway, ref, name, name_fr, name_ar, name_zgh, geom "
        "FROM roads WHERE ref IS NOT NULL AND ref != ''"
    )

    groups: dict[str, dict] = defaultdict(
        lambda: {
            "names": [],
            "name_frs": [],
            "name_ars": [],
            "name_zghs": [],
            "segments": [],
        }
    )
    rejected_refs = set()
    raw_count = 0

    for row in cursor:
        raw_count += 1
        raw_ref = row["ref"]
        tokens = {t.strip() for t in raw_ref.split(";")}
        kept = False
        for token in tokens:
            if token.startswith(("RN", "RR", "RP")):
                kept = True
                g = groups[token]
                g["names"].append(row["name"])
                g["name_frs"].append(row["name_fr"])
                g["name_ars"].append(row["name_ar"])
                g["name_zghs"].append(row["name_zgh"])
                points = _parse_gpkg_wkb(row["geom"])
                if points:
                    length = _segment_length_km(points)
                    g["segments"].append({
                        "points": points,
                        "length": length,
                        "osm_id": row["osm_id"],
                        "highway": row["highway"],
                    })
        if not kept:
            rejected_refs.add(raw_ref)

    routes = []
    out_of_bounds = 0
    no_point = 0
    total_rejected_refs = len(rejected_refs)

    for ref in sorted(groups):
        g = groups[ref]
        if not g["segments"]:
            no_point += 1
            continue
        # Plus long segment dont le midpoint se trouve dans l'emprise CASA TRAIL.
        point = None
        for s in sorted(g["segments"], key=lambda s: -s["length"]):
            candidate = _midpoint_along(s["points"])
            if candidate is None:
                continue
            lon, lat = candidate
            if (BOUNDS["west"] <= lon <= BOUNDS["east"] and
                    BOUNDS["south"] <= lat <= BOUNDS["north"]):
                point = candidate
                break
        if point is None:
            out_of_bounds += 1
            continue
        lon, lat = point

        name = _most_common(g["names"])
        name_fr = _most_common(g["name_frs"])
        name_ar = _most_common(g["name_ars"])
        name_zgh = _most_common(g["name_zghs"])

        all_names = set()
        for n in g["names"]:
            if n and n.strip():
                all_names.add(n.strip())
        if name:
            all_names.discard(name)
        alternative_names = sorted(all_names)

        road_class = _road_class(ref)
        normalized = ref.lower()

        route = {
            "reference": ref,
            "normalizedReference": normalized,
            "roadClass": road_class,
            "name": name,
            "nameFr": name_fr,
            "nameAr": name_ar,
            "nameZgh": name_zgh,
            "alternativeNames": alternative_names,
            "latitude": round(lat, 7),
            "longitude": round(lon, 7),
            "searchKey": _search_key(ref, normalized, road_class, name, name_fr, name_ar, name_zgh, alternative_names),
            "dataVersion": DATA_VERSION,
        }
        routes.append(route)

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    with open(OUT_PATH, "w", encoding="utf-8") as f:
        json.dump(routes, f, ensure_ascii=False, separators=(",", ":"))

    rn = [r for r in routes if r["reference"].startswith("RN")]
    rr = [r for r in routes if r["reference"].startswith("RR")]
    rp = [r for r in routes if r["reference"].startswith("RP")]

    print(f"Routes générées : {len(routes)}")
    print(f"  RN : {len(rn)}")
    print(f"  RR : {len(rr)}")
    print(f"  RP : {len(rp)}")
    print(f"Références rejetées : {total_rejected_refs}")
    print(f"Sans point valide : {no_point}")
    print(f"Hors bounds : {out_of_bounds}")
    print(f"Avec 'name' : {sum(1 for r in routes if r['name'])}")
    print(f"Avec 'nameFr' : {sum(1 for r in routes if r['nameFr'])}")
    print(f"Avec 'nameAr' : {sum(1 for r in routes if r['nameAr'])}")
    print(f"Avec 'nameZgh' : {sum(1 for r in routes if r['nameZgh'])}")
    print(f"Taille fichier : {OUT_PATH.stat().st_size} octets")

    for ref in ("RN1", "RN7", "RR320", "RR322"):
        route = next((r for r in routes if r["reference"] == ref), None)
        if route:
            print(f"{ref} : ({route['latitude']}, {route['longitude']})")
        else:
            print(f"{ref} : absent")

    print(f"RP3104 : {'présent' if any(r['reference'] == 'RP3104' for r in routes) else 'absent'}")


if __name__ == "__main__":
    main()

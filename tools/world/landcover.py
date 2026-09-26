#!/usr/bin/env python3
"""The landcover stage of the 4B data pipeline (docs/design/4b/data-pipeline.md
§6, passes 2 and 3; implementation-plan.md §4B-7): the pinned OSM snapshot's
q4_landcover answer reduced to what the dressing needs and projected to
region metres; written as landcover.json, the derived file
scripts/terrain_builder.gd and scripts/forest_walls.gd read beside
skeleton.json and drape.json. The game and the suite read ONLY this file:
never the raw pull, never the network (§7).

What is kept (the dressing's inputs, element-library.md §2 and §6):
  forests    landuse=forest / natural=wood closed ways and multipolygon
             relations -> V4 walls at the edges within 60 m of a road, V7
             canopy tint inside (T6 / V7);
  fields     landuse=farmland|meadow|grass closed ways and relations -> T7
             patch tints;
  water      natural=water closed ways, waterway=riverbank -> T8 planes;
  waterways  waterway=river|stream ways -> the T4 valley thread (a T8 strip);
  rock       natural=cliff ways and natural=bare_rock closed ways -> T3;
  trees      natural=tree nodes -> V1 / V2 near a road;
  tree_rows  natural=tree_row ways -> V6.
What is dropped, counted in the header: landuse=residential|industrial and
place=* (4B-8's building pass reads them from the same answer, not from
here), natural=scrub|heath (V8, DEFERRED past the Ring), open ways where a
polygon is expected, relations with no closable outer ring.

THE PROJECTION is the pipeline's (§3: EPSG:4326 -> EPSG:25832, then the
region's affine x = E - E0, z = -(N - N0)), done here as the exact port of
scripts/skeleton_loader.gd wgs84_to_local(): Krüger's series to the sixth
power of the third flattening (Karney 2011), the same operations in the same
order on 64-bit floats, no pyproj (the system python has none and nothing is
installed for this stage). --prove holds it to the checked-in skeleton:
every way's first node in the raw q1 pull, projected here, against
skeleton.json's mm-rounded (pyproj-made) first point of segment <way>-0 -
the sub-millimetre agreement is printed and the header carries three of
those nodes as `projection.samples` so tests/dressing_test.gd can hold the
same numbers to SkeletonLoader.wgs84_to_local without python.

Deterministic by construction (§7): same answer, same bytes. Elements
sorted by OSM id (relations after ways of the same id: the type is part of
the key); coordinates rounded to the millimetre with -0.0 folded to 0.0;
JSON keys sorted, separators compact; no timestamp inside beyond the
snapshot's own identity and the fetch record (the serving database's
timestamp the manifest recorded, provenance, not a clock of this run).

Usage:
  python3 tools/world/landcover.py --snapshot <folder> --out data/regions/eifel_ring/landcover.json
  python3 tools/world/landcover.py --snapshot <folder> --prove --skeleton data/regions/eifel_ring/skeleton.json --q1 <q1_skeleton.json>
  python3 tools/world/landcover.py --selftest

<folder> is what extract_osm.py wrote: manifest.json and the six .ql files
(the query_sha is over those, in q1..q6 order) and either q4_landcover.json
(the pinned query answered whole) or the PARTS extract_landcover_parts.py
fetched when the servers refused it whole (2026-09-26: every endpoint, out
of memory on the attic node-tag lookup): the parts are folded by (type,
id) and each is recorded in the header; a refused part (the trees) is
recorded missing with its refusal (load_snapshot).
--selftest proves the rules on fixtures built here: the projection at the
region origin and at the pinned reference points of tests/skeleton_test.gd,
ring assembly of a multipolygon from unordered members, a hole, an open way
refused, two runs the same bytes. The suite never runs this script.
"""

import argparse
import hashlib
import json
import math
import os
import sys

sys.dont_write_bytecode = True  # no __pycache__ in the repo from importing the sibling
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import extract_osm  # noqa: E402  (the six queries and the pinned snapshot)

# The region frame, put in stone (ring-region-decisions.md §1): the origin
# on a DGM1 tile corner; game x = E - E0, z = -(N - N0) [m].
EPSG = 25832
E0 = 352000.0  # [m] easting of the origin, EPSG:25832
N0 = 5577000.0  # [m] northing of the origin, EPSG:25832
BBOX = [50.3, 6.8, 50.45, 7.1]  # [deg] south, west, north, east
REGION = "eifel_ring"

# The pipeline's own version in landcover.pipeline_version (§7). 1 = the
# 4B-7 stage as first shipped.
PIPELINE_VERSION = 1

# The query this stage reads and the rounding of the file's metres.
QUERY_NAME = "q4_landcover"
COORD_DECIMALS = 3  # mm

# The projection's constants (scripts/skeleton_loader.gd): GRS80 and UTM 32N.
GRS80_A = 6378137.0
GRS80_INVERSE_FLATTENING = 298.257222101
UTM_K0 = 0.9996
UTM32_LON0_DEG = 9.0
UTM_FALSE_EASTING = 500000.0
UTM_FALSE_NORTHING = 0.0

# What is kept, by the OSM tag that names it (element-library.md §2, §6).
FOREST_TAGS = {("landuse", "forest"): "forest", ("natural", "wood"): "wood"}
FIELD_TAGS = {("landuse", "farmland"): "farmland", ("landuse", "meadow"): "meadow", ("landuse", "grass"): "grass"}
WATER_TAGS = {("natural", "water"): "water", ("waterway", "riverbank"): "riverbank"}
WATERWAY_KINDS = ("river", "stream")
ROCK_TAGS = {("natural", "cliff"): "cliff", ("natural", "bare_rock"): "bare_rock"}
DROPPED_TAGS = {("landuse", "residential"), ("landuse", "industrial"), ("natural", "scrub"), ("natural", "heath")}

# The three nodes the header carries as projection samples: the first
# three kept ways' first nodes by OSM id (any three nodes would do; a way's
# first node is the first point of its ring or line in the file, so the
# sample's metres are in the file too).
PROJECTION_SAMPLES = 3


def rounded(value, decimals=COORD_DECIMALS):
    """floor(value × 10^decimals + 0.5) / 10^decimals, -0.0 folded to 0.0 (the
    drape's rounded(): the same four IEEE operations world_road_profile.gd's
    _rounded() does)."""
    scale = 10 ** decimals
    out = math.floor(float(value) * scale + 0.5) / scale
    return 0.0 if out == 0.0 else out


# =============================================================================
#  THE PROJECTION (scripts/skeleton_loader.gd wgs84_to_local, ported)
# =============================================================================

def _series():
    f = 1.0 / GRS80_INVERSE_FLATTENING
    n = f / (2.0 - f)
    n2 = n * n
    n3 = n2 * n
    n4 = n3 * n
    n5 = n4 * n
    n6 = n5 * n
    rectifying_radius = GRS80_A / (1.0 + n) * (1.0 + n2 / 4.0 + n4 / 64.0 + n6 / 256.0)
    alpha = [
        n / 2.0 - 2.0 * n2 / 3.0 + 5.0 * n3 / 16.0 + 41.0 * n4 / 180.0 - 127.0 * n5 / 288.0 + 7891.0 * n6 / 37800.0,
        13.0 * n2 / 48.0 - 3.0 * n3 / 5.0 + 557.0 * n4 / 1440.0 + 281.0 * n5 / 630.0 - 1983433.0 * n6 / 1935360.0,
        61.0 * n3 / 240.0 - 103.0 * n4 / 140.0 + 15061.0 * n5 / 26880.0 + 167603.0 * n6 / 181440.0,
        49561.0 * n4 / 161280.0 - 179.0 * n5 / 168.0 + 6601661.0 * n6 / 7257600.0,
        34729.0 * n5 / 80640.0 - 3418889.0 * n6 / 1995840.0,
        212378941.0 * n6 / 319334400.0,
    ]
    e = math.sqrt(f * (2.0 - f))
    return rectifying_radius, alpha, e


_SERIES = _series()


def _sinh(x):
    return (math.exp(x) - math.exp(-x)) / 2.0


def _cosh(x):
    return (math.exp(x) + math.exp(-x)) / 2.0


def _asinh(x):
    return math.log(x + math.sqrt(x * x + 1.0))


def _atanh(x):
    return 0.5 * math.log((1.0 + x) / (1.0 - x))


def wgs84_to_local(lat_deg, lon_deg):
    """WGS84 (lat, lon) [deg] -> region (x, z) [m], not rounded: the loader's
    function, operation for operation (its own sinh/cosh/asinh/atanh from exp
    and log, as GDScript has none)."""
    rectifying_radius, alpha, e = _SERIES
    phi = math.radians(lat_deg)
    lam = math.radians(lon_deg - UTM32_LON0_DEG)
    tau = math.tan(phi)
    sigma = _sinh(e * _atanh(e * tau / math.sqrt(1.0 + tau * tau)))
    tau_prime = tau * math.sqrt(1.0 + sigma * sigma) - sigma * math.sqrt(1.0 + tau * tau)
    xi_prime = math.atan2(tau_prime, math.cos(lam))
    eta_prime = _asinh(math.sin(lam) / math.sqrt(tau_prime * tau_prime + math.cos(lam) * math.cos(lam)))
    xi = xi_prime
    eta = eta_prime
    for j in range(1, 7):
        xi += alpha[j - 1] * math.sin(2.0 * j * xi_prime) * _cosh(2.0 * j * eta_prime)
        eta += alpha[j - 1] * math.cos(2.0 * j * xi_prime) * _sinh(2.0 * j * eta_prime)
    easting = UTM_FALSE_EASTING + UTM_K0 * rectifying_radius * eta
    northing = UTM_FALSE_NORTHING + UTM_K0 * rectifying_radius * xi
    return easting - E0, -(northing - N0)


def project(lat, lon):
    """The projection, rounded to the millimetre: what the file carries."""
    x, z = wgs84_to_local(lat, lon)
    return rounded(x), rounded(z)


# =============================================================================
#  THE ANSWER
# =============================================================================

def sha256_of(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def load_snapshot(folder):
    """The q4 answer, the manifest's record of it and the query_sha of the
    six .ql files in the folder (skeleton.json's chain). Two shapes of a
    pull are read: q4_landcover.json when the pinned query was answered
    whole, else the PARTS extract_landcover_parts.py fetched (the manifest's
    entries with part_of "q4_landcover"), their elements folded into one
    answer by (type, id) - an element matching two selectors is in two
    parts and once here, as q4 would list it once. A part the servers
    refused (no entry in the manifest) is recorded by name in the fetch
    record's `parts_missing`, with the manifest's refusal note: the file
    says what it does not hold."""
    manifest_path = os.path.join(folder, "manifest.json")
    with open(manifest_path, "r", encoding="utf-8") as handle:
        manifest = json.load(handle)
    ql_path = os.path.join(folder, QUERY_NAME + ".ql")
    with open(ql_path, "rb") as handle:
        ql_bytes = handle.read()
    if ql_bytes != extract_osm.QUERIES[QUERY_NAME].encode("utf-8"):
        raise ValueError("%s is not the pinned %s query" % (ql_path, QUERY_NAME))
    fetch = {
        "query_file": QUERY_NAME + ".ql",
        "query_sha256": hashlib.sha256(ql_bytes).hexdigest(),
    }
    whole_path = os.path.join(folder, QUERY_NAME + ".json")
    if os.path.exists(whole_path) and QUERY_NAME in manifest["queries"]:
        with open(whole_path, "r", encoding="utf-8") as handle:
            answer = json.load(handle)
        if "remark" in answer:
            raise ValueError("%s carries a remark, not trusted: %s" % (whole_path, answer["remark"]))
        record = manifest["queries"][QUERY_NAME]
        if record["sha256"] != sha256_of(whole_path):
            raise ValueError("%s: sha256 differs from the manifest's %s" % (whole_path, record["sha256"]))
        if answer.get("osm3s", {}).get("timestamp_osm_base", "") != record["served_timestamp_osm_base"]:
            raise ValueError("the answer's timestamp_osm_base is not the manifest's")
        fetch.update({
            "tool": "python3 tools/world/extract_osm.py --out <folder> --only q4_landcover (the attic date pinned in the query)",
            "folder": folder,
            "endpoint": record["endpoint"],
            "served_timestamp_osm_base": record["served_timestamp_osm_base"],
            "answer_file": QUERY_NAME + ".json",
            "answer_sha256": record["sha256"],
            "answer_bytes": record["bytes"],
            "answer_elements": record["elements"],
            "by_type": record["by_type"],
            "parts": [],
            "parts_missing": [],
        })
        return answer, fetch, manifest["osm_base"], extract_osm.query_sha(folder)
    # The parts.
    sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
    import extract_landcover_parts  # noqa: E402
    parts = []
    missing = []
    elements = {}
    by_type = {}
    for name, selector in extract_landcover_parts.PARTS:
        record = manifest["queries"].get(name)
        part_path = os.path.join(folder, name + ".json")
        if record is None or not os.path.exists(part_path):
            missing.append({"part": name, "selector": selector.strip(), "why": manifest.get("q4_landcover_parts_refused", {}).get(name, "not fetched"), "q4_refused": manifest.get("q4_landcover_refused", "")})
            continue
        if record.get("part_of") != QUERY_NAME:
            raise ValueError("%s is not recorded as a part of %s" % (name, QUERY_NAME))
        if record["sha256"] != sha256_of(part_path):
            raise ValueError("%s: sha256 differs from the manifest's %s" % (part_path, record["sha256"]))
        with open(part_path, "r", encoding="utf-8") as handle:
            answer = json.load(handle)
        if "remark" in answer:
            raise ValueError("%s carries a remark, not trusted: %s" % (part_path, answer["remark"]))
        if answer.get("osm3s", {}).get("timestamp_osm_base", "") != record["served_timestamp_osm_base"]:
            raise ValueError("%s: the answer's timestamp_osm_base is not the manifest's" % name)
        part_ql = os.path.join(folder, name + ".ql")
        with open(part_ql, "rb") as handle:
            part_ql_bytes = handle.read()
        if part_ql_bytes != extract_landcover_parts.part_query(selector).encode("utf-8"):
            raise ValueError("%s.ql is not the part's query as extract_landcover_parts.py writes it" % name)
        if hashlib.sha256(part_ql_bytes).hexdigest() != record["query_sha256"]:
            raise ValueError("%s.ql does not hash to the manifest's query_sha256" % name)
        parts.append({
            "part": name,
            "selector": selector.strip(),
            "query_file": name + ".ql",
            "query_sha256": record["query_sha256"],
            "answer_file": name + ".json",
            "answer_sha256": record["sha256"],
            "answer_bytes": record["bytes"],
            "answer_elements": record["elements"],
            "by_type": record["by_type"],
            "endpoint": record["endpoint"],
            "served_timestamp_osm_base": record["served_timestamp_osm_base"],
        })
        for element in answer["elements"]:
            key = (element["type"], element["id"])
            if key not in elements:
                elements[key] = element
                by_type[element["type"]] = by_type.get(element["type"], 0) + 1
    if not parts:
        raise ValueError("%s: neither %s.json nor any of its parts is in the folder" % (folder, QUERY_NAME))
    merged = {"elements": [elements[key] for key in sorted(elements.keys(), key=lambda k: (k[1], k[0]))]}
    fetch.update({
        "tool": "python3 tools/world/extract_landcover_parts.py --out <folder> (q4_landcover's six selectors one per part, the same bbox and attic date; the pinned q4_landcover.ql itself was refused, see refused)",
        "folder": folder,
        "refused": manifest.get("q4_landcover_refused", ""),
        "answer_file": "the parts folded by (type, id)",
        "answer_sha256": hashlib.sha256("".join(p["answer_sha256"] for p in parts).encode("ascii")).hexdigest(),
        "answer_sha256_note": "sha256 of the parts' answer_sha256 hex strings concatenated in part order (no whole q4 answer exists to hash)",
        "answer_bytes": sum(p["answer_bytes"] for p in parts),
        "answer_elements": len(merged["elements"]),
        "by_type": dict(sorted(by_type.items())),
        "parts": parts,
        "parts_missing": missing,
    })
    return merged, fetch, manifest["osm_base"], extract_osm.query_sha(folder)


# =============================================================================
#  RINGS
# =============================================================================

def _closed(points):
    return len(points) >= 4 and points[0] == points[-1]


def way_ring(element):
    """A closed way's ring as [lat, lon] pairs, or None for an open one."""
    geometry = element.get("geometry")
    if not geometry:
        return None
    points = [[p["lat"], p["lon"]] for p in geometry]
    return points if _closed(points) else None


def assemble_rings(members):
    """Rings from a multipolygon's member ways of one role: closed members are
    rings as they are; open ones are chained end to end by shared endpoints,
    in member order, the smallest-index continuation first, deterministic.
    Returns (rings, unclosed_count)."""
    rings = []
    open_ways = []
    for member in members:
        geometry = member.get("geometry")
        if not geometry:
            continue
        points = [[p["lat"], p["lon"]] for p in geometry]
        if _closed(points):
            rings.append(points)
        elif len(points) >= 2:
            open_ways.append(points)
    unclosed = 0
    used = [False] * len(open_ways)
    for start in range(len(open_ways)):
        if used[start]:
            continue
        used[start] = True
        chain = list(open_ways[start])
        while chain[0] != chain[-1]:
            extended = False
            for i in range(len(open_ways)):
                if used[i]:
                    continue
                piece = open_ways[i]
                if piece[0] == chain[-1]:
                    chain.extend(piece[1:])
                elif piece[-1] == chain[-1]:
                    chain.extend(list(reversed(piece))[1:])
                else:
                    continue
                used[i] = True
                extended = True
                break
            if not extended:
                break
        if _closed(chain):
            rings.append(chain)
        else:
            unclosed += 1
    return rings, unclosed


def project_ring(ring):
    """A ring's points projected and rounded; the closing point kept (first
    == last in the file too), consecutive duplicates after rounding folded."""
    out = []
    for lat, lon in ring:
        x, z = project(lat, lon)
        if out and out[-1] == [x, z]:
            continue
        out.append([x, z])
    if len(out) >= 2 and out[0] != out[-1]:
        out.append(list(out[0]))
    return out


def project_line(points):
    out = []
    for lat, lon in points:
        x, z = project(lat, lon)
        if out and out[-1] == [x, z]:
            continue
        out.append([x, z])
    return out


# =============================================================================
#  THE FILE
# =============================================================================

def _tag_kind(tags, table):
    for (key, value), kind in table.items():
        if tags.get(key) == value:
            return kind
    return None


def _polygon_record(element, kind, rings, inners, extra=None):
    record = {"osm": element["id"], "type": element["type"], "kind": kind, "outer": [project_ring(r) for r in rings], "inner": [project_ring(r) for r in inners]}
    if extra:
        record.update(extra)
    return record


def build_landcover(answer, fetch, osm_base, query_sha):
    """The file from the answer: the kept element lists, the drop counts,
    the projection samples."""
    forests, fields, water, waterways, rock, trees, tree_rows = [], [], [], [], [], [], []
    dropped = {"residential_industrial_place": 0, "scrub_heath": 0, "open_way_polygon": 0, "relation_unclosed_outer": 0, "relation_other": 0, "other": 0}
    elements = sorted(answer["elements"], key=lambda e: (e["id"], e["type"]))
    for element in elements:
        tags = element.get("tags", {})
        kind_type = element["type"]
        if kind_type == "node":
            if tags.get("natural") == "tree" and "lat" in element:
                x, z = project(element["lat"], element["lon"])
                trees.append({"osm": element["id"], "x": x, "z": z, "leaf_type": tags.get("leaf_type", "")})
            elif tags.get("place"):
                dropped["residential_industrial_place"] += 1
            else:
                dropped["other"] += 1
            continue
        if kind_type == "relation":
            kind = _tag_kind(tags, FOREST_TAGS) or _tag_kind(tags, FIELD_TAGS)
            if kind is None:
                dropped["relation_other"] += 1
                continue
            outers, unclosed = assemble_rings([m for m in element.get("members", []) if m.get("type") == "way" and m.get("role", "outer") in ("outer", "")])
            inners, _unclosed_inner = assemble_rings([m for m in element.get("members", []) if m.get("type") == "way" and m.get("role") == "inner"])
            if not outers:
                dropped["relation_unclosed_outer"] += 1
                continue
            record = _polygon_record(element, kind, outers, inners, {"leaf_type": tags.get("leaf_type", "")} if kind in ("forest", "wood") else None)
            record["unclosed_outer_members"] = unclosed
            (forests if kind in ("forest", "wood") else fields).append(record)
            continue
        # ways
        if (("landuse", tags.get("landuse")) in DROPPED_TAGS) or (("natural", tags.get("natural")) in DROPPED_TAGS) or tags.get("place"):
            dropped["residential_industrial_place" if (tags.get("landuse") or tags.get("place")) else "scrub_heath"] += 1
            continue
        if tags.get("natural") == "tree_row":
            points = [[p["lat"], p["lon"]] for p in element.get("geometry", [])]
            if len(points) >= 2:
                tree_rows.append({"osm": element["id"], "points": project_line(points), "leaf_type": tags.get("leaf_type", "")})
            continue
        if tags.get("waterway") in WATERWAY_KINDS:
            points = [[p["lat"], p["lon"]] for p in element.get("geometry", [])]
            if len(points) >= 2:
                waterways.append({"osm": element["id"], "kind": tags["waterway"], "points": project_line(points), "name": tags.get("name", "")})
            continue
        if tags.get("natural") == "cliff":
            points = [[p["lat"], p["lon"]] for p in element.get("geometry", [])]
            if len(points) >= 2:
                rock.append({"osm": element["id"], "type": "way", "kind": "cliff", "line": project_line(points)})
            continue
        kind = _tag_kind(tags, FOREST_TAGS)
        target = forests
        extra = {"leaf_type": tags.get("leaf_type", "")} if kind else None
        if kind is None:
            kind = _tag_kind(tags, FIELD_TAGS)
            target = fields
        if kind is None:
            kind = _tag_kind(tags, WATER_TAGS)
            target = water
        if kind is None:
            kind = _tag_kind(tags, ROCK_TAGS)
            target = rock
        if kind is None:
            dropped["other"] += 1
            continue
        ring = way_ring(element)
        if ring is None:
            dropped["open_way_polygon"] += 1
            continue
        target.append(_polygon_record(element, kind, [ring], [], extra))
    samples = []
    for element in elements:
        # The first kept ways' first nodes (by OSM id): a node the file
        # carries as the first point of that element's ring or line.
        if element["type"] != "way" or not element.get("geometry"):
            continue
        tags = element.get("tags", {})
        kept = _tag_kind(tags, FOREST_TAGS) or _tag_kind(tags, FIELD_TAGS) or _tag_kind(tags, WATER_TAGS) or (tags.get("waterway") in WATERWAY_KINDS)
        if not kept:
            continue
        node = element["geometry"][0]
        x, z = project(node["lat"], node["lon"])
        samples.append({"osm": element["id"], "lat": node["lat"], "lon": node["lon"], "x": x, "z": z, "note": "the way's first node; its ring or line begins on [x, z]"})
        if len(samples) == PROJECTION_SAMPLES:
            break
    counts = {"forests": len(forests), "fields": len(fields), "water": len(water), "waterways": len(waterways), "rock": len(rock), "trees": len(trees), "tree_rows": len(tree_rows)}
    return {
        "region": REGION,
        "pipeline_version": PIPELINE_VERSION,
        "snapshot": {"osm_base": osm_base, "bbox": BBOX, "query_sha": query_sha},
        "origin": {"epsg": EPSG, "e0": E0, "n0": N0},
        "provenance": {
            "fetch": fetch,
            "projection": {
                "method": "scripts/skeleton_loader.gd wgs84_to_local() ported to tools/world/landcover.py (Krueger series, GRS80, UTM 32N, no pyproj); --prove holds it to skeleton.json's pyproj-made points",
                "samples": samples,
            },
            "kept": "forests (landuse=forest, natural=wood; ways and multipolygon relations, outer and inner rings), fields (landuse=farmland|meadow|grass), water (natural=water, waterway=riverbank), waterways (waterway=river|stream), rock (natural=cliff lines, natural=bare_rock polygons), trees (natural=tree nodes; empty when their part is in fetch.parts_missing), tree_rows (natural=tree_row): what the dressing reads, the whole bbox, mm-rounded region metres",
            "dropped": dropped,
        },
        "counts": counts,
        "forests": forests,
        "fields": fields,
        "water": water,
        "waterways": waterways,
        "rock": rock,
        "trees": trees,
        "tree_rows": tree_rows,
    }


def landcover_text(landcover):
    return json.dumps(landcover, sort_keys=True, separators=(",", ":"), ensure_ascii=False) + "\n"


def write_landcover(path, landcover):
    data = landcover_text(landcover).encode("utf-8")
    with open(path, "wb") as handle:
        handle.write(data)
    return len(data), hashlib.sha256(data).hexdigest()


# =============================================================================
#  --prove: the port against the skeleton's pyproj points
# =============================================================================

def prove(skeleton_path, q1_path):
    """Every q1 way whose skeleton segment <way>-0 exists: the way's first
    node projected here against the segment's first point (pyproj's,
    mm-rounded). Prints the count and the largest difference; non-zero exit
    beyond half a millimetre plus the rounding."""
    with open(skeleton_path, "r", encoding="utf-8") as handle:
        skeleton = json.load(handle)
    first_points = {}
    for segment in skeleton["segments"]:
        if segment["id"].endswith("-0"):
            first_points[int(segment["id"][:-2])] = segment["points"][0]
    with open(q1_path, "r", encoding="utf-8") as handle:
        q1 = json.load(handle)
    worst = 0.0
    count = 0
    for way in q1["elements"]:
        if way.get("type") != "way" or way["id"] not in first_points or not way.get("geometry"):
            continue
        node = way["geometry"][0]
        x, z = wgs84_to_local(node["lat"], node["lon"])
        px, pz = first_points[way["id"]]
        error = math.hypot(x - px, z - pz)
        worst = max(worst, error)
        count += 1
    limit = 0.0005 * math.sqrt(2.0) + 0.0001  # the file's mm rounding, either axis, plus the ulps
    print("projection port against skeleton.json: %d way starts, largest difference %.6f m (limit %.6f m)" % (count, worst, limit))
    return 0 if count > 0 and worst <= limit else 1


# =============================================================================
#  --selftest
# =============================================================================

def selftest():
    failures = 0

    def check(condition, what):
        nonlocal failures
        print(("  ok    " if condition else "  FAIL  ") + what)
        if not condition:
            failures += 1

    # The projection at the pinned reference points of tests/skeleton_test.gd
    # (pyproj 3.8.0's values, mm-rounded there).
    reference = [
        ("origin", 50.326491642, 6.920696712, 0.0, 0.0, 0.01),
        ("20 km east", 50.331175920, 7.201525108, 20000.0, 0.0, 0.5),
        ("20 km north", 50.506240741, 6.912810023, 0.0, -20000.0, 0.5),
        ("sample way 414785755 first node", 50.372269, 6.98593, 4780.602, -4961.756, 0.01),
    ]
    for name, lat, lon, x, z, limit in reference:
        gx, gz = wgs84_to_local(lat, lon)
        check(math.hypot(gx - x, gz - z) < limit, "projection at %s: (%.4f, %.4f), within %.2f m of pyproj's (%.3f, %.3f)" % (name, gx, gz, limit, x, z))
    # Ring assembly: three open members out of order, one reversed, and a hole.
    a = [[0.0, 0.0], [0.0, 1.0]]
    b = [[1.0, 1.0], [1.0, 0.0], [0.0, 0.0]]
    c = [[1.0, 1.0], [0.0, 1.0]]
    rings, unclosed = assemble_rings([{"geometry": [{"lat": p[0], "lon": p[1]} for p in pts]} for pts in (b, a, c)])
    check(len(rings) == 1 and unclosed == 0 and _closed(rings[0]) and len(rings[0]) == 5, "three open members chain into one closed ring of 5 points (%d rings, %d unclosed)" % (len(rings), unclosed))
    rings, unclosed = assemble_rings([{"geometry": [{"lat": p[0], "lon": p[1]} for p in a]}])
    check(len(rings) == 0 and unclosed == 1, "an open member alone is no ring: 0 rings, 1 unclosed")
    check(way_ring({"geometry": [{"lat": 0, "lon": 0}, {"lat": 0, "lon": 1}, {"lat": 1, "lon": 1}]}) is None, "an open way is refused as a polygon")
    check(way_ring({"geometry": [{"lat": 0, "lon": 0}, {"lat": 0, "lon": 1}, {"lat": 1, "lon": 1}, {"lat": 0, "lon": 0}]}) is not None, "a closed way is a ring")
    # A fixture answer, twice the same bytes.
    answer = {"osm3s": {"timestamp_osm_base": "2026-09-26T00:00:00Z"}, "elements": [
        {"type": "node", "id": 7, "lat": 50.33, "lon": 6.92, "tags": {"natural": "tree", "leaf_type": "broadleaved"}},
        {"type": "way", "id": 5, "tags": {"landuse": "forest"}, "geometry": [{"lat": 50.33, "lon": 6.92}, {"lat": 50.331, "lon": 6.92}, {"lat": 50.331, "lon": 6.921}, {"lat": 50.33, "lon": 6.92}]},
        {"type": "way", "id": 6, "tags": {"landuse": "farmland"}, "geometry": [{"lat": 50.33, "lon": 6.93}, {"lat": 50.331, "lon": 6.93}]},
        {"type": "way", "id": 8, "tags": {"waterway": "stream"}, "geometry": [{"lat": 50.33, "lon": 6.93}, {"lat": 50.331, "lon": 6.93}]},
        {"type": "way", "id": 9, "tags": {"landuse": "residential"}, "geometry": [{"lat": 50.33, "lon": 6.93}, {"lat": 50.331, "lon": 6.93}, {"lat": 50.331, "lon": 6.931}, {"lat": 50.33, "lon": 6.93}]},
        {"type": "relation", "id": 5, "tags": {"natural": "wood"}, "members": [
            {"type": "way", "role": "outer", "geometry": [{"lat": 50.34, "lon": 6.92}, {"lat": 50.341, "lon": 6.92}]},
            {"type": "way", "role": "outer", "geometry": [{"lat": 50.341, "lon": 6.92}, {"lat": 50.341, "lon": 6.921}, {"lat": 50.34, "lon": 6.92}]},
            {"type": "way", "role": "inner", "geometry": [{"lat": 50.3405, "lon": 6.9201}, {"lat": 50.3406, "lon": 6.9201}, {"lat": 50.3406, "lon": 6.9202}, {"lat": 50.3405, "lon": 6.9201}]},
        ]},
    ]}
    fetch = {"answer_sha256": "0" * 64}
    one = landcover_text(build_landcover(answer, fetch, "x", "0" * 64))
    two = landcover_text(build_landcover(json.loads(json.dumps(answer)), fetch, "x", "0" * 64))
    built = json.loads(one)
    check(one == two, "two runs on the same answer give the same bytes (%d)" % len(one))
    check(built["counts"] == {"forests": 2, "fields": 0, "water": 0, "waterways": 1, "rock": 0, "trees": 1, "tree_rows": 0}, "the fixture keeps 2 forests (a way, a relation), 1 waterway, 1 tree: %s" % built["counts"])
    check(built["provenance"]["dropped"]["open_way_polygon"] == 1 and built["provenance"]["dropped"]["residential_industrial_place"] == 1, "the open farmland way and the residential polygon are dropped and counted: %s" % built["provenance"]["dropped"])
    relation = [f for f in built["forests"] if f["type"] == "relation"][0]
    check(len(relation["outer"]) == 1 and len(relation["inner"]) == 1 and relation["outer"][0][0] == relation["outer"][0][-1], "the relation's two outer members chain into one ring, the inner ring kept, closed in the file")
    check([f["osm"] for f in built["forests"]] == [5, 5] and built["forests"][0]["type"] == "relation", "elements sorted by (id, type): the relation 5 before the way 5")
    sample = built["provenance"]["projection"]["samples"][0]
    check(sample["osm"] == 5 and built["forests"][1]["outer"][0][0] == [sample["x"], sample["z"]], "the projection sample is forest way 5's first node, the same metres as its ring's first point")
    print("LANDCOVER SELFTEST PASSED" if failures == 0 else "LANDCOVER SELFTEST FAILED: %d" % failures)
    return 0 if failures == 0 else 1


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--snapshot", help="the snapshot folder extract_osm.py wrote")
    parser.add_argument("--out", help="where to write landcover.json")
    parser.add_argument("--prove", action="store_true", help="hold the projection port to skeleton.json (needs --skeleton and --q1)")
    parser.add_argument("--skeleton", help="the checked-in skeleton.json")
    parser.add_argument("--q1", help="the raw q1_skeleton.json of the 4B-2 pull")
    parser.add_argument("--selftest", action="store_true", help="prove the rules on fixtures built here")
    args = parser.parse_args(argv)
    if args.selftest:
        return selftest()
    if args.prove:
        if not args.skeleton or not args.q1:
            parser.error("--prove needs --skeleton and --q1")
        return prove(args.skeleton, args.q1)
    if not args.snapshot or not args.out:
        parser.error("--snapshot and --out are needed")
    answer, fetch, osm_base, query_sha = load_snapshot(args.snapshot)
    landcover = build_landcover(answer, fetch, osm_base, query_sha)
    size, sha = write_landcover(args.out, landcover)
    print("wrote %s: %d bytes, sha256 %s, counts %s, dropped %s" % (args.out, size, sha, landcover["counts"], landcover["provenance"]["dropped"]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

#!/usr/bin/env python3
"""The project and skeleton stages of the 4B data pipeline
(docs/design/4b/data-pipeline.md §3 and §4): the pinned OSM snapshot's
drivable ways (q1) projected to EPSG:25832 region metres, split at
junctions, Douglas-Peucker'd at 0.3 m, given a width by tag or class, and
relation 38566's members chained into the Nordschleife loop; written as
skeleton.json, the one derived file the game reads (scripts/skeleton_loader.gd).

Deterministic by construction (§7): same snapshot, same bytes. Ids are the
OSM ids; segments and junctions are sorted by id; coordinates are rounded to
the millimetre; JSON keys are sorted, separators compact; the only timestamp
inside is the snapshot's own identity. Heights are not here: the drape (4B-3)
adds them; a point is [x, z] only.

Usage:
  venv/bin/python tools/world/skeleton.py --snapshot <folder> --out data/regions/eifel_ring/skeleton.json
  venv/bin/python tools/world/skeleton.py --snapshot <folder> --selftest
  venv/bin/python tools/world/skeleton.py --reference

<folder> is what extract_osm.py wrote: q1_skeleton.json, q2_nordschleife.json
and the six .ql files (the query_sha is over those, in q1..q6 order).
--selftest proves the pipeline's rules on the checked-in sample
(docs/design/4b/samples/), a synthetic fixture and the real snapshot: the
pyproj round trip, every removed node within the tolerance of its chord,
every node with a heading change over 1° kept, the sample's ways in the
output. --reference prints the pinned projection table tests/skeleton_test.gd
embeds. Neither is a suite step: the suite has no pyproj.

Needs pyproj, which the system python does not have. The venv:
  python3 -m venv venv && venv/bin/pip install pyproj
"""

import argparse
import hashlib
import json
import math
import os
import re
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

# The pipeline's own version in skeleton.snapshot (data-pipeline.md §7: a
# derived file carries the pipeline's own version; the codex review of 4B-2
# counted the field missing). Bumped when the pipeline's output changes:
# 1 = the 4B-2 pipeline (projection, split, DP 0.3 m + heading keep, widths,
# loop), as first shipped. chosen for the skeleton: the docs' schema gained
# the field with this commit, the loader and the test hold it.
PIPELINE_VERSION = 1

# The simplification (data-pipeline.md §4 item 2): Douglas-Peucker at 0.3 m
# removes collinear noise only. chosen for the skeleton: a node whose heading
# changes by more than HEADING_KEEP_DEG is never removed, whatever its
# offset — at OSM's ~19 m node spacing a 1° bend sits only ~0.17 m off its
# chord, so plain DP would eat it; the plan's test ("DP keeps every node with
# heading change > 1°") is the rule, the tolerance is the filter within it.
DP_TOLERANCE_M = 0.3  # [m] a node closer than this to its chord is noise
HEADING_KEEP_DEG = 1.0  # [deg] a node bending more than this is geometry

# Total paved width by highway class [m], data-pipeline.md §4's table.
# chosen for the skeleton: motorway/trunk carry the 7.5 m carriageway; the
# 2.5 m hard shoulder is the element's (R13) own parameter, not the paved
# centre width. The *_link classes take their parent's value (the table has
# no row for them; a link is the same cross-section, shorter).
CLASS_WIDTH_M = {
    "motorway": 7.5, "trunk": 7.5, "motorway_link": 7.5, "trunk_link": 7.5,
    "primary": 7.0, "primary_link": 7.0,
    "secondary": 6.5, "secondary_link": 6.5,
    "tertiary": 6.0, "tertiary_link": 6.0, "unclassified": 6.0,
    "residential": 5.5, "living_street": 5.5,
    "service": 3.0, "track": 3.0,
    "raceway": 8.5,
}

# The Karussell (ring-region-decisions.md §2, put in stone): 7.5 m where the
# rest of the R17 is 8.5 m. And OSM width=* on raceway ways is ignored (22
# of the 52 say 5; the recorded track is 8-9 m; element-library.md open
# question 1).
KARUSSELL_WAY = 414785755
KARUSSELL_WIDTH_M = 7.5  # [m]
WIDTH_TAG_IGNORED_CLASSES = ("raceway",)

# chosen for the skeleton: "plausible for the class" (§4 item 3) is not
# defined in the docs. A width=* tag is taken when it is within
# [0.5, 2.0] × the class value: half a lane's road is still a road of that
# class, twice is a dual carriageway mis-tagged or a car park; outside the
# band the class value stands and width_source says so.
TAG_WIDTH_BAND = (0.5, 2.0)  # [× class width]

# What is carried per segment when the OSM tag is there (§4 item 4), values
# verbatim as OSM strings.
CARRIED_TAGS = ["bridge", "layer", "maxspeed", "name", "oneway", "ref", "surface", "tunnel"]

# The loop (§4 item 5). chosen for the skeleton: the documented schema has no
# loop anchor; the closure test needs one, so `loops` is an additive list of
# {id, rel, segments}. The chain is built from shared endpoint nodes (way(r)'s
# output order is not the member order), start pinned: the member way with
# the smallest OSM id, its smaller endpoint node as the first point; at a
# node with more than one unused continuation the smallest segment id.
NORDSCHLEIFE_RELATION = 38566
NORDSCHLEIFE_LOOP_ID = "nordschleife"

SEGMENT_ID_PATTERN = re.compile(r"^[1-9][0-9]*-(0|[1-9][0-9]*)$")
QUERY_DATE_PATTERN = re.compile(r'\[date:"([0-9T:Z-]+)"\]')

SAMPLE_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "docs", "design", "4b", "samples", "nordschleife-karussell-sample.json")

_transformer = None
_inverse = None


def _transformers():
    """pyproj's 4326 -> 25832 (always_xy: lon, lat in) and its inverse, made once."""
    global _transformer, _inverse
    if _transformer is None:
        from pyproj import Transformer
        _transformer = Transformer.from_crs(4326, EPSG, always_xy=True)
        _inverse = Transformer.from_crs(EPSG, 4326, always_xy=True)
    return _transformer, _inverse


def project(lat, lon):
    """WGS84 (lat, lon) [deg] -> region (x, z) [m], rounded to the millimetre."""
    forward, _ = _transformers()
    easting, northing = forward.transform(lon, lat)
    # + 0.0 turns a rounded -0.0 into 0.0: one spelling of zero in the file.
    return round(easting - E0, 3) + 0.0, round(-(northing - N0), 3) + 0.0


def unproject(x, z):
    """Region (x, z) [m] -> WGS84 (lat, lon) [deg], the inverse for the self-test."""
    _, inverse = _transformers()
    lon, lat = inverse.transform(x + E0, N0 - z)
    return lat, lon


def load_snapshot(folder):
    """The snapshot folder's q1 ways, q2 way ids, osm_base and query_sha.
    The osm_base is the attic date the six queries asked for (they must agree
    with each other and with extract_osm.OSM_BASE); the server's own
    timestamp_osm_base only has to be at or after it (it reports its live
    database, not the attic view), else the answer cannot be the snapshot.
    A manifest.json is verified when the folder carries one: its sha256 per
    raw file must match, so a raw file rewritten by anything but the extract
    is refused (codex review of 4B-2)."""
    dates = set()
    manifest = None
    manifest_path = os.path.join(folder, "manifest.json")
    if os.path.exists(manifest_path):
        with open(manifest_path, "r", encoding="utf-8") as handle:
            manifest = json.load(handle)
    for name in extract_osm.QUERY_NAMES:
        with open(os.path.join(folder, name + ".ql"), "r", encoding="utf-8") as handle:
            text = handle.read()
        if text != extract_osm.QUERIES[name]:
            raise ValueError("%s.ql in %s is not the query extract_osm.py writes" % (name, folder))
        dates.update(QUERY_DATE_PATTERN.findall(text))
    if dates != {extract_osm.OSM_BASE}:
        raise ValueError("the queries' attic dates are %s, the pinned snapshot is %s" % (sorted(dates), extract_osm.OSM_BASE))
    osm_base = extract_osm.OSM_BASE
    raws = {}
    for name in ("q1_skeleton", "q2_nordschleife"):
        with open(os.path.join(folder, name + ".json"), "r", encoding="utf-8") as handle:
            raws[name] = json.load(handle)
        served = raws[name].get("osm3s", {}).get("timestamp_osm_base", "")
        if served < osm_base:
            raise ValueError("%s was served from a database of %s, older than the attic date %s" % (name, served, osm_base))
        if "remark" in raws[name]:
            # Overpass puts a remark on a failed or truncated run even with
            # some elements in it (codex review of 4B-2); a raw file like that
            # is not the query's data: refuse it, never build from it.
            raise ValueError("%s carries a remark, not a clean answer: %s" % (name, raws[name]["remark"]))
        if extract_osm.sha256_of(os.path.join(folder, name + ".json")) != (manifest or {}).get("queries", {}).get(name, {}).get("sha256"):
            raise ValueError("%s's sha256 does not match the snapshot's manifest; the raw file was written by something else" % name)
    ways = [e for e in raws["q1_skeleton"]["elements"] if e.get("type") == "way"]
    loop_way_ids = sorted(e["id"] for e in raws["q2_nordschleife"]["elements"] if e.get("type") == "way")
    relations = [e for e in raws["q2_nordschleife"]["elements"] if e.get("type") == "relation"]
    if [r["id"] for r in relations] != [NORDSCHLEIFE_RELATION]:
        raise ValueError("q2 holds relations %s, expected exactly %d" % ([r["id"] for r in relations], NORDSCHLEIFE_RELATION))
    return ways, loop_way_ids, osm_base, extract_osm.query_sha(folder)


def perpendicular_distance(point, start, end):
    """Distance [m] of `point` from the chord start-end (from `start` when the chord has no length)."""
    dx, dz = end[0] - start[0], end[1] - start[1]
    length_sq = dx * dx + dz * dz
    if length_sq == 0.0:
        return math.hypot(point[0] - start[0], point[1] - start[1])
    t = ((point[0] - start[0]) * dx + (point[1] - start[1]) * dz) / length_sq
    t = max(0.0, min(1.0, t))
    return math.hypot(point[0] - (start[0] + t * dx), point[1] - (start[1] + t * dz))


def heading_change_deg(points, i):
    """The bend at interior point i [deg]: the angle between the step in and
    the step out; 0 where a step has no length (a repeated node)."""
    ax, az = points[i][0] - points[i - 1][0], points[i][1] - points[i - 1][1]
    bx, bz = points[i + 1][0] - points[i][0], points[i + 1][1] - points[i][1]
    la, lb = math.hypot(ax, az), math.hypot(bx, bz)
    if la == 0.0 or lb == 0.0:
        return 0.0
    cosine = max(-1.0, min(1.0, (ax * bx + az * bz) / (la * lb)))
    return math.degrees(math.acos(cosine))


def douglas_peucker_keep(points, first, last, tolerance, keep):
    """Marks in `keep` the points of points[first..last] DP keeps at `tolerance`:
    the farthest point from the chord when it is not closer than the tolerance,
    then each side again. Iterative, in index order: deterministic."""
    stack = [(first, last)]
    while stack:
        a, b = stack.pop()
        if b - a < 2:
            continue
        farthest, distance = -1, -1.0
        for i in range(a + 1, b):
            d = perpendicular_distance(points[i], points[a], points[b])
            if d > distance:
                farthest, distance = i, d
        if distance >= tolerance:
            keep[farthest] = True
            stack.append((farthest, b))
            stack.append((a, farthest))


def simplify_indices(points, tolerance=DP_TOLERANCE_M, keep_deg=HEADING_KEEP_DEG):
    """The indices of `points` the skeleton keeps: both ends, every interior
    point bending more than keep_deg, and between those what DP keeps."""
    n = len(points)
    if n <= 2:
        return list(range(n))
    keep = [False] * n
    keep[0] = keep[n - 1] = True
    for i in range(1, n - 1):
        if heading_change_deg(points, i) > keep_deg:
            keep[i] = True
    anchors = [i for i in range(n) if keep[i]]
    for a, b in zip(anchors, anchors[1:]):
        douglas_peucker_keep(points, a, b, tolerance, keep)
    return [i for i in range(n) if keep[i]]


def parse_width_tag(value):
    """OSM width=* as metres, or None when it is not a plain number ("5",
    "5.5", "5,5", "5 m" are; "2 lanes" is not)."""
    text = value.strip().lower().replace(",", ".")
    if text.endswith("m"):
        text = text[:-1].strip()
    try:
        width = float(text)
    except ValueError:
        return None
    if not math.isfinite(width) or width <= 0.0:
        return None
    return width


def width_of(way_id, road_class, tags):
    """(width_m, width_source) per §4 item 3 and the Ring's stone."""
    if way_id == KARUSSELL_WAY:
        return KARUSSELL_WIDTH_M, "class"
    by_class = CLASS_WIDTH_M[road_class]
    if road_class in WIDTH_TAG_IGNORED_CLASSES or "width" not in tags:
        return by_class, "class"
    tagged = parse_width_tag(tags["width"])
    if tagged is None or tagged < TAG_WIDTH_BAND[0] * by_class or tagged > TAG_WIDTH_BAND[1] * by_class:
        return by_class, "class"
    return round(tagged, 3), "tag"


def road_ways(ways):
    """The q1 ways that are roads here, sorted by id: a class of the table,
    two or more nodes, a geometry per node. The rest is skipped (the count
    is in build_skeleton's summary)."""
    kept = []
    for way in sorted(ways, key=lambda w: w["id"]):
        road_class = way.get("tags", {}).get("highway")
        if road_class in CLASS_WIDTH_M and len(way.get("nodes", [])) >= 2 and len(way.get("geometry", [])) == len(way["nodes"]):
            kept.append(way)
    return kept


def junction_nodes(ways):
    """§4 item 1: the node ids two or more of `ways` share."""
    usage = {}
    for way in ways:
        for node in set(way["nodes"]):
            usage[node] = usage.get(node, 0) + 1
    return {node for node, count in usage.items() if count >= 2}


def pieces_of(way, junctions):
    """A way split at every interior junction node: (k, node ids, projected
    points) per piece, k the split index in the segment id."""
    nodes = way["nodes"]
    points = [project(g["lat"], g["lon"]) for g in way["geometry"]]
    cuts = [0] + [i for i in range(1, len(nodes) - 1) if nodes[i] in junctions] + [len(nodes) - 1]
    return [(k, nodes[a:b + 1], points[a:b + 1]) for k, (a, b) in enumerate(zip(cuts, cuts[1:]))]


def build_skeleton(ways, loop_way_ids, osm_base, query_sha):
    """§4 on the q1 ways: junctions where ≥ 2 ways share a node, ways split
    there, each piece simplified, widened, tagged; then the loop."""
    kept_ways = road_ways(ways)
    skipped = len(ways) - len(kept_ways)
    junctions = junction_nodes(kept_ways)

    segments = []
    ends = {}  # segment id -> (first node, last node)
    junction_of = {}  # node id -> {"point": (x, z), "segments": set()}
    for way in kept_ways:
        for k, nodes, piece in pieces_of(way, junctions):
            kept = simplify_indices(piece)
            width, source = width_of(way["id"], way["tags"]["highway"], way["tags"])
            segment = {
                "id": "%d-%d" % (way["id"], k),
                "osm_way": way["id"],
                "class": way["tags"]["highway"],
                "width_m": width,
                "width_source": source,
                "points": [[piece[i][0], piece[i][1]] for i in kept],
            }
            for tag in CARRIED_TAGS:
                if tag in way["tags"]:
                    segment[tag] = way["tags"][tag]
            segments.append(segment)
            ends[segment["id"]] = (nodes[0], nodes[-1])
            for node, point in ((nodes[0], piece[0]), (nodes[-1], piece[-1])):
                if node in junctions:
                    junction_of.setdefault(node, {"point": point, "segments": set()})["segments"].add(segment["id"])
    segments.sort(key=lambda s: s["id"])
    junction_records = [
        {"id": str(node), "x": entry["point"][0], "z": entry["point"][1], "segments": sorted(entry["segments"])}
        for node, entry in junction_of.items()
    ]
    junction_records.sort(key=lambda j: j["id"])
    loop = chain_loop(segments, ends, loop_way_ids)
    skeleton = {
        "snapshot": {"osm_base": osm_base, "bbox": BBOX, "query_sha": query_sha, "pipeline_version": PIPELINE_VERSION},
        "origin": {"epsg": EPSG, "e0": E0, "n0": N0},
        "segments": segments,
        "junctions": junction_records,
        "loops": [loop],
    }
    points_split = sum(len(nodes) for way in kept_ways for _, nodes, _ in pieces_of(way, junctions))
    summary = {
        "ways": len(ways), "skipped": skipped, "junctions": len(junction_records), "segments": len(segments),
        "way_nodes": sum(len(w["nodes"]) for w in kept_ways),
        "points_split": points_split, "points_out": sum(len(s["points"]) for s in segments), "points_removed": points_split - sum(len(s["points"]) for s in segments),
        "loop_segments": len(loop["segments"]), "loop_length_m": round(loop_length(skeleton), 3),
    }
    return skeleton, summary


def chain_loop(segments, ends, loop_way_ids):
    """Relation 38566's members as one ordered chain of segment ids (the
    rule in the header comment). Raises when the members do not close into
    one loop: that is a data change, never something to paper over."""
    members = [s for s in segments if s["osm_way"] in set(loop_way_ids)]
    found_ways = sorted({s["osm_way"] for s in members})
    if found_ways != list(loop_way_ids):
        raise ValueError("relation %d has %d ways, %d of them in q1: %s missing" % (NORDSCHLEIFE_RELATION, len(loop_way_ids), len(found_ways), sorted(set(loop_way_ids) - set(found_ways))))
    at_node = {}
    for s in members:
        for node in ends[s["id"]]:
            at_node.setdefault(node, []).append(s["id"])
    start_way = min(loop_way_ids)
    start_way_segments = sorted(s["id"] for s in members if s["osm_way"] == start_way)
    start_node = min(ends[start_way_segments[0]][0], ends[start_way_segments[-1]][1])
    chain = []
    used = set()
    node = start_node
    while True:
        candidates = sorted(sid for sid in at_node.get(node, []) if sid not in used)
        if not candidates:
            break
        sid = candidates[0]
        used.add(sid)
        chain.append(sid)
        a, b = ends[sid]
        node = b if a == node else a
        if node == start_node:
            break
    if node != start_node or len(chain) != len(members):
        raise ValueError("relation %d does not close into one loop: %d of %d members chained, ended at node %s" % (NORDSCHLEIFE_RELATION, len(chain), len(members), node))
    # The stored chain must also be walkable as it is stored (codex review of
    # 4B-2: the chain walked node ids, not the stored points, so a segment
    # stored tail-first passed silently): consecutive segments share an
    # endpoint to the millimetre, and an oneway segment must be entered at its
    # stored first point — the whole loop runs the way traffic does.
    by_id = {s["id"]: s for s in segments}
    for a, b in zip(chain, chain[1:] + chain[:1]):
        pa, pb = by_id[a]["points"], by_id[b]["points"]
        if pa[-1] == pb[0]:
            enters_first = True
        elif pa[-1] == pb[-1]:
            enters_first = False
        else:
            raise ValueError("loop: %s's stored points do not join %s's" % (a, b))
        if not enters_first and by_id[b].get("oneway") == "yes":
            raise ValueError("loop: %s is oneway but the chain runs it backwards" % b)
    return {"id": NORDSCHLEIFE_LOOP_ID, "rel": NORDSCHLEIFE_RELATION, "segments": chain}


def polyline_length(points):
    return sum(math.hypot(b[0] - a[0], b[1] - a[1]) for a, b in zip(points, points[1:]))


def loop_length(skeleton, loop_index=0):
    by_id = {s["id"]: s for s in skeleton["segments"]}
    return sum(polyline_length(by_id[sid]["points"]) for sid in skeleton["loops"][loop_index]["segments"])


def dumps(skeleton):
    """The bytes of skeleton.json: keys sorted, separators compact, UTF-8 as is, one trailing newline."""
    return json.dumps(skeleton, sort_keys=True, separators=(",", ":"), ensure_ascii=False) + "\n"


def write_skeleton(path, skeleton):
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    data = dumps(skeleton).encode("utf-8")
    with open(path, "wb") as handle:
        handle.write(data)
    return len(data), hashlib.sha256(data).hexdigest()


# --- the self-test and the reference table -----------------------------------

def reference_points():
    """The pinned (lat, lon) -> (x, z) pairs tests/skeleton_test.gd embeds:
    the origin, 20 km east and north of it, the bbox corners, and the
    checked-in sample's way endpoints. lat/lon rounded to 1e-9° (0.1 mm)
    first, then projected, so the table is consistent with itself."""
    named = [("origin", 0.0, 0.0), ("20 km east", 20000.0, 0.0), ("20 km north", 0.0, -20000.0)]
    points = []
    for name, x, z in named:
        lat, lon = unproject(x, z)
        points.append((name, round(lat, 9), round(lon, 9)))
    for name, lat, lon in (("bbox south-west", BBOX[0], BBOX[1]), ("bbox north-east", BBOX[2], BBOX[3])):
        points.append((name, lat, lon))
    with open(SAMPLE_PATH, "r", encoding="utf-8") as handle:
        sample = json.load(handle)
    for way in sample["elements"]:
        for label, node in (("first", way["geometry_latlon"][0]), ("last", way["geometry_latlon"][-1])):
            points.append(("sample way %d %s node" % (way["id"], label), node[0], node[1]))
    rows = []
    for name, lat, lon in points:
        x, z = project(lat, lon)
        rows.append({"name": name, "lat": lat, "lon": lon, "x": x, "z": z})
    return rows


def print_reference():
    print("# pyproj %s (PROJ %s), EPSG:4326 -> EPSG:%d always_xy, origin E0 %.0f N0 %.0f; x = E - E0, z = -(N - N0), mm-rounded" % (__import__("pyproj").__version__, __import__("pyproj").proj_version_str, EPSG, E0, N0))
    for row in reference_points():
        print('\t{"name": "%s", "lat": %.9f, "lon": %.9f, "x": %.3f, "z": %.3f},' % (row["name"], row["lat"], row["lon"], row["x"], row["z"]))


def synthetic_ways():
    """A five-way fixture in raw OSM shape (the same the GDScript test builds
    from its own numbers): two roads crossing at a junction, a third ending
    on one of them, and a two-way mini loop; classes from the table,
    oneway and width tags on some."""
    def geom(latlons):
        return [{"lat": lat, "lon": lon} for lat, lon in latlons]
    return [
        {"type": "way", "id": 1, "nodes": [11, 12, 13, 14], "tags": {"highway": "primary", "ref": "B 999"},
         "geometry": geom([(50.35, 6.90), (50.35, 6.905), (50.35, 6.910), (50.35, 6.915)])},
        {"type": "way", "id": 2, "nodes": [21, 12, 22], "tags": {"highway": "residential", "name": "Ringstraße", "width": "4.5"},
         "geometry": geom([(50.352, 6.905), (50.35, 6.905), (50.348, 6.905)])},
        {"type": "way", "id": 3, "nodes": [31, 13], "tags": {"highway": "service", "oneway": "yes", "width": "40"},
         "geometry": geom([(50.353, 6.910), (50.35, 6.910)])},
        {"type": "way", "id": 4, "nodes": [14, 41, 42], "tags": {"highway": "raceway", "oneway": "yes", "width": "5"},
         "geometry": geom([(50.35, 6.915), (50.351, 6.916), (50.352, 6.915)])},
        {"type": "way", "id": 5, "nodes": [42, 51, 14], "tags": {"highway": "raceway", "oneway": "yes"},
         "geometry": geom([(50.352, 6.915), (50.351, 6.914), (50.35, 6.915)])},
    ]


def selftest(folder):
    """The pipeline's rules proven and reported; exits 1 on any fault."""
    faults = 0

    def ok(condition, what):
        nonlocal faults
        print(("  ok    " if condition else "  FAIL  ") + what)
        if not condition:
            faults += 1

    # The projection round trip, the plan's numbers: < 0.01 m at the origin, < 0.5 m at 20 km.
    for name, x, z, limit in (("origin", 0.0, 0.0, 0.01), ("20 km east", 20000.0, 0.0, 0.5), ("20 km north", 0.0, -20000.0, 0.5), ("20 km north-east", 14142.136, -14142.136, 0.5)):
        lat, lon = unproject(x, z)
        back = project(lat, lon)
        error = math.hypot(back[0] - x, back[1] - z)
        ok(error < limit, "projection round trip at %s: %.4f m (< %.2f m)" % (name, error, limit))

    # The simplification rules, on the sample, the fixture and the real snapshot.
    sources = []
    with open(SAMPLE_PATH, "r", encoding="utf-8") as handle:
        sample = json.load(handle)
    sources.append(("the checked-in sample", [[project(lat, lon) for lat, lon in w["geometry_latlon"]] for w in sample["elements"]]))
    sources.append(("the synthetic fixture", [[project(g["lat"], g["lon"]) for g in w["geometry"]] for w in synthetic_ways()]))
    ways, loop_way_ids, osm_base, query_sha = load_snapshot(folder)
    kept_ways = road_ways(ways)
    junctions = junction_nodes(kept_ways)
    real = [piece for way in kept_ways for _, _, piece in pieces_of(way, junctions)]
    sources.append(("the snapshot's q1 ways split at junctions", real))
    for name, polylines in sources:
        nodes = removed = bends = bends_kept = worst = 0
        worst_offset = 0.0
        for points in polylines:
            kept = simplify_indices(points)
            kept_set = set(kept)
            nodes += len(points)
            for i in range(1, len(points) - 1):
                if heading_change_deg(points, i) > HEADING_KEEP_DEG:
                    bends += 1
                    bends_kept += 1 if i in kept_set else 0
            for a, b in zip(kept, kept[1:]):
                for i in range(a + 1, b):
                    removed += 1
                    offset = perpendicular_distance(points[i], points[a], points[b])
                    worst_offset = max(worst_offset, offset)
                    worst += 1 if offset >= DP_TOLERANCE_M else 0
        ok(worst == 0, "%s: %d of %d nodes removed, every one < %.1f m off its chord (worst %.4f m)" % (name, removed, nodes, DP_TOLERANCE_M, worst_offset))
        ok(bends_kept == bends, "%s: every node with a heading change > %.0f° kept (%d of %d)" % (name, HEADING_KEEP_DEG, bends_kept, bends))

    # The whole pipeline on the fixture: ids, junctions, widths, the mini loop.
    fixture, summary = build_skeleton(synthetic_ways(), [4, 5], osm_base, query_sha)
    by_id = {s["id"]: s for s in fixture["segments"]}
    ok(sorted(by_id) == ["1-0", "1-1", "1-2", "2-0", "2-1", "3-0", "4-0", "5-0"], "fixture: way 1 split at its two junctions, way 2 at one: %s" % sorted(by_id))
    ok([j["id"] for j in fixture["junctions"]] == ["12", "13", "14", "42"] and all(len(j["segments"]) >= 2 for j in fixture["junctions"]), "fixture: junctions 12, 13, 14, 42, each with ≥ 2 segments")
    ok(by_id["1-0"]["width_m"] == 7.0 and by_id["1-0"]["width_source"] == "class", "fixture: primary without width=* is 7.0 m by class")
    ok(by_id["2-0"]["width_m"] == 4.5 and by_id["2-0"]["width_source"] == "tag", "fixture: residential width=4.5 (inside [0.5, 2] × 5.5) is 4.5 m by tag")
    ok(by_id["3-0"]["width_m"] == 3.0 and by_id["3-0"]["width_source"] == "class", "fixture: service width=40 (outside the band) is 3.0 m by class")
    ok(by_id["4-0"]["width_m"] == 8.5 and by_id["4-0"]["width_source"] == "class", "fixture: raceway width=5 ignored, 8.5 m by class")
    ok(by_id["3-0"].get("oneway") == "yes" and "oneway" not in by_id["1-0"] and by_id["2-0"].get("name") == "Ringstraße", "fixture: oneway/name carried only where tagged")
    ok(fixture["loops"][0]["segments"] == ["4-0", "5-0"] and summary["loop_segments"] == 2, "fixture: the two raceway ways chain into the loop [4-0, 5-0]")
    ok(dumps(fixture) == dumps(build_skeleton(synthetic_ways(), [4, 5], osm_base, query_sha)[0]), "fixture: built twice, the same bytes")

    # The real snapshot: the sample's ways present, their endpoints where the sample's lat/lon say.
    skeleton, summary = build_skeleton(ways, loop_way_ids, osm_base, query_sha)
    print("  snapshot %s: %s" % (osm_base, summary))
    ways_of = {}
    for s in skeleton["segments"]:
        ways_of.setdefault(s["osm_way"], []).append(s)
    for way in sample["elements"]:
        pieces = sorted(ways_of.get(way["id"], []), key=lambda s: int(s["id"].split("-")[1]))
        if not pieces:
            ok(False, "sample way %d (%s) is in the skeleton" % (way["id"], way["tags"].get("name")))
            continue
        first, last = project(*way["geometry_latlon"][0]), project(*way["geometry_latlon"][-1])
        got_first, got_last = pieces[0]["points"][0], pieces[-1]["points"][-1]
        error = max(math.hypot(got_first[0] - first[0], got_first[1] - first[1]), math.hypot(got_last[0] - last[0], got_last[1] - last[1]))
        ok(error < 0.5, "sample way %d (%s) is in the skeleton as %d segment(s), endpoints within 0.5 m of the sample's lat/lon (%.3f m; the sample is rounded to 1e-6°)" % (way["id"], way["tags"].get("name"), len(pieces), error))
    karussell = ways_of.get(KARUSSELL_WAY, [])
    ok(karussell and all(s["width_m"] == KARUSSELL_WIDTH_M for s in karussell), "the Karussell (way %d) is %.1f m wide" % (KARUSSELL_WAY, KARUSSELL_WIDTH_M))
    length = loop_length(skeleton)
    ok(abs(length - 20830.0) <= 0.01 * 20830.0, "the Nordschleife loop: %d segments, %.1f m, within 1 %% of 20 830 m" % (summary["loop_segments"], length))
    ok(dumps(skeleton) == dumps(build_skeleton(ways, loop_way_ids, osm_base, query_sha)[0]), "the snapshot built twice, the same bytes")
    print("SKELETON SELFTEST PASSED" if faults == 0 else "SKELETON SELFTEST FAILED: %d fault(s)" % faults)
    return 0 if faults == 0 else 1


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--snapshot", help="the snapshot folder extract_osm.py wrote")
    parser.add_argument("--out", help="where to write skeleton.json")
    parser.add_argument("--selftest", action="store_true", help="prove the pipeline's rules on the sample, a fixture and the snapshot")
    parser.add_argument("--reference", action="store_true", help="print the pinned projection table for tests/skeleton_test.gd")
    args = parser.parse_args(argv)
    if args.reference:
        print_reference()
        return 0
    if not args.snapshot:
        parser.error("--snapshot is needed")
    if args.selftest:
        return selftest(args.snapshot)
    if not args.out:
        parser.error("--out is needed")
    ways, loop_way_ids, osm_base, query_sha = load_snapshot(args.snapshot)
    skeleton, summary = build_skeleton(ways, loop_way_ids, osm_base, query_sha)
    size, sha = write_skeleton(args.out, skeleton)
    print("wrote %s: %d bytes, sha256 %s" % (args.out, size, sha))
    print("  %s" % summary)
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

#!/usr/bin/env python3
"""The OSM extract of the 4B data pipeline (docs/design/4b/data-pipeline.md
§2.1): the six Overpass queries of the Ring bbox, written out as .ql files
and fetched one after the other into one pinned snapshot folder.

This runs OFFLINE, ahead of the game, and never inside it: the suite runs no
network step (data-pipeline.md §7). Raw pulls are large and live outside the
repo; the repo keeps only the small derived skeleton (skeleton.py).

The snapshot is pinned (ring-region-decisions.md §1, put in stone): every
query carries the attic date `[date:"2026-09-22T08:45:51Z"]` so a re-run asks
the server for the same database state. The answer's
`osm3s.timestamp_osm_base` is the serving database's own (live) time, not
the attic date (measured 2026-09-23); it has to be at or past the attic
date, else the answer is refused. The date the data is as of is the .ql
files' `[date:...]`, which is what skeleton.json carries as osm_base. A
re-pin is a documented "was ->" decision, never this script's.

Usage:
  python3 tools/world/extract_osm.py --out <folder>            fetch all six
  python3 tools/world/extract_osm.py --out <folder> --only q1_skeleton,q2_nordschleife
  python3 tools/world/extract_osm.py --write-queries <folder>  the .ql files only

The folder gets a sub-folder named after the snapshot
(`ring_2026-09-22T08-45-51Z`, the timestamp with ':' as '-': §7's naming),
holding q*.ql, q*.json and manifest.json (endpoint, element count, sha256 per
query). Fetching uses curl exactly as §2.1's loop does (form-encoded `data@`:
a raw POST body gives 406 Not Acceptable) — curl is the one dependency.

This script needs no pyproj. skeleton.py does; its venv:
  python3 -m venv venv && venv/bin/pip install pyproj
"""

import argparse
import hashlib
import json
import os
import subprocess
import sys
import time

# The pinned snapshot: osm3s.timestamp_osm_base of the pull the Ring region
# was put in stone on (ring-region-decisions.md §1). Every query below asks
# for exactly this database state.
OSM_BASE = "2026-09-22T08:45:51Z"

# The Ring bbox, south, west, north, east [deg] (ring-region-decisions.md §1).
BBOX = "50.30,6.80,50.45,7.10"

# The Overpass endpoints, in the order they are tried: lz4 answered every
# query when measured; the other two said "too busy" (data-pipeline.md §2.1).
ENDPOINTS = [
    "https://lz4.overpass-api.de/api/interpreter",
    "https://overpass.kumi.systems/api/interpreter",
    "https://overpass-api.de/api/interpreter",
]

# The User-Agent naming the project (data-pipeline.md §2.1).
USER_AGENT = "factory-driver-4b/0.1 (world pipeline; okaypeace@gmail.com)"

CURL_MAX_TIME_S = 300  # [s] curl --max-time; the queries' own timeout is 300 s
PAUSE_BETWEEN_QUERIES_S = 10  # [s] one after the other; parallel pulls were throttled
RETRIES_PER_ENDPOINT = 3  # the first try and two retries
RETRY_PAUSE_S = 30  # [s] between retries of a busy endpoint

# The six queries of data-pipeline.md §2.1, verbatim, each with the attic
# date added to its settings block. q2 has no bbox: the relation is fetched
# whole, wherever its ways are. Fixed order: the query_sha of skeleton.json
# is the sha256 of these six files concatenated in this order.
QUERY_NAMES = ["q1_skeleton", "q2_nordschleife", "q3_economy", "q4_landcover", "q5_buildings", "q6_furniture"]

QUERIES = {
    "q1_skeleton": (
        '[out:json][timeout:300][bbox:' + BBOX + '][date:"' + OSM_BASE + '"];\n'
        'way["highway"~"^(motorway|trunk|primary|secondary|tertiary|unclassified|residential|living_street|service|track|raceway|motorway_link|trunk_link|primary_link|secondary_link|tertiary_link)$"];\n'
        "out geom;\n"
    ),
    "q2_nordschleife": (
        '[out:json][timeout:120][date:"' + OSM_BASE + '"];\n'
        "relation(38566);\n"
        "out tags;\n"
        "way(r);\n"
        "out geom;\n"
    ),
    "q3_economy": (
        '[out:json][timeout:300][bbox:' + BBOX + '][date:"' + OSM_BASE + '"];\n'
        "(\n"
        '  nwr["amenity"~"^(fuel|driving_school|animal_shelter|parking|place_of_worship)$"];\n'
        '  nwr["shop"~"^(car|car_repair|car_parts|tyres)$"];\n'
        '  nwr["historic"="castle"];\n'
        '  nwr["building"~"^(grandstand|industrial|warehouse|garage|garages|barn|farm|church)$"];\n'
        '  nwr["man_made"="storage_tank"];\n'
        '  nwr["landuse"="industrial"];\n'
        ");\n"
        "out geom;\n"
    ),
    "q4_landcover": (
        '[out:json][timeout:300][bbox:' + BBOX + '][date:"' + OSM_BASE + '"];\n'
        "(\n"
        '  way["landuse"~"^(forest|farmland|meadow|grass|residential|industrial)$"];\n'
        '  relation["landuse"~"^(forest|farmland|meadow)$"];\n'
        '  way["natural"~"^(wood|water|scrub|heath|cliff|bare_rock|tree_row)$"];\n'
        '  node["natural"="tree"];\n'
        '  way["waterway"~"^(river|stream|riverbank)$"];\n'
        '  way["place"~"^(village|town)$"]; node["place"~"^(village|town|hamlet)$"];\n'
        ");\n"
        "out geom;\n"
    ),
    "q5_buildings": (
        '[out:json][timeout:300][bbox:' + BBOX + '][date:"' + OSM_BASE + '"];\n'
        'way["building"];\n'
        "out geom;\n"
    ),
    # chosen for the skeleton: §2.1 gives q6 as a sentence ("barrier=* ways,
    # highway=street_lamp|stop|give_way, traffic_sign=*, power=pole|line,
    # railway=level_crossing|rail; out geom;"), not as QL. This is its faithful
    # composition: ways where the sentence says ways, nwr where it names a tag
    # that sits on nodes as well (traffic signs, level crossings). Nothing in
    # 4B-2 consumes q6; 4B-8's furniture pass is where its shape matters.
    "q6_furniture": (
        '[out:json][timeout:300][bbox:' + BBOX + '][date:"' + OSM_BASE + '"];\n'
        "(\n"
        '  way["barrier"];\n'
        '  way["highway"~"^(street_lamp|stop|give_way)$"];\n'
        '  nwr["traffic_sign"];\n'
        '  way["power"~"^(pole|line)$"];\n'
        '  nwr["railway"~"^(level_crossing|rail)$"];\n'
        ");\n"
        "out geom;\n"
    ),
}


def snapshot_folder_name(osm_base):
    """§7's snapshot naming: `ring_` + the timestamp with ':' written as '-'."""
    return "ring_" + osm_base.replace(":", "-")


def query_sha(folder):
    """sha256 over the six .ql files of `folder` concatenated in q1..q6 order:
    the identity of what was asked, carried by every derived file."""
    digest = hashlib.sha256()
    for name in QUERY_NAMES:
        with open(os.path.join(folder, name + ".ql"), "rb") as handle:
            digest.update(handle.read())
    return digest.hexdigest()


def write_queries(folder):
    """Writes the six .ql files into `folder`, byte-for-byte the constants above."""
    os.makedirs(folder, exist_ok=True)
    for name in QUERY_NAMES:
        with open(os.path.join(folder, name + ".ql"), "w", encoding="utf-8", newline="\n") as handle:
            handle.write(QUERIES[name])


def sha256_of(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def fetch_one(name, folder, endpoints, log):
    """Fetches query `name` into folder/name.json: §2.1's curl line, the
    endpoints in order, RETRIES_PER_ENDPOINT tries each. Returns the endpoint
    that served it and the parsed answer, or raises with the reason."""
    ql_path = os.path.join(folder, name + ".ql")
    json_path = os.path.join(folder, name + ".json")
    last_reason = "no endpoint tried"
    for endpoint in endpoints:
        for attempt in range(RETRIES_PER_ENDPOINT):
            if attempt > 0:
                log("  %s: retry %d of %d after %d s" % (name, attempt, RETRIES_PER_ENDPOINT - 1, RETRY_PAUSE_S))
                time.sleep(RETRY_PAUSE_S)
            command = [
                "curl", "-s", "--max-time", str(CURL_MAX_TIME_S), "-A", USER_AGENT,
                "--data-urlencode", "data@" + ql_path, endpoint, "-o", json_path, "-w", "%{http_code}",
            ]
            started = time.time()
            run = subprocess.run(command, capture_output=True, text=True)
            elapsed = time.time() - started
            code = run.stdout.strip()
            if run.returncode != 0:
                last_reason = "%s: curl exit %d (%s)" % (endpoint, run.returncode, run.stderr.strip())
                log("  " + last_reason)
                continue
            if code != "200":
                last_reason = "%s: HTTP %s after %.0f s" % (endpoint, code, elapsed)
                log("  " + last_reason)
                continue
            try:
                with open(json_path, "r", encoding="utf-8") as handle:
                    answer = json.load(handle)
            except ValueError as fault:
                last_reason = "%s: not JSON (%s)" % (endpoint, fault)
                log("  " + last_reason)
                continue
            if "remark" in answer and "elements" in answer and not answer["elements"]:
                last_reason = "%s: empty answer with remark: %s" % (endpoint, answer["remark"])
                log("  " + last_reason)
                continue
            return endpoint, answer, elapsed
    raise RuntimeError("%s: every endpoint failed; last: %s" % (name, last_reason))


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--out", help="folder that gets the snapshot sub-folder")
    parser.add_argument("--only", help="comma-separated query names to fetch (default: all six)")
    parser.add_argument("--write-queries", metavar="FOLDER", help="only write the six .ql files into FOLDER")
    parser.add_argument("--pause", type=float, default=PAUSE_BETWEEN_QUERIES_S, help="seconds between queries")
    args = parser.parse_args(argv)

    def log(line):
        print(line, flush=True)

    if args.write_queries:
        write_queries(args.write_queries)
        log("wrote %d queries to %s (query_sha %s)" % (len(QUERY_NAMES), args.write_queries, query_sha(args.write_queries)))
        return 0
    if not args.out:
        parser.error("--out or --write-queries is needed")
    names = QUERY_NAMES if not args.only else [n.strip() for n in args.only.split(",")]
    for name in names:
        if name not in QUERIES:
            parser.error("no query named %s; the six are %s" % (name, ", ".join(QUERY_NAMES)))

    folder = os.path.join(args.out, snapshot_folder_name(OSM_BASE))
    write_queries(folder)
    manifest_path = os.path.join(folder, "manifest.json")
    manifest = {"osm_base": OSM_BASE, "bbox": BBOX, "query_sha": query_sha(folder), "queries": {}}
    if os.path.exists(manifest_path):
        with open(manifest_path, "r", encoding="utf-8") as handle:
            manifest["queries"] = json.load(handle).get("queries", {})
    log("snapshot %s -> %s (query_sha %s)" % (OSM_BASE, folder, manifest["query_sha"]))

    failed = 0
    for i, name in enumerate(names):
        if i > 0:
            time.sleep(args.pause)
        log("%s ..." % name)
        try:
            endpoint, answer, elapsed = fetch_one(name, folder, ENDPOINTS, log)
        except RuntimeError as fault:
            log("  FAIL  %s" % fault)
            failed += 1
            continue
        # Measured 2026-09-23: an attic query's answer reports the serving
        # database's own timestamp_osm_base (live, minutes old), not the
        # attic date; the data is the attic view all the same (q2 answered
        # the recorded 52 ways / 1 119 nodes to the node). So the check is:
        # the server is at or past the attic date. What is recorded is the
        # attic date (the snapshot's identity) and, in the manifest only,
        # what the server said.
        base = answer.get("osm3s", {}).get("timestamp_osm_base", "")
        count = len(answer.get("elements", []))
        if base < OSM_BASE:
            log("  FAIL  %s: served from a database of %s, older than the pinned snapshot %s (a re-pin is a documented decision, not this script's)" % (name, base, OSM_BASE))
            failed += 1
            continue
        kinds = {}
        for element in answer["elements"]:
            kinds[element.get("type")] = kinds.get(element.get("type"), 0) + 1
        entry = {
            "endpoint": endpoint,
            "elements": count,
            "by_type": dict(sorted(kinds.items())),
            "served_timestamp_osm_base": base,
            "sha256": sha256_of(os.path.join(folder, name + ".json")),
            "bytes": os.path.getsize(os.path.join(folder, name + ".json")),
            "seconds": round(elapsed, 1),
        }
        manifest["queries"][name] = entry
        log("  ok    %s as of %s (served by a database of %s): %d elements %s from %s in %.0f s" % (name, OSM_BASE, base, count, entry["by_type"], endpoint, elapsed))
        with open(manifest_path, "w", encoding="utf-8") as handle:
            json.dump(manifest, handle, indent=1, sort_keys=True)
            handle.write("\n")
    if failed:
        log("EXTRACT FAILED: %d of %d queries" % (failed, len(names)))
        return 1
    log("EXTRACT OK: %d queries in %s" % (len(names), folder))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

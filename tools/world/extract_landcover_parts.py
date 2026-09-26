#!/usr/bin/env python3
"""The q4_landcover pull in parts (2026-09-26, the 4B-7 landing): the pinned
q4_landcover.ql of extract_osm.py, one union of six selectors with `out
geom`, was refused by every Overpass endpoint on the day the landcover was
first fetched - lz4 answered HTTP 504 three times, kumi.systems "runtime
error: Query run out of memory using about 2048 MB of RAM" and then, with
overpass-api.de, "runtime error: open64: 12 Cannot allocate memory
node_tags_global.bin" (extract_osm.py's own log; the attic node-tag lookup
over the bbox is what the servers could not hold). The data is not in
question: the same six selectors, each on its own, with the SAME settings
line (the Ring bbox, the pinned attic date [date:"2026-09-22T08:45:51Z"]),
answer the same attic state; the union of the six answers is q4's element
set (an element matching two selectors appears in two parts and once in
q4: landcover.py folds the parts by (type, id)).

This is the one network touch of the landcover stage and runs OFFLINE, ahead
of the game, never inside it (data-pipeline.md §7). It writes into the same
snapshot folder extract_osm.py uses (ring_2026-09-22T08-45-51Z/): one .ql
and one .json per part, named q4_landcover_part<N>_<what>, and records each
part in that folder's manifest.json under `queries` beside the six named
queries (additive keys: extract_osm.py's own entries are untouched, its
query_sha is over the six pinned .ql files and does not change). The refusal
itself is recorded in the manifest too (`q4_landcover_refused`), so the
derived file's header can cite it.

Usage:
  python3 tools/world/extract_landcover_parts.py --out <folder>     (the folder given to extract_osm.py --out)

The fetch is extract_osm.fetch_one: curl, the endpoints in order, the
retries, a staged download committed only when it parsed without a remark.
"""

import argparse
import hashlib
import json
import os
import sys
import time

sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import extract_osm  # noqa: E402

# The settings line q4 carries, verbatim (the bbox, the attic date).
SETTINGS = '[out:json][timeout:300][bbox:' + extract_osm.BBOX + '][date:"' + extract_osm.OSM_BASE + '"];\n'

# q4_landcover's six selectors, verbatim from extract_osm.QUERIES, one part each.
PARTS = [
    ("q4_landcover_part1_landuse_ways", 'way["landuse"~"^(forest|farmland|meadow|grass|residential|industrial)$"];\n'),
    ("q4_landcover_part2_landuse_relations", 'relation["landuse"~"^(forest|farmland|meadow)$"];\n'),
    ("q4_landcover_part3_natural_ways", 'way["natural"~"^(wood|water|scrub|heath|cliff|bare_rock|tree_row)$"];\n'),
    ("q4_landcover_part4_trees", 'node["natural"="tree"];\n'),
    ("q4_landcover_part5_waterways", 'way["waterway"~"^(river|stream|riverbank)$"];\n'),
    ("q4_landcover_part6_places", 'way["place"~"^(village|town)$"]; node["place"~"^(village|town|hamlet)$"];\n'),
]

REFUSAL = (
    "the pinned q4_landcover.ql was refused by every endpoint on 2026-09-26: lz4.overpass-api.de HTTP 504 (three tries), "
    "overpass.kumi.systems 'runtime error: Query run out of memory using about 2048 MB of RAM' then 'open64: 12 Cannot allocate memory "
    "/opt/osm/db/node_tags_global.bin', overpass-api.de 'open64: 12 Cannot allocate memory /srv/overpass/db/node_tags_global.bin' "
    "(extract_osm.py --only q4_landcover, its log); the six selectors were fetched one per part with the same settings line"
)


def part_query(selector):
    """A part's query text: the settings line, the selector inside a union
    block as q4 has it, out geom."""
    return SETTINGS + "(\n  " + selector.replace("; ", ";\n  ").rstrip("\n") + "\n);\nout geom;\n"


def main(argv):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--out", required=True, help="folder that holds the snapshot sub-folder (extract_osm.py --out)")
    parser.add_argument("--pause", type=float, default=extract_osm.PAUSE_BETWEEN_QUERIES_S, help="seconds between parts")
    parser.add_argument("--only", help="comma-separated part names to fetch (default: all six)")
    args = parser.parse_args(argv)
    only = None if not args.only else [n.strip() for n in args.only.split(",")]

    def log(line):
        print(line, flush=True)

    # The pinned selectors have to be q4's: a part that is not verbatim in
    # q4_landcover.ql is not a part of it.
    q4 = extract_osm.QUERIES["q4_landcover"]
    for name, selector in PARTS:
        for piece in selector.strip().split("; "):
            piece = piece if piece.endswith(";") else piece + ";"
            if piece not in q4:
                log("FAIL  %s: selector %r is not in the pinned q4_landcover query" % (name, piece))
                return 1

    folder = os.path.join(args.out, extract_osm.snapshot_folder_name(extract_osm.OSM_BASE))
    os.makedirs(folder, exist_ok=True)
    manifest_path = os.path.join(folder, "manifest.json")
    manifest = {"osm_base": extract_osm.OSM_BASE, "bbox": extract_osm.BBOX, "queries": {}}
    if os.path.exists(manifest_path):
        with open(manifest_path, "r", encoding="utf-8") as handle:
            manifest = json.load(handle)
    manifest.setdefault("queries", {})
    manifest["q4_landcover_refused"] = REFUSAL
    manifest.setdefault("q4_landcover_parts_refused", {})
    failed = 0
    for i, (name, selector) in enumerate(PARTS):
        if only is not None and name not in only:
            continue
        ql_path = os.path.join(folder, name + ".ql")
        with open(ql_path, "w", encoding="utf-8", newline="\n") as handle:
            handle.write(part_query(selector))
        if i > 0:
            time.sleep(args.pause)
        log("%s ..." % name)
        try:
            endpoint, answer, elapsed = extract_osm.fetch_one(name, folder, extract_osm.ENDPOINTS, log)
        except RuntimeError as fault:
            log("  FAIL  %s" % fault)
            failed += 1
            # The refusal is data too: the derived file's header cites it.
            manifest["q4_landcover_parts_refused"][name] = str(fault)
            with open(manifest_path, "w", encoding="utf-8") as handle:
                json.dump(manifest, handle, indent=1, sort_keys=True)
                handle.write("\n")
            continue
        manifest["q4_landcover_parts_refused"].pop(name, None)
        base = answer.get("osm3s", {}).get("timestamp_osm_base", "")
        count = len(answer.get("elements", []))
        if base < extract_osm.OSM_BASE:
            log("  FAIL  %s: served from a database of %s, older than the pinned snapshot" % (name, base))
            failed += 1
            continue
        kinds = {}
        for element in answer["elements"]:
            kinds[element.get("type")] = kinds.get(element.get("type"), 0) + 1
        with open(ql_path, "rb") as handle:
            ql_sha = hashlib.sha256(handle.read()).hexdigest()
        manifest["queries"][name] = {
            "endpoint": endpoint,
            "elements": count,
            "by_type": dict(sorted(kinds.items())),
            "served_timestamp_osm_base": base,
            "sha256": extract_osm.sha256_of(os.path.join(folder, name + ".json")),
            "bytes": os.path.getsize(os.path.join(folder, name + ".json")),
            "seconds": round(elapsed, 1),
            "query_sha256": ql_sha,
            "part_of": "q4_landcover",
        }
        log("  ok    %s as of %s (served by a database of %s): %d elements %s from %s in %.0f s" % (name, extract_osm.OSM_BASE, base, count, kinds, endpoint, elapsed))
        with open(manifest_path, "w", encoding="utf-8") as handle:
            json.dump(manifest, handle, indent=1, sort_keys=True)
            handle.write("\n")
    if failed:
        log("PARTS FAILED: %d of %d" % (failed, len(PARTS)))
        return 1
    log("PARTS OK: %d parts in %s" % (len(PARTS), folder))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))

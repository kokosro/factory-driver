# FACTORY DRIVER — 4B DATA PIPELINE: OSM + DGM1 → ELEMENT ASSEMBLY (design, 2026-09-23)
# Status: 4B-PREP design package, documents only. Nothing here runs in the game yet.
# Companion: element-library.md (what gets assembled), ring-region-decisions.md (the first region),
# implementation-plan.md (when each stage is built). Recorded research: docs/nordschleife-data-sources.md.

## 0. SCOPE AND PRINCIPLES

The pipeline turns public data into placed library elements. It runs OFFLINE, ahead of the game:
the game never touches the network, and every derived file is deterministic (same snapshot, same
seed, same bytes: the project's determinism canon applied to data). Stages:

```
extract (Overpass, DGM1 tiles)  →  project (EPSG:25832 → region metres)  →  skeleton (drivable graph)
→  drape (elevation along the skeleton)  →  dress (region table → elements)  →  bake (game files)
```

Every stage writes a file that the next reads; every file carries the snapshot ids it came from.

## 1. SOURCES AND LICENCES

| Source | What | Resolution | Licence | Wording status | URL, accessed |
|---|---|---|---|---|---|
| OpenStreetMap via Overpass | roads, buildings, landcover, POIs | ~1 m horizontal, no elevation | ODbL 1.0 | live-verified | https://www.openstreetmap.org/copyright/en, 2026-09-23 |
| DGM1 Rheinland-Pfalz | terrain height grid | 1 m grid; "+/- 10 cm + 5% der Gitterweite" in flat, low-vegetation terrain (tile metadata, live) | DL-DE BY 2.0 (also offered under CC BY-SA 4.0 per the shop footer) | live-verified | https://geoshop.rlp.de/opendata-dgm1.html, 2026-09-23 |
| DGM-2 (recorded) | the older record in docs/nordschleife-data-sources.md §1 | ~1-2 m | "free with attribution" | recorded; the page now reads "Nutzungsbestimmung: Open Data, Datenlizenz Deutschland – Namensnennung 2.0 / Geldleistungspflichtig: kostenfrei" (live 2026-09-23) | https://geoshop.rlp.de/digitale_gelaendemodelle/digitale_gelaendemodelle_dgm.html |
| DOM1 / DOMB | surface models (structures included: the Karussell bank) | 1 m | same OpenData catalogue | listed on the DGM1 page's sibling links (opendata-dom1.html, opendata-domb.html); download path NOT verified | https://geoshop.rlp.de/opendata-dom1.html |
| DOP20 | 0.2 m orthophotos (width verification) | 0.2 m | same catalogue | listed; not fetched | https://geoshop.rlp.de/opendata-dop20.html |
| touristenfahrten.geojson | community centreline with elevation | ~5 m vertical | NONE declared (GitHub API `license: null`, live 2026-09-23) | verification only, never shipped | https://github.com/maciejb2k/nurburgring-nordschleife-geojson |
| SRTM-30 / Copernicus | fallback outside RLP DGM1 coverage | 30 m | public domain / CC-0 (recorded) | recorded | docs/nordschleife-data-sources.md §1 |

Upgrade over the recorded research: DGM1 (1 m) replaces DGM-2 (~2 m) as primary; it is direct HTTPS
download with no account (HEAD on a tile returned `200 OK`, `Access-Control-Allow-Origin: *`,
2026-09-23), indexed by metalink files with SHA-256 per tile.

## 2. EXTRACTION

### 2.1 OSM (Overpass QL)
Endpoint notes (measured 2026-09-23 ~01:50 CEST): `https://overpass-api.de/api/interpreter` and
`https://overpass.kumi.systems/api/interpreter` answered "server is probably too busy";
`https://lz4.overpass-api.de/api/interpreter` answered every query. A raw POST body gives
`406 Not Acceptable`: the query must be form-encoded as `data=`. Parallel requests from one IP
were throttled; run the queries one after the other. Send a User-Agent naming the project.

The Ring bbox (put in stone in ring-region-decisions.md §1): `50.30,6.80,50.45,7.10`
(south, west, north, east). Each query is a file; the loop below runs one:

```sh
UA="factory-driver-4b/0.1 (world pipeline; okaypeace@gmail.com)"
EP="https://lz4.overpass-api.de/api/interpreter"
for q in q1_skeleton q2_nordschleife q3_economy q4_landcover q5_buildings q6_furniture; do
  curl -s --max-time 300 -A "$UA" --data-urlencode "data@$q.ql" "$EP" > "$q.json"
  python3 -c "import json,sys; d=json.load(open('$q.json')); print('$q', d['osm3s']['timestamp_osm_base'], len(d['elements']))"
  sleep 10
done
```

`q1_skeleton.ql` — every drivable way with geometry (2 181 ways in the bbox, live count
— was 2 181 -> 9 188 ways at the pinned snapshot 2026-09-22T08:45:51Z, measured 2026-09-23
by the 4B-2 extract: the prep-time count was likely of the paved classes only, ~2 208
without track and service):
```
[out:json][timeout:300][bbox:50.30,6.80,50.45,7.10];
way["highway"~"^(motorway|trunk|primary|secondary|tertiary|unclassified|residential|living_street|service|track|raceway|motorway_link|trunk_link|primary_link|secondary_link|tertiary_link)$"];
out geom;
```

`q2_nordschleife.ql` — the Ring's centreline (relation 38566; 52 ways, 1 119 nodes, 20 746 m summed):
```
[out:json][timeout:120];
relation(38566);
out tags;
way(r);
out geom;
```

`q3_economy.ql` — the typed-building inputs (element-library.md §5):
```
[out:json][timeout:300][bbox:50.30,6.80,50.45,7.10];
(
  nwr["amenity"~"^(fuel|driving_school|animal_shelter|parking|place_of_worship)$"];
  nwr["shop"~"^(car|car_repair|car_parts|tyres)$"];
  nwr["historic"="castle"];
  nwr["building"~"^(grandstand|industrial|warehouse|garage|garages|barn|farm|church)$"];
  nwr["man_made"="storage_tank"];
  nwr["landuse"="industrial"];
);
out geom;
```

`q4_landcover.ql` — the masses and planes (T1-T8, V4, V7):
```
[out:json][timeout:300][bbox:50.30,6.80,50.45,7.10];
(
  way["landuse"~"^(forest|farmland|meadow|grass|residential|industrial)$"];
  relation["landuse"~"^(forest|farmland|meadow)$"];
  way["natural"~"^(wood|water|scrub|heath|cliff|bare_rock|tree_row)$"];
  node["natural"="tree"];
  way["waterway"~"^(river|stream|riverbank)$"];
  way["place"~"^(village|town)$"]; node["place"~"^(village|town|hamlet)$"];
);
out geom;
```

`q5_buildings.ql` — every footprint (B0 shells): `way["building"]; out geom;` with the bbox line.
`q6_furniture.ql` — `barrier=*` ways, `highway=street_lamp|stop|give_way`, `traffic_sign=*`,
`power=pole|line`, `railway=level_crossing|rail`; `out geom;`.

### 2.2 DGM1 tiles (geoshop.rlp.de OpenData)
Tiles are 1 km × 1 km GeoTIFF in EPSG:25832, named `dgm1_32_<E km>_<N km>_1_rp_<year>.tif`, served
from `https://geobasis-rlp.de/data/dgm1/current/tif/` and indexed per Landkreis in metalink files
(`https://geobasis-rlp.de/data/dgm1/current/meta4/dgm1_tif_<Kreisschlüssel>.meta4`, each entry with
`<size>` and `<hash type="sha-256">`). Found by reading the download viewer's config
(`https://geoshop.rlp.de/files/anpassungen/hvd/products/dgm1.json`, live 2026-09-23). No account,
no checkout: the shop's "Warenkorb" is for the paid custom-cut product, not for these tiles.

The Ring bbox spans three districts: Ahrweiler 07131 (286 of the bbox's tiles), Mayen-Koblenz 07137,
Vulkaneifel 07233. Copy-pasteable pull of the Ring core (E 352-358 km, N 5577-5582 km; the
Nordschleife and Nürburg):

```sh
mkdir -p dgm1 && cd dgm1
for k in 07131 07137 07233; do curl -sO "https://geobasis-rlp.de/data/dgm1/current/meta4/dgm1_tif_$k.meta4"; done
python3 - <<'PY'
import re,glob
want={f"{e}_{n}" for e in range(352,359) for n in range(5577,5583)}
seen=set()
for f in glob.glob("dgm1_tif_*.meta4"):
    for name,url,sha in re.findall(r'<file name="(dgm1_32_(?:\d{3}_\d{4})_1_rp_\d{4}\.tif)">.*?<hash type="sha-256">([0-9a-f]+)</hash>.*?<url>([^<]+)</url>', open(f).read(), re.S):
        key=name[8:16]
        if key in want and key not in seen:
            seen.add(key); print(f"{sha}  {name}"); open("urls.txt","a").write(url+"\n")
PY
xargs -n1 curl -sO < urls.txt
# (the python above printed sha256 lines; save them as SHA256SUMS and verify:)
shasum -a 256 -c SHA256SUMS
```
Measured 2026-09-23: the core is 42 tiles, 68.3 MB (every tile dated 2025); the whole bbox is 391
tiles, 658.2 MB. One tile: `dgm1_32_355_5580_1_rp_2025.tif`, 1 770 201 bytes,
`Last-Modified: 12 May 2026` (was "(the Karussell)" -> the Karussell is in tile 356_5581: the
skeleton's first point of way 414785755 is E 356 780.6 / N 5 581 961.7, measured at 4B-3; the
Conductor's docs pass, 4B-4). Metadata per tile:
`https://geobasis-rlp.de/data/dgm1/current/metadata/<tile>_meta.xml` (carries the licence note
quoted in §8 and the accuracy statement).

DOM1/DOMB: by the same viewer pattern the config would be `.../hvd/products/dom1.json`; NOT
fetched, so the tile path is a guess until 4B-3 verifies it.

### 2.3 What is NOT pulled
No community track meshes (docs/nordschleife-data-sources.md §3 (d): non-commercial); no
touristenfahrten.geojson in the repo (no licence); no orthophotos in the repo (verification only).

## 3. PROJECTION

- CRS: EPSG:25832 (ETRS89 / UTM zone 32N), the DGM1 tiles' own CRS (tile metadata, live). OSM
  WGS84 lat/lon → 25832 with pyproj (`Transformer.from_crs(4326, 25832, always_xy=True)`).
- Region-local origin (E0, N0) on a tile corner, put in stone per region (Ring: E 352 000,
  N 5 577 000 → ring-region-decisions.md §1). Game axes: `x = E - E0`, `z = -(N - N0)`, `y = height`
  (Godot y-up; the car's nose is local -Z, so a car spawned with yaw 0 faces north).
- Precision: Godot's single-precision floats give ~2 mm at 20 km from the origin; a region up to
  ~30 km across is one origin. Europe-wide is many regions with their own origins and a floating
  origin at the seams: a 4C design, not 4B's.
- Heights stay absolute (m above DHHN2016, the DGM1's datum) so Breidscheid reads ~320 and Hohe Acht
  ~620 in-game, as recorded.

## 4. SKELETON ASSEMBLY (centreline → drivable graph)

1. Nodes shared by ≥ 2 ways become junctions (R4); a way is split at every junction node.
2. Douglas-Peucker at 0.3 m on each way's node list (removes only collinear noise), then a
   Catmull-Rom spline through the remaining nodes for G1 continuity (R2). OSM node spacing on the
   Nordschleife is 19.4 m mean; the spline is sampled every 2 m for the road mesh.
3. Width per way: `width=*` if present and plausible for the class, else by class:

| `highway=*` | lanes | lane width [m] | total paved [m] | shoulder [m] |
|---|---|---|---|---|
| motorway / trunk | `lanes` or 2 per carriageway | 3.75 | 7.5 + 2.5 hard | 0 |
| primary (B 258, B 257, B 412) | 2 | 3.50 | 7.0 | 1.0 grass |
| secondary (L 10, L 73, L 74, L 93) | 2 | 3.25 | 6.5 | 1.0 |
| tertiary / unclassified | 2 | 3.00 | 6.0 | 0.75 |
| residential / living_street | 2 | 2.75 | 5.5 + kerb | 0 |
| service / track | 1 | 3.00 | 3.0 | 0.5 |
| raceway (Nordschleife) | 1 (one-way) | recorded 8-9 m, 7.5 at the Karussell | 8.5 | 0 + F1 |
These are German road-design values (RAL/RASt), not measured: open question 2 in element-library.md.
4. `oneway`, `layer`, `bridge`, `tunnel`, `maxspeed`, `surface`, `ref`, `name` are carried per segment.
5. Relation 38566's member order closes the Nordschleife into one loop; the loop is the R17
   spine, the public roads join it only at R18 (Döttinger Höhe).
6. Output `skeleton.json`: `{snapshot: {osm_base, bbox, query_sha}, origin: {epsg, e0, n0},
   segments: [{id, osm_way, class, width_m, oneway, layer, surface, ref, name, points: [[x,z],...]}],
   junctions: [{id, x, z, segments: [...]}]}`. Small: ~2 181 ways × ~30 points (was -> the
   real bbox is 9 188 ways and the honest skeleton is 5 953 503 bytes — see open question 4,
   decided 4B-2).

## 5. ELEVATION DRAPE

- Mosaic the tiles into one float32 grid (GDAL `gdalbuildvrt`, or rasterio); sample bilinearly.
- Along each spline sample (2 m): height at the centre; across: the road platform is the centre
  height plus crossfall (2 % crown on straights, superelevation into bends per R2/R3), NOT the raw
  DEM across the width: the DEM contains verges, kerbs and ditches, and a road is level across.
- The terrain lattice (T-family) samples the DEM raw; a blend band of 6 m outside the paved edge
  eases the platform into it (the same "lane band" idea as road_profile.gd's LANE_BAND_HALF_WIDTH,
  there to keep a lane from leaning sideways).
- Vertical smoothing: none beyond the 1 m grid's own noise (0.1 m stated accuracy). Crest/dip
  detection (R7/R8): second difference of height over 20 m and 40 m windows; a crest is where the
  20 m curvature exceeds 0.004 /m (a 100 km/h car lightens by ~0.3 g there). These thresholds
  are for the assembler's *labels* only; the physics reads the height field, not the labels.
- Bridges (`bridge=yes`): deck height interpolated linearly between the abutment samples; tunnels
  (`tunnel=yes`): the road sits below the DEM by `layer × 6 m` at the portal, ramped in over 30 m.
- The Karussell: DGM1 is a ground model; whether it carries the concrete bank at 1 m is unknown
  until the tile is opened. Decision tree in ring-region-decisions.md §3 (DOM1/DOMB, else a
  parametric bank on the R9 element).
- Output `drape.json`: per segment, `heights: [...]` aligned with `points`, plus `crossfall: [...]`
  and `labels: [{at, kind: crest|dip|bank}]`.

## 6. REGION DRESSING PASSES

A region is one table (`regions/<id>/focus.json`, the "put in stone" file) of rules
`{match: {tag: value | regex}, element: <library id>, params: {...}}` plus the region's sky set,
palette and density ceilings. Passes run in library priority order, each deterministic:
1. roads: skeleton + drape → R-elements (class → R1/R13/R15/R16/R17; geometry → R2/R3/R7/R8; tags →
   R4/R5/R6/R10/R11; slope → R12; surface class);
2. terrain: DEM lattice → T-forms by slope and landcover polygons; water planes;
3. masses: forest polygons → V4 walls at road-facing edges within 60 m, V7 interior tint; tree rows;
4. buildings: footprints → B shells; economy tags → E types with privileges; rule-placed E-types
   (test centre, sanctuary, tyre centre) at positions the region file names explicitly;
5. furniture: barrier tags → F1-F3/F13/F14; rules → F4/F9 spacing, F5/F6 at junctions and limits;
6. sky/light: the region's S-set and the S5 haze table.
What a region decides is *only* the table: no hand-placed meshes, except landmarks (B3, B4) whose
placement the table names by OSM id.

## 7. CACHING AND DETERMINISM

- Snapshots are pinned: an OSM pull is named by its `osm3s.timestamp_osm_base`
  (`snapshots/osm/ring_2026-09-22T08-45-51Z/q*.json`) and never re-pulled in place; a new pull is
  a new snapshot and a documented change ("was -> ").
- DGM1 tiles are pinned by the metalink's SHA-256; the tile year is in the file name.
- Derived files carry `snapshot` ids and the pipeline's own version; a rebuild from the same inputs
  must be byte-identical (JSON keys sorted, floats rounded to 3 decimals = mm, no timestamps
  inside — the telemetry recorder's rule, scripts/telemetry.gd "WALL CLOCK").
- Seeds: `region_seed = fnv1a(region_id)`; every stochastic choice (which stations are social,
  tree placement jitter, house tint) draws from a hash of (region_seed, osm_id, purpose), never from
  a running RNG (the pattern of road_profile.gd's `_hash`).
- Tests never touch the network: the suite's fixtures are the checked-in sample
  (docs/design/4b/samples/) and synthetic mini-skeletons.
- Raw pulls (hundreds of MB) live outside the repo (`FD_DATA_DIR`-style folder, or `snapshots/`
  git-ignored); the repo keeps the small derived skeleton for the Ring only if under ~1 MB.

## 8. ATTRIBUTION (exact wording)

RECORDED (docs/nordschleife-data-sources.md, §3 and §1):
- OSM: "OSM ODbL (free with attribution)"; DGM-2: "Free with attribution (GeoPortal RLP)";
  GPX: "GPX from community (usually CC‑BY‑SA)" — the last is superseded: the repo declares no licence.

LIVE-VERIFIED 2026-09-23:
- OSM, https://www.openstreetmap.org/copyright/en: "OpenStreetMap is open data, licensed under the
  Open Data Commons Open Database License (ODbL) by the OpenStreetMap Foundation (OSMF)." Required:
  "Provide credit to OpenStreetMap by displaying our attribution notice. Make clear that the data is
  available under the Open Database License." In-game and in-repo string:
  `© OpenStreetMap contributors — data licensed under ODbL 1.0, https://www.openstreetmap.org/copyright`
- DGM1, tile metadata `dgm1_32_355_5580_1_rp_2025_meta.xml` (live): "Open-data-Produkt: Datenlizenz
  Deutschland -Namensnennung- Version 2.0 ©GeoBasis-DE / LVermGeoRP <Jahr des Datenbezugs>,
  dl-de/by-2-0, www.lvermgeo.rlp.de [Daten bearbeitet]". The licence text
  (https://www.govdata.de/dl-de/by-2-0, live) §(2)-(3) requires the provider's name, the notice
  "dl-de/by-2-0" with a link to the licence text, a dataset reference, and a note that the data
  was changed. In-game and in-repo string:
  `© GeoBasis-DE / LVermGeoRP 2026, dl-de/by-2-0 (https://www.govdata.de/dl-de/by-2-0), www.lvermgeo.rlp.de, DGM1 Rheinland-Pfalz [Daten bearbeitet]`
- The shop footer (https://geoshop.rlp.de/opendata-dgm1.html, live) lists both "Datenlizenz
  Deutschland – Namensnennung 2.0" and "CC BY-SA 4.0 International" under "Nutzungsbedingungen
  OpenData". We attribute under DL-DE BY 2.0 (no share-alike obligation on the game's assets).
- Where shown: the garage's SETTINGS page (beside the data-location text, garage.gd:531) and the
  README's data section. Both strings also live in docs/design/4b/samples/LICENSE-NOTES.md.

## 9. EXPECTED VOLUMES, RING BBOX (live counts 2026-09-23, osm_base 2026-09-22T08:45:51Z)

| Item | Count | Raw size (estimate) |
|---|---|---|
| ways: highway + railway + building + landuse + natural | 33 163 | ~40-60 MB JSON with geometry |
| drivable ways (q1 classes) | 9 188 (was -> 2 181, the prep-time estimate; likely the paved classes only) | ~11 MB (measured) |
| Nordschleife relation ways / nodes | 52 / 1 119 | 92 KB (measured) |
| fuel / car_repair / car / driving_school / castle / grandstand | 9 / 9 / 1 / 1 / 4 / 12 | < 1 MB |
| roundabouts / bridges / tunnels / industrial polygons | 11 / 188 / 28 / 16 | in q1/q3 |
| DGM1 core (42 tiles) / whole bbox (391 tiles) | 68.3 MB / 658.2 MB | GeoTIFF |
| derived skeleton + drape for the bbox | — | ~3-6 MB JSON, ~1 MB gzipped |

## Open questions
1. DOM1/DOMB download path and whether the 1 m surface model resolves the Karussell's bank: verify
   in 4B-3 by opening `dgm1_32_356_5581` (was `dgm1_32_355_5580` -> the Karussell's tile is
   356_5581, measured at 4B-3) and, if flat, the DOM tile. DONE 4B-3: ring-region-decisions.md §3.
2. CC BY-SA 4.0 vs DL-DE BY 2.0: both offered; is DL-DE alone acceptable to the driver for a
   shipped game? (No share-alike on the game's meshes under DL-DE.)
3. Overpass reliability: pin one mirror or keep a fallback list? Snapshots make this a one-time cost.
4. Repo policy for derived data: check in the Ring skeleton (≤ 1 MB) or generate on first run?
   DECIDED 4B-2: checked in, full bbox — 5 953 503 bytes (§9's own estimate; reproducible
   byte-exact from the pinned snapshot via tools/world/, the gate proven) — was the ≤ 1 MB /
   generate-on-demand alternative, which assumed the 2 181 way count.
5. Europe-wide extraction (the driver's "All europe, must be drivable"): Overpass cannot serve a
   continent; that is a Geofabrik `.osm.pbf` + osmium job, sized in 4C, not here.

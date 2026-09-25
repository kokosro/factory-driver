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
- Vertical smoothing: was "none beyond the 1 m grid's own noise (0.1 m stated accuracy)" ->
  ROAD-SMOOTHING (2026-09-23, the driver's issue-0001 "the road tile is very pointy" and
  issue-0005 "two tiles connect ... like a stair"; the research survey's recipe as the Conductor
  adjudicated it, its numbers verified on the data; `tools/world/drape.py`'s header is the
  record): per covered plain segment (not a bridge's deck, not a tunnel, not a partly covered
  segment) the raw dense centre heights are smoothed by a **Whittaker penalised-smoothness
  fit** (Eilers 2003, "A Perfect Smoother"): z = argmin Σ wᵢ(yᵢ − zᵢ)² + λ Σ(Δ²z)², the penalty
  on the second difference, the very curvature the labels below read. The recipe's primary was
  a Savitzky-Golay filter (window 11, order 2), which needs scipy; scipy is absent from the
  venv that builds the file (pip list, 2026-09-23: rasterio 1.5.1 depends on numpy, affine and
  attrs, not scipy; no network, nothing installed), so the recipe's pre-approved alternative is
  the deliverable, pure python (a banded Cholesky of the pentadiagonal system in plain floats:
  no BLAS, so two builds are the same bytes). **λ = 5**, a hardcoded constant: the λ range
  rescaled for 2 m stations, Conductor-approved 2026-09-23; was the recipe's per-1 m-sample
  1e2..1e5. The Whittaker cutoff wavelength scales as L_cut ≈ 2π·h·λ^(1/4) for a sample spacing
  h, so an equal cutoff needs λ ∝ h⁻⁴ - at 2 m stations the same cutoff takes a λ 16× SMALLER
  than at 1 m. was (this paragraph and the Conductor's ruling text) "λ ∝ h⁴; the recipe's range
  at ~1 m is L_cut ≈ 12.6-126 m, at 2 m ≈ 39-126 m" -> corrected (the codex read-only review
  found the proportionality inverted and the numbers wrong; recorded, not blamed): at 1 m the
  recipe's 1e2..1e5 gives L_cut ≈ 19.9-111.7 m, at 2 m the same λ range gives ≈ 39.7-223.5 m,
  attenuating the very 20-40 m crests the gates require to survive (measured on the checked-in
  file: λ 1e2 loses 258 labels of |curvature| ≥ 0.01 and moves loop heights by up to 2.47 m;
  a rule that fails its own gates is mis-scaled, not sacred). λ 5 at 2 m gives L_cut ≈ 18.8 m
  (the half-power wavelength 18.4 m) and corresponds to λ ≈ 80 at 1 m - just under the recipe's
  1e2 floor, its intent's lower edge; the decision stands, only the scaling argument's direction
  and numbers are corrected. H ≈ 1/21 at 8 m, ~58 % of a raw 20 m wave kept, 95 % at 40 m, 99 %
  at 60 m; the protection carries the labelled crests. **The edge**: natural (free) ends, D of n − 2 rows, no second
  difference imposed across a segment's end; the end station past the last whole one (an
  uneven length) is outside the uniform spacing and takes the fit's last grade over its own
  length. **The protection**: the labels are taken on the smoothed heights; every station of a
  crest/dip run plus one flank station either side is held to its raw height (weight 1e6 in the
  same solve, so the neighbours bend onto the raw stations instead of stepping to them), and
  the file's labels are recomputed on the final heights, which is what the suite's recount
  reads. Measured on the file: 2 623 of the 3 314 covered segments smoothed (33 bridges, 10
  tunnels and 648 plain segments under 20 m left as sampled); labels 2 551 crests / 2 465 dips
  -> 1 927 / 1 874; of the raw
  labels of |curvature| ≥ 0.01 seven have no label of their kind within 6 m afterwards, five of
  them still labelled with the run's steepest station moved 8-20 m along and two one- or
  two-station spikes on forest tracks, none a crest of a road, none on the loop; the loop's
  station-to-station grade change fell from 1.5 % (90th percentile) and 3.0 % (99th) to the
  centimetre rounding's own 0.5 % and 1.0 %; the loop's lowest, highest and Hohe Acht samples
  (332.94, 627.52, 616.50 m) are the same to the centimetre; the DGM1 on the paved loop reads
  5 mm rms in the 4-16 m band, far under the survey's ±15 cm per cell (the forest tracks are
  the noisy class: a 5 % grade change per station at their 90th percentile). The noisy fixture
  (drape.py --selftest: ±15 cm of seeded white noise per cell on a plane with a 30 m crest):
  the flat band's height residual peak-to-peak shrinks 2.3× on the finished, centimetre-rounded
  record (2.4× on the unrounded fit; the brief's 3× is first reached at λ 30 on white noise,
  where the 40 m wavelength is cut to 0.78: the feature gate's loss - recorded, not taken), the
  station-to-station grade change ≥ 3×, the crest still labelled with the raw data's own
  curvature and its top station the raw height.
- **The junction rule** (write-side, the readers untouched): at every skeleton junction the
  draped segments' ends on the node are stitched. Height: a rigid participant holds the node -
  a bridge's deck end, a tunnel's portal, a partly covered segment's raw sample (all the raw
  ground at the node); else the highest road class wins (raceway, primary, primary_link,
  secondary, secondary_link, tertiary, tertiary_link, unclassified, residential, living_street,
  service, track), the Nordschleife loop wins ties, and the winners' mean is the node's height;
  every covered plain participant's stations within **8 m** of the node are shifted by
  smoothstep(1 − d / 8 m) times (node height − its own end height), the grade kept and the gap
  closed (the radius is half the segment's length under 16 m so both ends land; a zero-length
  record - the skeleton admits identical points - has no radius and is written nothing, the
  codex review's F2). Crossfall, as a tilt in WORLD space (the codex review's F1: a crossfall
  is "rise to the right of travel" and right is each segment's own frame, so the same signed
  value on two segments leaving a node in opposite directions is two opposite tilts - measured
  18.2 cm of one-side stair at node 3183494700 between the primaries 312490275-0 and
  82512875-0 with the first stitch): each non-bank participant's end crossfall times its end
  chord's right normal is its tilt vector; a rigid participant holds its end tilt and is never
  moved (the pick when several: class rank, the loop, the segment id, the start before the
  end - the codex review's F4: the first stitch let a track's mean move the bridge 440567173-0's
  end from 0.06 to 0.0055), else the winners' mean of the plain participants' tilt vectors by
  the same class/loop priority; only the plain non-bank participants are written, each its
  own right normal's component of the target (the Karussell's bank neither votes nor moves).
  The file's centre heights already agreed at every junction (the same DEM sample), so on the
  loop the height stitch closes only what the smoother's free ends open: the loop's 184
  segment ends move by at most 2 cm, except the T13 four-way node's two by 8 cm (known limit
  (2) in docs/night-shift-3.md); on a side road ending at a structure's cut the offset is the
  DEM's wall the smoother turned into a ramp - the largest 3.08 m at 159029005-1's end, a
  tertiary (known limit (1)). "The grade kept" holds at the end station (smoothstep's
  derivative is zero there); the offset's own grade spreads over the blend, at most
  1.5 × offset / radius at its middle: 58 % per metre on that worst case, 1.5 % on the T13
  node's 8 cm (the codex review's F5). The crossfall stitch is what issue-0005 was: the two
  loop segments met at one centre height with −0.8 % and +4.0 % of crossfall, a 0.255 m stair
  at the right paved edge and 0.150 m at the left, now 0.000; T13's pit lane met the loop at
  −4 % against +4 %, a 0.340 m ridge, now 0.000; 1 562 junctions had a crossfall gap over 2 %
  (29 on the loop), now none. The T13 four-way junction's 0.413 m step in the ring drive
  test's loop sweep was never in the file (the four ends read 618.65 m alike): it is the
  reader's rim rule lifting one branch through the junction; recorded below, not this rule's.
- Crest/dip detection (R7/R8): second difference of height over 20 m and 40 m windows; a crest
  is where the 20 m curvature exceeds 0.004 /m (a 100 km/h car lightens by ~0.3 g there).
  These thresholds are for the assembler's *labels* only; the physics reads the height field,
  not the labels.
- Bridges (`bridge=yes`): deck height interpolated linearly between the abutment samples; tunnels
  (`tunnel=yes`): the road sits below the DEM by `layer × 6 m` at the portal, ramped in over 30 m.
- The Karussell: DGM1 is a ground model; whether it carries the concrete bank at 1 m is unknown
  until the tile is opened. Decision tree in ring-region-decisions.md §3 (DOM1/DOMB, else a
  parametric bank on the R9 element).
- Output `drape.json`: per segment, `heights: [...]` aligned with `points` (since ROAD-SMOOTHING
  the field's own value at the point: the rounded dense heights interpolated there), plus
  `crossfall: [...]` and `labels: [{at, kind: crest|dip|bank}]`. The file's `rules` and its
  `pipeline_version` (1) are unchanged by the smoothing: the reader refuses other rules and
  another version, and the readers are frozen; the smoothing's constants are recorded in
  `drape.py` and here, the file is pinned by sha256 in `tests/ring_drive_test.gd`.
- THE CROSSFALL-TWIST RULE (2026-09-25, the ROAD-GEOMETRY FIX-NOW landing after
  `docs/issues-analysis-2026-09-24.md` §4.2; `drape.py`'s header carries the record): the
  signed curvature at a skeleton point is the polyline's heading change over a 20 m window
  centred on it, clamped to the segment, over that length (`CURVATURE_WINDOW_M`; was the
  three-point circle through the point and its neighbours, whose sign flipped on every short
  chord - a 0.94 m/m edge twist across a 0.45 m chord at 799394513-1, the driver's "rear tyres
  suspended"); the superelevation then changes by at most 0.004 per metre of chainage
  (`SUPERELEVATION_RUNOFF_PER_M`, the design notion of a superelevation runoff: a 4 % bank runs
  off over 10 m; the values projected onto the bound by the midpoint of their McShane envelopes,
  the ends free before the junction stitch and pinned after it); a plain segment shorter than
  15 m (`STUB_M`) between a rigid participant and a junction holds the rigid tilt through to the
  node (the stub rule). The loop's 965 chords: 19 twisting over 0.02 m/m -> 0 (the top 0.0173).
- THE KARUSSELL BLEND (the same landing, §3.3 (a) of the analysis; ring-region-decisions.md §3's
  branch (c) unchanged in bank, bowl and strip): the bank label carries `at` = 30, `to` = length
  - 30 and a new additive key `ramp_m` = 30 (`KARUSSELL_RAMP_M`; the reader's `BANK_LABEL_KEYS`
  gains it, a label without it reads as before), the way's crossfall array ramps linearly from
  each end's stitched plane value to 0.30 over the ramp (the way's ends now take the node's tilt
  like any plain participant; it still does not vote), and the reader blends the platform from
  the plane to the bowl over [at - ramp_m, at] and [to, to + ramp_m]. was the bank at every
  point and a step against the neighbours' planes: -0.878 / +1.211 m at the entry's paved edges,
  +1.269 / -1.281 at the exit's -> the largest one-step at any offset within ±10 m of either
  junction 0.038 / 0.034 m. 30 m, not the doc's first candidate 20: measured, 20 m read 0.053 m
  at the entry against the 0.05 m fence (the crown's fade where the ramped crossfall passes
  through zero adds its own edge kink). The centre heights are untouched: the regenerated file
  (aac02239...) differs from f3ca142b... only in 2 813 segments' crossfall arrays (12 871 of
  22 215 points) and the one bank label.

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

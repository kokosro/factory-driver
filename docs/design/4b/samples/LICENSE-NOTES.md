# 4B samples — licence notes (verified 2026-09-23)

The one data file here, `nordschleife-karussell-sample.json`, is a trimmed extract (3 of 52 ways,
4.2 KB) of OpenStreetMap relation 38566 pulled from `https://lz4.overpass-api.de/api/interpreter`
on 2026-09-23 (`timestamp_osm_base 2026-09-22T08:45:51Z`), coordinates rounded to 1e-6 degrees.
It is a design reference and a test fixture, nothing more. No DGM1 tile is checked in.

## OpenStreetMap (the sample, and every OSM-derived file the pipeline will make)
Live-verified at https://www.openstreetmap.org/copyright/en (2026-09-23): "OpenStreetMap is open
data, licensed under the Open Data Commons Open Database License (ODbL) by the OpenStreetMap
Foundation (OSMF)." Required: credit OpenStreetMap by its attribution notice and make clear the
data is under the ODbL. The string to show in-game and in the repo:

    © OpenStreetMap contributors — data licensed under ODbL 1.0, https://www.openstreetmap.org/copyright

## DGM1 Rheinland-Pfalz (no file here; the pipeline's elevation source)
Live-verified in the tile metadata
`https://geobasis-rlp.de/data/dgm1/current/metadata/dgm1_32_355_5580_1_rp_2025_meta.xml`
(2026-09-23): "Open-data-Produkt: Datenlizenz Deutschland -Namensnennung- Version 2.0
©GeoBasis-DE / LVermGeoRP <Jahr des Datenbezugs>, dl-de/by-2-0, www.lvermgeo.rlp.de [Daten
bearbeitet]". Licence text: https://www.govdata.de/dl-de/by-2-0 (§2: provider's name, the notice
"dl-de/by-2-0" with a link to the licence text, a dataset reference; §3: note that the data was
changed). The shop page https://geoshop.rlp.de/opendata-dgm1.html also lists "CC BY-SA 4.0
International" in its OpenData terms; we attribute under DL-DE BY 2.0. The string:

    © GeoBasis-DE / LVermGeoRP 2026, dl-de/by-2-0 (https://www.govdata.de/dl-de/by-2-0), www.lvermgeo.rlp.de, DGM1 Rheinland-Pfalz [Daten bearbeitet]

("2026" is the year of data retrieval, per the metadata's "<Jahr des Datenbezugs>".)

## Not included, on purpose
- `touristenfahrten.geojson` (github.com/maciejb2k/nurburgring-nordschleife-geojson): the repository
  declares NO licence (GitHub API `license: null`, 2026-09-23). Verification use only; never shipped.
- Community track meshes from other sims: non-commercial (docs/nordschleife-data-sources.md §3 d).

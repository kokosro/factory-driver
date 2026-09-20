# Nürburgring Nordschleife – Data Sources for Godot Reconstruction

## 1️⃣ Elevation

| Claim | Value | Location / Section | Source |
|-------|-------|--------------------|--------|
| Elevation range | ~300 m (≈ 984 ft) between lowest and highest points | Lowest: **Breidscheid** (~320 m); Highest: **Hohe Acht / T13 Grandstand** (~620 m) | Wikipedia – "Nürburgring" (https://en.wikipedia.org/wiki/N%C3%BCrburgring) |
| Detailed gradient info (up‑to 18 % downhill, 27 % short steep) | – | Flugplatz → Karussell → Hohe Acht; Fuchsröhre (11 % downhill) | Nordschleife‑BtG – Gradient of altitude (https://www.nordschleife-btg.net/nordschleife/gradient-of-altitude/) |
| Public elevation data (GPX) | GPX track with per‑point elevation (≈ 5 m vertical resolution) | Tourist‑drive GPX (touristenfahrten.geojson) | GitHub repo maciejb2k/nurburgring‑nordschleife‑geojson (https://github.com/maciejb2k/nurburgring-nordschleife-geojson) |
| DEM tiles (30 m) | SRTM‑30 / Copernicus DEM (1° × 1° HGT files) | Covers whole Eifel region (incl. Nürburgring) | NASA SRTM download (https://srtm.csi.cgiar.org) |
| High‑resolution LiDAR (≈ 1 m) | DGM‑2 (RLP) – laser‑scanned DEM, free with attribution | Rhineland‑Palatinate GeoPortal (https://www.geoportal.rlp.de) | DGM‑2 download page (https://geoshop.rlp.de/digitale_gelaendemodelle.html) |

## 2️⃣ Road Surface Types & Bumps

| Section | Surface | Notable bumps / seams | Source |
|---------|----------|----------------------|--------|
| **Karussell (Caracciola‑Karussell)** | Concrete slabs (steep bank) with a thin asphalt strip at the bottom | Individual concrete slabs cause a characteristic “jolt” | nring.info – Corner description (https://nring.info/nurburgring-nordschleife-corners/caracciola-karussell/) |
| **Flugplatz** | Asphalt, but a pronounced crest ("air‑field") that can lift the car | Crest creates a short airborne moment | Nordschleife‑BtG – Gradient description |
| **Schwedenkreuz / Aremberg** | Asphalt, high‑speed crest | Sudden change of gradient (up‑to 18 %) | Nordschleife‑BtG |
| **Bergwerk** | Asphalt, but a rough surface with visible seams from historic resurfacing | Small bumps felt by drivers | WorldPartsDirect article (https://www.worldpartsdirect.com/articles/nurburgring-explained) |
| **Brünnchen / Ex‑Mühle** | Older concrete‑like surface (historical “cement” patch) | Noticeable seam where concrete meets asphalt | Sim‑racing forum thread (e.g., Assetto Corsa discussion) – cited as public community observation |
| **Pflanzgarten** | Recently repaved asphalt (2024‑2025 works) | No major bumps, smoother than older sections | Nürburgring news (https://mobile.nuerburgring.de/news/bauarbeiten-am-nuerburgring-haben-begonnen) |

## 3️⃣ Data‑Pipeline Options for Godot

| Option | Data source | Resolution | License | Feasibility (1‑sentence verdict) |
|--------|------------|------------|---------|-----------------------------------|
| **(a) GPX elevation + OSM centreline** | GPX (touristenfahrten.geojson) + OpenStreetMap road geometry | GPX points ~5 m vertical, OSM ~1 m horizontal | OSM ODbL (free with attribution); GPX from community (usually CC‑BY‑SA) | Works for a quick prototype; elevation density may miss micro‑bumps like Karussell concrete slabs. |
| **(b) DEM tiles sampled along track** | SRTM‑30 (30 m) or Copernicus (30 m) | 30 m grid | Public domain / CC‑0 | Adequate for overall profile but too coarse for steep banked sections; up‑sampling needed. |
| **(c) High‑resolution LiDAR (DGM‑2)** | Rhineland‑Palatinate DGM‑2 (≈ 1 m) | 1 m grid | Free with attribution (GeoPortal RLP) | Captures fine‑scale gradients and the Karussell bank; requires raster processing but yields high‑quality mesh. |
| **(d) Community‑generated 3D models (e.g., Assetto Corsa, R3E)** | Exported track meshes from sim games | Varies (often 0.5 m) | Usually **non‑commercial** (license restricts reuse) | Useful for reference only; cannot be reused in the project without permission. |

## 4️⃣ Lap Length, Layout & Landmarks

- **Official full‑lap length**: **20.830 km** (12.943 mi) – current tourist‑drive configuration (source: Wikipedia).  
- **Corner count**: **154** bends (often quoted as “73 major corners”).  
- **Section naming**: Standard T‑numbers (T1‑T13) plus named sections (Flugplatz, Karussell, Brünnchen, etc.).  
- **Track width**: Typically **8‑9 m**; narrowest sections around the Karussell are ~7.5 m (source: Nürburgring technical data).  
- **Barriers**: Arm‑coated steel guardrails run close to the road; runoff is limited to gravel or grass in most places.  
- **Key landmarks**: Breidscheid bridge (lowest point), Nürburg castle (mid‑lap view), T13 grandstand (highest point), and the historic **Karussell** concrete bowl.

## 5️⃣ Gaps & Fallbacks

- No openly licensed **high‑resolution LiDAR** covering the entire loop is known beyond the state‑provided DGM‑2; if unavailable, fall back to the 30 m DEM plus GPX for a hybrid approach.
- Precise surface‑type polygons (asphalt vs. concrete) are not published; rely on community documentation and visual inspection from satellite imagery.
- If GPX elevation lacks vertical detail for the Karussell, supplement with DGM‑2 raster values sampled at the Karussell coordinates.

## 📌 Recommended Pipeline (short)

Combine the **touristenfahrten GPX** (provides the exact centreline) with **RLP DGM‑2 LiDAR DEM** sampled along the track to generate a high‑resolution elevation mesh. Use OSM road geometry for width and barrier placement. This yields a faithful 1‑meter‑scale terrain while staying fully within free‑use licenses.

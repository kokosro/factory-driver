#!/usr/bin/env python3
"""The elevation drape of the 4B data pipeline (docs/design/4b/data-pipeline.md
§5): the DGM1 tiles mosaicked into one 1 m grid, sampled bilinearly along
every skeleton segment inside the mosaic; a road platform per segment (the
centre height plus a crossfall: 2 % crown on straights, superelevation into
bends per R2/R3, the Karussell's R9 bank), the bridge and tunnel rules,
crest/dip labels from the second difference of height over 20 m and 40 m
windows, and a terrain lattice of the raw DEM; written as drape.json, the
one derived file scripts/world_road_profile.gd reads beside skeleton.json.

Deterministic by construction (§7): same tiles, same skeleton, same bytes.
Segments in the skeleton's order (sorted by id); JSON keys sorted, separators
compact; no timestamp inside; heights rounded to the centimetre, crossfall
to 1e-4, curvature to 1e-5; -0.0 folded to 0.0. The tiles are pinned by
their sha256 (the metalink's), listed in the file; the skeleton by its
sha256. The DGM1 tiles never enter the repo: they live in a scratch folder
(--tiles) and are verified against a SHA256SUMS there when one exists.

Usage:
  venv/bin/python tools/world/drape.py --tiles <dir> --skeleton data/regions/eifel_ring/skeleton.json --out data/regions/eifel_ring/drape.json
  venv/bin/python tools/world/drape.py --tiles <dir> --skeleton <path> --report        (coverage numbers, no file written)
  venv/bin/python tools/world/drape.py --tiles <dir> --skeleton <path> --section 414785755   (a way's cross-section, the Karussell evidence)
  venv/bin/python tools/world/drape.py --selftest                                       (a synthetic DEM, no tiles)

<dir> holds the DGM1 GeoTIFFs (dgm1_32_<E km>_<N km>_1_rp_<year>.tif, 1 km ×
1 km, EPSG:25832, float32, AREA_OR_POINT=Area) pulled per data-pipeline.md
§2.2; --tile-prefix dom1 reads a DOM1 folder the same way (the decision
tree's branch (b)). --selftest proves the rules on a synthetic DEM (a plane
with a bowl and a crest): the plane reproduced, the crest labelled, a bridge
deck linear, a tunnel below the ground, two runs the same bytes, the
mosaic assembly refusing a missing tile, a NaN and an infinity. Neither the
suite nor the game runs this script: the suite reads only the checked-in
drape.json (tests/world_profile_test.gd).

Needs rasterio (GDAL) and pyproj, which the system python does not have.
The venv, never installed system-wide:
  python3 -m venv venv && venv/bin/pip install rasterio pyproj
(proven: rasterio 1.5.1 on GDAL 3.12.4, pyproj 3.8.0 on PROJ 9.8.1; pyproj is
the skeleton stage's, the drape itself only needs rasterio and numpy.)
"""

import argparse
import glob
import hashlib
import json
import math
import os
import re
import sys

# The region frame, put in stone (ring-region-decisions.md §1): the origin on
# a DGM1 tile corner; game x = E - E0, z = -(N - N0) [m], y = height [m]
# absolute above DHHN2016 (the tiles' own vertical datum).
EPSG = 25832
E0 = 352000.0  # [m] easting of the origin, EPSG:25832
N0 = 5577000.0  # [m] northing of the origin, EPSG:25832

# The drape's own version in drape.snapshot (data-pipeline.md §7). Bumped
# when the output changes: 1 = the 4B-3 drape as first shipped.
PIPELINE_VERSION = 1

# The DEM's grid [m] (DGM1: 1 m) and what a tile is (1 km × 1 km).
GRID_M = 1.0
TILE_M = 1000.0
TILE_NAME = re.compile(r"^(dgm1|dom1)_32_(\d{3})_(\d{4})_1_rp_(\d{4})\.tif$")

# Stations along a segment [m]: §4's spline sampling for the road mesh; the
# platform's centre height is carried at this spacing (chosen for the
# drape: heights aligned with the skeleton's points alone would cut through
# hills, Douglas-Peucker keeps plan-view bends and drops the collinear nodes,
# so a chord can be hundreds of metres long; the physics reads the height
# field, so the field is dense where the road is).
STATION_STEP_M = 2.0

# The terrain lattice's spacing [m] (chosen for the drape: the pad's own
# ground lattice is 5 m (TestPad.GROUND_FINE_STEP); 10 m over the 7 km × 6 km
# core is 421 301 heights ≈ 3 MB, 5 m would be 12 MB; the T-family's own
# bands (4B-7) come from the tiles, this lattice is the physics' off-road
# height and the blend band's target).
LATTICE_STEP_M = 10.0

# Crossfall (§5; element-library.md R1-R3). Rise over run.
CROWN = 0.02  # 2 % crown on a straight: both edges fall from the centre
SUPERELEVATION_GAIN_M = 8.0  # e = GAIN / R: R 200 m -> 4 %, R 400 m -> 2 %
SUPERELEVATION_MAX = 0.04  # R2: ≤ 4 % on public roads
HAIRPIN_RADIUS_M = 30.0  # R3: a hairpin has R < 30 m ...
HAIRPIN_SUPERELEVATION_MAX = 0.06  # ... and crossfall 6 % max
# chosen for the drape: the crown's share fades as the superelevation grows,
# 1 - min(|e| / CROWN, 1), so the platform's shape is continuous from a
# crowned straight (e = 0) to a plane tilted at e (|e| ≥ 2 %):
#   platform(o) = centre + e·o - (1 - min(|e| / CROWN, 1))·CROWN·|o|
# with o the offset to the right of travel [m]. e > 0 rises to the right:
# the outside of a left bend. Every class takes the same rule (R17 too);
# a two-point segment has no bend and gets the crown.

# Crest/dip labels (§5; R7/R8): the second difference of the centre height
# over a 20 m window (±10 m = ±5 stations) and a 40 m window (±10 stations)
# [1/m]; a crest where the 20 m curvature is below -CREST_CURVATURE (convex),
# a dip above +CREST_CURVATURE (concave). One label per run above the
# threshold, at the run's steepest station. Labels are for the assembler; the
# physics reads the height field.
CREST_CURVATURE = 0.004  # [1/m]
WINDOW_20_STATIONS = 5  # 10 m either side at 2 m stations
WINDOW_40_STATIONS = 10  # 20 m either side

# Bridges and tunnels (§5): a bridge's deck is linear between its abutment
# samples (the DEM under a bridge is the valley floor: a ground model); a
# tunnel's road sits TUNNEL_DEPTH_PER_LAYER_M × |layer| below the DEM, ramped
# in over TUNNEL_RAMP_M from each portal. chosen for the drape: bridge=* other
# than "no" (OSM's viaduct is a bridge) takes the rule; the doc says bridge=yes.
TUNNEL_DEPTH_PER_LAYER_M = 6.0  # [m]
TUNNEL_RAMP_M = 30.0  # [m]

# The Karussell (ring-region-decisions.md §3, the decision tree's branch (c),
# recorded there as "was ->"): the R9 element's parametric bank fitted to OSM
# way 414785755. Bank 30 % over a 6.5 m bowl with a 1 m asphalt strip at the
# bottom (element-library.md R9; the catalogue's ranges 20-40 % / 6-12 m /
# 0.5-2 m). The bank rises to the outside of the bend (the Karussell is a
# left-hander: the right of travel), from the inside edge:
#   u = distance from the low edge; platform = low + BANK·max(u - STRIP, 0),
#   anchored so the centre (u = width / 2) sits at the DEM's centre height.
KARUSSELL_WAY = 414785755
KARUSSELL_BANK = 0.30  # rise over run
KARUSSELL_BOWL_M = 6.5  # [m]
KARUSSELL_STRIP_M = 1.0  # [m]

# Rounding (§7's mm rule, adapted: chosen for the drape, heights to the
# centimetre — the DGM1's stated accuracy is ±10 cm + 5 % of the grid, so a
# millimetre would be false precision and a third of the file's bytes).
HEIGHT_DECIMALS = 2
CROSSFALL_DECIMALS = 4
CURVATURE_DECIMALS = 5
CHAINAGE_DECIMALS = 3

# The blend band the profile eases the platform into the terrain over [m]
# (§5; road_profile.gd's LANE_BAND_HALF_WIDTH). Recorded in the file so the
# reader and the writer agree.
BLEND_BAND_M = 6.0

# The two labels kinds the file carries for the geometry, and the bank.
LABEL_KINDS = ("crest", "dip", "bank")


def rounded(value, decimals):
    """floor(value × 10^decimals + 0.5) / 10^decimals, with -0.0 folded to 0.0:
    one spelling of zero in the file. Not round(): this is the same four
    IEEE operations world_road_profile.gd's _rounded() does, so the reader's
    recount of the labels lands on the same digits (round() is
    half-to-even on the exact binary value; 12 of 3 314 segments' 40 m
    curvatures differed in the fifth decimal before this)."""
    scale = 10 ** decimals
    out = math.floor(float(value) * scale + 0.5) / scale
    return 0.0 if out == 0.0 else out


def sha256_of(path):
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


# --- the mosaic ----------------------------------------------------------------

class Mosaic:
    """One float64 grid over the tiles' union in region metres. A height is
    sampled bilinearly between cell centres (AREA_OR_POINT=Area: the cell
    (row, col) is the square from its corner, its value at the centre);
    valid where all four centres are inside the grid: half a cell in from
    the edge. x_min..x_max, z_min..z_max are the grid's outer edges in game
    metres; z grows southward (z = -(N - N0))."""

    def __init__(self, heights, x_min, z_min):
        import numpy  # noqa: F401  (the sampler is numpy-free by design; the array is)
        self.heights = heights  # [row, col], row 0 at z_min (the north edge)
        self.rows, self.cols = heights.shape
        self.x_min = x_min
        self.z_min = z_min
        self.x_max = x_min + self.cols * GRID_M
        self.z_max = z_min + self.rows * GRID_M

    def covers(self, x, z):
        """Whether (x, z) can be sampled: half a cell inside the edges."""
        return (self.x_min + 0.5 * GRID_M <= x <= self.x_max - 0.5 * GRID_M
                and self.z_min + 0.5 * GRID_M <= z <= self.z_max - 0.5 * GRID_M)

    def sample(self, x, z):
        """The DEM's height at (x, z) [m], bilinear; None outside."""
        if not self.covers(x, z):
            return None
        c = (x - self.x_min) / GRID_M - 0.5
        r = (z - self.z_min) / GRID_M - 0.5
        c0 = int(math.floor(c))
        r0 = int(math.floor(r))
        # The far edge: the last centre exactly, no cell beyond it.
        c0 = min(c0, self.cols - 2)
        r0 = min(r0, self.rows - 2)
        fc = c - c0
        fr = r - r0
        h = self.heights
        return float(h[r0, c0] * (1.0 - fc) * (1.0 - fr) + h[r0, c0 + 1] * fc * (1.0 - fr)
                     + h[r0 + 1, c0] * (1.0 - fc) * fr + h[r0 + 1, c0 + 1] * fc * fr)

    def sample_clamped(self, x, z):
        """The height with (x, z) clamped into the valid area: the lattice's
        border nodes sit on the grid's outer edge, half a cell out."""
        x = min(max(x, self.x_min + 0.5 * GRID_M), self.x_max - 0.5 * GRID_M)
        z = min(max(z, self.z_min + 0.5 * GRID_M), self.z_max - 0.5 * GRID_M)
        return self.sample(x, z)


def tile_files(folder, prefix):
    """The tiles in `folder`, sorted by name, with their (E km, N km, year)."""
    found = []
    for path in sorted(glob.glob(os.path.join(folder, "%s_32_*.tif" % prefix))):
        match = TILE_NAME.match(os.path.basename(path))
        if match is None:
            raise ValueError("%s is not a tile of the documented name" % path)
        found.append((path, int(match.group(2)), int(match.group(3)), int(match.group(4))))
    if not found:
        raise ValueError("no %s_32_*.tif in %s" % (prefix, folder))
    return found


def verify_tiles(folder, files):
    """Every tile's sha256, and each checked against SHA256SUMS in `folder`
    when the file is there (the metalink's hashes, data-pipeline.md §2.2);
    a mismatch refuses the run. Returns [{name, sha256}] sorted by name."""
    sums = {}
    sums_path = os.path.join(folder, "SHA256SUMS")
    if os.path.exists(sums_path):
        with open(sums_path, "r", encoding="utf-8") as handle:
            for line in handle:
                parts = line.split()
                if len(parts) == 2:
                    sums[parts[1]] = parts[0]
    pins = []
    for path, _e, _n, _year in files:
        name = os.path.basename(path)
        digest = sha256_of(path)
        if name in sums and sums[name] != digest:
            raise ValueError("%s: sha256 %s, SHA256SUMS says %s (a tile that is not the pinned one)" % (name, digest, sums[name]))
        pins.append({"name": name, "sha256": digest, "verified": name in sums})
    return pins


def assemble_mosaic(tiles):
    """One float64 grid from `tiles`, a list of (E km, N km, array) with
    every array TILE_M / GRID_M square, pasted into the rectangle the names
    span, NaN wherever no tile writes a finite value. Refused (ValueError)
    when any cell inside the rectangle is left without a finite height: a
    missing tile, a nodata cell, a NaN or an infinity. was rasterio.merge
    with the first tile's nodata -> this (the codex review of 4B-3: merge
    fills uncovered cells with ZERO when the rasters carry no nodata, a
    fictitious valid terrain the nodata-is-None check never saw, and a NaN
    nodata escaped `grid == nodata` too)."""
    import numpy as np
    if not tiles:
        raise ValueError("no tiles to assemble")
    per_tile = int(round(TILE_M / GRID_M))
    e_min = min(e for e, _n, _a in tiles)
    e_max = max(e for e, _n, _a in tiles)
    n_min = min(n for _e, n, _a in tiles)
    n_max = max(n for _e, n, _a in tiles)
    cols = (e_max - e_min + 1) * per_tile
    rows = (n_max - n_min + 1) * per_tile
    grid = np.full((rows, cols), np.nan, dtype="float64")
    for e_km, n_km, array in tiles:
        if array.shape != (per_tile, per_tile):
            raise ValueError("tile E %d N %d is %s cells, a tile is %d × %d" % (e_km, n_km, array.shape, per_tile, per_tile))
        # Row 0 of the grid is the north edge: the tile's top row goes at
        # (n_max - n_km) tiles down.
        r0 = (n_max - n_km) * per_tile
        c0 = (e_km - e_min) * per_tile
        grid[r0:r0 + per_tile, c0:c0 + per_tile] = array
    holes = int(np.sum(~np.isfinite(grid)))
    if holes:
        raise ValueError("%d cells without a finite height inside the tiles' rectangle E %d-%d km × N %d-%d km (a missing tile, a nodata cell or a non-finite value); the drape has no rule for holes" % (holes, e_min, e_max + 1, n_min, n_max + 1))
    x_min = e_min * TILE_M - E0
    z_min = -((n_max + 1) * TILE_M - N0)
    return Mosaic(grid, x_min, z_min)


def load_mosaic(folder, prefix="dgm1"):
    """The tiles of `folder` assembled into one Mosaic in game metres, and
    the tile pins. Every tile has to be 1 m, EPSG:25832 by its name,
    AREA_OR_POINT=Area; its nodata cells (by its own nodata value, which
    may be NaN) become NaN and assemble_mosaic refuses any hole."""
    import numpy as np
    import rasterio

    files = tile_files(folder, prefix)
    pins = verify_tiles(folder, files)
    tiles = []
    for path, e_km, n_km, _year in files:
        with rasterio.open(path) as source:
            if source.res != (GRID_M, GRID_M):
                raise ValueError("%s is %s m, the DGM1 is %s m" % (path, source.res, GRID_M))
            if source.bounds.left != e_km * TILE_M or source.bounds.bottom != n_km * TILE_M:
                raise ValueError("%s: bounds %s, the name says E %d N %d km" % (path, source.bounds, e_km, n_km))
            if source.tags().get("AREA_OR_POINT", "Area") != "Area":
                raise ValueError("%s is AREA_OR_POINT=%s; the sampler assumes Area" % (path, source.tags().get("AREA_OR_POINT")))
            array = source.read(1).astype("float64")
            nodata = source.nodata
        if nodata is not None and not math.isnan(nodata):
            array[array == nodata] = np.nan
        tiles.append((e_km, n_km, array))
    return assemble_mosaic(tiles), pins


# --- the skeleton ---------------------------------------------------------------

def load_skeleton(path):
    with open(path, "r", encoding="utf-8") as handle:
        return json.load(handle), sha256_of(path)


def chord_length(p, q):
    dx = q[0] - p[0]
    dz = q[1] - p[1]
    return math.sqrt(dx * dx + dz * dz)


def chainages(points):
    """Distance along the polyline at every point [m], from 0."""
    out = [0.0]
    for i in range(1, len(points)):
        out.append(out[-1] + chord_length(points[i - 1], points[i]))
    return out


def station_chainages(length, step=STATION_STEP_M):
    """The stations along a segment: 0, step, 2·step, ... up to the length,
    and the end itself when it is more than a millimetre past the last
    whole station. Mirrored to the operation in world_road_profile.gd."""
    whole = int(math.floor(length / step + 1e-9))
    out = [k * step for k in range(whole + 1)]
    if length - whole * step > 1e-3:
        out.append(length)
    return out


def point_along(points, chain, s):
    """The point at chainage s on the polyline (chain = chainages(points))."""
    if s <= 0.0:
        return points[0][0], points[0][1]
    for i in range(1, len(points)):
        if chain[i] >= s:
            span = chain[i] - chain[i - 1]
            u = 0.0 if span <= 0.0 else (s - chain[i - 1]) / span
            return (points[i - 1][0] + u * (points[i][0] - points[i - 1][0]),
                    points[i - 1][1] + u * (points[i][1] - points[i - 1][1]))
    return points[-1][0], points[-1][1]


def travel_right(points, chain, s):
    """The unit vector to the right of travel at chainage s, in (x, z)."""
    i = 1
    while i < len(points) - 1 and chain[i] < s:
        i += 1
    dx = points[i][0] - points[i - 1][0]
    dz = points[i][1] - points[i - 1][1]
    n = math.sqrt(dx * dx + dz * dz)
    if n == 0.0:
        return 0.0, 0.0
    # Travel (tx, tz) in the x-east / z-south frame: right = (-tz, tx).
    return -dz / n, dx / n


def signed_curvature(p0, p1, p2):
    """Menger curvature of the circle through three points [1/m], negative
    for a left turn in the x-east / z-south frame (cross < 0), 0 when
    collinear or degenerate."""
    ax = p1[0] - p0[0]
    az = p1[1] - p0[1]
    bx = p2[0] - p1[0]
    bz = p2[1] - p1[1]
    cross = ax * bz - az * bx
    a = math.sqrt(ax * ax + az * az)
    b = math.sqrt(bx * bx + bz * bz)
    c = chord_length(p0, p2)
    if a == 0.0 or b == 0.0 or c == 0.0:
        return 0.0
    return 2.0 * cross / (a * b * c)


def superelevation(curvature):
    """The crossfall e for a signed curvature: GAIN / R capped at the class
    of bend (4 %, or 6 % on a hairpin's radius), rising to the outside of the
    bend: a left turn (curvature < 0) rises to the right (e > 0)."""
    if curvature == 0.0:
        return 0.0
    radius = 1.0 / abs(curvature)
    cap = HAIRPIN_SUPERELEVATION_MAX if radius < HAIRPIN_RADIUS_M else SUPERELEVATION_MAX
    e = min(SUPERELEVATION_GAIN_M / radius, cap)
    return e if curvature < 0.0 else -e


def crossfall_of(points):
    """The crossfall at every point of a segment: the three-point circle
    through each interior point and its neighbours; the ends take their
    neighbour's value; a two-point segment is a crowned straight (0)."""
    n = len(points)
    if n < 3:
        return [0.0] * n
    out = [0.0] * n
    for i in range(1, n - 1):
        out[i] = superelevation(signed_curvature(points[i - 1], points[i], points[i + 1]))
    out[0] = out[1]
    out[n - 1] = out[n - 2]
    return out


def bridge_of(segment):
    return "bridge" in segment and segment["bridge"] != "no"


def tunnel_of(segment):
    return segment.get("tunnel") == "yes"


def layer_of(segment):
    try:
        return int(segment.get("layer", "-1"))
    except ValueError:
        return -1


def tunnel_depth(s, length, layer):
    """How far below the DEM a tunnel's road sits at chainage s [m]:
    |layer| × 6 m, ramped in over 30 m from either portal."""
    full = TUNNEL_DEPTH_PER_LAYER_M * max(abs(layer), 1)
    ramp = min(s, length - s) / TUNNEL_RAMP_M
    return full * min(max(ramp, 0.0), 1.0)


def labels_of(dense, length, step=STATION_STEP_M):
    """Crest/dip labels from the dense centre heights (the rounded values
    the file carries, so world_road_profile.gd's mirror computes the same):
    the 20 m second difference at every whole station with the window
    inside the segment; a run beyond the threshold is one label at its
    steepest station. The end station past the last whole one (an uneven
    length) is outside the uniform spacing and takes no window."""
    whole = int(math.floor(length / step + 1e-9))
    count = whole + 1  # the uniform stations 0..whole
    labels = []
    run_kind = None
    run_best = None
    for k in range(count):
        kind = None
        k20 = None
        k40 = None
        if k >= WINDOW_20_STATIONS and k + WINDOW_20_STATIONS < count and None not in (dense[k - WINDOW_20_STATIONS], dense[k], dense[k + WINDOW_20_STATIONS]):
            half = WINDOW_20_STATIONS * step
            k20 = (dense[k + WINDOW_20_STATIONS] - 2.0 * dense[k] + dense[k - WINDOW_20_STATIONS]) / (half * half)
            if k >= WINDOW_40_STATIONS and k + WINDOW_40_STATIONS < count and None not in (dense[k - WINDOW_40_STATIONS], dense[k + WINDOW_40_STATIONS]):
                half40 = WINDOW_40_STATIONS * step
                k40 = (dense[k + WINDOW_40_STATIONS] - 2.0 * dense[k] + dense[k - WINDOW_40_STATIONS]) / (half40 * half40)
            if k20 < -CREST_CURVATURE:
                kind = "crest"
            elif k20 > CREST_CURVATURE:
                kind = "dip"
        if kind != run_kind:
            if run_best is not None:
                labels.append(run_best)
            run_kind = kind
            run_best = None
        if kind is not None and (run_best is None or abs(k20) > abs(run_best["_k20"])):
            run_best = {"at": k * step, "kind": kind, "_k20": k20, "_k40": k40}
    if run_best is not None:
        labels.append(run_best)
    out = []
    for label in labels:
        entry = {"at": rounded(label["at"], CHAINAGE_DECIMALS), "kind": label["kind"], "curvature_20m": rounded(label["_k20"], CURVATURE_DECIMALS)}
        if label["_k40"] is not None:
            entry["curvature_40m"] = rounded(label["_k40"], CURVATURE_DECIMALS)
        out.append(entry)
    return out


def drape_segment(segment, sample):
    """One segment's drape record, or None when no point of it can be
    sampled. `sample(x, z)` is the DEM (None outside). Heights are the
    platform's centre: the DEM at the centreline, a bridge's deck linear
    between its ends, a tunnel's road below the DEM; `heights` at the
    skeleton's points, `dense` at the stations, `crossfall` per point,
    `labels` for a fully covered segment."""
    points = segment["points"]
    chain = chainages(points)
    length = chain[-1]
    stations = station_chainages(length)
    raw_dense = [sample(*point_along(points, chain, s)) for s in stations]
    raw_points = [sample(p[0], p[1]) for p in points]
    covered = None not in raw_dense and None not in raw_points
    if all(h is None for h in raw_points) and all(h is None for h in raw_dense):
        return None
    if bridge_of(segment) or tunnel_of(segment):
        if not covered:
            # A rule needs both portals/abutments: a partly covered bridge or
            # tunnel is left without heights (honest: the profile treats it
            # as outside coverage).
            return {"id": segment["id"], "covered": False, "heights": [None] * len(points), "dense": [None] * len(stations), "crossfall": [rounded(e, CROSSFALL_DECIMALS) for e in crossfall_of(points)], "labels": []}
        if bridge_of(segment):
            h0 = raw_dense[0]
            h1 = raw_dense[-1]
            raw_dense = [h0 + (h1 - h0) * (s / length if length > 0.0 else 0.0) for s in stations]
            raw_points = [h0 + (h1 - h0) * (s / length if length > 0.0 else 0.0) for s in chain]
        else:
            layer = layer_of(segment)
            raw_dense = [h - tunnel_depth(s, length, layer) for h, s in zip(raw_dense, stations)]
            raw_points = [h - tunnel_depth(s, length, layer) for h, s in zip(raw_points, chain)]
    dense = [None if h is None else rounded(h, HEIGHT_DECIMALS) for h in raw_dense]
    heights = [None if h is None else rounded(h, HEIGHT_DECIMALS) for h in raw_points]
    crossfall = crossfall_of(points)
    labels = labels_of(dense, length) if covered else []
    if segment["osm_way"] == KARUSSELL_WAY:
        # Branch (c): the bank's sign from the bend's own direction (a
        # left-hander rises to the right), its size the R9 element's.
        sign = 1.0 if sum(crossfall) >= 0.0 else -1.0
        crossfall = [sign * KARUSSELL_BANK] * len(points)
        labels.append({"at": 0.0, "kind": "bank", "to": rounded(length, CHAINAGE_DECIMALS), "bank": KARUSSELL_BANK, "bowl_m": KARUSSELL_BOWL_M, "strip_m": KARUSSELL_STRIP_M})
    return {
        "id": segment["id"],
        "covered": covered,
        "heights": heights,
        "dense": dense,
        "crossfall": [rounded(e, CROSSFALL_DECIMALS) for e in crossfall],
        "labels": labels,
    }


def lattice_of(mosaic, step=LATTICE_STEP_M):
    """The terrain lattice: the raw DEM at every `step` metres over the
    mosaic's extent, nodes on the outer edges included (sampled half a cell
    in), row-major from the north edge (z_min) southward, x eastward."""
    cols = int(round((mosaic.x_max - mosaic.x_min) / step)) + 1
    rows = int(round((mosaic.z_max - mosaic.z_min) / step)) + 1
    heights = []
    for i in range(rows):
        z = mosaic.z_min + i * step
        for j in range(cols):
            x = mosaic.x_min + j * step
            heights.append(rounded(mosaic.sample_clamped(x, z), HEIGHT_DECIMALS))
    return {"step_m": step, "x0": rounded(mosaic.x_min, CHAINAGE_DECIMALS), "z0": rounded(mosaic.z_min, CHAINAGE_DECIMALS), "cols": cols, "rows": rows, "heights": heights}


def build_drape(skeleton, skeleton_sha, mosaic, pins, source):
    segments = []
    for segment in skeleton["segments"]:
        record = drape_segment(segment, mosaic.sample)
        if record is not None:
            segments.append(record)
    snapshot = dict(skeleton["snapshot"])
    return {
        "snapshot": {
            "osm_base": snapshot["osm_base"],
            "bbox": snapshot["bbox"],
            "query_sha": snapshot["query_sha"],
            "skeleton_pipeline_version": snapshot["pipeline_version"],
            "skeleton_sha256": skeleton_sha,
            "pipeline_version": PIPELINE_VERSION,
        },
        "origin": dict(skeleton["origin"]),
        "dem": {
            "source": source,
            "epsg": EPSG,
            "vertical_datum": "DHHN2016",
            "grid_m": GRID_M,
            "tiles": pins,
        },
        "coverage": {
            "x_min": rounded(mosaic.x_min, CHAINAGE_DECIMALS), "x_max": rounded(mosaic.x_max, CHAINAGE_DECIMALS),
            "z_min": rounded(mosaic.z_min, CHAINAGE_DECIMALS), "z_max": rounded(mosaic.z_max, CHAINAGE_DECIMALS),
        },
        "rules": {
            "station_step_m": STATION_STEP_M,
            "crown": CROWN,
            "superelevation_gain_m": SUPERELEVATION_GAIN_M,
            "superelevation_max": SUPERELEVATION_MAX,
            "hairpin_radius_m": HAIRPIN_RADIUS_M,
            "hairpin_superelevation_max": HAIRPIN_SUPERELEVATION_MAX,
            "crest_curvature": CREST_CURVATURE,
            "tunnel_depth_per_layer_m": TUNNEL_DEPTH_PER_LAYER_M,
            "tunnel_ramp_m": TUNNEL_RAMP_M,
            "blend_band_m": BLEND_BAND_M,
        },
        "lattice": lattice_of(mosaic),
        "segments": segments,
    }


def dumps(drape):
    """The bytes of drape.json: keys sorted, separators compact, UTF-8 as is, one trailing newline."""
    return json.dumps(drape, sort_keys=True, separators=(",", ":"), ensure_ascii=False) + "\n"


def write_drape(path, drape):
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    data = dumps(drape).encode("utf-8")
    with open(path, "wb") as handle:
        handle.write(data)
    return len(data), hashlib.sha256(data).hexdigest()


# --- reports -----------------------------------------------------------------------

def report(skeleton, drape, mosaic):
    covered = [s for s in drape["segments"] if s["covered"]]
    partial = [s for s in drape["segments"] if not s["covered"]]
    by_id = {s["id"]: s for s in skeleton["segments"]}
    total_km = sum(chainages(s["points"])[-1] for s in skeleton["segments"]) / 1000.0
    covered_km = sum(chainages(by_id[s["id"]]["points"])[-1] for s in covered) / 1000.0
    loop = skeleton["loops"][0]
    loop_ids = set(loop["segments"])
    loop_m = sum(chainages(by_id[sid]["points"])[-1] for sid in loop["segments"])
    loop_covered = sum(chainages(by_id[s["id"]]["points"])[-1] for s in covered if s["id"] in loop_ids)
    crest = sum(1 for s in covered for l in s["labels"] if l["kind"] == "crest")
    dip = sum(1 for s in covered for l in s["labels"] if l["kind"] == "dip")
    bank = sum(1 for s in covered for l in s["labels"] if l["kind"] == "bank")
    bridges = sum(1 for s in covered if bridge_of(by_id[s["id"]]))
    tunnels = sum(1 for s in covered if tunnel_of(by_id[s["id"]]))
    stations = sum(len(s["dense"]) for s in drape["segments"])
    low = min((h, s["id"]) for s in covered if s["id"] in loop_ids for h in s["dense"])
    high = max((h, s["id"]) for s in covered if s["id"] in loop_ids for h in s["dense"])
    print("mosaic: x %.0f..%.0f, z %.0f..%.0f (%d × %d cells), heights %.2f..%.2f m" % (mosaic.x_min, mosaic.x_max, mosaic.z_min, mosaic.z_max, mosaic.cols, mosaic.rows, float(mosaic.heights.min()), float(mosaic.heights.max())))
    print("skeleton: %d segments, %.1f km; covered %d segments %.1f km (%.1f %%), partly covered %d, outside %d" % (len(skeleton["segments"]), total_km, len(covered), covered_km, 100.0 * covered_km / total_km, len(partial), len(skeleton["segments"]) - len(drape["segments"])))
    print("loop %s: %.1f m, covered %.1f m (%.2f %%); lowest dense sample %.2f m (%s), highest %.2f m (%s)" % (loop["id"], loop_m, loop_covered, 100.0 * loop_covered / loop_m, low[0], low[1], high[0], high[1]))
    print("stations %d at %.0f m; labels crest %d, dip %d, bank %d; bridges draped %d, tunnels %d" % (stations, STATION_STEP_M, crest, dip, bank, bridges, tunnels))
    print("lattice %d × %d at %.0f m = %d heights" % (drape["lattice"]["cols"], drape["lattice"]["rows"], drape["lattice"]["step_m"], len(drape["lattice"]["heights"])))


def section(skeleton, mosaic, way, offsets=range(-8, 9), every=5.0):
    """A way's cross-sections every `every` metres: the DEM relative to the
    centre at offsets to the right of travel, the slope across the paved
    width, the steepest 1 m cell inside ±5 m. The Karussell evidence
    (ring-region-decisions.md §3)."""
    segments = [s for s in skeleton["segments"] if s["osm_way"] == way]
    if not segments:
        raise ValueError("no segment of way %d" % way)
    for segment in segments:
        points = segment["points"]
        chain = chainages(points)
        half = segment["width_m"] / 2.0
        print("way %d segment %s: %.1f m, %d points, width %.1f m; offsets [m] %s" % (way, segment["id"], chain[-1], len(points), segment["width_m"], list(offsets)))
        best = 0.0
        steep = 0.0
        s = 0.0
        while s <= chain[-1] + 1e-9:
            x, z = point_along(points, chain, s)
            rx, rz = travel_right(points, chain, s)
            centre = mosaic.sample(x, z)
            row = [mosaic.sample(x + o * rx, z + o * rz) for o in offsets]
            left = mosaic.sample(x - half * rx, z - half * rz)
            right = mosaic.sample(x + half * rx, z + half * rz)
            if None in row or centre is None or left is None or right is None:
                print("  s=%6.1f outside the mosaic" % s)
            else:
                slope = (right - left) / (2.0 * half)
                cells = max(abs(row[i + 1] - row[i]) for i in range(len(row) - 1) if abs(list(offsets)[i]) <= 5)
                best = max(best, abs(slope))
                steep = max(steep, cells)
                print("  s=%6.1f centre %7.2f  platform slope %+6.1f %%  steepest 1 m cell %5.1f %% :: %s" % (s, centre, 100.0 * slope, 100.0 * cells, " ".join("%+.2f" % (h - centre) for h in row)))
            s += every
        print("  max |platform slope| %.1f %%, steepest 1 m cell %.1f %% (the tree's threshold: a bank ≥ 20 %%)" % (100.0 * best, 100.0 * steep))


# --- the self-test ----------------------------------------------------------------

class SyntheticMosaic(Mosaic):
    """A DEM from a vectorised function of (x, z) arrays, over a square box,
    for the self-test: no tiles."""

    def __init__(self, function, x_min=0.0, z_min=-3000.0, size=3000.0):
        import numpy as np
        n = int(size / GRID_M)
        centres_x = x_min + (np.arange(n) + 0.5) * GRID_M
        centres_z = z_min + (np.arange(n) + 0.5) * GRID_M
        xs, zs = np.meshgrid(centres_x, centres_z)
        Mosaic.__init__(self, function(xs, zs).astype("float64"), x_min, z_min)


def selftest():
    """The rules on a synthetic DEM: a plane 400 + 0.05·x - 0.02·z with a
    bowl 20 m deep at (1500, -1500) and a crest 3 m high, 30 m long at
    x = 800 across a road running along z."""
    import numpy as np

    def plane(x, z):
        return 400.0 + 0.05 * x - 0.02 * z

    def bowl(x, z):
        d = np.sqrt((x - 1500.0) ** 2 + (z + 1500.0) ** 2)
        return -20.0 * np.maximum(0.0, 1.0 - (d / 200.0) ** 2)

    def crest(x, z):
        d = np.abs(z + 800.0)
        return np.where(np.abs(x - 800.0) < 50.0, 3.0 * np.maximum(0.0, 1.0 - (d / 15.0) ** 2), 0.0)

    mosaic = SyntheticMosaic(lambda x, z: plane(x, z) + bowl(x, z) + crest(x, z))
    failures = 0

    def ok(condition, what):
        nonlocal failures
        print(("  ok    " if condition else "  FAIL  ") + what)
        failures += 0 if condition else 1

    worst = max(abs(mosaic.sample(x, z) - plane(x, z)) for x, z in ((0.5, -0.5), (123.3, -456.7), (2999.5, -2999.5), (1000.0, -2000.0)))
    ok(worst < 1e-9, "the plane is sampled back within %.1e m" % worst)
    ok(abs(mosaic.sample(1500.0, -1500.0) - (plane(1500.0, -1500.0) - 20.0)) < 1e-3, "the bowl's centre is 20 m down (within a millimetre: it sits on four cell corners)")
    ok(mosaic.sample(0.4, -0.5) is None and mosaic.sample(2999.6, -1.0) is None, "half a cell outside the edge is outside")
    road = {"id": "1-0", "osm_way": 1, "class": "primary", "width_m": 7.0, "width_source": "class", "points": [[800.0, -600.0], [800.0, -1000.0]]}
    record = drape_segment(road, mosaic.sample)
    ok(record["covered"] and len(record["dense"]) == 201 and len(record["heights"]) == 2, "a 400 m road along z has 201 stations at 2 m and 2 point heights")
    kinds = [(l["kind"], l["at"]) for l in record["labels"]]
    ok(("crest", 200.0) in kinds, "the crest at z = -800 (chainage 200) is labelled a crest: %s" % kinds)
    ok(all(k != "dip" or abs(a - 200.0) > 10.0 for k, a in kinds), "the dips are the crest's feet, not its top: %s" % kinds)
    ok(record["crossfall"] == [0.0, 0.0], "a straight has crossfall 0 (the crown)")
    bridge = {"id": "2-0", "osm_way": 2, "class": "primary", "width_m": 7.0, "width_source": "class", "bridge": "yes", "layer": "1", "points": [[700.0, -800.0], [900.0, -800.0]]}
    record = drape_segment(bridge, mosaic.sample)
    h0, h1 = record["dense"][0], record["dense"][-1]
    linear = max(abs(h - (h0 + (h1 - h0) * k / (len(record["dense"]) - 1))) for k, h in enumerate(record["dense"]))
    ok(linear <= 0.011, "a bridge over the crest is linear between its abutments (worst %.3f m off)" % linear)
    ok(record["labels"] == [], "a bridge deck has no crest")
    tunnel = {"id": "3-0", "osm_way": 3, "class": "primary", "width_m": 7.0, "width_source": "class", "tunnel": "yes", "layer": "-1", "points": [[700.0, -800.0], [900.0, -800.0]]}
    record = drape_segment(tunnel, mosaic.sample)
    ok(abs(record["dense"][0] - mosaic.sample(700.0, -800.0)) < 0.006 and abs(record["dense"][50] - (mosaic.sample(800.0, -800.0) - 6.0)) < 0.006, "a tunnel is at the DEM at its portal and 6 m under it 100 m in")
    # -z is north (z = -(N - N0)): east then towards -z is a left-hander.
    bend = {"id": "4-0", "osm_way": 4, "class": "secondary", "width_m": 6.5, "width_source": "class", "points": [[100.0, -100.0], [200.0, -100.0], [200.0, -200.0]]}
    ok(crossfall_of(bend["points"])[1] > 0.0 and abs(crossfall_of(bend["points"])[1]) == SUPERELEVATION_MAX, "a left-hand bend (east then north) rises to the right, capped at 4 %%: e = %.3f" % crossfall_of(bend["points"])[1])
    right = {"id": "5-0", "osm_way": 5, "class": "secondary", "width_m": 6.5, "width_source": "class", "points": [[100.0, -100.0], [200.0, -100.0], [200.0, -50.0]]}
    ok(crossfall_of(right["points"])[1] < 0.0, "a right-hand bend (east then south) rises to the left: e = %.3f" % crossfall_of(right["points"])[1])
    hairpin = [[0.0, 0.0], [20.0, -10.0], [0.0, -20.0]]
    ok(abs(crossfall_of(hairpin)[1]) == HAIRPIN_SUPERELEVATION_MAX, "a hairpin's radius (R = %.1f m) is capped at 6 %%" % (1.0 / abs(signed_curvature(*hairpin))))
    gentle = [[0.0, 0.0], [100.0, 0.0], [200.0, -1.0]]
    ok(0.0 < abs(crossfall_of(gentle)[1]) < CROWN, "a gentle bend (R ≈ 10 km) keeps most of its crown: e = %.4f" % crossfall_of(gentle)[1])
    ok(station_chainages(100.0) == [k * 2.0 for k in range(51)] and station_chainages(101.5)[-2:] == [100.0, 101.5] and len(station_chainages(0.0)) == 1, "stations: whole steps and the uneven end")
    skeleton = {"snapshot": {"osm_base": "x", "bbox": [0, 0, 0, 0], "query_sha": "0" * 64, "pipeline_version": 1}, "origin": {"epsg": EPSG, "e0": E0, "n0": N0}, "segments": [road, bridge, tunnel, bend], "junctions": [], "loops": []}
    first = dumps(build_drape(skeleton, "0" * 64, mosaic, [], "synthetic"))
    second = dumps(build_drape(skeleton, "0" * 64, mosaic, [], "synthetic"))
    ok(first == second, "built twice, the same bytes (%d)" % len(first))
    per_tile = int(TILE_M / GRID_M)
    flat = np.full((per_tile, per_tile), 500.0)
    complete = assemble_mosaic([(352, 5577, flat), (353, 5577, flat + 1.0), (352, 5578, flat + 2.0), (353, 5578, flat + 3.0)])
    # z grows southward: z = -0.5 is the south edge (N 5577), z = -1999.5 the north (N 5578).
    ok(complete.rows == 2 * per_tile and complete.cols == 2 * per_tile and complete.sample(0.5, -0.5) == 500.0 and complete.sample(1999.5, -0.5) == 501.0 and complete.sample(0.5, -1999.5) == 502.0 and complete.sample(1999.5, -1999.5) == 503.0, "assemble: four tiles in their places (south-west 500, south-east 501, north-west 502, north-east 503)")
    ok(complete.sample(1000.0, -1000.0) == 501.5, "assemble: a sample on the four tiles' corner blends them, no seam")
    for name, tiles in (("a missing tile", [(352, 5577, flat), (353, 5577, flat), (352, 5578, flat)]),
                        ("a NaN cell", [(352, 5577, np.where(np.arange(per_tile * per_tile).reshape(per_tile, per_tile) == 7, np.nan, 500.0))]),
                        ("an infinite cell", [(352, 5577, np.where(np.arange(per_tile * per_tile).reshape(per_tile, per_tile) == 7, np.inf, 500.0))])):
        refused = ""
        try:
            assemble_mosaic(tiles)
        except ValueError as error:
            refused = str(error)
        ok("without a finite height" in refused, "assemble refuses %s: %s" % (name, refused[:60]))
    ok(re.search(r"-0\.0(?![0-9])", first) is None, "no -0.0 in the file")
    print("DRAPE SELFTEST PASSED" if failures == 0 else "DRAPE SELFTEST FAILED: %d fault(s)" % failures)
    return failures == 0


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--tiles", help="folder of DGM1 tiles (never the repo)")
    parser.add_argument("--tile-prefix", default="dgm1", help="dgm1 (default) or dom1")
    parser.add_argument("--skeleton", help="skeleton.json to drape")
    parser.add_argument("--out", help="where to write drape.json")
    parser.add_argument("--report", action="store_true", help="print the coverage numbers")
    parser.add_argument("--section", type=int, metavar="WAY", help="print a way's cross-sections")
    parser.add_argument("--selftest", action="store_true")
    args = parser.parse_args(argv)
    if args.selftest:
        return 0 if selftest() else 1
    if not args.tiles or not args.skeleton:
        parser.error("--tiles and --skeleton are needed (or --selftest)")
    skeleton, skeleton_sha = load_skeleton(args.skeleton)
    mosaic, pins = load_mosaic(args.tiles, args.tile_prefix)
    if args.section:
        section(skeleton, mosaic, args.section)
        return 0
    source = "DGM1 Rheinland-Pfalz (LVermGeoRP), dl-de/by-2-0" if args.tile_prefix == "dgm1" else "DOM1 Rheinland-Pfalz (LVermGeoRP), dl-de/by-2-0"
    drape = build_drape(skeleton, skeleton_sha, mosaic, pins, source)
    if args.report or not args.out:
        report(skeleton, drape, mosaic)
    if args.out:
        size, digest = write_drape(args.out, drape)
        print("wrote %s: %d bytes, sha256 %s" % (args.out, size, digest))
    return 0


if __name__ == "__main__":
    sys.exit(main())

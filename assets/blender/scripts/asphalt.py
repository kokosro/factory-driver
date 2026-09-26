"""The road's asphalt texture set (docs/art-direction.md "Materials /
Asphalt: diffuse/albedo texture, subtle normal, very mild roughness
variation"; "road: repeating 512/1024"; palette "road: medium cool grey";
docs/design/4b/element-library.md §1 names the file road_asphalt_1024).

    blender -b -P assets/blender/scripts/asphalt.py

writes assets/textures/road/road_asphalt_1024_basecolor.png,
road_asphalt_1024_roughness.png and road_asphalt_1024_normal.png, 1024 x
1024 each, tileable in both directions.

THE UV CONTRACT (assets/blender/README.md, verbatim there): u = (offset -
left_paved_edge) / paved_width, so u 0..1 spans the full paved cross-
section of a strip (shoulder grime at u 0 and 1, wheel ruts symmetric
about u 0.5); v = chainage_m / TILE_ALONG_M with TILE_ALONG_M = 8.0, so
one tile is paved_width x 8 m. The tile is authored for a two-lane
section: a lane's centre at u 0.25 and 0.75, its two wheel ruts a track's
width apart (1.6 m of a 6.5 m section: ±0.12 in u) - so the four ruts
stand at u 0.13 / 0.37 / 0.63 / 0.87, mirrored about the centre line.

THE LAYERED-ROAD LOOK, coarse to fine (the driver's issue-0023: "real
roads have multiple layers"): the aged lighter body of the surface with
its exposed aggregate; the wheel tracks polished darker and smoother
(the roughness map drops there, the height map dips); the lighter
centre between the lanes and the lane centres where no tyre runs; the
shoulder grime darkening toward u 0 and u 1 into the gravel; the
occasional repair patch - a darker rectangle of the tile's own grid with
a visible seam line around it; fine aggregate grain; sparse pale stones
and dark pits. GREYSCALE-NEUTRAL: R = G = B everywhere; the game
multiplies its region tint (RoadBuilder.ASPHALT_TINT, the canon's
"medium cool grey"), so the mean brightness is authored at 0.78 - the
procedural texture it replaces (scripts/asphalt_texture.gd
BASE_BRIGHTNESS) had the same mean, so the tinted road keeps its value.
The normal map is Godot's convention (+Y up, OpenGL) and deliberately
shallow: the ruts and the seams, not every stone.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import common  # noqa: E402
from common import Graph  # noqa: E402

SIZE = 1024
MEAN = 0.815
## The four rut centres in u (two per lane, mirrored about 0.5) and a
## rut's half-width in u (0.03 x 6.5 m = 0.2 m either side).
RUT_CENTRES = [0.13, 0.37, 0.63, 0.87]
RUT_HALF_WIDTH = 0.03
RUT_WANDER = 0.012
## The repair-patch grid over the tile (4 x 3 cells of 1.6 x 2.7 m) and
## the share of cells that are patches.
PATCH_GRID = (4, 3)
PATCH_SHARE = 0.10
## The patch's inset from its cell's border, as a share of the cell.
PATCH_INSET = 0.12
SEAM_ACROSS = 0.012
SEAM_UP = 0.010
## Shoulder grime: full at the edge, gone this far in (0.09 x 6.5 m = 0.6 m).
GRIME_REACH = 0.09
## Stones and pits: a Voronoi of this many cells across / up, the shares.
STONE_CELLS = (170, 210)
STONE_SHARE = 0.03
PIT_SHARE = 0.025
## The normal map's slope scale ("subtle normal").
NORMAL_STRENGTH = 1.6


class Fields:
    """The shared masks of the asphalt tile, built once per graph."""

    def __init__(self, g: Graph):
        u, v = g.u, g.v
        # Aggregate grain, medium variation and broad blotches, all in [0, 1]
        # about 0.5 and tileable (isotropic on a 6.5 x 8 m tile: su:sv 13:16).
        self.grain = g.noise(u, v, 210, 258, detail=2.0, roughness=0.65, phase=0.3)
        self.micro = g.noise(u, v, 430, 530, detail=1.0, roughness=0.5, phase=5.1)
        self.medium = g.noise(u, v, 26, 32, detail=3.0, roughness=0.55, phase=1.1)
        self.blotch = g.noise(u, v, 5, 6, detail=2.0, roughness=0.5, phase=2.2)
        # The ruts: four Gaussians about wandering centres (the wander is a
        # function of v alone, so it tiles along the road).
        wander = g.mul(g.sub(g.noise(0.0, v, 1, 2, detail=1.0, phase=0.7), 0.5), 2.0 * RUT_WANDER)
        rut = 0.0
        for centre in RUT_CENTRES:
            d = g.div(g.sub(u, g.add(wander, centre)), RUT_HALF_WIDTH)
            bell = g.math('EXPONENT', g.mul(g.mul(d, d), -1.0))
            rut = g.add(rut, bell) if not isinstance(rut, float) else bell
        # The polish is uneven along the track: the medium noise modulates it.
        self.rut = g.mul(g.clamp01(rut), g.add(0.7, g.mul(self.medium, 0.6)))
        # The lighter aged strips: between the lanes and at each lane's centre.
        light = 0.0
        for centre, width, weight in ((0.5, 0.05, 1.0), (0.25, 0.07, 0.6), (0.75, 0.07, 0.6)):
            d = g.div(g.sub(u, centre), width)
            bell = g.mul(g.math('EXPONENT', g.mul(g.mul(d, d), -1.0)), weight)
            light = g.add(light, bell) if not isinstance(light, float) else bell
        self.light = g.clamp01(light)
        # Shoulder grime: distance to the nearer edge, its boundary ragged.
        edge = g.minimum(u, g.sub(1.0, u))
        ragged = g.mul(g.sub(g.noise(u, v, 3, 14, detail=2.0, phase=3.3), 0.5), 0.05)
        self.grime = g.smoothstep(g.add(edge, ragged), GRIME_REACH, 0.005)
        # Repair patches on the tile's grid: a cell is a patch when its
        # random is under the share; the patch is the cell inset by
        # PATCH_INSET each side (plain asphalt around it, so a patch never
        # touches the tile's edge and the tile's border rows stay plain);
        # the seam is the band just inside the patch's border.
        rnd, fu, fv = g.cells(u, v, PATCH_GRID[0], PATCH_GRID[1], salt=17.0)
        inner_u = g.minimum(fu, g.sub(1.0, fu))
        inner_v = g.minimum(fv, g.sub(1.0, fv))
        chosen = g.less(rnd, PATCH_SHARE)
        self.patch = g.mul(chosen, g.mul(g.greater(inner_u, PATCH_INSET), g.greater(inner_v, PATCH_INSET)))
        seam_u = g.less(inner_u, PATCH_INSET + SEAM_ACROSS * PATCH_GRID[0])
        seam_v = g.less(inner_v, PATCH_INSET + SEAM_UP * PATCH_GRID[1])
        self.seam = g.mul(self.patch, g.clamp01(g.add(seam_u, seam_v)))
        # A lighter hairline just inside the seam (the sealant's edge).
        lip_u = g.less(inner_u, PATCH_INSET + SEAM_ACROSS * PATCH_GRID[0] * 1.6)
        lip_v = g.less(inner_v, PATCH_INSET + SEAM_UP * PATCH_GRID[1] * 1.6)
        self.lip = g.mul(self.patch, g.mul(g.clamp01(g.add(lip_u, lip_v)), g.sub(1.0, self.seam)))
        # Stones and pits: sparse Voronoi cells, the feature point's disc.
        distance, cell_random = g.voronoi(u, v, STONE_CELLS[0], STONE_CELLS[1], phase=4.4)
        disc = g.less(distance, 0.34)
        self.stone = g.mul(disc, g.less(cell_random, STONE_SHARE))
        self.pit = g.mul(disc, g.greater(cell_random, 1.0 - PIT_SHARE))


def basecolor(g: Graph):
    f = Fields(g)
    value = MEAN
    value = g.add(value, g.mul(g.sub(f.grain, 0.5), 0.13))
    value = g.add(value, g.mul(g.sub(f.micro, 0.5), 0.06))
    value = g.add(value, g.mul(g.sub(f.medium, 0.5), 0.07))
    value = g.add(value, g.mul(g.sub(f.blotch, 0.5), 0.06))
    value = g.add(value, g.mul(f.light, 0.045))
    value = g.sub(value, g.mul(f.rut, 0.11))
    value = g.sub(value, g.mul(f.patch, 0.045))
    value = g.sub(value, g.mul(f.seam, 0.11))
    value = g.add(value, g.mul(f.lip, 0.04))
    value = g.sub(value, g.mul(f.grime, 0.22))
    value = g.add(value, g.mul(f.stone, 0.18))
    value = g.sub(value, g.mul(f.pit, 0.16))
    g.emit(g.clamp01(value))


def roughness(g: Graph):
    f = Fields(g)
    value = 0.84
    value = g.add(value, g.mul(g.sub(f.medium, 0.5), 0.06))
    value = g.add(value, g.mul(g.sub(f.grain, 0.5), 0.04))
    value = g.sub(value, g.mul(f.rut, 0.26))
    value = g.sub(value, g.mul(f.patch, 0.06))
    value = g.add(value, g.mul(f.grime, 0.10))
    value = g.sub(value, g.mul(f.stone, 0.15))
    g.emit(g.clamp01(value))


def height(g: Graph):
    f = Fields(g)
    value = 0.5
    value = g.sub(value, g.mul(f.rut, 0.30))
    value = g.add(value, g.mul(g.sub(f.grain, 0.5), 0.08))
    value = g.add(value, g.mul(g.sub(f.medium, 0.5), 0.05))
    value = g.sub(value, g.mul(f.seam, 0.18))
    value = g.add(value, g.mul(f.patch, 0.03))
    value = g.add(value, g.mul(f.stone, 0.10))
    value = g.sub(value, g.mul(f.pit, 0.12))
    g.emit(g.clamp01(value))


def build(preview_dir=None, reset=True):
    common.ensure_dirs()
    if reset:
        common.reset_scene()
    plane = common.unit_plane("Asphalt")
    base = common.to_array(common.bake_float_image(plane, basecolor, SIZE, "asphalt_basecolor"))
    rough = common.to_array(common.bake_float_image(plane, roughness, SIZE, "asphalt_roughness"))
    high = common.to_array(common.bake_float_image(plane, height, SIZE, "asphalt_height"))
    base[..., 3] = 1.0
    rough[..., 3] = 1.0
    path = os.path.join(common.TEXTURES_ROAD, "road_asphalt_1024_basecolor.png")
    common.save_rgba_png(base, path, "road_asphalt_1024_basecolor")
    common.report(path)
    path = os.path.join(common.TEXTURES_ROAD, "road_asphalt_1024_roughness.png")
    common.save_rgba_png(rough, path, "road_asphalt_1024_roughness")
    common.report(path)
    normal = common.normal_map_from_height(high[..., 0], NORMAL_STRENGTH, wrap=True)
    path = os.path.join(common.TEXTURES_ROAD, "road_asphalt_1024_normal.png")
    common.save_rgba_png(normal, path, "road_asphalt_1024_normal")
    common.report(path)
    print("asphalt basecolor mean %.4f, ruts at u %s" % (float(base[..., 0].mean()), RUT_CENTRES))
    if preview_dir:
        common.tiled_preview(base, os.path.join(preview_dir, "asphalt_basecolor_2x2.png"))
        common.tiled_preview(normal, os.path.join(preview_dir, "asphalt_normal_2x2.png"))
    return plane


if __name__ == "__main__":
    build(common.preview_dir_from_argv())

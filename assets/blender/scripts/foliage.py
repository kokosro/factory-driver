"""The vegetation textures (docs/art-direction.md "Trees": "simple trunks /
crossed foliage cards / billboard foliage / chunky low-poly crowns /
several repeated tree archetypes / dark forest walls made from layered
vegetation cards"; "vegetation: 128-512"; docs/design/4b/element-
library.md §6 V1 / V2 / V4).

    blender -b -P assets/blender/scripts/foliage.py

writes, into assets/textures/vegetation/, all GREYSCALE-NEUTRAL (R = G =
B; the region's tint table colours them: data/regions/eifel_ring/
dressing.json, multiplied in as the vertex colour):

  bark_256.png             256 x 256, opaque, tileable both ways: vertical
                           bark ridges and dark fissures; wraps once
                           around a trunk and every 2 m up it.
  foliage_wall_512.png     512 x 512, alpha; tileable across (u): the V4
                           forest-wall card. Opaque canopy body with tree
                           columns and three layered canopy tiers, the
                           spruce tops a jagged alpha silhouette in the
                           upper third, holes of sky between the crowns.
                           A card offsets u by its hash, so no two
                           neighbours show the same skyline.
  foliage_spruce_512.png   512 x 512, alpha, an atlas of three regions:
                           LEFT HALF (u 0..0.5, full height) the spruce
                           side card - a tapering tiered silhouette with
                           drooping branch fringes, gaps above each tier,
                           the trunk dark up the middle; RIGHT-TOP
                           quadrant (u 0.5..1, v 0.5..1 in Blender's up-
                           going v) the branch whorl seen from above, a
                           seven-pointed star of alpha for the tier cones;
                           RIGHT-BOTTOM quadrant a sparser five-pointed
                           whorl for the top tiers.
  foliage_beech_512.png    512 x 512, alpha, an atlas of two regions:
                           LEFT HALF the beech crown card - an irregular
                           chunky crown of lumped clusters with holes of
                           sky; RIGHT HALF a leaf-cluster fill, tileable
                           within the half, that the crown lobes wear.

Godot reads v downwards: a card's top is v = 0 there and v = 1 here
(common.py, ORIENTATION). The foliage means sit near 0.8 so the tint
dominates: the canon's forest is "deep green and almost black" by its
tints, the textures add the age and the silhouette.
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import numpy as np  # noqa: E402

import common  # noqa: E402
from common import Graph  # noqa: E402

BARK_SIZE = 256
CARD_SIZE = 512


# =============================================================================
#  BARK
# =============================================================================

def bark_grey(g: Graph):
    u, v = g.u, g.v
    ridges = g.noise(u, v, 16, 2.5, detail=3.0, roughness=0.6, phase=0.4)
    fine = g.noise(u, v, 90, 70, detail=1.0, roughness=0.5, phase=1.9)
    fissure = g.power(g.sub(1.0, g.mul(g.absolute(g.sub(ridges, 0.5)), 2.0)), 4.0)
    value = 0.66
    value = g.add(value, g.mul(g.sub(ridges, 0.5), 0.34))
    value = g.sub(value, g.mul(fissure, 0.32))
    value = g.add(value, g.mul(g.sub(fine, 0.5), 0.14))
    g.emit(g.clamp01(value))


# =============================================================================
#  THE WALL CARD
# =============================================================================

def wall_top(g: Graph, u):
    """The skyline of the wall card as a function of u alone (tileable):
    rolling crowns with the pointed tops of spruces."""
    roll = g.mul(g.sub(g.noise(u, 0.0, 5, 1, detail=1.0, phase=0.9), 0.5), 0.24)
    top = g.add(0.74, roll)
    for columns, phase, weight in ((9, 0.3, 0.11), (5, 0.7, 0.07)):
        saw = g.sub(1.0, g.absolute(g.sub(g.mul(g.fract(g.mad(u, columns, phase)), 2.0), 1.0)))
        height = g.noise(u, 0.0, columns, 1, detail=0.0, phase=phase * 9.0)
        top = g.add(top, g.mul(g.power(saw, 1.5), g.mul(height, weight)))
    return top


def wall_alpha(g: Graph):
    u, v = g.u, g.v
    top = wall_top(g, u)
    ragged = g.mul(g.sub(g.noise(u, v, 40, 40, detail=1.0, phase=2.1), 0.5), 0.03)
    edge = g.sub(v, g.add(top, ragged))
    alpha = g.smoothstep(edge, 0.006, -0.006)
    # Sky through the crowns just under the skyline.
    holes = g.noise(u, v, 16, 16, detail=2.0, phase=3.7)
    near_top = g.smoothstep(v, g.sub(top, 0.3), g.sub(top, 0.05))
    alpha = g.mul(alpha, g.sub(1.0, g.mul(near_top, g.greater(holes, 0.62))))
    g.emit(alpha)


def wall_grey(g: Graph):
    u, v = g.u, g.v
    top = wall_top(g, u)
    columns = g.noise(u, v, 14, 1.6, detail=2.0, roughness=0.6, phase=1.3)
    deep = g.power(g.sub(1.0, columns), 2.0)
    fine = g.noise(u, v, 70, 70, detail=2.0, roughness=0.55, phase=4.2)
    clusters = g.noise(u, v, 9, 9, detail=2.0, phase=6.1)
    wave = g.mul(g.sub(g.noise(u, 0.0, 6, 1, detail=1.0, phase=4.4), 0.5), 0.5)
    tier = g.fract(g.add(g.mad(v, 3.0, 0.2), wave))
    tier_shade = g.smoothstep(tier, 0.0, 0.6)
    lit = g.smoothstep(v, g.sub(top, 0.25), top)
    value = g.mad(v, 0.3, 0.5)
    value = g.add(value, g.mul(g.sub(columns, 0.5), 0.3))
    value = g.sub(value, g.mul(deep, 0.2))
    value = g.add(value, g.mul(g.sub(fine, 0.5), 0.12))
    value = g.add(value, g.mul(g.sub(clusters, 0.5), 0.16))
    value = g.add(value, g.mul(g.sub(tier_shade, 0.5), 0.2))
    value = g.add(value, g.mul(lit, 0.14))
    g.emit(g.clamp01(value))


# =============================================================================
#  THE SPRUCE ATLAS
# =============================================================================

def spruce_card_halfwidth(g: Graph, uc, v):
    """The half-width of the spruce silhouette at height v: a taper with
    ten drooping tiers, branch groups and a ragged edge. Also returns the
    tier phase."""
    wave = g.mul(g.sub(g.noise(uc, v, 7, 3, detail=1.0, phase=4.9), 0.5), 0.6)
    tier = g.fract(g.add(g.mad(v, 10.0, 0.5), wave))
    taper = g.mad(g.power(g.sub(1.0, v), 0.9), 0.44, 0.03)
    droop = g.mad(g.sub(1.0, tier), 0.22, 0.78)
    ragged = g.mul(g.sub(g.noise(uc, v, 24, 70, detail=2.0, phase=0.8), 0.5), 0.10)
    tips = g.mul(g.sub(g.noise(uc, v, 6, 40, detail=1.0, phase=6.6), 0.5), 0.08)
    return g.add(g.add(g.mul(taper, droop), ragged), tips), tier


def whorl(g: Graph, ur, vr, points, sparse, phase):
    """A star of `points` branches about the centre of the (ur, vr) unit
    square: (alpha, radius, angle)."""
    a = g.mul(g.sub(ur, 0.5), 2.0)
    b = g.mul(g.sub(vr, 0.5), 2.0)
    r = g.sqrt(g.add(g.mul(a, a), g.mul(b, b)))
    theta = g.math('ARCTAN2', b, a)
    star = g.power(g.mad(g.cos(g.mad(theta, float(points), g.mul(g.sin(g.mul(theta, 3.0)), 0.8))), 0.5, 0.5), 0.9)
    wobble = g.mad(g.sub(g.noise(ur, vr, 30, 30, detail=1.0, phase=phase + 5.5), 0.5), 0.24, 0.92 - sparse)
    needles = g.mul(g.sub(g.noise(ur, vr, 70, 70, detail=1.0, phase=phase + 8.5), 0.5), 0.12)
    reach = g.add(g.mul(g.mad(star, 0.75, 0.2), wobble), needles)
    disc = g.smoothstep(g.sub(r, reach), 0.01, -0.01)
    disc = g.maximum(disc, g.less(r, 0.15))
    return disc, r, theta


def spruce_alpha(g: Graph):
    u, v = g.u, g.v
    left = g.less(u, 0.5)
    uc = g.mul(u, 2.0)
    hw, tier = spruce_card_halfwidth(g, uc, v)
    off = g.absolute(g.sub(uc, 0.5))
    card = g.smoothstep(g.sub(off, hw), 0.006, -0.006)
    card = g.mul(card, g.mul(g.greater(v, 0.02), g.less(v, 0.985)))
    # Above a tier's fringe the outer branches leave a gap, here and there.
    gap = g.mul(g.greater(tier, 0.9), g.greater(off, g.mul(hw, 0.5)))
    gap = g.mul(gap, g.greater(g.noise(uc, v, 20, 20, detail=1.0, phase=3.1), 0.4))
    card = g.mul(card, g.sub(1.0, gap))
    ur = g.sub(g.mul(u, 2.0), 1.0)
    whorls = 0.0
    for v0, points, sparse, phase in ((0.5, 9, 0.0, 0.0), (0.0, 6, 0.1, 2.0)):
        vr = g.mul(g.sub(v, v0), 2.0)
        disc, _, _ = whorl(g, ur, vr, points, sparse, phase)
        inside = g.mul(g.mul(g.greater(vr, 0.0), g.less(vr, 1.0)), g.greater(ur, 0.0))
        whorls = g.add(whorls, g.mul(disc, inside)) if not isinstance(whorls, float) else g.mul(disc, inside)
    alpha = g.add(g.mul(left, card), g.mul(g.sub(1.0, left), g.clamp01(whorls)))
    g.emit(alpha)


def spruce_grey(g: Graph):
    u, v = g.u, g.v
    left = g.less(u, 0.5)
    uc = g.mul(u, 2.0)
    hw, tier = spruce_card_halfwidth(g, uc, v)
    off = g.absolute(g.sub(uc, 0.5))
    fine = g.noise(uc, v, 50, 100, detail=3.0, roughness=0.6, phase=1.4)
    outward = g.clamp01(g.div(off, g.maximum(hw, 0.02)))
    card = 0.56
    card = g.add(card, g.mul(g.power(outward, 0.6), 0.26))
    card = g.add(card, g.mul(g.sub(fine, 0.5), 0.24))
    card = g.add(card, g.mul(g.sub(1.0, tier), 0.14))
    card = g.add(card, g.mul(v, 0.08))
    trunk = g.mul(g.less(off, 0.011), g.less(v, 0.75))
    card = g.mix(trunk, card, 0.34)
    ur = g.sub(g.mul(u, 2.0), 1.0)
    vr = g.fract(g.mul(v, 2.0))
    _, r, theta = whorl(g, ur, vr, 9, 0.0, 0.0)
    streaks = g.noise(g.mad(theta, 0.15915494, 0.5), g.mul(r, 0.5), 28, 5, detail=2.0, phase=7.7)
    star_shade = g.mad(g.cos(g.mul(theta, 9.0)), 0.5, 0.5)
    whorl_value = 0.58
    whorl_value = g.add(whorl_value, g.mul(r, 0.2))
    whorl_value = g.add(whorl_value, g.mul(g.sub(streaks, 0.5), 0.22))
    whorl_value = g.add(whorl_value, g.mul(star_shade, 0.12))
    whorl_value = g.add(whorl_value, g.mul(g.sub(fine, 0.5), 0.1))
    value = g.add(g.mul(left, card), g.mul(g.sub(1.0, left), whorl_value))
    g.emit(g.clamp01(value))


# =============================================================================
#  THE BEECH ATLAS
# =============================================================================

BEECH_BLOBS = ((0.5, 0.64, 0.3), (0.25, 0.5, 0.24), (0.75, 0.54, 0.23), (0.5, 0.36, 0.24), (0.36, 0.84, 0.16), (0.66, 0.82, 0.15))


def beech_crown_mass(g: Graph, uc, v):
    mass = 0.0
    for cx, cy, radius in BEECH_BLOBS:
        dx = g.div(g.sub(uc, cx), radius)
        dy = g.div(g.sub(v, cy), radius)
        bell = g.math('EXPONENT', g.mul(g.add(g.mul(dx, dx), g.mul(dy, dy)), -3.0))
        mass = g.add(mass, bell) if not isinstance(mass, float) else bell
    big = g.mul(g.sub(g.noise(uc, v, 7, 7, detail=2.0, phase=2.6), 0.5), 1.0)
    small = g.mul(g.sub(g.noise(uc, v, 22, 22, detail=2.0, phase=2.9), 0.5), 0.5)
    return g.add(g.add(mass, big), small)


def beech_alpha(g: Graph):
    u, v = g.u, g.v
    left = g.less(u, 0.5)
    uc = g.mul(u, 2.0)
    mass = beech_crown_mass(g, uc, v)
    crown = g.smoothstep(mass, 0.5, 0.6)
    holes = g.noise(uc, v, 12, 12, detail=2.0, phase=3.9)
    crown = g.mul(crown, g.sub(1.0, g.mul(g.greater(holes, 0.64), g.less(mass, 1.2))))
    crown = g.mul(crown, g.less(v, 0.985))
    ul = g.sub(g.mul(u, 2.0), 1.0)
    fill = g.smoothstep(g.noise(ul, v, 9, 9, detail=2.0, phase=8.3), 0.40, 0.46)
    fill = g.mul(fill, g.sub(1.0, g.greater(g.noise(ul, v, 20, 20, detail=1.0, phase=8.8), 0.7)))
    alpha = g.add(g.mul(left, crown), g.mul(g.sub(1.0, left), fill))
    g.emit(alpha)


def leaf_shading(g: Graph, uc, v, base, phase):
    clusters = g.noise(uc, v, 12, 12, detail=3.0, roughness=0.55, phase=phase)
    fine = g.noise(uc, v, 64, 64, detail=2.0, roughness=0.5, phase=phase + 3.1)
    shadow = g.smoothstep(clusters, 0.55, 0.3)
    value = base
    value = g.add(value, g.mul(g.power(clusters, 1.3), 0.5))
    value = g.sub(value, g.mul(shadow, 0.22))
    value = g.add(value, g.mul(g.sub(fine, 0.5), 0.16))
    return value


def beech_grey(g: Graph):
    u, v = g.u, g.v
    left = g.less(u, 0.5)
    uc = g.mul(u, 2.0)
    crown = leaf_shading(g, uc, v, 0.5, 1.7)
    crown = g.add(crown, g.mul(v, 0.1))
    crown = g.sub(crown, g.mul(g.smoothstep(v, 0.45, 0.15), 0.15))
    ul = g.sub(g.mul(u, 2.0), 1.0)
    fill = leaf_shading(g, ul, v, 0.52, 9.1)
    value = g.add(g.mul(left, crown), g.mul(g.sub(1.0, left), fill))
    g.emit(g.clamp01(value))


# =============================================================================
#  THE BUILD
# =============================================================================

def build(preview_dir=None, reset=True):
    common.ensure_dirs()
    if reset:
        common.reset_scene()
    plane = common.unit_plane("Foliage")
    plane.location.y = -2.0
    written = {}

    bark = common.to_array(common.bake_float_image(plane, bark_grey, BARK_SIZE, "bark"))
    bark[..., 3] = 1.0
    path = os.path.join(common.TEXTURES_VEG, "bark_256.png")
    common.save_rgba_png(bark, path, "bark_256")
    common.report(path)
    written["bark"] = bark

    for name, grey_fn, alpha_fn in (
        ("foliage_wall_512", wall_grey, wall_alpha),
        ("foliage_spruce_512", spruce_grey, spruce_alpha),
        ("foliage_beech_512", beech_grey, beech_alpha),
    ):
        grey = common.to_array(common.bake_float_image(plane, grey_fn, CARD_SIZE, name + "_grey"))[..., 0]
        alpha = common.to_array(common.bake_float_image(plane, alpha_fn, CARD_SIZE, name + "_alpha"))[..., 0]
        rgba = common.grey_with_alpha(grey, alpha)
        path = os.path.join(common.TEXTURES_VEG, name + ".png")
        common.save_rgba_png(rgba, path, name)
        common.report(path)
        covered = alpha > 0.5
        print("%s: mean grey where opaque %.3f, opaque share %.3f" % (name, float(grey[covered].mean()) if covered.any() else 0.0, float(covered.mean())))
        written[name] = rgba

    if preview_dir:
        for name, rgba in written.items():
            common.tiled_preview(rgba, os.path.join(preview_dir, name + "_2x2.png"))
            common.checker_preview(rgba, os.path.join(preview_dir, name + "_alpha.png"))
    return plane


if __name__ == "__main__":
    build(common.preview_dir_from_argv())

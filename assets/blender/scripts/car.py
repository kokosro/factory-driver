"""The hero car's exterior: a 1997 Boxster 986, soft top up (CARS-1 slice 1;
docs/art-direction.md "The cars are different": "Car: lovingly modeled",
"correct Porsche silhouette", "wheel wells", "separate glass", "headlights",
"taillights", "mirrors", "exhaust" - "But resist modern manufacturing-CAD
density. The silhouette and proportions matter more than tiny panel
fasteners."; "Car paint": "glossy but relatively simple", "strong specular /
moderate roughness / simple environment reflection"; "Windows": "fairly dark
glass").

    blender -b -P assets/blender/scripts/car.py [-- --preview DIR]

writes assets/meshes/car_boxster_986.glb: eight meshes, one material each,
no textures (plain glTF factors), which scenes/car.tscn instances AS its
Body node - so each mesh is a direct MeshInstance3D child of Body and
scripts/xray.gd fades every one of them:

  Paint      the body shell and the two mirrors (the shipped red)
  Glass      windscreen, door glass, the soft top's rear window (dark,
             tinted-opaque: the interior is the next slice)
  SoftTop    the fabric roof, up (double-sided: the cockpit camera keeps
             "the roof above")
  Trim       black: A-pillars and header, the three front intakes, the two
             side intakes ahead of the rear wheels, the wheel wells, the
             underbody, the cabin's inner sill, the exhaust's surround and
             bore
  Headlight  the two teardrop lenses on the fender fronts (emissive)
  Taillight  the two corner lamps (emissive)
  Indicator  the amber section of each lamp unit
  Exhaust    the single central oval tailpipe

A FREE PROCEDURAL INTERPRETATION, no reference photos and no blueprint: the
shape is a handful of curves along the car (width, sill, widest line,
fender crest, centre line) and one cross-section rule, lofted. It is sized
to the game's physics, not to the real car: 4.2 m long (the collision box),
the wheels where car.gd has them (HALF_TRACK 0.86, axles at z -+1.3, tyre
radius 0.34, width 0.26 - a track 0.22 m wider than the real 986's), so the
fenders reach x ~1.02 to stand over tyres whose outer face is at x 0.99.

SPACES. Everything below is authored in CAR SPACE (scenes/car.tscn: origin
on the ground under the middle of the car, nose towards -Z, +X to the
driver's right, +Y up, metres). The file is written in BODY SPACE: car.tscn's
Body node sits PIVOT_Y (0.3 m) over the car's origin and car.gd pitches,
rolls and heaves it, so every vertex is stored PIVOT_Y lower and the
instanced Body draws it back in car space.

Deterministic: no randomness anywhere (common.SEED is not consumed), a fixed
vertex and face order, Blender's own smooth normals, the glTF JSON
re-serialised by trees.pack_glb with sorted keys; run twice, the bytes are
the same (assets/blender/README.md).
"""

import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402
from mathutils import Vector  # noqa: E402

import common  # noqa: E402
import trees  # noqa: E402  (pack_glb, the repo's sorted-keys packer)

NAME = "car_boxster_986"

# --- The physics envelope (scripts/car.gd, scenes/car.tscn, scenes/wheel.tscn) ---

## Height of car.tscn's Body node over the car's origin [m].
PIVOT_Y = 0.30
## The collision box is 4.2 m long: nose at -HALF_LENGTH, tail at +HALF_LENGTH.
HALF_LENGTH = 2.10
## Axles at z -AXLE_Z (front) and +AXLE_Z; wheel centres HALF_TRACK out, WHEEL_Y up.
AXLE_Z = 1.30
HALF_TRACK = 0.86
WHEEL_Y = 0.34
TYRE_RADIUS = 0.34
TYRE_WIDTH = 0.26

# --- The wheel arches ---

## Arch radius [m]: 0.06 over the tyre all round (the suspension travels
## 0.07 either way, car.gd SUSPENSION_TRAVEL: at full droop the gap opens, and
## a wheel 0.06 into its bump travel reaches the well's roof, inside the fender).
ARCH_RADIUS = 0.40
ARCH_SEGMENTS = 14
## How far either side of the axle the arch's columns spread at the fender crest [m].
ARCH_FAN = 0.50
## The wheel well's inner wall [m from the centre line]: inboard of a front
## tyre at full lock (car.gd MAX_STEER_LOCK 0.48 rad: its inner corner swings
## in to x 0.59).
WELL_INNER_X = 0.55

# --- The materials (name, albedo sRGB, metallic, roughness, emission sRGB, energy, double-sided) ---
# Paint, Glass, Headlight and Taillight carry the placeholder's values
# (car.tscn's mat_paint, mat_glass, mat_headlight, mat_taillight before
# CARS-1): the driver's ruling keeps the shipped red.
MATERIALS = (
    ("Paint", (0.82, 0.16, 0.12), 0.3, 0.35, None, 0.0, False),
    ("Glass", (0.08, 0.12, 0.17), 0.5, 0.15, None, 0.0, False),
    ("SoftTop", (0.035, 0.035, 0.04), 0.0, 0.9, None, 0.0, True),
    ("Trim", (0.05, 0.05, 0.055), 0.0, 0.8, None, 0.0, False),
    ("Headlight", (1.0, 0.96, 0.8), 0.0, 0.25, (1.0, 0.95, 0.75), 1.5, False),
    ("Taillight", (0.7, 0.05, 0.05), 0.0, 0.3, (1.0, 0.1, 0.1), 1.2, False),
    ("Indicator", (0.95, 0.5, 0.05), 0.0, 0.3, None, 0.0, False),
    ("Exhaust", (0.8, 0.8, 0.82), 0.9, 0.25, None, 0.0, False),
)


# =============================================================================
#  Curves along the car
# =============================================================================

class Curve:
    """A monotone piecewise cubic through (z, value) knots (Fritsch-Carlson):
    no overshoot between knots, flat at a local extreme."""

    def __init__(self, knots):
        self.x = [k[0] for k in knots]
        self.y = [k[1] for k in knots]
        n = len(knots)
        h = [self.x[i + 1] - self.x[i] for i in range(n - 1)]
        d = [(self.y[i + 1] - self.y[i]) / h[i] for i in range(n - 1)]
        m = [0.0] * n
        m[0] = d[0]
        m[-1] = d[-1]
        for i in range(1, n - 1):
            if d[i - 1] * d[i] <= 0.0:
                m[i] = 0.0
            else:
                w1 = 2.0 * h[i] + h[i - 1]
                w2 = h[i] + 2.0 * h[i - 1]
                m[i] = (w1 + w2) / (w1 / d[i - 1] + w2 / d[i])
        self.h = h
        self.m = m

    def __call__(self, v):
        x = self.x
        if v <= x[0]:
            return self.y[0]
        if v >= x[-1]:
            return self.y[-1]
        i = 0
        while v > x[i + 1]:
            i += 1
        h = self.h[i]
        s = (v - x[i]) / h
        s2 = s * s
        s3 = s2 * s
        return ((2 * s3 - 3 * s2 + 1) * self.y[i] + (s3 - 2 * s2 + s) * h * self.m[i]
                + (-2 * s3 + 3 * s2) * self.y[i + 1] + (s3 - s2) * h * self.m[i + 1])


## Half the body's greatest width before the ends round in [m]: the front
## fenders, the waist at the doors, the rear haunches (the widest of the car).
WIDTH = Curve([(-2.1, 1.00), (-1.3, 1.02), (-0.6, 0.945), (0.0, 0.925), (0.55, 0.95), (1.3, 1.03), (2.1, 1.01)])
## The ends round in, seen from above, as a superellipse from here to the tip.
NOSE_ROUND_FROM = -1.40
NOSE_ROUND_POWER = 2.5
TAIL_ROUND_FROM = 1.42
TAIL_ROUND_POWER = 2.9
## Where the flank turns into the deck (the fender crest, the door's
## shoulder), as a share of the width ...
SHOULDER_SHARE = Curve([(-2.1, 0.62), (-1.3, 0.72), (-0.76, 0.80), (-0.3, 0.865), (0.3, 0.865), (0.70, 0.82), (1.3, 0.76), (2.1, 0.66)])
## ... and its height [m]: low at the nose, the front fender's crest over the
## axle, the beltline, the haunch, the tail.
SHOULDER_Y = Curve([(-2.10, 0.44), (-2.07, 0.50), (-2.0, 0.575), (-1.85, 0.68), (-1.6, 0.80), (-1.3, 0.87), (-1.0, 0.90),
                    (-0.76, 0.925), (0.0, 0.93), (0.70, 0.94), (1.0, 0.945), (1.3, 0.935), (1.6, 0.89), (1.85, 0.81),
                    (2.0, 0.74), (2.07, 0.68), (2.10, 0.62)])
## The centre line's height [m]: the bonnet lies in a valley between the
## fenders, the engine deck stands a little over the haunches.
CENTRE_Y = Curve([(-2.10, 0.44), (-2.07, 0.505), (-2.0, 0.575), (-1.85, 0.65), (-1.6, 0.725), (-1.3, 0.785), (-1.0, 0.835),
                  (-0.86, 0.855), (-0.76, 0.875), (0.0, 0.93), (0.70, 0.965), (1.0, 0.96), (1.3, 0.94), (1.6, 0.89),
                  (1.85, 0.81), (2.0, 0.745), (2.07, 0.69), (2.10, 0.62)])
## The sill: the body's lower edge [m]. The collision box's underside is at
## 0.12 (car.gd GROUND_CLEARANCE); the drawn sill stays over it.
SILL_Y = Curve([(-2.1, 0.20), (-1.75, 0.20), (-1.3, 0.17), (1.3, 0.17), (1.7, 0.22), (1.9, 0.27), (2.1, 0.27)])
## The sill tucks under: its half width as a share of the greatest.
SILL_SHARE = 0.91
## Height of the body's widest line [m].
WIDEST_Y = Curve([(-2.1, 0.36), (-1.75, 0.52), (-1.3, 0.62), (-0.5, 0.56), (0.5, 0.56), (1.3, 0.64), (1.8, 0.56), (2.1, 0.46)])
## How far across the deck (0 at the shoulder, 1 at the centre line) the
## surface has come to the centre line's height: a narrow value is a fender
## standing over a flat bonnet.
DECK_BLEND = Curve([(-2.1, 0.8), (-1.3, 0.5), (-0.76, 0.6), (0.7, 0.9), (2.1, 1.0)])
## The upper flank's roundness (a superellipse's exponent: 2 an ellipse, more
## a squarer shoulder).
SHOULDER_POWER = Curve([(-2.1, 2.2), (-1.3, 2.2), (0.0, 2.6), (1.3, 2.2), (2.1, 2.2)])
## The ledge between the shoulder and the glass's foot [m].
LEDGE = 0.055
## The ends lean, seen from the side: the nose and the tail stand furthest out
## at *_LEAN_Y [m up] and fall back by *_LEAN [m] for every 0.2 m over or under
## it (squared, capped), from *_LEAN_FROM [m along the car] to the tip.
NOSE_LEAN_FROM = -1.80
NOSE_LEAN_Y = 0.40
NOSE_LEAN = 0.05
TAIL_LEAN_FROM = 1.80
TAIL_LEAN_Y = 0.46
TAIL_LEAN = 0.06

# --- The cabin ---

## The windscreen's foot at the A-pillars and the soft top's foot at its rear
## corners [m along the car]; both lines bow, seen from above, by BOW_* at the
## centre line.
COWL_Z = -0.76
COWL_BOW = -0.16
TOP_REAR_Z = 0.70
TOP_REAR_BOW = 0.10
## The deck's cross rails inboard of the glass's foot, as shares of its half
## width (the cabin's own rails stand on the same shares: the two meet point
## for point along the cowl and the top's rear foot).
INNER_RAILS = (0.66, 0.33, 0.0)
## The cabin's stations: z, bow at the centre line, then the roof edge's
## half width and height and the centre line's height [m] (None: a foot, on
## the deck; "mid": half-way up the A-pillar).
CABIN = (
    (COWL_Z, COWL_BOW, None),
    (-0.49, -0.13, "mid"),
    (-0.22, -0.10, (0.575, 1.245, 1.272)),
    (0.10, -0.02, (0.59, 1.262, 1.30)),
    (0.36, 0.03, (0.58, 1.25, 1.288)),
    (0.44, 0.05, (0.60, 1.20, 1.245)),
    (0.62, 0.09, (0.66, 1.03, 1.07)),
    (TOP_REAR_Z, TOP_REAR_BOW, None),
)
## Indices into CABIN: the header, the door glass's rear edge, the rear
## window's upper and lower edge.
CABIN_HEADER = 2
CABIN_DOOR_END = 4
CABIN_WINDOW_TOP = 5
CABIN_WINDOW_BOTTOM = 6
## How far the windscreen bulges at mid height [m].
SCREEN_BULGE = 0.012
## The cabin's inner sill ends this far from the centre plane and this high
## [m]: under the edge of the cockpit camera's dashboard floor
## (scripts/chase_camera.gd DASH_FLOOR_*: 1.4 m wide at y 0.86).
SILL_INNER_X = 0.66
SILL_INNER_Y = 0.80


def smooth(v):
    v = min(1.0, max(0.0, v))
    return v * v * (3.0 - 2.0 * v)


def hat(v):
    return (1.0 - v * v) ** 2 if abs(v) < 1.0 else 0.0


def bow(z):
    """How far the deck's cross lines bow along the car at the centre line."""
    return COWL_BOW * hat((z - COWL_Z) / 0.45) + TOP_REAR_BOW * hat((z - TOP_REAR_Z) / 0.40)


def round_in(z):
    """The share of the width left where the ends round in (1 amidships)."""
    share = 1.0
    if z < NOSE_ROUND_FROM:
        u = min(1.0, (NOSE_ROUND_FROM - z) / (HALF_LENGTH + NOSE_ROUND_FROM))
        share *= max(0.0, 1.0 - u ** NOSE_ROUND_POWER) ** (1.0 / NOSE_ROUND_POWER)
    if z > TAIL_ROUND_FROM:
        u = min(1.0, (z - TAIL_ROUND_FROM) / (HALF_LENGTH - TAIL_ROUND_FROM))
        share *= max(0.0, 1.0 - u ** TAIL_ROUND_POWER) ** (1.0 / TAIL_ROUND_POWER)
    return share


def lean(z, y):
    """How far along the car a point of the nose or the tail falls back."""
    if z < NOSE_LEAN_FROM:
        return NOSE_LEAN * min(2.0, ((y - NOSE_LEAN_Y) / 0.2) ** 2) * smooth((NOSE_LEAN_FROM - z) / 0.3)
    if z > TAIL_LEAN_FROM:
        return -TAIL_LEAN * min(2.0, ((y - TAIL_LEAN_Y) / 0.2) ** 2) * smooth((z - TAIL_LEAN_FROM) / 0.3)
    return 0.0


def section(z):
    """The cross-section's numbers at z: greatest half width, sill half
    width and height, the widest line's height, the shoulder's half width
    and height, the centre line's height."""
    w = WIDTH(z) * round_in(z)
    return w, w * SILL_SHARE, SILL_Y(z), WIDEST_Y(z), w * SHOULDER_SHARE(z), SHOULDER_Y(z), CENTRE_Y(z)


def ledge_share(z):
    """The glass's foot on the deck, as a share of the way in from the shoulder."""
    xs = WIDTH(z) * round_in(z) * SHOULDER_SHARE(z)
    if xs <= 1e-9:
        return 0.25
    return min(LEDGE / xs, 0.25)


def body_point(z, t):
    """The body's surface, right-hand half, at station z and at t round the
    section: 0..1 the lower flank (sill to the widest line), 1..2 the upper
    flank (round the shoulder), 2..3 the deck (shoulder to the centre line)."""
    w, xb, yb, yw, xs, ys, yc = section(z)
    if t <= 1.0:
        y = yb + (yw - yb) * t
        x = w - (w - xb) * (1.0 - t) ** 2
    elif t <= 2.0:
        phi = (t - 1.0) * math.pi * 0.5
        e = 2.0 / SHOULDER_POWER(z)
        x = xs + (w - xs) * max(0.0, math.cos(phi)) ** e
        y = yw + (ys - yw) * max(0.0, math.sin(phi)) ** e
    else:
        s = min(1.0, t - 2.0)
        x = xs * (1.0 - s)
        y = yc + (ys - yc) * (1.0 - smooth(s / DECK_BLEND(z)))
        xg = xs * (1.0 - ledge_share(z))
        if x < xg and xg > 1e-9:
            return (x, y, z + bow(z) * (1.0 - (x / xg) ** 2) + lean(z, y))
    return (x, y, z + lean(z, y))


def flank_t(z, y):
    """The t at which the flank of station z is at height y."""
    w, xb, yb, yw, xs, ys, yc = section(z)
    if y <= yw:
        return min(1.0, max(0.0, (y - yb) / (yw - yb)))
    v = min(1.0, (y - yw) / (ys - yw))
    return 1.0 + math.asin(v ** (SHOULDER_POWER(z) * 0.5)) / (math.pi * 0.5)


def deck_t(z, share):
    """The t of the deck rail `share` of the glass foot's half width out."""
    return 3.0 - share * (1.0 - ledge_share(z))


def sub(a, b):
    return (a[0] - b[0], a[1] - b[1], a[2] - b[2])


def add(a, b):
    return (a[0] + b[0], a[1] + b[1], a[2] + b[2])


def scale(a, k):
    return (a[0] * k, a[1] * k, a[2] * k)


def dot(a, b):
    return a[0] * b[0] + a[1] * b[1] + a[2] * b[2]


def cross(a, b):
    return (a[1] * b[2] - a[2] * b[1], a[2] * b[0] - a[0] * b[2], a[0] * b[1] - a[1] * b[0])


def unit(a):
    n = math.sqrt(dot(a, a))
    return (a[0] / n, a[1] / n, a[2] / n) if n > 1e-12 else (0.0, 0.0, 0.0)


def lerp(a, b, f):
    return tuple(a[i] + (b[i] - a[i]) * f for i in range(len(a)))


def body_normal(z, t):
    """The outward normal of the body's surface at (z, t)."""
    dz = 2e-3
    dt = 2e-3
    z0 = min(HALF_LENGTH - dz - 1e-4, max(-HALF_LENGTH + dz + 1e-4, z))
    t0 = min(3.0 - dt, max(dt, t))
    along_t = sub(body_point(z0, t0 + dt), body_point(z0, t0 - dt))
    along_z = sub(body_point(z0 + dz, t0), body_point(z0 - dz, t0))
    return unit(cross(along_t, along_z))


# =============================================================================
#  Meshes
# =============================================================================

class Shell:
    """One mesh: welded vertices (per smoothing group), faces wound to face
    a given way. Every helper appends in a fixed order."""

    def __init__(self, name):
        self.name = name
        self.verts = []
        self.index = {}
        self.faces = []

    def vertex(self, p, group):
        key = (group, round(p[0], 5) + 0.0, round(p[1], 5) + 0.0, round(p[2], 5) + 0.0)
        if key not in self.index:
            self.index[key] = len(self.verts)
            self.verts.append((key[1], key[2], key[3]))
        return self.index[key]

    def face(self, points, normal=None, toward=None, away=None, group=0):
        """A polygon through `points`, wound so that it faces along `normal`,
        towards the point `toward` or away from the point `away`."""
        ids = []
        kept = []
        for p in points:
            i = self.vertex(p, group)
            if i not in ids:
                ids.append(i)
                kept.append(self.verts[i])
        if len(ids) < 3:
            return
        # Newell's normal of the polygon.
        nx = ny = nz = 0.0
        cx = cy = cz = 0.0
        for k in range(len(kept)):
            a = kept[k]
            b = kept[(k + 1) % len(kept)]
            nx += (a[1] - b[1]) * (a[2] + b[2])
            ny += (a[2] - b[2]) * (a[0] + b[0])
            nz += (a[0] - b[0]) * (a[1] + b[1])
            cx += a[0]
            cy += a[1]
            cz += a[2]
        if nx * nx + ny * ny + nz * nz < 1e-16:
            return
        centre = (cx / len(kept), cy / len(kept), cz / len(kept))
        if normal is not None:
            ref = normal
        elif toward is not None:
            ref = sub(toward, centre)
        else:
            ref = sub(centre, away)
        if nx * ref[0] + ny * ref[1] + nz * ref[2] < 0.0:
            ids.reverse()
        self.faces.append(tuple(ids))

    def pair(self, points, normal=None, toward=None, away=None, group=0):
        """The face and its mirror image across the car's centre plane."""
        self.face(points, normal, toward, away, group)

        def flip(p):
            return None if p is None else (-p[0], p[1], p[2])

        self.face([flip(p) for p in points], flip(normal), flip(toward), flip(away), group)

    def triangles(self):
        return sum(len(f) - 2 for f in self.faces)


def arch_angle(zc, side):
    """The angle under the horizontal at which the arch about the axle at zc
    meets the sill, on its front (side -1) or rear (side +1)."""
    lo = 0.0
    hi = math.radians(60.0)
    for _ in range(40):
        mid = (lo + hi) * 0.5
        if WHEEL_Y - ARCH_RADIUS * math.sin(mid) > SILL_Y(zc + side * ARCH_RADIUS * math.cos(mid)):
            lo = mid
        else:
            hi = mid
    return (lo + hi) * 0.5


## The flank's rails of a plain column (t round the section) and of an arch
## column (shares of the way from the arch's edge up to the shoulder).
FLANK_T = (0.0, 0.5, 1.0, 1.4, 1.75, 2.0)
ARCH_SHARES = (0.0, 0.25, 0.5, 0.72, 0.9, 1.0)
NOSE_COLUMNS = (-2.10, -2.093, -2.075, -2.04, -1.98, -1.90)
MID_COLUMNS = (COWL_Z, -0.45, -0.10, 0.30, TOP_REAR_Z)
TAIL_COLUMNS = (1.90, 1.98, 2.04, 2.075, 2.093, 2.10)
## The first deck rail inboard of the glass's foot (rails 0..5 the flank up to
## the shoulder, 6 the glass's foot, 7.. the INNER_RAILS).
GLASS_RAIL = 6


def plain_column(z):
    column = [(z, t) for t in FLANK_T]
    column.append((z, 2.0 + ledge_share(z)))
    for share in INNER_RAILS:
        column.append((z, deck_t(z, share)))
    return {"z": z, "rails": column, "arch": None}


def arch_columns(zc):
    """The columns that fan round the arch about the axle at zc: each starts
    on the arch's edge and leans to its own place along the shoulder."""
    front = arch_angle(zc, -1.0)
    rear = arch_angle(zc, 1.0)
    columns = []
    for k in range(ARCH_SEGMENTS + 1):
        share = k / ARCH_SEGMENTS
        theta = (math.pi + front) + (-rear - (math.pi + front)) * share
        z_edge = zc + ARCH_RADIUS * math.cos(theta)
        y_edge = WHEEL_Y + ARCH_RADIUS * math.sin(theta)
        z_top = zc - ARCH_FAN + 2.0 * ARCH_FAN * share
        column = []
        for f in ARCH_SHARES:
            z = z_edge + (z_top - z_edge) * f
            if f >= 1.0:
                column.append((z, 2.0))
            else:
                y = y_edge + (SHOULDER_Y(z) - y_edge) * f
                column.append((z, flank_t(z, y)))
        column.append((z_top, 2.0 + ledge_share(z_top)))
        for inner in INNER_RAILS:
            column.append((z_top, deck_t(z_top, inner)))
        columns.append({"z": z_top, "rails": column, "arch": zc})
    return columns


def body_columns():
    columns = [plain_column(z) for z in NOSE_COLUMNS]
    columns += arch_columns(-AXLE_Z)
    columns += [plain_column(z) for z in MID_COLUMNS]
    columns += arch_columns(AXLE_Z)
    columns += [plain_column(z) for z in TAIL_COLUMNS]
    return columns


def build_body(paint, trim):
    """The shell (paint), the wheel wells and the underbody (trim)."""
    columns = body_columns()
    for a, b in zip(columns, columns[1:]):
        under_cabin = a["z"] >= COWL_Z - 1e-9 and b["z"] <= TOP_REAR_Z + 1e-9
        for j in range(len(a["rails"]) - 1):
            if under_cabin and j >= GLASS_RAIL:
                continue  # the cabin stands over this hole in the deck
            corners = (a["rails"][j], a["rails"][j + 1], b["rails"][j + 1], b["rails"][j])
            z_mid = sum(c[0] for c in corners) / 4.0
            t_mid = sum(c[1] for c in corners) / 4.0
            paint.pair([body_point(z, t) for z, t in corners], normal=body_normal(z_mid, t_mid))

    # The wheel wells: a tunnel from the arch's edge in to the inner wall.
    for zc in (-AXLE_Z, AXLE_Z):
        edge = [body_point(*c["rails"][0]) for c in columns if c["arch"] == zc]
        axis = (HALF_TRACK, WHEEL_Y, zc)
        hub = (WELL_INNER_X, WHEEL_Y, zc)
        for p, q in zip(edge, edge[1:]):
            p_in = (WELL_INNER_X, p[1], p[2])
            q_in = (WELL_INNER_X, q[1], q[2])
            trim.pair([p, q, q_in, p_in], toward=axis, group=1)
            trim.pair([hub, p_in, q_in], normal=(1.0, 0.0, 0.0), group=2)

    # The underbody: flat between the sills, inboard of the wells.
    stations = []
    for c in columns:
        if c["arch"] is None:
            stations.append((c["z"], False))
    for zc in (-AXLE_Z, AXLE_Z):
        fan = [c for c in columns if c["arch"] == zc]
        stations.append((fan[0]["rails"][0][0], True))
        stations.append((fan[-1]["rails"][0][0], False))
    stations.sort()
    down = (0.0, -1.0, 0.0)
    for (za, in_well), (zb, _) in zip(stations, stations[1:]):
        ya = SILL_Y(za)
        yb = SILL_Y(zb)
        xa = section(za)[1]
        xb = section(zb)[1]
        ia = min(WELL_INNER_X, xa)
        ib = min(WELL_INNER_X, xb)
        trim.pair([(0.0, ya, za), (ia, ya, za), (ib, yb, zb), (0.0, yb, zb)], normal=down, group=3)
        if not in_well:
            trim.pair([(ia, ya, za), (xa, ya, za), (xb, yb, zb), (ib, yb, zb)], normal=down, group=3)


def cabin_rows():
    """The cabin's stations as rows of five points: the glass's foot, the
    roof's edge, then the INNER_RAILS in to the centre line."""
    rows = []
    for z, station_bow, shape in CABIN:
        foot = body_point(z, 2.0 + ledge_share(z))
        if shape is None:
            rows.append([foot, foot] + [body_point(z, deck_t(z, share)) for share in INNER_RAILS])
        elif shape == "mid":
            rows.append(None)
        else:
            xe, ye, yc = shape
            row = [foot, (xe, ye, z)]
            for share in INNER_RAILS:
                row.append((xe * share, yc - (yc - ye) * share * share, z + station_bow * (1.0 - share * share)))
            rows.append(row)
    for k, row in enumerate(rows):
        if row is None:
            below = rows[k - 1]
            above = rows[k + 1]
            mid = [lerp(below[i], above[i], 0.5) for i in range(len(below))]
            for i, share in enumerate(INNER_RAILS):
                p = mid[2 + i]
                bulge = SCREEN_BULGE * (1.0 - share * share)
                mid[2 + i] = (p[0], p[1] + bulge, p[2] - bulge * 0.6)
            rows[k] = mid
    return rows


def build_cabin(glass, top, trim):
    rows = cabin_rows()
    inside = (0.0, 1.0, 0.0)  # a point inside the cabin: every face looks away from it
    for k in range(len(rows) - 1):
        a = rows[k]
        b = rows[k + 1]
        # The side: door glass up to the door's rear edge, fabric behind it.
        if k < CABIN_DOOR_END:
            glass.pair([a[0], a[1], b[1], b[0]], away=inside, group=10)
        else:
            top.pair([a[0], a[1], b[1], b[0]], away=inside)
        # The top: windscreen, roof, the rear slope with its window.
        for j in range(1, len(a) - 1):
            quad = [a[j], a[j + 1], b[j + 1], b[j]]
            if k < CABIN_HEADER:
                glass.pair(quad, away=inside, group=11)
            elif CABIN_WINDOW_TOP <= k < CABIN_WINDOW_BOTTOM and j >= 2:
                glass.pair(quad, away=inside, group=12)
            else:
                top.pair(quad, away=inside)

    # The cabin's inner sill: a dark wall from the glass's foot down and in,
    # all round the opening in the deck. Seen only from inside (the cockpit
    # camera): without it the eye looks past the dashboard's floor through
    # the one-sided doors at the wheels. The interior proper is the next slice.
    def sill(p):
        return (min(abs(p[0]) * 0.9, SILL_INNER_X), SILL_INNER_Y, p[2])

    for a, b in zip(rows, rows[1:]):
        trim.pair([a[0], b[0], sill(b[0]), sill(a[0])], toward=inside, group=22)
    for row, back in ((rows[0], 0.08), (rows[-1], -0.08)):
        for j in range(1, len(row) - 1):
            a, b = row[j], row[j + 1]
            trim.pair([a, b, (b[0] * 0.9, SILL_INNER_Y, b[2] + back), (a[0] * 0.9, SILL_INNER_Y, a[2] + back)], toward=inside, group=23)

    # The windscreen's frame, black on every 986: a strip up each A-pillar,
    # lapping the door glass and the screen, and one along the header.
    lift = 0.004
    outward = []
    for k in range(CABIN_HEADER + 1):
        row = rows[k if k > 0 else 1]
        to_foot = unit(sub(row[0], row[1]))
        to_screen = unit(sub(row[2], row[1]))
        side_normal = unit(cross(to_foot, sub(rows[2][1], rows[0][1])))
        if side_normal[0] < 0.0:
            side_normal = scale(side_normal, -1.0)
        screen_normal = unit(cross(sub(rows[2][1], rows[0][1]), to_screen))
        if screen_normal[1] < 0.0:
            screen_normal = scale(screen_normal, -1.0)
        edge = rows[k][1]
        width = 0.5 + 0.5 * k / CABIN_HEADER
        outward.append((
            add(add(edge, scale(to_foot, 0.035 * width)), scale(side_normal, lift)),
            add(edge, scale(unit(add(side_normal, screen_normal)), lift * 1.5)),
            add(add(edge, scale(to_screen, 0.04 * width)), scale(screen_normal, lift)),
        ))
    for a, b in zip(outward, outward[1:]):
        trim.pair([a[0], a[1], b[1], b[0]], away=inside, group=20)
        trim.pair([a[1], a[2], b[2], b[1]], away=inside, group=20)
    header = rows[CABIN_HEADER]
    below = rows[CABIN_HEADER - 1]
    for j in range(1, len(header) - 1):
        up = (0.0, lift, -lift)
        a0 = add(header[j], up)
        a1 = add(header[j + 1], up)
        b0 = add(lerp(header[j], below[j], 0.16), up)
        b1 = add(lerp(header[j + 1], below[j + 1], 0.16), up)
        trim.pair([a0, a1, b1, b0], away=inside, group=21)


def densify(outline, step_z=0.09, step_t=0.2):
    """The closed outline with its long edges split, so a patch follows the
    body round a curve instead of cutting the corner under the paint."""
    out = []
    for k, a in enumerate(outline):
        b = outline[(k + 1) % len(outline)]
        parts = max(1, int(math.ceil(max(abs(b[0] - a[0]) / step_z, abs(b[1] - a[1]) / step_t) - 1e-9)))
        for i in range(parts):
            out.append(lerp(a, b, i / parts))
    return out


def patch(shell, outline, centre, lift, skirt, rings=(0.5,), group=0):
    """A patch lying on the body: `outline` and `centre` are (z, t) on the
    body's surface; the patch stands `lift` proud of it and a skirt round its
    edge goes `skirt` back under it, so no light shows beneath."""
    def at(zt, offset):
        return add(body_point(*zt), scale(body_normal(*zt), offset))

    outline = densify(outline)
    middle = at(centre, lift)
    facing = body_normal(*centre)
    loops = []
    for share in tuple(rings) + (1.0,):
        loops.append([lerp(centre, o, share) for o in outline])
    count = len(outline)
    for k in range(count):
        n = (k + 1) % count
        shell.pair([middle, at(loops[0][k], lift), at(loops[0][n], lift)], normal=facing, group=group)
        for inner, outer in zip(loops, loops[1:]):
            hint = body_normal(*lerp(outer[k], outer[n], 0.5))
            shell.pair([at(inner[k], lift), at(outer[k], lift), at(outer[n], lift), at(inner[n], lift)], normal=hint, group=group)
        a = loops[-1][k]
        b = loops[-1][n]
        if body_point(*a)[0] < 1e-6 and body_point(*b)[0] < 1e-6:
            continue  # on the centre plane: the mirror image closes it
        shell.pair([at(a, lift), at(b, lift), at(b, -skirt), at(a, -skirt)], away=at(centre, -skirt), group=group + 1)


def on_end(x, y, end):
    """The (z, t) of the body's nose (end -1) or tail (end +1) face at x
    across and y up: the point a ray along the car meets."""
    tip = end * HALF_LENGTH
    inner = end * 1.45
    lo = 0.0  # share of the way from the tip to `inner`: the body is narrower than x at lo
    hi = 1.0
    for _ in range(48):
        mid = (lo + hi) * 0.5
        z = tip + (inner - tip) * mid
        if body_point(z, flank_t(z, y))[0] < x:
            lo = mid
        else:
            hi = mid
    z = tip + (inner - tip) * (lo + hi) * 0.5
    if x <= 1e-9:
        z = tip
    return (z, flank_t(z, y))


def rounded_box(x0, x1, y0, y1, radius, per_corner=2, step=0.11):
    """A rounded rectangle's outline in (x, y), anticlockwise from its lower
    right corner, its straight edges split every `step`; with x0 at 0 the
    box is the right-hand half of one that straddles the centre plane."""
    corners = [(x1 - radius, y0 + radius, -90.0), (x1 - radius, y1 - radius, 0.0)]
    if x0 > 1e-9:
        corners += [(x0 + radius, y1 - radius, 90.0), (x0 + radius, y0 + radius, 180.0)]
    points = []
    for cx, cy, start in corners:
        for k in range(per_corner + 1):
            a = math.radians(start + 90.0 * k / per_corner)
            points.append((cx + radius * math.cos(a), cy + radius * math.sin(a)))
    if x0 <= 1e-9:
        points += [(0.0, y1), (0.0, y0)]
    out = []
    for k, a in enumerate(points):
        b = points[(k + 1) % len(points)]
        parts = max(1, int(math.ceil(math.hypot(b[0] - a[0], b[1] - a[1]) / step - 1e-9)))
        for i in range(parts):
            out.append(lerp(a, b, i / parts))
    return out


def onto_body(centre, along, outline):
    """Lays (across, along) points [m] of the plane touching the body at
    `centre` (a (z, t)) down on the body, each along the body's normal
    there: `along` is the way the plane's second axis points (taken square
    to the normal), its first axis is normal x along - towards the tail on
    the right flank, towards the centre plane on the tail's face. Returns
    their (z, t)."""
    origin = body_point(*centre)
    n = body_normal(*centre)
    v = unit(sub(along, scale(n, dot(along, n))))
    u = cross(n, v)
    h = 1e-4
    out = []
    for a, b in outline:
        z, t = centre
        for share in (0.25, 0.5, 0.75, 1.0):
            target = add(origin, add(scale(u, a * share), scale(v, b * share)))
            for _ in range(12):
                p = body_point(z, t)
                r = sub(p, target)
                fu = dot(r, u)
                fv = dot(r, v)
                if fu * fu + fv * fv < 1e-14:
                    break
                pz = scale(sub(body_point(z + h, t), p), 1.0 / h)
                pt = scale(sub(body_point(z, t + h), p), 1.0 / h)
                a11, a12, a21, a22 = dot(pz, u), dot(pt, u), dot(pz, v), dot(pt, v)
                det = a11 * a22 - a12 * a21
                if abs(det) < 1e-12:
                    break
                z -= (fu * a22 - fv * a12) / det
                t -= (fv * a11 - fu * a21) / det
                z = min(HALF_LENGTH - 2e-3, max(-HALF_LENGTH + 2e-3, z))
                t = min(2.99, max(0.0, t))
        out.append((z, t))
    return out


def egg(length, width, sharp, start_deg, end_deg, count):
    """Part of an egg's outline as (across, along) points: its blunt end at
    -along, its pointed end (`sharp` 0 none .. 1 a point) at +along; the
    angle runs from the pointed end round."""
    points = []
    for k in range(count + 1):
        a = math.radians(start_deg + (end_deg - start_deg) * k / count)
        points.append((math.sin(a) * width * 0.5 * (1.0 - sharp * max(0.0, math.cos(a))), math.cos(a) * length * 0.5))
    return points


def build_lamps_and_intakes(headlight, taillight, indicator, trim):
    def flank(z, y):
        return (z, flank_t(z, y))

    # The lamp unit on each front fender: an egg lying up and back from the
    # nose's corner, its blunt end forward; the lens over most of it and the
    # amber section across its blunt end (the early 986's "fried egg").
    unit_centre = (-1.86, 1.60)
    unit_axis = (0.30, 0.30, 0.42)
    split = 118.0
    lens = onto_body(unit_centre, unit_axis, egg(0.50, 0.27, 0.45, -split, split, 12) + [(0.0, 0.05)])
    patch(headlight, lens[:-1], lens[-1], 0.006, 0.03)
    amber = onto_body(unit_centre, unit_axis, egg(0.50, 0.27, 0.45, split, 360.0 - split, 6) + [(0.0, -0.185)])
    patch(indicator, amber[:-1], amber[-1], 0.006, 0.03)

    # The taillight: an egg wrapped round the tail's corner, its blunt end
    # on the flank, its point drawn out towards the middle of the tail.
    lamp_centre = (1.955, 1.50)
    lamp = onto_body(lamp_centre, (-0.5, -0.02, 0.25), egg(0.56, 0.25, 0.4, 0.0, 360.0, 16)[:-1])
    patch(taillight, lamp, lamp_centre, 0.006, 0.03)

    # The front intakes, in the bumper under the nose: one in the middle,
    # one either side.
    middle = [on_end(x, y, -1.0) for x, y in rounded_box(0.0, 0.25, 0.245, 0.35, 0.04)]
    patch(trim, middle, on_end(0.0, 0.30, -1.0), 0.005, 0.02, group=30)
    side = [on_end(x, y, -1.0) for x, y in rounded_box(0.36, 0.76, 0.245, 0.38, 0.05)]
    patch(trim, side, on_end(0.56, 0.31, -1.0), 0.005, 0.02, group=32)

    # The side intakes ahead of the rear wheels: the mid-engined car's mark.
    intake_centre = flank(0.62, 0.63)
    intake = onto_body(intake_centre, (0.0, 1.0, 0.0), [(-0.11, -0.14), (0.05, -0.15), (0.115, -0.08), (0.13, 0.04), (0.08, 0.13), (-0.11, 0.15)])
    patch(trim, intake, intake_centre, 0.005, 0.02, group=34)

    # The exhaust's surround in the rear valance.
    surround = [on_end(x, y, 1.0) for x, y in rounded_box(0.0, 0.17, 0.315, 0.445, 0.04)]
    patch(trim, surround, on_end(0.0, 0.38, 1.0), 0.005, 0.02, group=36)


def pod(shell, centre, radii, power, segments=8, rings=3, group=0):
    """A rounded housing: an ellipsoid squared off by `power` (1 an
    ellipsoid, less a boxier pod)."""
    def bend(v):
        return math.copysign(abs(v) ** power, v)

    cx, cy, cz = centre
    rx, ry, rz = radii
    top = (cx, cy + ry, cz)
    bottom = (cx, cy - ry, cz)
    loops = []
    for r in range(rings):
        lat = math.pi * (r + 1) / (rings + 1) - math.pi * 0.5
        loops.append([(cx + bend(math.cos(2.0 * math.pi * i / segments) * math.cos(lat)) * rx,
                       cy + bend(math.sin(lat)) * ry,
                       cz + bend(math.sin(2.0 * math.pi * i / segments) * math.cos(lat)) * rz) for i in range(segments)])
    for i in range(segments):
        n = (i + 1) % segments
        shell.pair([bottom, loops[0][i], loops[0][n]], away=centre, group=group)
        for lower, upper in zip(loops, loops[1:]):
            shell.pair([lower[i], lower[n], upper[n], upper[i]], away=centre, group=group)
        shell.pair([loops[-1][i], loops[-1][n], top], away=centre, group=group)


def build_mirrors(paint):
    """A housing on a short foot on each door's shoulder, by the A-pillar."""
    housing = (0.885, 0.975, -0.585)
    pod(paint, housing, (0.10, 0.052, 0.05), 0.7, group=40)
    foot = (0.775, 0.895, -0.60)
    head = (0.835, 0.955, -0.59)
    axis = lerp(foot, head, 0.5)
    ring_foot = [add(foot, o) for o in ((0.0, 0.0, -0.06), (0.04, 0.0, 0.0), (0.0, 0.0, 0.05), (-0.04, 0.0, 0.0))]
    ring_head = [add(head, o) for o in ((0.0, 0.0, -0.04), (0.04, 0.0, 0.0), (0.0, 0.0, 0.035), (-0.04, 0.0, 0.0))]
    for k in range(4):
        n = (k + 1) % 4
        paint.pair([ring_foot[k], ring_foot[n], ring_head[n], ring_head[k]], away=axis, group=41)


def build_exhaust(exhaust, trim):
    """The 986's single oval tailpipe in the middle of the rear valance."""
    y = 0.38
    z0 = 2.00
    z1 = 2.12
    bore = 2.07
    segments = 12
    outer = [(0.078 * math.cos(2.0 * math.pi * k / segments), y + 0.042 * math.sin(2.0 * math.pi * k / segments)) for k in range(segments)]
    inner = [(0.064 * math.cos(2.0 * math.pi * k / segments), y + 0.030 * math.sin(2.0 * math.pi * k / segments)) for k in range(segments)]
    for k in range(segments):
        n = (k + 1) % segments
        a, b = outer[k], outer[n]
        c, d = inner[k], inner[n]
        exhaust.face([(a[0], a[1], z0), (b[0], b[1], z0), (b[0], b[1], z1), (a[0], a[1], z1)], away=(0.0, y, (z0 + z1) * 0.5), group=0)
        exhaust.face([(a[0], a[1], z1), (b[0], b[1], z1), (d[0], d[1], z1), (c[0], c[1], z1)], normal=(0.0, 0.0, 1.0), group=1)
        trim.face([(c[0], c[1], z1), (d[0], d[1], z1), (d[0], d[1], bore), (c[0], c[1], bore)], toward=(0.0, y, (bore + z1) * 0.5), group=50)
        trim.face([(0.0, y, bore), (c[0], c[1], bore), (d[0], d[1], bore)], normal=(0.0, 0.0, 1.0), group=51)


# =============================================================================
#  Blender
# =============================================================================

def srgb_to_linear(c):
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def make_material(name, albedo, metallic, roughness, emission, energy, double_sided):
    """A Principled material the glTF exporter writes as plain factors.
    The table's colours are sRGB, as Godot's inspector shows them; glTF's
    factors are linear, and Godot converts them back on import."""
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    bsdf = material.node_tree.nodes["Principled BSDF"]
    bsdf.inputs["Base Color"].default_value = tuple(srgb_to_linear(c) for c in albedo) + (1.0,)
    bsdf.inputs["Metallic"].default_value = metallic
    bsdf.inputs["Roughness"].default_value = roughness
    if emission is not None:
        bsdf.inputs["Emission Color"].default_value = tuple(srgb_to_linear(c) for c in emission) + (1.0,)
        bsdf.inputs["Emission Strength"].default_value = energy
    material.use_backface_culling = not double_sided
    return material


def to_blender(p):
    """Car space (+Y up, nose -Z) into Blender's (+Z up; the exporter's
    Y-up turns it back), lowered into the Body node's space."""
    return (p[0], -p[2], p[1] - PIVOT_Y)


def make_object(shell, material):
    mesh = bpy.data.meshes.new(shell.name)
    mesh.from_pydata([to_blender(v) for v in shell.verts], [], shell.faces)
    mesh.update()
    mesh.materials.append(material)
    for poly in mesh.polygons:
        poly.use_smooth = True
    obj = bpy.data.objects.new(shell.name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    return obj


def export(objects):
    gltf_path = os.path.join(common.MESHES, NAME + ".gltf")
    bin_path = os.path.join(common.MESHES, NAME + ".bin")
    glb_path = os.path.join(common.MESHES, NAME + ".glb")
    bpy.ops.object.select_all(action='DESELECT')
    for obj in objects:
        obj.select_set(True)
    bpy.context.view_layer.objects.active = objects[0]
    bpy.ops.export_scene.gltf(
        filepath=gltf_path,
        export_format='GLTF_SEPARATE',
        use_selection=True,
        export_materials='EXPORT',
        export_yup=True,
        export_apply=True,
        export_normals=True,
        export_texcoords=False,
        export_tangents=False,
        export_animations=False,
        export_skins=False,
        export_morph=False,
        export_lights=False,
        export_cameras=False,
        export_extras=False,
    )
    trees.pack_glb(gltf_path, bin_path, glb_path)
    os.remove(gltf_path)
    os.remove(bin_path)
    common.report(glb_path)


# --- The preview (scratch, never committed) -----------------------------------

PREVIEW_VIEWS = (
    # name, eye and target in car space [m], lens [mm]
    ("front34", (-3.3, 1.35, -4.4), (0.0, 0.55, 0.0), 50.0),
    ("rear34", (3.3, 1.5, 4.6), (0.0, 0.55, 0.0), 50.0),
    ("side", (-7.5, 0.75, 0.0), (0.0, 0.62, 0.0), 60.0),
    ("front", (0.0, 0.8, -7.0), (0.0, 0.6, 0.0), 60.0),
    ("rear", (0.0, 0.9, 7.0), (0.0, 0.6, 0.0), 60.0),
    ("top", (0.0, 9.0, 0.01), (0.0, 0.0, 0.0), 50.0),
    ("wheelcam", (-1.75, 0.5, -2.2), (-0.86, 0.3, -1.3), 24.0),
    ("high_rear", (-2.4, 2.6, 4.2), (0.0, 0.6, 0.0), 45.0),
)


def render_previews(folder):
    """The car on stand-in wheels over a grey floor, from PREVIEW_VIEWS."""
    os.makedirs(folder, exist_ok=True)
    scene = bpy.context.scene
    tyre = bpy.data.materials.new("preview_tyre")
    tyre.use_nodes = True
    tyre.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.01, 0.01, 0.012, 1.0)
    rim = bpy.data.materials.new("preview_rim")
    rim.use_nodes = True
    rim.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.55, 0.57, 0.6, 1.0)
    rim.node_tree.nodes["Principled BSDF"].inputs["Metallic"].default_value = 0.6
    floor = bpy.data.materials.new("preview_floor")
    floor.use_nodes = True
    floor.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.25, 0.26, 0.27, 1.0)
    for sx in (-1.0, 1.0):
        for sz in (-1.0, 1.0):
            where = to_blender((sx * HALF_TRACK, WHEEL_Y, sz * AXLE_Z))
            bpy.ops.mesh.primitive_cylinder_add(vertices=24, radius=TYRE_RADIUS, depth=TYRE_WIDTH, location=where, rotation=(0.0, math.pi * 0.5, 0.0))
            bpy.context.object.data.materials.append(tyre)
            bpy.ops.mesh.primitive_cylinder_add(vertices=16, radius=0.2, depth=TYRE_WIDTH + 0.02, location=where, rotation=(0.0, math.pi * 0.5, 0.0))
            bpy.context.object.data.materials.append(rim)
    bpy.ops.mesh.primitive_plane_add(size=80.0, location=(0.0, 0.0, -PIVOT_Y))
    bpy.context.object.data.materials.append(floor)
    world = bpy.data.worlds.new("preview_world")
    world.use_nodes = True
    world.node_tree.nodes["Background"].inputs["Color"].default_value = (0.55, 0.68, 0.9, 1.0)
    world.node_tree.nodes["Background"].inputs["Strength"].default_value = 0.9
    scene.world = world
    sun = bpy.data.objects.new("preview_sun", bpy.data.lights.new("preview_sun", 'SUN'))
    sun.data.energy = 3.5
    sun.data.angle = math.radians(3.0)
    sun.rotation_euler = (math.radians(52.0), math.radians(8.0), math.radians(-35.0))
    scene.collection.objects.link(sun)
    camera = bpy.data.objects.new("preview_camera", bpy.data.cameras.new("preview_camera"))
    scene.collection.objects.link(camera)
    scene.camera = camera
    scene.cycles.samples = 24
    scene.render.resolution_x = 960
    scene.render.resolution_y = 540
    scene.render.image_settings.file_format = 'PNG'
    for name, eye, target, lens in PREVIEW_VIEWS:
        e = Vector(to_blender(eye))
        t = Vector(to_blender(target))
        camera.location = e
        camera.rotation_euler = (t - e).to_track_quat('-Z', 'Y').to_euler()
        camera.data.lens = lens
        scene.render.filepath = os.path.join(folder, "car_%s.png" % name)
        bpy.ops.render.render(write_still=True)


def build(reset=True, preview=None):
    common.ensure_dirs()
    if reset:
        common.reset_scene()
    shells = {name: Shell(name) for name, *_ in MATERIALS}
    build_body(shells["Paint"], shells["Trim"])
    build_cabin(shells["Glass"], shells["SoftTop"], shells["Trim"])
    build_lamps_and_intakes(shells["Headlight"], shells["Taillight"], shells["Indicator"], shells["Trim"])
    build_mirrors(shells["Paint"])
    build_exhaust(shells["Exhaust"], shells["Trim"])
    objects = []
    total = 0
    for spec in MATERIALS:
        shell = shells[spec[0]]
        if not shell.faces:
            continue
        objects.append(make_object(shell, make_material(*spec)))
        total += shell.triangles()
        print("%s: %d triangles, %d vertices" % (shell.name, shell.triangles(), len(shell.verts)))
    print("%s: %d triangles in %d meshes" % (NAME, total, len(objects)))
    export(objects)
    if preview:
        render_previews(preview)


if __name__ == "__main__":
    build(preview=common.preview_dir_from_argv())

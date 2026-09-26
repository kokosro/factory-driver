"""Shared authoring helpers for the factory-driver Blender scripts
(docs/art-direction.md, the visual contract; docs/design/4b/element-library.md
§1 / §6; assets/blender/README.md documents every artifact these make).

Everything here is deterministic: Cycles on the CPU with a fixed seed, no
animated seed, procedural shader networks evaluated by an EMIT bake onto a
unit plane, the pixels quantised once into an 8-bit PNG. Run the same script
twice and the bytes are the same (assets/blender/README.md records what was
verified).

TILEABILITY. Blender's noise textures are not periodic in the plane, so a
tile is authored on a torus: the plane's (u, v) become the 4D point
(Ru cos 2πu, Ru sin 2πu, Rv cos 2πv, Rv sin 2πv) with Ru = su / 2π and
Rv = sv / 2π, so a noise of scale 1 sees su feature lengths across and sv
up; every 4D noise / Voronoi fed from `torus()` wraps exactly at the tile's
edges. Features that are a function of u alone (the wheel ruts) tile in v
trivially; grids (the repair patches) tile when their period divides 1.

ORIENTATION. Blender's UV v runs upwards (v = 1 is the PNG's top row);
Godot's v runs downwards (v = 0 is the PNG's top row). Author "up" as
v -> 1 here; the GDScript side maps the top of a card to v = 0.
"""

import os
import sys

import bpy
import numpy as np

BLENDER_VERSION = bpy.app.version_string
SAMPLES = 16
SEED = 4711

HERE = os.path.dirname(os.path.abspath(__file__))
ASSETS = os.path.abspath(os.path.join(HERE, "..", ".."))
TEXTURES_ROAD = os.path.join(ASSETS, "textures", "road")
TEXTURES_VEG = os.path.join(ASSETS, "textures", "vegetation")
MESHES = os.path.join(ASSETS, "meshes")
BLEND_FILE = os.path.join(ASSETS, "blender", "factory_driver_assets.blend")


def reset_scene():
    """A fresh empty file with the deterministic render settings."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.render.engine = 'CYCLES'
    scene.cycles.device = 'CPU'
    scene.cycles.samples = SAMPLES
    scene.cycles.use_denoising = False
    scene.cycles.seed = SEED
    scene.cycles.use_animated_seed = False
    scene.render.bake.use_clear = True
    scene.render.bake.margin = 0
    scene.render.bake.use_selected_to_active = False
    scene.view_settings.view_transform = 'Standard'
    scene.view_settings.look = 'None'
    return scene


## The bake plane's apron beyond the tile, in UV units: the pixel filter's
## tails at the image's border rows must still land on geometry (a plane
## ending exactly at the UV square leaves the border rows under-covered
## and darker, and the tile is then not seamless: measured 0.045 against
## 0.007 between neighbouring rows before this). 0.004 is one pixel at
## 256 and four at 1024; the Graph wraps u and v with fract(), so the
## apron continues the tile periodically.
APRON = 0.004


def unit_plane(name="BakePlane"):
    """A plane whose UVs span [-APRON, 1 + APRON]² over a matching extent
    (the pixel <-> UV mapping of the [0, 1]² tile is exact)."""
    half = 0.5 + APRON
    mesh = bpy.data.meshes.new(name + "Mesh")
    mesh.from_pydata([(-half, -half, 0.0), (half, -half, 0.0), (half, half, 0.0), (-half, half, 0.0)], [], [(0, 1, 2, 3)])
    mesh.update()
    uv_layer = mesh.uv_layers.new(name="UVMap")
    for loop_index, uv in zip(mesh.polygons[0].loop_indices, ((-APRON, -APRON), (1.0 + APRON, -APRON), (1.0 + APRON, 1.0 + APRON), (-APRON, 1.0 + APRON))):
        uv_layer.data[loop_index].uv = uv
    plane = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(plane)
    return plane


class Graph:
    """A thin builder over a material's node tree: floats in, floats out.

    Every method returns a NodeSocket (or a Python float, which the linker
    turns into a default value). Sockets and floats can be mixed freely.
    """

    def __init__(self, material):
        material.use_nodes = True
        self.tree = material.node_tree
        for node in list(self.tree.nodes):
            self.tree.nodes.remove(node)
        self.output = self.tree.nodes.new("ShaderNodeOutputMaterial")
        self._coord = self.tree.nodes.new("ShaderNodeTexCoord")
        self._sep = self.tree.nodes.new("ShaderNodeSeparateXYZ")
        self.tree.links.new(self._coord.outputs["UV"], self._sep.inputs["Vector"])
        # Periodic in both directions: the apron beyond the tile (APRON)
        # sees the tile's other edge.
        self.u = self.fract(self._sep.outputs["X"])
        self.v = self.fract(self._sep.outputs["Y"])

    def _feed(self, socket, value):
        if isinstance(value, (int, float)):
            socket.default_value = float(value)
        elif isinstance(value, (tuple, list)):
            socket.default_value = value
        else:
            self.tree.links.new(value, socket)

    def math(self, op, a, b=0.0, c=0.0):
        node = self.tree.nodes.new("ShaderNodeMath")
        node.operation = op
        node.use_clamp = False
        self._feed(node.inputs[0], a)
        self._feed(node.inputs[1], b)
        self._feed(node.inputs[2], c)
        return node.outputs["Value"]

    def add(self, a, b):
        return self.math('ADD', a, b)

    def sub(self, a, b):
        return self.math('SUBTRACT', a, b)

    def mul(self, a, b):
        return self.math('MULTIPLY', a, b)

    def mad(self, a, b, c):
        return self.math('MULTIPLY_ADD', a, b, c)

    def div(self, a, b):
        return self.math('DIVIDE', a, b)

    def absolute(self, a):
        return self.math('ABSOLUTE', a)

    def fract(self, a):
        return self.math('FRACT', a)

    def floor(self, a):
        return self.math('FLOOR', a)

    def power(self, a, b):
        return self.math('POWER', a, b)

    def minimum(self, a, b):
        return self.math('MINIMUM', a, b)

    def maximum(self, a, b):
        return self.math('MAXIMUM', a, b)

    def less(self, a, b):
        return self.math('LESS_THAN', a, b)

    def greater(self, a, b):
        return self.math('GREATER_THAN', a, b)

    def sin(self, a):
        return self.math('SINE', a)

    def cos(self, a):
        return self.math('COSINE', a)

    def sqrt(self, a):
        return self.math('SQRT', a)

    def clamp01(self, a):
        node = self.tree.nodes.new("ShaderNodeClamp")
        self._feed(node.inputs["Value"], a)
        node.inputs["Min"].default_value = 0.0
        node.inputs["Max"].default_value = 1.0
        return node.outputs["Result"]

    def smoothstep(self, value, edge0, edge1, out0=0.0, out1=1.0):
        node = self.tree.nodes.new("ShaderNodeMapRange")
        node.data_type = 'FLOAT'
        node.interpolation_type = 'SMOOTHSTEP'
        node.clamp = True
        self._feed(node.inputs["Value"], value)
        self._feed(node.inputs["From Min"], edge0)
        self._feed(node.inputs["From Max"], edge1)
        self._feed(node.inputs["To Min"], out0)
        self._feed(node.inputs["To Max"], out1)
        return node.outputs["Result"]

    def linstep(self, value, edge0, edge1, out0=0.0, out1=1.0):
        node = self.tree.nodes.new("ShaderNodeMapRange")
        node.data_type = 'FLOAT'
        node.interpolation_type = 'LINEAR'
        node.clamp = True
        self._feed(node.inputs["Value"], value)
        self._feed(node.inputs["From Min"], edge0)
        self._feed(node.inputs["From Max"], edge1)
        self._feed(node.inputs["To Min"], out0)
        self._feed(node.inputs["To Max"], out1)
        return node.outputs["Result"]

    def mix(self, factor, a, b):
        """a where factor is 0, b where it is 1 (floats)."""
        node = self.tree.nodes.new("ShaderNodeMix")
        node.data_type = 'FLOAT'
        node.clamp_factor = True
        self._feed(node.inputs["Factor"], factor)
        self._feed(node.inputs[2], a)
        self._feed(node.inputs[3], b)
        return node.outputs[0]

    def combine(self, x, y, z):
        node = self.tree.nodes.new("ShaderNodeCombineXYZ")
        self._feed(node.inputs["X"], x)
        self._feed(node.inputs["Y"], y)
        self._feed(node.inputs["Z"], z)
        return node.outputs["Vector"]

    def torus(self, u, v, su, sv, phase=0.0):
        """The 4D point (vector, w) at which noise tiles over [0, 1]²
        with su feature lengths across and sv up."""
        tau = 6.283185307179586
        ru = su / tau
        rv = sv / tau
        au = self.mad(u, tau, phase)
        av = self.mad(v, tau, phase * 0.5)
        x = self.mul(self.cos(au), ru)
        y = self.mul(self.sin(au), ru)
        z = self.mul(self.cos(av), rv)
        w = self.mul(self.sin(av), rv)
        return self.combine(x, y, z), w

    def noise(self, u, v, su, sv, detail=2.0, roughness=0.5, phase=0.0, distortion=0.0):
        """Tileable noise in [0, 1] (about 0.5), su / sv features per tile."""
        vector, w = self.torus(u, v, su, sv, phase)
        node = self.tree.nodes.new("ShaderNodeTexNoise")
        node.noise_dimensions = '4D'
        node.normalize = True
        self.tree.links.new(vector, node.inputs["Vector"])
        self._feed(node.inputs["W"], w)
        node.inputs["Scale"].default_value = 1.0
        node.inputs["Detail"].default_value = detail
        node.inputs["Roughness"].default_value = roughness
        node.inputs["Distortion"].default_value = distortion
        return node.outputs["Fac"]

    def voronoi(self, u, v, su, sv, phase=0.0):
        """Tileable Voronoi cells: (distance to the feature point, a
        per-cell random in [0, 1])."""
        vector, w = self.torus(u, v, su, sv, phase)
        node = self.tree.nodes.new("ShaderNodeTexVoronoi")
        node.voronoi_dimensions = '4D'
        node.feature = 'F1'
        node.distance = 'EUCLIDEAN'
        node.normalize = False
        self.tree.links.new(vector, node.inputs["Vector"])
        self._feed(node.inputs["W"], w)
        node.inputs["Scale"].default_value = 1.0
        node.inputs["Randomness"].default_value = 1.0
        sep = self.tree.nodes.new("ShaderNodeSeparateColor")
        sep.mode = 'RGB'
        self.tree.links.new(node.outputs["Color"], sep.inputs["Color"])
        return node.outputs["Distance"], sep.outputs["Red"]

    def cells(self, u, v, nu, nv, salt=0.0):
        """An nu x nv grid over the tile: (a per-cell random in [0, 1],
        the position inside the cell across, up). Tiles exactly."""
        cu = self.floor(self.mul(u, nu))
        cv = self.floor(self.mul(v, nv))
        # A hash of the cell: fract(sin(a) * k) with a from the cell index.
        a = self.mad(cu, 12.9898, self.mad(cv, 78.233, salt))
        r = self.fract(self.mul(self.sin(a), 43758.5453))
        fu = self.fract(self.mul(u, nu))
        fv = self.fract(self.mul(v, nv))
        return r, fu, fv

    def emit(self, r, g=None, b=None):
        """Wires an emission of (r, g, b) - or the grey r - to the output."""
        if g is None:
            g = r
        if b is None:
            b = r
        col = self.tree.nodes.new("ShaderNodeCombineColor")
        col.mode = 'RGB'
        self._feed(col.inputs["Red"], r)
        self._feed(col.inputs["Green"], g)
        self._feed(col.inputs["Blue"], b)
        emission = self.tree.nodes.new("ShaderNodeEmission")
        self.tree.links.new(col.outputs["Color"], emission.inputs["Color"])
        emission.inputs["Strength"].default_value = 1.0
        self.tree.links.new(emission.outputs["Emission"], self.output.inputs["Surface"])


def bake_float_image(plane, build, size, name):
    """Bakes the emission `build(graph)` wires up onto a size x size float
    image (Non-Color, so a value of x is stored as x) and returns it."""
    material = bpy.data.materials.new(name + "_mat")
    graph = Graph(material)
    build(graph)
    image = bpy.data.images.new(name, size, size, alpha=True, float_buffer=True)
    image.colorspace_settings.name = 'Non-Color'
    target = graph.tree.nodes.new("ShaderNodeTexImage")
    target.image = image
    graph.tree.nodes.active = target
    plane.data.materials.clear()
    plane.data.materials.append(material)
    bpy.ops.object.select_all(action='DESELECT')
    plane.select_set(True)
    bpy.context.view_layer.objects.active = plane
    bpy.ops.object.bake(type='EMIT', target='IMAGE_TEXTURES')
    return image


def to_array(image):
    """The image's pixels as a (height, width, 4) float array, row 0 at
    the bottom (Blender's order)."""
    w, h = image.size
    data = np.empty(w * h * 4, dtype=np.float32)
    image.pixels.foreach_get(data)
    return data.reshape(h, w, 4)


def save_rgba_png(array, path, name):
    """Quantises a (h, w, 4) float array in [0, 1] into an 8-bit PNG."""
    h, w, _ = array.shape
    image = bpy.data.images.new(name, w, h, alpha=True, float_buffer=False)
    image.colorspace_settings.name = 'Non-Color'
    flat = np.clip(array, 0.0, 1.0).astype(np.float32).reshape(-1)
    image.pixels.foreach_set(flat)
    image.filepath_raw = path
    image.file_format = 'PNG'
    bpy.context.scene.render.image_settings.color_depth = '8'
    image.save()
    return image


def grey_with_alpha(grey, alpha):
    """(h, w) grey and alpha arrays into an RGBA array."""
    out = np.empty(grey.shape + (4,), dtype=np.float32)
    out[..., 0] = grey
    out[..., 1] = grey
    out[..., 2] = grey
    out[..., 3] = alpha
    return out


def normal_map_from_height(height, strength, wrap=True):
    """An OpenGL-convention (Godot's: +Y up) tangent-space normal map from
    a (h, w) height field in [0, 1]. `strength` scales the slope; wrap-
    around differences keep the map tileable."""
    if wrap:
        dx = (np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)) * 0.5
        dy = (np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)) * 0.5
    else:
        dx = np.gradient(height, axis=1)
        dy = np.gradient(height, axis=0)
    nx = -dx * strength
    ny = -dy * strength
    nz = np.ones_like(height)
    length = np.sqrt(nx * nx + ny * ny + nz * nz)
    out = np.empty(height.shape + (4,), dtype=np.float32)
    out[..., 0] = nx / length * 0.5 + 0.5
    out[..., 1] = ny / length * 0.5 + 0.5
    out[..., 2] = nz / length * 0.5 + 0.5
    out[..., 3] = 1.0
    return out


def tiled_preview(array, path):
    """A 2 x 2 tiling of an RGBA array, halved, for a tileability check
    (scratch output, never committed)."""
    tiled = np.concatenate([np.concatenate([array, array], axis=1)] * 2, axis=0)
    small = tiled[::2, ::2]
    os.makedirs(os.path.dirname(path), exist_ok=True)
    save_rgba_png(small, path, os.path.basename(path))


def checker_preview(array, path):
    """The RGBA array composited over a magenta / grey checker so the
    alpha reads (scratch output, never committed)."""
    h, w, _ = array.shape
    yy, xx = np.mgrid[0:h, 0:w]
    checker = ((yy // 16 + xx // 16) % 2).astype(np.float32)
    back = np.empty((h, w, 4), dtype=np.float32)
    back[..., 0] = 0.8 * checker + 0.2
    back[..., 1] = 0.2
    back[..., 2] = 0.8 * checker + 0.2
    back[..., 3] = 1.0
    a = array[..., 3:4]
    out = array * a + back * (1.0 - a)
    out[..., 3] = 1.0
    os.makedirs(os.path.dirname(path), exist_ok=True)
    save_rgba_png(out, path, os.path.basename(path))


def preview_dir_from_argv():
    """`-- --preview DIR` after the script: where to write scratch previews."""
    if "--" in sys.argv:
        rest = sys.argv[sys.argv.index("--") + 1:]
        if "--preview" in rest:
            return rest[rest.index("--preview") + 1]
    return None


def report(path):
    print("wrote %s (%d bytes)" % (os.path.relpath(path, ASSETS), os.path.getsize(path)))


def ensure_dirs():
    for folder in (TEXTURES_ROAD, TEXTURES_VEG, MESHES):
        os.makedirs(folder, exist_ok=True)

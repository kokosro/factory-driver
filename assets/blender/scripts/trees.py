"""The tree archetypes (docs/art-direction.md "Trees": "simple trunks /
crossed foliage cards / billboard foliage / chunky low-poly crowns /
several repeated tree archetypes"; "Geometry philosophy: A tree can be
mostly cards"; docs/design/4b/element-library.md §6: V1 "trunk cylinder +
3-lobe crown, <= 120 tris, 256-512 card", V2 "trunk + 3 crossed cards",
V6 "V1 at OSM spacing").

    blender -b -P assets/blender/scripts/trees.py

writes, into assets/meshes/, three .glb files whose textures stay the
PNGs of assets/textures/vegetation/ (foliage.py), referenced by relative
URI, never embedded (Godot loads the shared textures once):

  tree_spruce.glb  V2, the Eifel default. 20 m tall: a tapered 8-sided
                   trunk (16 tris, bark), three crossed side cards of the
                   spruce silhouette (6 tris, the atlas' left half), seven
                   branch-whorl cones stacked up the trunk and shrinking
                   (12 segments each, 84 tris, the atlas' whorl quadrants;
                   the top two the sparser whorl). 106 triangles, 121
                   vertices.
  tree_beech.glb   V1, the broadleaf. 14 m tall: the trunk (16 tris),
                   three chunky low-poly crown lobes (6 x 3 UV spheres, 36
                   tris each, 108, wearing the atlas' leaf fill), three
                   crossed crown cards (6 tris, the atlas' crown). 130
                   triangles, 99 vertices.
  tree_row.glb     the V6 avenue tree (a V1 in a row, the smaller lime of
                   a roadside line). 10 m tall: the trunk (16), three
                   lobes (108), two crossed crown cards (4). 128
                   triangles, 95 vertices.

Each mesh has two material slots, "bark" (bark_256.png, opaque) and
"foliage" (the archetype's atlas, alpha) - one glTF primitive each, so
Godot reads two surfaces; scripts/forest_walls.gd bakes the surfaces into
its chunk meshes with its own materials (vertex colour x texture) and
takes the geometry, UVs and normals from here. The origin is the foot of
the trunk, +Y up in the file (Blender's +Z, the exporter's Y-up); the
game scales a tree to its own height from the archetype's height.

FOLIAGE NORMALS are authored, not computed: a foliage vertex's normal is
its direction from the trunk axis blended with up, so the three crossed
cards and the whorls light like one rounded mass whichever way the card
faces (the 2000 trick behind "billboard foliage"). Trunk normals are the
tube's radial ones.

Deterministic: fixed vertex order, no randomness anywhere; the exporter
writes the same bytes for the same scene (assets/blender/README.md).
"""

import json
import math
import os
import struct
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402

import common  # noqa: E402

BARK_TILE_M = 2.0

ARCHETYPES = {
    "tree_spruce": {"height_m": 20.0, "kind": "spruce", "atlas": "foliage_spruce_512.png"},
    "tree_beech": {"height_m": 14.0, "kind": "beech", "atlas": "foliage_beech_512.png"},
    "tree_row": {"height_m": 10.0, "kind": "row", "atlas": "foliage_beech_512.png"},
}


class Builder:
    """Collects vertices, faces, UVs (per loop), normals and material
    indices; every helper appends in a fixed order."""

    def __init__(self):
        self.verts = []
        self.normals = []
        self.faces = []
        self.face_uvs = []
        self.face_mats = []

    def vertex(self, x, y, z, normal):
        self.verts.append((x, y, z))
        n = math.sqrt(normal[0] ** 2 + normal[1] ** 2 + normal[2] ** 2) or 1.0
        self.normals.append((normal[0] / n, normal[1] / n, normal[2] / n))
        return len(self.verts) - 1

    def face(self, indices, uvs, material):
        self.faces.append(tuple(indices))
        self.face_uvs.append(tuple(uvs))
        self.face_mats.append(material)

    @staticmethod
    def foliage_normal(x, y, z, up_share=0.6):
        r = math.sqrt(x * x + y * y)
        if r < 1e-6:
            return (0.0, 0.0, 1.0)
        return (x / r, y / r, up_share)

    def trunk(self, radius_bottom, radius_top, top, segments=8):
        """A tapered open tube from z 0 to `top`; bark wraps once around
        and every BARK_TILE_M up."""
        rings = []
        for ring, (radius, z) in enumerate(((radius_bottom, 0.0), (radius_top, top))):
            ids = []
            for i in range(segments + 1):
                a = 2.0 * math.pi * (i % segments) / segments
                x = math.cos(a) * radius
                y = math.sin(a) * radius
                ids.append(self.vertex(x, y, z, (math.cos(a), math.sin(a), 0.0)))
            rings.append(ids)
        for i in range(segments):
            u0 = i / segments
            u1 = (i + 1) / segments
            v1 = top / BARK_TILE_M
            self.face((rings[0][i], rings[0][i + 1], rings[1][i + 1], rings[1][i]), ((u0, 0.0), (u1, 0.0), (u1, v1), (u0, v1)), 0)

    def card(self, width, z0, z1, heading, u_range, v_range=(0.0, 1.0)):
        """A vertical quad through the axis, `heading` radians about z,
        its UVs the atlas region."""
        hx = math.cos(heading) * width * 0.5
        hy = math.sin(heading) * width * 0.5
        corners = ((-hx, -hy, z0), (hx, hy, z0), (hx, hy, z1), (-hx, -hy, z1))
        ids = [self.vertex(x, y, z, self.foliage_normal(x, y, z)) for x, y, z in corners]
        u0, u1 = u_range
        v0, v1 = v_range
        self.face(ids, ((u0, v0), (u1, v0), (u1, v1), (u0, v1)), 1)

    def cone(self, z, radius, apex_rise, centre_uv, uv_radius, segments=12, phase=0.0):
        """A branch whorl: a shallow cone with its apex above the rim."""
        apex = self.vertex(0.0, 0.0, z + apex_rise, (0.0, 0.0, 1.0))
        rim = []
        for i in range(segments):
            a = 2.0 * math.pi * i / segments + phase
            x = math.cos(a) * radius
            y = math.sin(a) * radius
            rim.append((self.vertex(x, y, z, self.foliage_normal(x, y, z, 0.8)), a))
        cu, cv = centre_uv
        for i in range(segments):
            (a_id, a_ang) = rim[i]
            (b_id, b_ang) = rim[(i + 1) % segments]
            uv_a = (cu + math.cos(a_ang - phase) * uv_radius, cv + math.sin(a_ang - phase) * uv_radius)
            uv_b = (cu + math.cos(b_ang - phase) * uv_radius, cv + math.sin(b_ang - phase) * uv_radius)
            self.face((a_id, b_id, apex), (uv_a, uv_b, (cu, cv)), 1)

    def lobe(self, centre, radii, u_range, segments=6, rings=3):
        """A low-poly UV sphere (an ellipsoid) wearing the leaf fill."""
        cx, cy, cz = centre
        rx, ry, rz = radii
        u0, u1 = u_range
        top = self.vertex(cx, cy, cz + rz, self.foliage_normal(cx, cy, cz + rz))
        bottom = self.vertex(cx, cy, cz - rz, self.foliage_normal(cx, cy, cz - rz))
        ring_ids = []
        ring_v = []
        for r in range(rings):
            lat = math.pi * (r + 1) / (rings + 1) - math.pi / 2.0
            ids = []
            for i in range(segments + 1):
                a = 2.0 * math.pi * (i % segments) / segments
                x = cx + math.cos(a) * math.cos(lat) * rx
                y = cy + math.sin(a) * math.cos(lat) * ry
                z = cz + math.sin(lat) * rz
                ids.append(self.vertex(x, y, z, self.foliage_normal(x - cx, y - cy, z - cz)))
            ring_ids.append(ids)
            ring_v.append(lat / math.pi + 0.5)

        def uv(i, v):
            return (u0 + (u1 - u0) * i / segments, v)

        for i in range(segments):
            self.face((bottom, ring_ids[0][i + 1], ring_ids[0][i]), (uv(i + 0.5, 0.0), uv(i + 1, ring_v[0]), uv(i, ring_v[0])), 1)
        for r in range(rings - 1):
            for i in range(segments):
                self.face((ring_ids[r][i], ring_ids[r][i + 1], ring_ids[r + 1][i + 1], ring_ids[r + 1][i]), (uv(i, ring_v[r]), uv(i + 1, ring_v[r]), uv(i + 1, ring_v[r + 1]), uv(i, ring_v[r + 1])), 1)
        for i in range(segments):
            self.face((ring_ids[-1][i], ring_ids[-1][i + 1], top), (uv(i, ring_v[-1]), uv(i + 1, ring_v[-1]), uv(i + 0.5, 1.0)), 1)


def spruce(b: Builder, h: float):
    b.trunk(0.32, 0.07, 0.62 * h)
    for k in range(3):
        b.card(0.36 * h, 0.08 * h, h, math.pi * k / 3.0, (0.0, 0.5))
    for k in range(7):
        z = (0.16 + 0.12 * k) * h
        radius = 0.19 * h * (1.0 - k / 8.0)
        centre = (0.75, 0.75) if k < 5 else (0.75, 0.25)
        b.cone(z, radius, 0.04 * h, centre, 0.25, phase=0.3 * k)


def beech(b: Builder, h: float):
    b.trunk(0.35, 0.12, 0.5 * h)
    b.lobe((0.0, 0.0, 0.66 * h), (0.3 * h, 0.3 * h, 0.26 * h), (0.5, 1.0))
    b.lobe((-0.2 * h, 0.06 * h, 0.56 * h), (0.24 * h, 0.24 * h, 0.2 * h), (0.5, 1.0))
    b.lobe((0.2 * h, -0.06 * h, 0.56 * h), (0.24 * h, 0.24 * h, 0.2 * h), (0.5, 1.0))
    for k in range(3):
        b.card(0.72 * h, 0.28 * h, h, math.pi * k / 3.0, (0.0, 0.5))


def row_tree(b: Builder, h: float):
    b.trunk(0.25, 0.1, 0.45 * h)
    b.lobe((0.0, 0.0, 0.68 * h), (0.26 * h, 0.26 * h, 0.32 * h), (0.5, 1.0))
    b.lobe((0.06 * h, -0.04 * h, 0.5 * h), (0.2 * h, 0.2 * h, 0.16 * h), (0.5, 1.0))
    b.lobe((-0.09 * h, 0.05 * h, 0.56 * h), (0.16 * h, 0.16 * h, 0.14 * h), (0.5, 1.0))
    for k in range(2):
        b.card(0.6 * h, 0.3 * h, h, math.pi * k / 2.0, (0.0, 0.5))


KINDS = {"spruce": spruce, "beech": beech, "row": row_tree}


def texture_material(name, png_path, alpha):
    material = bpy.data.materials.new(name)
    material.use_nodes = True
    tree = material.node_tree
    bsdf = tree.nodes["Principled BSDF"]
    image = bpy.data.images.load(png_path, check_existing=True)
    # The same datablock name whether this runs alone or after foliage.py
    # in one session (build_all.py), so the glTF's image name - and the
    # .glb's bytes - are the same by either path.
    image.name = os.path.basename(png_path)
    if not alpha:
        image.colorspace_settings.name = 'sRGB'
    tex = tree.nodes.new("ShaderNodeTexImage")
    tex.image = image
    tree.links.new(tex.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 1.0
    if "Specular IOR Level" in bsdf.inputs:
        bsdf.inputs["Specular IOR Level"].default_value = 0.0
    if alpha:
        tree.links.new(tex.outputs["Alpha"], bsdf.inputs["Alpha"])
        if hasattr(material, "blend_method"):
            material.blend_method = 'CLIP'
        if hasattr(material, "alpha_threshold"):
            material.alpha_threshold = 0.5
        material.use_backface_culling = False
    return material


def make_object(name, spec, bark_material, foliage_material):
    b = Builder()
    KINDS[spec["kind"]](b, spec["height_m"])
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(b.verts, [], b.faces)
    mesh.update()
    mesh.materials.append(bark_material)
    mesh.materials.append(foliage_material)
    uv_layer = mesh.uv_layers.new(name="UVMap")
    for poly, uvs, material in zip(mesh.polygons, b.face_uvs, b.face_mats):
        poly.material_index = material
        poly.use_smooth = True
        for loop_index, uv in zip(poly.loop_indices, uvs):
            uv_layer.data[loop_index].uv = uv
    mesh.normals_split_custom_set_from_vertices(b.normals)
    obj = bpy.data.objects.new(name, mesh)
    bpy.context.scene.collection.objects.link(obj)
    triangles = sum(len(f) - 2 for f in b.faces)
    return obj, triangles, len(b.verts)


def pack_glb(gltf_path, bin_path, glb_path):
    """Packs a separate .gltf + .bin into one .glb, the image URIs kept
    (Blender's own GLB path embeds the images - and, with keep_originals,
    writes the URI beside the embedded copy, which is not valid glTF); the
    JSON is re-serialised with sorted keys and no whitespace."""
    with open(gltf_path, "rb") as f:
        doc = json.loads(f.read().decode("utf-8"))
    with open(bin_path, "rb") as f:
        blob = f.read()
    doc["buffers"][0].pop("uri", None)
    doc["buffers"][0]["byteLength"] = len(blob)
    # Blender 5 has no blend mode on the material any more, so the exporter
    # writes alphaMode BLEND for a linked alpha; the foliage is cut, not
    # blended (StandardMaterial3D alpha scissor at 0.5): MASK, cutoff 0.5.
    for material in doc.get("materials", []):
        if material.get("alphaMode") == "BLEND":
            material["alphaMode"] = "MASK"
            material["alphaCutoff"] = 0.5
    text = json.dumps(doc, separators=(",", ":"), sort_keys=True).encode("utf-8")
    text += b" " * ((4 - len(text) % 4) % 4)
    blob += b"\0" * ((4 - len(blob) % 4) % 4)
    total = 12 + 8 + len(text) + 8 + len(blob)
    with open(glb_path, "wb") as f:
        f.write(struct.pack("<4sII", b"glTF", 2, total))
        f.write(struct.pack("<I4s", len(text), b"JSON"))
        f.write(text)
        f.write(struct.pack("<I4s", len(blob), b"BIN\0"))
        f.write(blob)


def export(obj, name):
    gltf_path = os.path.join(common.MESHES, name + ".gltf")
    bin_path = os.path.join(common.MESHES, name + ".bin")
    glb_path = os.path.join(common.MESHES, name + ".glb")
    bpy.ops.object.select_all(action='DESELECT')
    obj.select_set(True)
    bpy.context.view_layer.objects.active = obj
    bpy.ops.export_scene.gltf(
        filepath=gltf_path,
        export_format='GLTF_SEPARATE',
        use_selection=True,
        export_keep_originals=True,
        export_image_format='AUTO',
        export_materials='EXPORT',
        export_yup=True,
        export_apply=True,
        export_normals=True,
        export_texcoords=True,
        export_tangents=False,
        export_animations=False,
        export_skins=False,
        export_morph=False,
        export_lights=False,
        export_cameras=False,
        export_extras=False,
    )
    pack_glb(gltf_path, bin_path, glb_path)
    os.remove(gltf_path)
    os.remove(bin_path)
    common.report(glb_path)


def build(reset=True):
    common.ensure_dirs()
    if reset:
        common.reset_scene()
    bark = texture_material("bark", os.path.join(common.TEXTURES_VEG, "bark_256.png"), alpha=False)
    foliage = {}
    x = 0.0
    for name, spec in ARCHETYPES.items():
        atlas = spec["atlas"]
        if atlas not in foliage:
            foliage[atlas] = texture_material("foliage_" + atlas.split("_")[1], os.path.join(common.TEXTURES_VEG, atlas), alpha=True)
        obj, triangles, vertices = make_object(name, spec, bark, foliage[atlas])
        print("%s: %d triangles, %d vertices, %.0f m" % (name, triangles, vertices, spec["height_m"]))
        export(obj, name)
        # Spread the archetypes along x in the saved .blend, for a human.
        obj.location.x = x
        x += 12.0


if __name__ == "__main__":
    build()

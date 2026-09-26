"""Regenerates every authored asset in one Blender session and saves the
working file (assets/blender/README.md):

    blender -b -P assets/blender/scripts/build_all.py [-- --preview DIR]

Runs asphalt.py (the road texture set), foliage.py (the vegetation
textures) and trees.py (the three archetypes, whose materials reference
the textures just written), then saves assets/blender/factory_driver_
assets.blend holding the bake planes with their procedural node materials
(kept by a fake user) and the three archetype objects side by side. The
.blend is a convenience for a human with Blender open; the scripts and
the exported PNG / .glb files are the source of truth (a .blend is not
byte-deterministic: it carries the session's memory layout).
"""

import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import bpy  # noqa: E402

import asphalt  # noqa: E402
import common  # noqa: E402
import foliage  # noqa: E402
import trees  # noqa: E402


def main():
    preview = common.preview_dir_from_argv()
    asphalt.build(preview)
    foliage.build(preview, reset=False)
    trees.build(reset=False)
    for material in bpy.data.materials:
        material.use_fake_user = True
    # The baked float images are gone with the session; the saved file
    # points its image nodes at the PNGs on disk instead.
    for image in list(bpy.data.images):
        if image.filepath_raw == "" or image.is_dirty and not os.path.exists(bpy.path.abspath(image.filepath_raw)):
            bpy.data.images.remove(image)
    bpy.context.preferences.filepaths.save_version = 0  # no .blend1 beside it
    bpy.ops.wm.save_as_mainfile(filepath=common.BLEND_FILE, relative_remap=True, compress=True)
    print("saved %s (%d bytes)" % (os.path.relpath(common.BLEND_FILE, common.ASSETS), os.path.getsize(common.BLEND_FILE)))


if __name__ == "__main__":
    main()

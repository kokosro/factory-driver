extends SceneTree
## Conductor's NON-HEADLESS visual probe v2 (2026-09-26, canon NON-HEADLESS ALLOWED):
## road-derived spots — the camera sits ON a named road's strip at a named
## chainage and offset (position interpolated from the RoadBuilder strip's own
## vertices, the same data the mesh was built from), aimed down-chainage.
## Survey-driven (claude survey of v1): top-down ruts shot, several drawn frames
## before capture, no HUD (a bare SceneTree draws only the ring).
## Saves to .scratch/fd-visual/ (in-repo, untracked) so external surveyors read them.
## Run: godot --path . --script tests/visual_probe.gd --quit-after 900   (NOT --headless)
## (--quit-after guarantees exit: quit(0) from an awaited _init does NOT
## terminate a windowed SceneTree script reliably — two leaked instances
## observed 2026-09-26 before the flag was adopted.)

const SPOTS := [
	# the Karussell bank, on the road, looking down-chainage
	{"name": "karussell_road", "seg": "414785755-0", "s": 76.0, "offset": 0.0, "eye_h": 2.2, "look_ahead": 60.0},
	# the drive-start straight (Döttinger Höhe approach), at the left rut, looking ahead
	{"name": "straight_ruts", "seg": "683303211-0", "s": 40.0, "offset": -2.2, "eye_h": 1.9, "look_ahead": 50.0},
	# 15 m above the straight, looking down at the ruts (the survey's ask)
	{"name": "ruts_topdown", "seg": "683303211-0", "s": 40.0, "offset": 0.0, "eye_h": 15.0, "look_ahead": 12.0, "down": true},
	# a forest wall beside the straight, from the road's right edge
	{"name": "forest_wall", "seg": "683303211-0", "s": 30.0, "offset": 14.0, "eye_h": 2.0, "look_ahead": 35.0},
]

var _road: RoadBuilder = null

func _init() -> void:
	var out_dir := "res://.scratch/fd-visual"
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(out_dir))
	var scene: PackedScene = load("res://scenes/eifel_ring.tscn")
	var ring := scene.instantiate()
	root.add_child(ring)
	for i: int in 6:
		await process_frame
	var road: RoadBuilder = ring.get_node_or_null("Road")
	assert(road != null, "the Ring scene has no Road node")
	assert(road.profile != null, "the Road has no profile")
	_road = road
	var cam := Camera3D.new()
	root.add_child(cam)
	cam.current = true
	cam.far = 4000.0
	for spot: Dictionary in SPOTS:
		var strip: RoadBuilder.Strip = road.strip(spot.seg)
		assert(strip != null, "no strip for %s" % spot.seg)
		var eye := _at(strip, spot.s, spot.offset, spot.eye_h)
		var look := _at(strip, spot.s + spot.look_ahead, spot.offset, 0.0)
		var target: Vector3 = look if spot.get("down", false) else Vector3(look.x, eye.y - spot.eye_h + 0.6, look.z)
		if spot.get("down", false):
			target = Vector3(look.x, road.profile.sample_height(look.x, look.z), look.z)
		cam.global_position = eye
		cam.look_at(target, Vector3.UP)
		for i: int in 3:
			await process_frame
		await RenderingServer.frame_post_draw
		var img := root.get_viewport().get_texture().get_image()
		var path := "%s/%s.png" % [out_dir, spot.name]
		img.save_png(path)
		print("saved ", path, " ", img.get_width(), "x", img.get_height(), " eye ", eye)
	print("VISUAL PROBE v2 DONE")
	# The windowed SceneTree ignores quit() from awaited code in some builds;
	# --quit-after on the command line is the guaranteed exit (see the header).
	get_tree().quit(0)

## The world point on a strip at chainage s and across-offset o, eh above the
## field: position from the strip's own section vertices (the centre column
## interpolated along), height the profile's (the field the car reads).
func _at(strip: RoadBuilder.Strip, s: float, o: float, eh: float) -> Vector3:
	var chain: PackedFloat64Array = strip.chainages
	var s_c: float = clampf(s, chain[0], chain[chain.size() - 1])
	var k: int = 1
	while k < chain.size() and chain[k] < s_c:
		k += 1
	if k >= chain.size():
		k = chain.size() - 1
	var span: float = chain[k] - chain[k - 1]
	var u: float = 0.0 if span <= 0.0 else (s_c - chain[k - 1]) / span
	var centre_i: int = 0
	var best: float = INF
	for i: int in strip.offsets.size():
		var d: float = absf(strip.offsets[i])
		if d < best:
			best = d
			centre_i = i
	var a: Vector3 = strip.vertex(k - 1, centre_i)
	var b: Vector3 = strip.vertex(k, centre_i)
	var centre: Vector3 = a.lerp(b, u)
	var dir: Vector3 = (b - a).normalized()
	var right := Vector3(-dir.z, 0.0, dir.x)
	var o_clamped: float = clampf(o, -strip.half_width - 6.0, strip.half_width + 6.0)
	var pos: Vector3 = centre + right * o_clamped
	var h: float = _road.profile.sample_height(pos.x, pos.z) if _road != null else centre.y
	return Vector3(pos.x, h + eh, pos.z)
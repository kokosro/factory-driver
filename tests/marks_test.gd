extends SceneTree
## Headless skidmarks test (SKIDMARKS-1, driver issue-0003: "there is no
## tire markings left on tarmac, this is not only for this zone, it's
## everywhere on the green hell"). Run via tests/run_tests.sh, or:
##
##   godot --headless --path . --import
##   godot --headless --fixed-fps 60 --path . --script res://tests/marks_test.gd
##
## THE WATCHER (scripts/marks_watch.gd, the MarksWatch autoload): registered,
## under the root, on node_added; the FD_MARKS switch ("0" off, "1" on,
## unset off with no window - this suite's default, so no other test sees
## a layer). THE LAYER (scripts/marks.gd, MarksLayer "Marks"): on the pad
## stripped of its own TyreMarks node (main.tscn's, which the watcher
## defers to - main.tscn as shipped gets NO layer, pinned below) one layer
## per car under the scene root, in front of the TelemetryRecorder (which
## stays the root's LAST child), no Surfaces node there; one MultiMesh of
## MAX_QUADS quads, colour per quad, no children, no collision; the three
## triggers as pure functions (the onsets at 1.5 peaks / 0.2875 / 0.5, solid
## at 3 peaks / 1 / 1, an ordinary launch and an ABS stop under them); the
## drives: a handbrake slide from 60 km/h lays quads (recorded to a file of
## this test's own), every one a tyre wide, LIFT_M over the ground the pad
## shows, face up, a quad every SPACING_M and not one a tick; flat out with
## TCS through a gear change and a full ABS pedal to a stop lay NOTHING;
## normal cornering (a steady quarter-lock corner at 45 km/h) lays NOTHING
## with the fronts under 1.5 peaks; a launch with TCS off lays the rears'
## wheelspin in their two tracks and nothing for the fronts; a stop with
## ABS off lays the locked fronts; DETERMINISM: a second scene instanced
## fresh and driven the same slide lays the same records (count, snapped
## positions, alphas, wheels, yaws, lengths) to the bit; the pool is
## bounded (MAX_QUADS + 1 laid: the oldest laid over); a quad fades in a
## line and is gone at LIFETIME_S; the colour refresh keeps within its
## stride; clear() empties the pool. FD_MARKS=0: a third scene gets no
## layer at all, and its recorder's samples of the same slide are
## byte-identical to the first scene's - the marks never touch the car. A
## bare car under the root gets a layer under the root. THE RING: a layer
## in front of the recorder with the scene's Surfaces node; a handbrake
## slide on the straight's tarmac lays quads, every one on road, on the
## RingProfile's height; the grass gate: the same slide and a TCS-off
## launch on the grass spot, the tyres past every onset, lay NOTHING.
##
## The store pinned off (FD_TELEMETRY=0, the refuel test's idiom); FD_MARKS
## restored at the end. Exits 0 on success, 1 on any failed check.

const PAD_SCENE := "res://scenes/main.tscn"
const RING_SCENE := "res://scenes/eifel_ring.tscn"
const CAR_SCENE := "res://scenes/car.tscn"

## Physics frames to let a scene settle after a load (the watcher's attach
## is one deferred call; the Ring builds its road at load).
const SETTLE_FRAMES := 20

## The slide (the smoke test's marks slide): up to this speed [m/s], then
## SLIDE_STEER of left steering and the handbrake for SLIDE_FRAMES, then
## everything let go for SLIDE_WATCH_FRAMES.
const SLIDE_SPEED := 16.5
const SLIDE_STEER := 0.3
const SLIDE_FRAMES := 40
const SLIDE_WATCH_FRAMES := 120
const SPEED_UP_FRAMES_MAX := 600

## Flat out with TCS for this long, then the ABS stop (to rest at the latest).
const GRIP_FRAMES := 180
const STOP_FRAMES_MAX := 600

## Normal cornering: this share of full lock from this speed [m/s], this long.
const CORNER_STEER := 0.25
const CORNER_SPEED := 12.5
const CORNER_FRAMES := 60

## The launch with TCS off, and the stop with ABS off from this speed [m/s].
const LAUNCH_FRAMES := 120
const LOCK_SPEED := 25.0

## The fade watch [ticks] and the colour stride's slack.
const FADE_FRAMES := 60

## The Ring's straight (the offroad test's reference) and its grass spot.
const STRAIGHT := "683303211-0"
const STRAIGHT_SECTION := 15
const GRASS_SPOT := Vector2(6120.0, -2640.0)
const GRASS_HEADING := Vector2(0.0, -1.0)

## Where this run writes: a tmp dir of its own, removed at the end.
const TMP_DIR_PREFIX := "/tmp/fd-SM-marks-"

## A snapped origin is on the ground within this [m] (POSITION_SNAP is
## 0.001) on the flat pad; on the Ring a quad's middle is the mean of its
## two ends' heights, which on a grade is not the profile's height there
## to the millimetre over half a metre.
const GROUND_TOLERANCE := 0.0006
const GROUND_TOLERANCE_RING := 0.005

var _failures := 0
var _tmp_dir := ""
var _marks_env_before := ""
var _attached := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	OS.set_environment("FD_TELEMETRY", "0")
	_marks_env_before = OS.get_environment(MarksWatcher.ENV_VAR)
	_tmp_dir = TMP_DIR_PREFIX + str(OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(_tmp_dir)
	print("-- the watcher")
	if not _check_watcher():
		_finish()
		return
	print("-- the triggers")
	_check_triggers()
	OS.set_environment(MarksWatcher.ENV_VAR, "1")
	print("-- the pad, its own marks stripped: the layer and the drives")
	var first := await _check_pad_drives()
	print("-- the pad again: determinism, the pool, the fade")
	await _check_pad_again(first)
	print("-- FD_MARKS=0: no layer, the same drive to the bit")
	OS.set_environment(MarksWatcher.ENV_VAR, "0")
	await _check_switched_off(first)
	OS.set_environment(MarksWatcher.ENV_VAR, "1")
	print("-- the pad as shipped keeps its own marks")
	await _check_pad_as_shipped()
	print("-- a bare car")
	await _check_bare_car()
	print("-- the Ring: tarmac marks, the grass gate")
	await _check_ring()
	OS.set_environment(MarksWatcher.ENV_VAR, _marks_env_before)
	_check(OS.get_environment(MarksWatcher.ENV_VAR) == _marks_env_before, "FD_MARKS restored to what it was (%s)" % ("unset" if _marks_env_before == "" else _marks_env_before))
	_remove_tmp()
	_finish()


# =============================================================================
#  The watcher
# =============================================================================

func _check_watcher() -> bool:
	var watch := MarksWatcher.of(self)
	var registered := String(ProjectSettings.get_setting("autoload/%s" % MarksWatcher.AUTOLOAD_NAME, "")) == "*res://scripts/marks_watch.gd"
	if not _check(watch != null and registered and watch.get_parent() == root and watch.name == MarksWatcher.AUTOLOAD_NAME and (watch.get_script() as Script).resource_path == "res://scripts/marks_watch.gd", "the MarksWatch autoload is registered (project.godot) and stands under the root, scripts/marks_watch.gd"):
		return false
	var telemetry := TelemetryWatcher.of(self)
	_check(telemetry != null and telemetry.get_index() < watch.get_index(), "it stands after TelemetryWatch under the root (registered after it: its attach runs after the recorder's)")
	watch.layer_attached.connect(func(_layer: MarksLayer) -> void: _attached += 1)
	_check(node_added.is_connected(watch._on_node_added) and watch.live_layers().is_empty() and _layers_under(root).is_empty(), "it watches the tree's node_added, and holds no layer while there is no car (no Marks node in the tree)")
	var was := OS.get_environment(MarksWatcher.ENV_VAR)
	OS.set_environment(MarksWatcher.ENV_VAR, "")
	var unset_headless := MarksWatcher.should_attach()
	OS.set_environment(MarksWatcher.ENV_VAR, "0")
	var off := MarksWatcher.should_attach()
	OS.set_environment(MarksWatcher.ENV_VAR, "1")
	var on := MarksWatcher.should_attach()
	OS.set_environment(MarksWatcher.ENV_VAR, was)
	_check(not unset_headless and not off and on and DisplayServer.get_name() == "headless", "THE SWITCH: FD_MARKS unset is off with no window (the suite's default: no other test sees a layer), \"0\" is off, \"1\" is on")
	return true


# =============================================================================
#  The triggers
# =============================================================================

func _check_triggers() -> void:
	var front: float = ArcadeCar.FRONT_PEAK_SLIP_ANGLE
	var rear: float = ArcadeCar.REAR_PEAK_SLIP_ANGLE
	_check(
		MarksLayer.lateral_intensity(0.0, front) == 0.0 and MarksLayer.lateral_intensity(front, front) == 0.0 and MarksLayer.lateral_intensity(front * MarksLayer.LATERAL_ONSET_PEAKS, front) == 0.0
			and MarksLayer.lateral_intensity(front * MarksLayer.LATERAL_SOLID_PEAKS, front) == 1.0 and MarksLayer.lateral_intensity(-PI * 0.5, front) == 1.0
			and MarksLayer.lateral_intensity(front * 2.25, front) == MarksLayer.lateral_intensity(-front * 2.25, front) and absf(MarksLayer.lateral_intensity(front * 2.25, front) - 0.5) < 1.0e-9
			and MarksLayer.lateral_intensity(rear * MarksLayer.LATERAL_ONSET_PEAKS, rear) == 0.0 and MarksLayer.lateral_intensity(rear * MarksLayer.LATERAL_SOLID_PEAKS, rear) == 1.0,
		"LATERAL: 0 at the axle's peak and up to %.1f peaks (front %.3f rad, rear %.3f), 1 from %.1f peaks (%.2f / %.2f), a line between (0.5 at 2.25 peaks), no left or right" % [MarksLayer.LATERAL_ONSET_PEAKS, front * MarksLayer.LATERAL_ONSET_PEAKS, rear * MarksLayer.LATERAL_ONSET_PEAKS, MarksLayer.LATERAL_SOLID_PEAKS, front * MarksLayer.LATERAL_SOLID_PEAKS, rear * MarksLayer.LATERAL_SOLID_PEAKS],
	)
	_check(
		absf(MarksLayer.spin_onset_ratio() - ArcadeCar.DRIVE_SLIP_RATIO * 1.15) < 1.0e-9 and MarksLayer.spin_intensity(ArcadeCar.DRIVE_SLIP_RATIO) == 0.0 and MarksLayer.spin_intensity(MarksLayer.spin_onset_ratio()) == 0.0
			and MarksLayer.spin_intensity(MarksLayer.SPIN_SOLID_RATIO) == 1.0 and MarksLayer.spin_intensity(2.8) == 1.0 and MarksLayer.spin_intensity(-1.0) == 0.0 and MarksLayer.spin_intensity(0.5) > 0.0 and MarksLayer.spin_intensity(0.5) < 0.5,
		"WHEELSPIN: 0 at the clutch limit's %.2f (an ordinary launch) and up to %.4f (x %.2f), 1 from %.1f (a clutch dumped without TCS spins to 2.8), nothing for a wheel turning slower than the road" % [ArcadeCar.DRIVE_SLIP_RATIO, MarksLayer.spin_onset_ratio(), MarksLayer.SPIN_ONSET_FACTOR, MarksLayer.SPIN_SOLID_RATIO],
	)
	_check(
		MarksLayer.lock_intensity(0.0) == 0.0 and MarksLayer.lock_intensity(-ArcadeCar.ABS_SLIP_RATIO) == 0.0 and MarksLayer.lock_intensity(-MarksLayer.LOCK_ONSET_RATIO) == 0.0 and MarksLayer.lock_intensity(MarksLayer.LOCK_ONSET_RATIO) == 0.0
			and MarksLayer.lock_intensity(-1.0) == 1.0 and MarksLayer.lock_intensity(1.0) == 1.0 and absf(MarksLayer.lock_intensity(-0.75) - 0.5) < 1.0e-9,
		"LOCK: 0 under ABS (%.2f) and up to %.1f either way, 1 at a locked wheel (-1), 0.5 at -0.75" % [ArcadeCar.ABS_SLIP_RATIO, MarksLayer.LOCK_ONSET_RATIO],
	)
	_check(
		MarksLayer.axle_intensity(0.0, ArcadeCar.DRIVE_SLIP_RATIO, rear, true) == 0.0 and MarksLayer.axle_intensity(0.0, -ArcadeCar.ABS_SLIP_RATIO, front, false) == 0.0 and MarksLayer.axle_intensity(front, 0.0, front, false) == 0.0
			and MarksLayer.axle_intensity(0.0, 2.8, rear, true) == 1.0 and MarksLayer.axle_intensity(0.0, 2.8, front, false) == 1.0 and MarksLayer.axle_intensity(0.0, 0.5, front, false) == 0.0 and MarksLayer.axle_intensity(0.0, 0.5, front, true) > 0.0
			and MarksLayer.axle_intensity(0.0, -1.0, front, false) == 1.0 and MarksLayer.axle_intensity(-0.5, 0.0, rear, false) == 1.0,
		"an axle marks with the largest of its triggers; wheelspin counts only on a driven axle (a ratio of 0.5 on an undriven front is nothing, on a driven one something)",
	)
	_check(
		MarksLayer.axle_driven(false, ArcadeCar.DrivenWheels.RWD) and not MarksLayer.axle_driven(true, ArcadeCar.DrivenWheels.RWD) and MarksLayer.axle_driven(true, ArcadeCar.DrivenWheels.FWD) and not MarksLayer.axle_driven(false, ArcadeCar.DrivenWheels.FWD)
			and MarksLayer.axle_driven(true, ArcadeCar.DrivenWheels.AWD) and MarksLayer.axle_driven(false, ArcadeCar.DrivenWheels.AWD) and ArcadeCar.DRIVEN_WHEELS == ArcadeCar.DrivenWheels.RWD,
		"the driven axle by layout: the rears under RWD (the car's own), the fronts under FWD, both under AWD",
	)
	_check(absf(MarksLayer.alpha_of(1.0) - MarksLayer.ALPHA_SOLID) < 1.0e-9 and MarksLayer.alpha_of(0.0) == 0.0 and MarksLayer.alpha_of(2.0) == MarksLayer.alpha_of(1.0) and MarksLayer.alpha_of(0.5) == snappedf(MarksLayer.ALPHA_SOLID * 0.5, MarksLayer.ALPHA_SNAP) and MarksLayer.alpha_of(0.3333) == snappedf(MarksLayer.alpha_of(0.3333), 0.001), "the alpha is %.2f at an intensity of 1, in a line down to 0, snapped to %.3f" % [MarksLayer.ALPHA_SOLID, MarksLayer.ALPHA_SNAP])
	_check(MarksLayer.LIFETIME_S >= 120.0 and MarksLayer.LIFETIME_S <= 300.0 and MarksLayer.MAX_QUADS == 4096 and MarksLayer.LIFT_M >= 0.02 and MarksLayer.LIFT_M <= 0.03 and MarksLayer.TYRE_WIDTH_REAR > MarksLayer.TYRE_WIDTH_FRONT, "a quad lives minutes (%.0f s), the pool holds %d, the lift is %.3f m, the rears' quads wider than the fronts'" % [MarksLayer.LIFETIME_S, MarksLayer.MAX_QUADS, MarksLayer.LIFT_M])


# =============================================================================
#  The pad: the layer and the drives
# =============================================================================

## The pad stripped of its own marks: the layer's place, its shape, the
## slide (recorded), the grip, the corner, the wheelspin, the lock. Returns
## the slide's records and the recorder's sample lines for the later scenes.
func _check_pad_drives() -> Dictionary:
	var out := {"records": [], "samples": PackedStringArray(), "end": Transform3D.IDENTITY}
	var scene := await _load_pad_stripped()
	if scene == null:
		return out
	var car: ArcadeCar = scene.get_node("Car")
	var pad: TestPad = scene.get_node("TestPad")
	var watch := MarksWatcher.of(self)
	var layer := watch.layer_for(car)
	var layers := _layers_under(root)
	var cars: Array[ArcadeCar] = []
	_cars_under(scene, cars)
	if not _check(layer != null and layers.size() == cars.size() and layers.has(layer) and layer.get_parent() == scene and layer.name == MarksLayer.NODE_NAME and layer.car == car and _attached == cars.size() and watch.live_layers().size() == cars.size(), "the pad without its TyreMarks: one Marks node per car in the whole tree (%d), under the scene root, the watcher's own for the HUD's car" % cars.size()):
		_drop(scene)
		return out
	var recorder := TelemetryWatcher.of(self).recorder_for(car)
	var last := scene.get_child(scene.get_child_count() - 1)
	_check(recorder != null and last is TelemetryRecorder and layer.get_index() == recorder.get_index() - 1, "it stands right in front of the TelemetryRecorder, which stays the scene root's LAST child (index %d of %d)" % [layer.get_index(), scene.get_child_count()])
	_check(layer.surfaces == null and watch.surfaces_of(car) == null and layer.surface_at(0.0, 0.0) == &"road", "no Surfaces node on the pad: every wheel is on road to the gate")
	_check(layer.process_physics_priority == -1 and layer.physics_interpolation_mode == Node.PHYSICS_INTERPOLATION_MODE_OFF and layer.cast_shadow == GeometryInstance3D.SHADOW_CASTING_SETTING_OFF, "it ticks at physics priority -1 (after the bubble, with Surfaces, before the car), no interpolation, no shadow")
	var multimesh := layer.multimesh
	var material := (multimesh.mesh.surface_get_material(0) as BaseMaterial3D) if multimesh != null and multimesh.mesh != null else null
	_check(multimesh != null and multimesh.mesh is QuadMesh and multimesh.use_colors and multimesh.instance_count == MarksLayer.MAX_QUADS and multimesh.visible_instance_count == 0 and layer.get_child_count() == 0 and layer is MultiMeshInstance3D, "one MultiMesh of %d quads with a colour each, none visible yet, no child node, no collision object" % MarksLayer.MAX_QUADS)
	_check(material != null and material.vertex_color_use_as_albedo and material.transparency == BaseMaterial3D.TRANSPARENCY_ALPHA, "the material takes colour and alpha per quad (vertex colour as albedo, alpha blended)")
	_check(layer.quad_count == 0 and layer.laid_total == 0 and layer.ticks > 0 and layer.records().is_empty(), "the pool is empty after %d idle ticks: the car at rest lays nothing" % layer.ticks)

	# The slide, recorded.
	var file := _tmp_dir.path_join("pad_slide_marks_on.jsonl")
	recorder.record_to_file(file)
	var slide := await _slide(car, layer)
	recorder.stop()
	out.samples = _sample_lines(file)
	out.records = layer.records()
	out.end = car.global_transform
	_check(slide.count > 0 and slide.peak_rear_ratio <= -MarksLayer.LOCK_SOLID_RATIO and slide.peak_rear_angle > ArcadeCar.REAR_PEAK_SLIP_ANGLE * MarksLayer.LATERAL_SOLID_PEAKS and out.samples.size() >= slide.ticks, "a handbrake slide from %.0f km/h lays quads: %d of them (the rears locked at %.2f, the tail out to %.3f rad); %d samples recorded over the run-up and the slide" % [slide.entry_speed * 3.6, slide.count, slide.peak_rear_ratio, slide.peak_rear_angle, out.samples.size()])
	var geometry := _geometry(layer, pad)
	_check(geometry.width_off < 0.01 and geometry.height_off <= GROUND_TOLERANCE and geometry.face_up and geometry.lean < 0.01, "every quad is its tyre's width (front %.2f / rear %.2f m; off by %.4f at most), lies %.3f m over the ground the pad shows (off by %.5f m at most), face up, not mirrored" % [MarksLayer.TYRE_WIDTH_FRONT, MarksLayer.TYRE_WIDTH_REAR, geometry.width_off, MarksLayer.LIFT_M, geometry.height_off])
	_check(geometry.shortest >= MarksLayer.MIN_LENGTH_M and geometry.longest < MarksLayer.SPACING_M + slide.max_step + 0.1 and slide.count < slide.wheel_ticks and geometry.in_order, "a streak is a quad every %.1f m, not one a tick (%.2f .. %.2f m long; %d quads from %d wheel-ticks past a threshold), the pool in order, the oldest first" % [MarksLayer.SPACING_M, geometry.shortest, geometry.longest, slide.count, slide.wheel_ticks])
	_check(geometry.alpha_max == MarksLayer.alpha_of(1.0) and geometry.alpha_min > 0.0 and geometry.rear_count > 0, "the locked rears' quads are solid (alpha %.2f at the darkest, %.3f at the faintest; %d rear quads, %d front)" % [geometry.alpha_max, geometry.alpha_min, geometry.rear_count, geometry.front_count])
	var snapped := true
	for record: Dictionary in out.records:
		for value: float in record.pos:
			snapped = snapped and value == snappedf(value, MarksLayer.POSITION_SNAP)
		snapped = snapped and record.alpha == snappedf(record.alpha, MarksLayer.ALPHA_SNAP)
	_check(snapped and out.records.size() == slide.count, "every record's position is snapped to %.3f m and its alpha to %.3f (%d records)" % [MarksLayer.POSITION_SNAP, MarksLayer.ALPHA_SNAP, out.records.size()])
	print("  ", layer.describe())

	# The grip: flat out with TCS, a full pedal with ABS. Nothing.
	layer.clear()
	car.reset_to_spawn()
	await _step(10)
	_check(layer.quad_count == 0 and layer.records().is_empty() and multimesh.visible_instance_count == 0, "clear() empties the pool (%d quads, nothing visible)" % layer.quad_count)
	var laid_before := layer.laid_total
	var peak_drive := 0.0
	var peak_brake := 0.0
	Input.action_press(&"accelerate")
	for frame in GRIP_FRAMES:
		await physics_frame
		peak_drive = maxf(peak_drive, car.rear_slip_ratio)
	Input.action_release(&"accelerate")
	var grip_speed := car.forward_speed
	Input.action_press(&"brake")
	for frame in STOP_FRAMES_MAX:
		await physics_frame
		peak_brake = minf(peak_brake, minf(car.front_slip_ratio, car.rear_slip_ratio))
		if car.forward_speed == 0.0:
			break
	Input.action_release(&"brake")
	await _step(2)
	_check(car.tcs_on and car.abs_on and layer.quad_count == 0 and layer.laid_total == laid_before and grip_speed > 10.0 and car.forward_speed == 0.0 and peak_drive < MarksLayer.spin_onset_ratio() and peak_brake > -MarksLayer.LOCK_ONSET_RATIO, "ZERO quads while the tyres grip: flat out to %.1f m/s with TCS (slip ratio %.3f at most, the onset %.4f) and a full pedal to a stop with ABS (%.3f, the onset -%.1f)" % [grip_speed, peak_drive, MarksLayer.spin_onset_ratio(), peak_brake, MarksLayer.LOCK_ONSET_RATIO])

	# Normal cornering: nothing.
	car.reset_to_spawn()
	await _step(10)
	await _speed_up(car, CORNER_SPEED)
	var peak_front := 0.0
	var peak_rear := 0.0
	Input.action_press(&"steer_left", CORNER_STEER)
	for frame in CORNER_FRAMES:
		await physics_frame
		peak_front = maxf(peak_front, absf(car.front_slip_angle))
		peak_rear = maxf(peak_rear, absf(car.rear_slip_angle))
	Input.action_release(&"steer_left")
	await _step(2)
	_check(layer.quad_count == 0 and layer.laid_total == laid_before and peak_front > 0.03 and peak_front < ArcadeCar.FRONT_PEAK_SLIP_ANGLE * MarksLayer.LATERAL_ONSET_PEAKS and peak_rear < ArcadeCar.REAR_PEAK_SLIP_ANGLE * MarksLayer.LATERAL_ONSET_PEAKS, "ZERO quads in normal cornering: %.2f of full lock from %.0f km/h for %.1f s, the fronts to %.3f rad and the rears to %.3f (the onsets %.3f / %.3f)" % [CORNER_STEER, CORNER_SPEED * 3.6, CORNER_FRAMES / 60.0, peak_front, peak_rear, ArcadeCar.FRONT_PEAK_SLIP_ANGLE * MarksLayer.LATERAL_ONSET_PEAKS, ArcadeCar.REAR_PEAK_SLIP_ANGLE * MarksLayer.LATERAL_ONSET_PEAKS])

	# The launch without TCS: the rears spin and mark in their two tracks.
	layer.clear()
	car.tcs_on = false
	car.reset_to_spawn()
	await _step(10)
	Input.action_press(&"accelerate")
	var spin := await _watch(car, layer, LAUNCH_FRAMES, false)
	Input.action_release(&"accelerate")
	car.tcs_on = true
	await _step(2)
	var spin_records := layer.records()
	var off_track := 0.0
	var spin_fronts := 0
	for record: Dictionary in spin_records:
		off_track = maxf(off_track, absf(absf(float(record.pos[0])) - ArcadeCar.HALF_TRACK))
		if int(record.wheel) < 2:
			spin_fronts += 1
	_check(spin_records.size() > 0 and spin_fronts == 0 and spin.peak_rear_ratio > MarksLayer.SPIN_SOLID_RATIO and spin.front_ticks == 0 and spin.rear_ticks > 0 and off_track < 0.01, "a launch with TCS off lays the rears' wheelspin (slip ratio %.2f at most): %d quads in the two rear tracks (%.3f m off HALF_TRACK at most), none for the fronts" % [spin.peak_rear_ratio, spin_records.size(), off_track])

	# The stop without ABS: the locked fronts.
	layer.clear()
	car.abs_on = false
	car.reset_to_spawn()
	await _step(10)
	await _speed_up(car, LOCK_SPEED)
	Input.action_press(&"brake")
	var stop := await _watch(car, layer, STOP_FRAMES_MAX, true)
	Input.action_release(&"brake")
	car.abs_on = true
	await _step(2)
	var stop_records := layer.records()
	var stop_fronts := 0
	for record: Dictionary in stop_records:
		if int(record.wheel) < 2:
			stop_fronts += 1
	_check(stop_records.size() > 0 and stop_fronts > 0 and stop.peak_front_ratio <= -MarksLayer.LOCK_SOLID_RATIO and stop.locked_way > 10.0 and stop.front_ticks > 0, "a stop with ABS off from %.0f km/h lays the locked fronts (slip ratio %.2f, %.1f m on wheels standing still): %d quads, %d of them the fronts'" % [LOCK_SPEED * 3.6, stop.peak_front_ratio, stop.locked_way, stop_records.size(), stop_fronts])
	_check(_layers_finite(layer), "no NaN / inf in any quad throughout")
	print("  ", layer.describe())

	# The scene goes, the layer with it.
	_drop(scene)
	await _step(1)
	_check(not is_instance_valid(layer) and watch.live_layers().is_empty() and _layers_under(root).is_empty(), "the scene freed, its layer is gone and the watcher holds none")
	return out


## A second scene, the same slide first thing: the same records. Then the
## pool's bound, the fade, the colour stride.
func _check_pad_again(first: Dictionary) -> void:
	var scene := await _load_pad_stripped()
	if scene == null:
		return
	var car: ArcadeCar = scene.get_node("Car")
	var layer := MarksWatcher.of(self).layer_for(car)
	if not _check(layer != null, "the second pad has its layer"):
		_drop(scene)
		return
	var slide := await _slide(car, layer)
	var records := layer.records()
	_report_first_difference(records, first.records, car.global_transform, first.end)
	_check(records.size() == (first.records as Array).size() and records == first.records and car.global_transform == first.end, "DETERMINISM: a second scene instanced fresh and driven the same slide lays the same %d records - positions, alphas, ages, wheels, yaws, lengths - to the bit, the car ending where it ended (%d quads)" % [records.size(), slide.count])

	# The pool's bound.
	layer.clear()
	car.reset_to_spawn()
	await _step(2)
	for i in MarksLayer.MAX_QUADS:
		layer.lay_quad(Vector3(i * 0.01, 0.0, 400.0), Vector3(i * 0.01 + 0.5, 0.0, 400.0), i % 4, 1.0)
	var full := layer.quad_count
	var first_place := layer.quad_transforms[0]
	var second_place := layer.quad_transforms[1]
	var laid_full := layer.laid_total
	var laid := layer.lay_quad(Vector3(0.0, 0.0, 410.0), Vector3(0.5, 0.0, 410.0), 0, 1.0)
	_check(full == MarksLayer.MAX_QUADS and laid and layer.quad_count == MarksLayer.MAX_QUADS and layer.laid_total == laid_full + 1 and layer.multimesh.visible_instance_count == MarksLayer.MAX_QUADS, "the pool is bounded: %d laid, %d live, %d laid in all" % [MarksLayer.MAX_QUADS + 1, layer.quad_count, layer.laid_total])
	_check(layer.quad_transforms[0] != first_place and layer.quad_transforms[0].origin.z == 410.0 and layer.quad_transforms[1] == second_place and layer.oldest() == 1 and (layer.records()[0] as Dictionary).pos[2] == second_place.origin.z, "full, the oldest quad is the one laid over (place 0 moved from z = %.0f to %.0f; place 1 is the oldest now and lies where it lay)" % [first_place.origin.z, layer.quad_transforms[0].origin.z])
	var before := layer.oldest()
	var short := layer.lay_quad(Vector3(1.0, 0.0, 420.0), Vector3(1.01, 0.0, 420.0), 0, 1.0)
	var nan := layer.lay_quad(Vector3(NAN, 0.0, 420.0), Vector3(1.0, 0.0, 420.0), 0, 1.0)
	var faint := layer.lay_quad(Vector3(1.0, 0.0, 420.0), Vector3(2.0, 0.0, 420.0), 0, 0.0)
	_check(not short and not nan and not faint and layer.oldest() == before and _layers_finite(layer), "a quad of no length, not finite, or of no intensity is not laid")

	# The fade.
	layer.clear()
	await _step(2)
	var alpha0 := MarksLayer.alpha_of(0.8)
	layer.lay_quad(Vector3(0.0, 0.0, 430.0), Vector3(0.5, 0.0, 430.0), 3, 0.8)
	await _step(FADE_FRAMES)
	var age := layer.quad_ages[0]
	var alpha := layer.quad_alpha(0)
	# (The instance colours themselves cannot be read back with no window:
	# the headless rendering server keeps none - the record is checked.)
	_check(absf(age - FADE_FRAMES / 60.0) < 1.0e-9 and absf(alpha - alpha0 * (1.0 - age / MarksLayer.LIFETIME_S)) < 1.0e-9 and alpha < alpha0 and layer.quad_count == 1 and layer.multimesh.visible_instance_count == 1, "a quad fades in a line: laid at alpha %.3f, %.4f after %.0f ticks (%.4f s old); one quad drawn" % [alpha0, alpha, FADE_FRAMES, age])
	var lifetime_ticks := ceili(MarksLayer.LIFETIME_S * 60.0)
	await _step(lifetime_ticks - FADE_FRAMES - 2)
	var late_alpha := layer.quad_alpha(0)
	var late_count := layer.quad_count
	await _step(4)
	_check(late_count == 1 and late_alpha > 0.0 and late_alpha < 0.001 and layer.quad_count == 0 and layer.quad_transforms[0] == MarksLayer.NO_QUAD and layer.quad_alpha(0) == 0.0 and layer.records().is_empty(), "at the end of its %.0f s the quad is gone and its place free (alpha %.5f two ticks before)" % [MarksLayer.LIFETIME_S, late_alpha])
	_drop(scene)
	await _step(1)


## FD_MARKS=0: a scene without a layer, the same slide recorded: the same
## samples, byte for byte.
func _check_switched_off(first: Dictionary) -> void:
	var attached_before := _attached
	var scene := await _load_pad_stripped()
	if scene == null:
		return
	var car: ArcadeCar = scene.get_node("Car")
	var watch := MarksWatcher.of(self)
	_check(watch.layer_for(car) == null and _layers_under(root).is_empty() and watch.live_layers().is_empty() and _attached == attached_before and scene.get_child(scene.get_child_count() - 1) is TelemetryRecorder, "FD_MARKS=0: no Marks node anywhere, the watcher holds none, the recorder still the scene root's last child")
	var recorder := TelemetryWatcher.of(self).recorder_for(car)
	var file := _tmp_dir.path_join("pad_slide_marks_off.jsonl")
	recorder.record_to_file(file)
	var slide := await _slide(car, null)
	recorder.stop()
	var samples := _sample_lines(file)
	var first_samples: PackedStringArray = first.samples
	for index in mini(samples.size(), first_samples.size()):
		if samples[index] != first_samples[index]:
			print("  the first differing sample is %d of %d / %d:\n    with the layer: %s\n    without:        %s" % [index, first_samples.size(), samples.size(), first_samples[index], samples[index]])
			break
	_check(samples.size() == first_samples.size() and samples.size() > 100 and samples == first_samples and car.global_transform == first.end, "NO PHYSICS IMPACT: the same slide with no layer writes the same %d telemetry samples byte for byte (the car's position, speed, slips, yaw rate every tick), the car ending where it ended (%.3f, %.3f)" % [samples.size(), car.global_position.x, car.global_position.z])
	_check(slide.count == 0, "and no quad to count")
	_drop(scene)
	await _step(1)


## main.tscn as shipped: the pad's own TyreMarks stands, the watcher defers.
func _check_pad_as_shipped() -> void:
	var attached_before := _attached
	var packed: PackedScene = load(PAD_SCENE)
	await physics_frame
	var scene := packed.instantiate()
	root.add_child(scene)
	await _step(SETTLE_FRAMES)
	var car: ArcadeCar = scene.get_node("Car")
	var own := scene.get_node_or_null("TyreMarks") as TyreMarks
	var watch := MarksWatcher.of(self)
	_check(own != null and own.car == car and MarksWatcher.has_own_marks(scene, car) and watch.layer_for(car) == null and _layers_under(root).is_empty() and _attached == attached_before and scene.get_child(scene.get_child_count() - 1) is TelemetryRecorder, "main.tscn as shipped keeps its own TyreMarks (the smoke test's) and gets no second layer; the recorder the last child")
	_drop(scene)
	await _step(1)


## A car straight under the root: a layer under the root, no Surfaces node;
## gone when the car leaves.
func _check_bare_car() -> void:
	var watch := MarksWatcher.of(self)
	var car: ArcadeCar = (load(CAR_SCENE) as PackedScene).instantiate()
	root.add_child(car)
	await _step(SETTLE_FRAMES)
	var layer := watch.layer_for(car)
	var layers := _layers_under(root)
	_check(layer != null and layers.size() == 1 and layers[0] == layer and layer.get_parent() == root and layer.car == car and layer.surfaces == null and layer.surface_at(0.0, 0.0) == &"road", "a bare car under the root gets one layer, under the root, no Surfaces node (all road to the gate)")
	root.remove_child(car)
	await _step(1)
	_check(not is_instance_valid(layer) and watch.layer_for(car) == null and watch.live_layers().is_empty() and _layers_under(root).is_empty(), "the car out of the tree: its layer freed, the watcher holds none")
	car.free()


# =============================================================================
#  The Ring
# =============================================================================

func _check_ring() -> void:
	var packed: PackedScene = load(RING_SCENE)
	if not _check(packed != null, "the Ring scene loads"):
		return
	await physics_frame
	var scene := packed.instantiate()
	root.add_child(scene)
	await _step(SETTLE_FRAMES)
	var car: ArcadeCar = scene.get_node("Car")
	var road: RoadBuilder = scene.get_node("Road")
	var surfaces: Surfaces = scene.get_node("Surfaces")
	var watch := MarksWatcher.of(self)
	var layer := watch.layer_for(car)
	var recorder := TelemetryWatcher.of(self).recorder_for(car)
	if not _check(layer != null and layer.get_parent() == scene and _layers_under(root).size() == 1 and recorder != null and scene.get_child(scene.get_child_count() - 1) is TelemetryRecorder and layer.get_index() == recorder.get_index() - 1, "THE RING HAS MARKS: one layer under EifelRing, in front of the recorder (the last child)"):
		_drop(scene)
		return
	_check(layer.surfaces == surfaces and watch.surfaces_of(car) == surfaces and car.road_profile is RingProfile and layer.quad_count == 0, "it holds the scene's Surfaces node (the gate) and reads the RingProfile the car drives on; nothing laid at the spawn")

	# The slide on the straight's tarmac.
	var strip: RoadBuilder.Strip = road.strip(STRAIGHT)
	var centre := strip.offsets.size() / 2
	var a := strip.vertex(STRAIGHT_SECTION, centre)
	var b := strip.vertex(STRAIGHT_SECTION + 1, centre)
	car.reset_to(_pose(a.x, a.z, Vector2(b.x - a.x, b.z - a.z).normalized()))
	await _step(SETTLE_FRAMES)
	var slide := await _slide(car, layer)
	var records := layer.records()
	var on_road := 0
	var height_off := 0.0
	for record: Dictionary in records:
		var x := float(record.pos[0])
		var z := float(record.pos[2])
		if surfaces.classify(x, z) == &"road":
			on_road += 1
		height_off = maxf(height_off, absf(float(record.pos[1]) - (car.road_profile.sample_height(x, z) + MarksLayer.LIFT_M)))
	_check(records.size() > 0 and slide.peak_rear_ratio <= -MarksLayer.LOCK_SOLID_RATIO and on_road == records.size() and height_off <= GROUND_TOLERANCE_RING, "a handbrake slide from %.0f km/h on %s lays %d quads, every one on road (Surfaces.classify at its origin), %.3f m over the RingProfile's height (off by %.5f m at most)" % [slide.entry_speed * 3.6, STRAIGHT, records.size(), MarksLayer.LIFT_M, height_off])
	var geometry := _geometry(layer, null)
	_check(geometry.width_off < 0.01 and geometry.face_up and geometry.lean < 0.05 and geometry.alpha_max == MarksLayer.alpha_of(1.0), "each its tyre's width, face up (the normal leaning %.4f at most on the straight's grade), the locked rears solid" % geometry.lean)
	print("  ", layer.describe())

	# The grass gate: a TCS-off launch on the grass spot, then the handbrake
	# pulled with the wheel turned from whatever speed that made.
	var laid_before := layer.laid_total
	car.reset_to(_pose(GRASS_SPOT.x, GRASS_SPOT.y, GRASS_HEADING))
	await _step(SETTLE_FRAMES)
	var first_wheels: Array[StringName] = surfaces.wheel_surfaces.duplicate()
	car.tcs_on = false
	Input.action_press(&"accelerate")
	var spin := await _watch(car, layer, LAUNCH_FRAMES, false)
	Input.action_release(&"accelerate")
	car.tcs_on = true
	var grass_speed := car.forward_speed
	var grass_ratio := 0.0
	var grass_angle := 0.0
	Input.action_press(&"steer_left", SLIDE_STEER)
	Input.action_press(&"handbrake")
	for frame in SLIDE_FRAMES + SLIDE_FRAMES:
		if frame == SLIDE_FRAMES:
			Input.action_release(&"handbrake")
			Input.action_release(&"steer_left")
		await physics_frame
		grass_ratio = minf(grass_ratio, car.rear_slip_ratio)
		grass_angle = maxf(grass_angle, absf(car.rear_slip_angle))
	await _step(2)
	var wheels_after: Array[StringName] = surfaces.wheel_surfaces.duplicate()
	var past_onset: bool = spin.peak_rear_ratio > MarksLayer.spin_onset_ratio() or grass_ratio <= -MarksLayer.LOCK_ONSET_RATIO or grass_angle > ArcadeCar.REAR_PEAK_SLIP_ANGLE * MarksLayer.LATERAL_ONSET_PEAKS
	_check(first_wheels == [&"grass", &"grass", &"grass", &"grass"] and wheels_after == first_wheels and past_onset and layer.laid_total == laid_before and layer.quad_count == records.size(), "THE GATE: on the grass spot (every wheel on grass before and after) a TCS-off launch (rear slip ratio %.2f, to %.1f m/s) and a handbrake slide (%.2f, the tail out to %.3f rad) lay NOTHING - %d quads still, the tarmac's" % [spin.peak_rear_ratio, grass_speed, grass_ratio, grass_angle, layer.quad_count])
	print("  ", layer.describe())
	_drop(scene)
	await _step(1)
	_check(watch.live_layers().is_empty() and _layers_under(root).is_empty(), "the Ring freed, its layer gone")


# =============================================================================
#  The drives
# =============================================================================

## The slide: up to SLIDE_SPEED, SLIDE_STEER left and the handbrake for
## SLIDE_FRAMES, everything let go for SLIDE_WATCH_FRAMES. Returns the
## entry speed, the rears' peak slip ratio (the most negative) and angle,
## the longest step of a tick, the wheel-ticks past a threshold, the ticks
## run and what the layer holds (0 without one).
func _slide(car: ArcadeCar, layer: MarksLayer) -> Dictionary:
	await _speed_up(car, SLIDE_SPEED)
	var out := {"entry_speed": car.forward_speed, "peak_rear_ratio": 0.0, "peak_rear_angle": 0.0, "max_step": 0.0, "wheel_ticks": 0, "ticks": 0, "count": 0}
	Input.action_press(&"steer_left", SLIDE_STEER)
	Input.action_press(&"handbrake")
	for frame in SLIDE_FRAMES + SLIDE_WATCH_FRAMES:
		if frame == SLIDE_FRAMES:
			Input.action_release(&"handbrake")
			Input.action_release(&"steer_left")
		var before := car.global_position
		await physics_frame
		out.ticks += 1
		out.max_step = maxf(out.max_step, car.global_position.distance_to(before))
		out.peak_rear_ratio = minf(out.peak_rear_ratio, car.rear_slip_ratio)
		out.peak_rear_angle = maxf(out.peak_rear_angle, absf(car.rear_slip_angle))
		if MarksLayer.axle_intensity(car.front_slip_angle, car.front_slip_ratio, ArcadeCar.FRONT_PEAK_SLIP_ANGLE, false) > 0.0:
			out.wheel_ticks += 2
		if MarksLayer.axle_intensity(car.rear_slip_angle, car.rear_slip_ratio, ArcadeCar.REAR_PEAK_SLIP_ANGLE, true) > 0.0:
			out.wheel_ticks += 2
	await _step(2)
	out.ticks += 2
	if layer != null:
		out.count = layer.quad_count
	return out


## Accelerates in a straight line from where the car is to `speed`, then lifts.
func _speed_up(car: ArcadeCar, speed: float) -> void:
	Input.action_press(&"accelerate")
	for frame in SPEED_UP_FRAMES_MAX:
		if car.forward_speed >= speed:
			break
		await physics_frame
	Input.action_release(&"accelerate")


## Steps `frames` ticks (to a standstill at the latest, if `until_rest`):
## the ticks each axle was past a threshold, the way on fronts standing
## still [m], the peak slip ratios.
func _watch(car: ArcadeCar, _layer: MarksLayer, frames: int, until_rest: bool) -> Dictionary:
	var out := {"front_ticks": 0, "rear_ticks": 0, "locked_way": 0.0, "peak_rear_ratio": 0.0, "peak_front_ratio": 0.0}
	for frame in frames:
		var before := car.global_position
		await physics_frame
		var way := car.global_position.distance_to(before)
		if MarksLayer.axle_intensity(car.front_slip_angle, car.front_slip_ratio, ArcadeCar.FRONT_PEAK_SLIP_ANGLE, false) > 0.0:
			out.front_ticks += 1
			if car.front_omega == 0.0:
				out.locked_way += way
		if MarksLayer.axle_intensity(car.rear_slip_angle, car.rear_slip_ratio, ArcadeCar.REAR_PEAK_SLIP_ANGLE, true) > 0.0:
			out.rear_ticks += 1
		out.peak_rear_ratio = maxf(out.peak_rear_ratio, car.rear_slip_ratio)
		out.peak_front_ratio = minf(out.peak_front_ratio, car.front_slip_ratio)
		if until_rest and car.forward_speed == 0.0:
			break
	return out


# =============================================================================
#  Helpers
# =============================================================================

## main.tscn with its own TyreMarks node freed before it enters the tree:
## the pad the watcher's layer goes on.
func _load_pad_stripped() -> Node:
	var packed: PackedScene = load(PAD_SCENE)
	if not _check(packed != null, "main.tscn loads"):
		return null
	# Every scene enters from the same phase of a physics frame (the offroad
	# test's idiom): the first is loaded from a deferred call otherwise.
	await physics_frame
	var scene := packed.instantiate()
	var own := scene.get_node_or_null("TyreMarks")
	if own != null:
		scene.remove_child(own)
		own.free()
	root.add_child(scene)
	await _step(SETTLE_FRAMES)
	return scene


## The first record that differs between two drives, and the two end
## transforms where they differ: printed for the eye, before the verdict.
func _report_first_difference(records: Array[Dictionary], other: Variant, end: Transform3D, other_end: Transform3D) -> void:
	var others: Array = other
	for index in mini(records.size(), others.size()):
		if records[index] != others[index]:
			print("  the first differing record is %d of %d / %d:\n    first:  %s\n    second: %s" % [index, others.size(), records.size(), others[index], records[index]])
			break
	if end != other_end:
		print("  the car ended at %s (first) against %s (second)" % [other_end, end])


## A yaw-only pose at (x, z) with the nose along `direction`, origin.y 0
## (the offroad test's).
func _pose(x: float, z: float, direction: Vector2) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, atan2(-direction.x, -direction.y)), Vector3(x, 0.0, z))


## The live quads' shape: how far off its tyre's width the widest is, how far
## off LIFT_M over the pad's ground (with a pad), face up and not mirrored,
## the lean of the normal, the shortest and longest, the pool's order, the
## alpha range, the count per axle.
func _geometry(layer: MarksLayer, pad: TestPad) -> Dictionary:
	var out := {"width_off": 0.0, "height_off": 0.0, "face_up": true, "lean": 0.0, "shortest": INF, "longest": 0.0, "in_order": true, "alpha_max": 0.0, "alpha_min": INF, "front_count": 0, "rear_count": 0}
	var slot := layer.oldest()
	var previous_age := INF
	for i in layer.quad_count:
		var lie := layer.quad_transforms[slot]
		var wheel := layer.quad_wheels[slot]
		var width: float = MarksLayer.TYRE_WIDTH_FRONT if wheel < 2 else MarksLayer.TYRE_WIDTH_REAR
		out.width_off = maxf(out.width_off, absf(lie.basis.x.length() - width))
		if pad != null:
			out.height_off = maxf(out.height_off, absf(lie.origin.y - pad.elevation_height(lie.origin.x, lie.origin.z) - MarksLayer.LIFT_M))
		out.face_up = out.face_up and lie.basis.determinant() > 0.0 and lie.basis.y.dot(Vector3.UP) > 0.0
		out.lean = maxf(out.lean, 1.0 - lie.basis.y.normalized().dot(Vector3.UP))
		out.shortest = minf(out.shortest, lie.basis.z.length())
		out.longest = maxf(out.longest, lie.basis.z.length())
		out.in_order = out.in_order and layer.quad_ages[slot] <= previous_age
		previous_age = layer.quad_ages[slot]
		out.alpha_max = maxf(out.alpha_max, layer.quad_alphas[slot])
		out.alpha_min = minf(out.alpha_min, layer.quad_alphas[slot])
		if wheel < 2:
			out.front_count += 1
		else:
			out.rear_count += 1
		slot = (slot + 1) % MarksLayer.MAX_QUADS
	return out


func _layers_finite(layer: MarksLayer) -> bool:
	for slot in MarksLayer.MAX_QUADS:
		if not layer.quad_transforms[slot].is_finite() or not is_finite(layer.quad_ages[slot]) or not is_finite(layer.quad_alphas[slot]):
			return false
	return true


## Every ArcadeCar under `node`, `node` itself included.
func _cars_under(node: Node, out: Array[ArcadeCar]) -> void:
	if node is ArcadeCar:
		out.append(node)
	for child in node.get_children():
		_cars_under(child, out)


## Every MarksLayer node under `node`, `node` itself included.
func _layers_under(node: Node) -> Array[MarksLayer]:
	var out: Array[MarksLayer] = []
	_collect_layers(node, out)
	return out


func _collect_layers(node: Node, out: Array[MarksLayer]) -> void:
	if node is MarksLayer:
		out.append(node)
	for child in node.get_children():
		_collect_layers(child, out)


## The sample lines of a recorder's file (the ones with t_session_s), as written.
func _sample_lines(file: String) -> PackedStringArray:
	var out := PackedStringArray()
	for raw in FileAccess.get_file_as_string(file).split("\n"):
		if raw.contains("\"t_session_s\""):
			out.append(raw)
	return out


func _drop(scene: Node) -> void:
	root.remove_child(scene)
	scene.free()


func _step(frames: int) -> void:
	for i in frames:
		await physics_frame


func _remove_tmp() -> void:
	if not DirAccess.dir_exists_absolute(_tmp_dir):
		return
	for file_name in DirAccess.get_files_at(_tmp_dir):
		DirAccess.remove_absolute(_tmp_dir.path_join(file_name))
	DirAccess.remove_absolute(_tmp_dir)


func _check(condition: bool, description: String) -> bool:
	if condition:
		print("  ok    ", description)
	else:
		_failures += 1
		printerr("  FAIL  ", description)
	return condition


func _finish() -> void:
	Input.action_release(&"accelerate")
	Input.action_release(&"brake")
	Input.action_release(&"handbrake")
	Input.action_release(&"steer_left")
	if _failures == 0:
		print("MARKS TEST PASSED")
	else:
		print("MARKS TEST FAILED: %d check(s) failed" % _failures)
	quit(1 if _failures > 0 else 0)

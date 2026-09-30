extends SceneTree
## Headless sound test (SOUND-1, backlog U-1: the game was completely
## silent). Run via tests/run_tests.sh, or:
##
##   godot --headless --path . --import
##   godot --headless --fixed-fps 60 --path . --script res://tests/sound_test.gd
##
## THE WATCHER (scripts/sound_watch.gd, the SoundWatch autoload): registered,
## under the root after TelemetryWatch / MarksWatch / ShellsWatch and before
## MissionRunner, on node_added; the FD_SOUND switch ("0" off, "1" on, unset
## off with no window - this suite's default, so no other test sees a sound
## node or an audio player). THE BUFFERS (scripts/sound.gd, SoundNode): three
## 16-bit mono loops of BUFFER_SAMPLES at MIX_RATE, looped end to end, built
## once and shared, the same bytes when built again, normalised to the peak,
## the engine's and the squeal's starting at zero. THE MAPPING, pure and
## snapped to 0.001: the engine's pitch 1 at idle and 2.5 at the redline
## (ArcadeCar's own numbers) and its volume -18 dB at idle with the pedal up
## to -8 dB at full load, MUTE_DB with the engine stopped; the rumble silent
## at rest on any surface, the speed wash alone on tarmac, gravel's drag and
## grip deficit louder at the same speed, -6 dB at the ceiling; the squeal
## MarksLayer's own triggers (called, not re-declared: a locked front, a
## spinning driven rear, an undriven front's spin nothing), muted at no
## intensity and under 1.5 m/s, -4 dB at solid. A BARE CAR under the root
## (FD_SOUND=1): one Sound node under the root with three players on the
## shared streams; every public field the node reads written straight on the
## car (engine_rpm, throttle_pedal, engine_running, the three surface inputs,
## the four slip numbers, forward_speed) and the mapped values following one
## tick later (the node ticks at priority -1, before the car's own tick
## overwrites the reads); never double-attached; freed with the car; a car
## added and freed in one frame leaves nothing and no error. DETERMINISM: two
## nodes fed the same reads carry the same mapped values to the bit. THE
## SWITCH on a car: "0" and unset give no node headless, "1" does. THE PAD
## (main.tscn as shipped, loaded once at a time, the store off so the world
## map never auto-opens and never pauses the tree): one Sound node per car
## under the scene root in front of the TelemetryRecorder (the root's LAST
## child), no other audio in the shipped scene (the has_own_sound guard is
## future-proofing), the marks test's handbrake slide from 60 km/h recorded:
## the engine note rises through the run-up, the surface channel is the wash
## alone every tick (the pad is all tarmac), the locked rears squeal solid.
## FD_SOUND=0: a second pad (the first freed) gets no node, and its recorder's
## samples of the same slide are byte-identical to the first's - the sound
## never touches the car.
##
## The store pinned off (FD_TELEMETRY=0, the marks test's idiom); FD_SOUND
## restored at the end. Exits 0 on success, 1 on any failed check.

const PAD_SCENE := "res://scenes/main.tscn"
const CAR_SCENE := "res://scenes/car.tscn"

## Physics frames to let a scene settle after a load (the watcher's attach
## is one deferred call).
const SETTLE_FRAMES := 20

## The slide (the marks test's, the smoke test's marks slide): up to this
## speed [m/s], then SLIDE_STEER of left steering and the handbrake for
## SLIDE_FRAMES, then everything let go for SLIDE_WATCH_FRAMES.
const SLIDE_SPEED := 16.5
const SLIDE_STEER := 0.3
const SLIDE_FRAMES := 40
const SLIDE_WATCH_FRAMES := 120
const SPEED_UP_FRAMES_MAX := 600

## Where this run writes: a tmp dir of its own, removed at the end.
const TMP_DIR_PREFIX := "/tmp/fd-SOUND-"

## A player's property (a 32-bit float) against the node's double.
const PLAYER_TOLERANCE := 1.0e-5

## The reads two nodes are fed for the determinism pin.
const SAME_READS := {"rpm": 4321.5, "throttle": 0.37, "running": true, "grip_front": 0.55, "grip_rear": 0.8, "drag": 2.2, "speed": 17.3, "front_angle": 0.2, "front_ratio": -0.6, "rear_angle": 0.05, "rear_ratio": 0.7}

var _failures := 0
var _tmp_dir := ""
var _sound_env_before := ""
var _attached := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	OS.set_environment("FD_TELEMETRY", "0")
	_sound_env_before = OS.get_environment(SoundWatcher.ENV_VAR)
	_tmp_dir = TMP_DIR_PREFIX + str(OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(_tmp_dir)
	print("-- the watcher")
	if not _check_watcher():
		_finish()
		return
	print("-- the buffers")
	_check_buffers()
	print("-- the mapping")
	_check_mapping()
	OS.set_environment(SoundWatcher.ENV_VAR, "1")
	print("-- a bare car: the node, the reads, the mapped values")
	await _check_bare_car()
	print("-- two bare cars: determinism")
	await _check_determinism()
	print("-- the switch on a car")
	await _check_switch()
	OS.set_environment(SoundWatcher.ENV_VAR, "1")
	print("-- the pad: the node in front of the recorder, the slide recorded")
	var first := await _check_pad()
	print("-- FD_SOUND=0: no node, the same slide to the bit")
	OS.set_environment(SoundWatcher.ENV_VAR, "0")
	await _check_switched_off(first)
	OS.set_environment(SoundWatcher.ENV_VAR, _sound_env_before)
	_check(OS.get_environment(SoundWatcher.ENV_VAR) == _sound_env_before, "FD_SOUND restored to what it was (%s)" % ("unset" if _sound_env_before == "" else _sound_env_before))
	_remove_tmp()
	_finish()


# =============================================================================
#  The watcher
# =============================================================================

func _check_watcher() -> bool:
	var watch := SoundWatcher.of(self)
	var registered := String(ProjectSettings.get_setting("autoload/%s" % SoundWatcher.AUTOLOAD_NAME, "")) == "*res://scripts/sound_watch.gd"
	if not _check(watch != null and registered and watch.get_parent() == root and watch.name == SoundWatcher.AUTOLOAD_NAME and (watch.get_script() as Script).resource_path == "res://scripts/sound_watch.gd", "the SoundWatch autoload is registered (project.godot) and stands under the root, scripts/sound_watch.gd"):
		return false
	var telemetry := TelemetryWatcher.of(self)
	var marks := MarksWatcher.of(self)
	var shells := root.get_node_or_null("ShellsWatch")
	var runner := root.get_node_or_null("MissionRunner")
	_check(telemetry != null and telemetry.get_index() < watch.get_index() and marks != null and marks.get_index() < watch.get_index() and shells != null and shells.get_index() < watch.get_index() and runner != null and watch.get_index() < runner.get_index(), "it stands after TelemetryWatch, MarksWatch and ShellsWatch under the root (registered after them: its attach runs after the recorder's) and before MissionRunner, which stays last")
	watch.sound_attached.connect(func(_sound: SoundNode) -> void: _attached += 1)
	_check(node_added.is_connected(watch._on_node_added) and watch.live_sounds().is_empty() and _sounds_under(root).is_empty() and _players_under(root).is_empty(), "it watches the tree's node_added, and holds no node while there is no car (no Sound node, no audio player anywhere in the tree)")
	var was := OS.get_environment(SoundWatcher.ENV_VAR)
	OS.set_environment(SoundWatcher.ENV_VAR, "")
	var unset_headless := SoundWatcher.should_attach()
	OS.set_environment(SoundWatcher.ENV_VAR, "0")
	var off := SoundWatcher.should_attach()
	OS.set_environment(SoundWatcher.ENV_VAR, "1")
	var on := SoundWatcher.should_attach()
	OS.set_environment(SoundWatcher.ENV_VAR, was)
	_check(not unset_headless and not off and on and DisplayServer.get_name() == "headless", "THE SWITCH: FD_SOUND unset is off with no window (the suite's default: no other test sees a node), \"0\" is off, \"1\" is on")
	return true


# =============================================================================
#  The buffers
# =============================================================================

func _check_buffers() -> void:
	var streams := SoundNode.buffers()
	var again := SoundNode.buffers()
	var names: Array[String] = [SoundNode.ENGINE_PLAYER, SoundNode.SURFACE_PLAYER, SoundNode.SKID_PLAYER]
	var shared := streams.size() == 3 and again.size() == 3
	for player_name in names:
		shared = shared and streams.has(player_name) and streams[player_name] is AudioStreamWAV and again[player_name] == streams[player_name]
	_check(shared, "three streams (%s), built once and shared: buffers() hands out the same instances again" % ", ".join(names))
	var shape := true
	var peaks := {}
	for player_name in names:
		var stream: AudioStreamWAV = streams[player_name]
		shape = shape and stream.format == AudioStreamWAV.FORMAT_16_BITS and stream.mix_rate == SoundNode.MIX_RATE and not stream.stereo and stream.loop_mode == AudioStreamWAV.LOOP_FORWARD and stream.loop_begin == 0 and stream.loop_end == SoundNode.BUFFER_SAMPLES and stream.data.size() == SoundNode.BUFFER_SAMPLES * 2
		var peak := 0
		for n in SoundNode.BUFFER_SAMPLES:
			peak = maxi(peak, absi(stream.data.decode_s16(n * 2)))
		peaks[player_name] = peak
	_check(shape, "each is 16-bit mono PCM at %d Hz, %d samples (%.1f s), looped forward end to end (loop_begin 0, loop_end %d)" % [SoundNode.MIX_RATE, SoundNode.BUFFER_SAMPLES, SoundNode.BUFFER_SAMPLES / float(SoundNode.MIX_RATE), SoundNode.BUFFER_SAMPLES])
	var full := roundi(SoundNode.BUFFER_PEAK * 32767.0)
	_check(absi(int(peaks[SoundNode.ENGINE_PLAYER]) - full) <= 1 and absi(int(peaks[SoundNode.SURFACE_PLAYER]) - full) <= 1 and absi(int(peaks[SoundNode.SKID_PLAYER]) - full) <= 1, "each is normalised to %.2f of full scale (peaks %d / %d / %d, %d expected)" % [SoundNode.BUFFER_PEAK, peaks[SoundNode.ENGINE_PLAYER], peaks[SoundNode.SURFACE_PLAYER], peaks[SoundNode.SKID_PLAYER], full])
	var engine: AudioStreamWAV = streams[SoundNode.ENGINE_PLAYER]
	var skid: AudioStreamWAV = streams[SoundNode.SKID_PLAYER]
	var hz := float(SoundNode.MIX_RATE) / float(SoundNode.BUFFER_SAMPLES)
	var whole := true
	for cycles: int in SoundNode.ENGINE_CYCLES + SoundNode.SURFACE_CYCLES + SoundNode.SKID_CYCLES:
		whole = whole and cycles > 0
	_check(whole and engine.data.decode_s16(0) == 0 and skid.data.decode_s16(0) == 0 and absf(SoundNode.ENGINE_CYCLES[0] * hz - 56.0) < 1.0e-9 and absf(SoundNode.SKID_CYCLES[0] * hz - 800.0) < 1.0e-9 and SoundNode.SURFACE_CYCLES[0] * hz >= 60.0 and SoundNode.SURFACE_CYCLES[SoundNode.SURFACE_CYCLES.size() - 1] * hz <= 230.0 and SoundNode.SURFACE_CYCLES.size() >= 16, "every partial is a whole number of cycles over the buffer (the grid %.0f Hz): the engine's stack from %.0f Hz, the squeal's from %.0f Hz, the rumble %d partials over %.0f..%.0f Hz; the engine and the squeal start at zero (seamless loops)" % [hz, SoundNode.ENGINE_CYCLES[0] * hz, SoundNode.SKID_CYCLES[0] * hz, SoundNode.SURFACE_CYCLES.size(), SoundNode.SURFACE_CYCLES[0] * hz, SoundNode.SURFACE_CYCLES[SoundNode.SURFACE_CYCLES.size() - 1] * hz])
	var rebuilt := SoundNode.build_buffers()
	var same := rebuilt.size() == 3
	var distinct := true
	for player_name in names:
		same = same and rebuilt[player_name] != streams[player_name] and (rebuilt[player_name] as AudioStreamWAV).data == (streams[player_name] as AudioStreamWAV).data
	distinct = engine.data != skid.data and engine.data != (streams[SoundNode.SURFACE_PLAYER] as AudioStreamWAV).data
	_check(same and distinct, "DETERMINISM: built again, three new streams carry the same bytes; the three buffers differ from each other")


# =============================================================================
#  The mapping
# =============================================================================

func _check_mapping() -> void:
	var idle: float = ArcadeCar.IDLE_RPM
	var limiter: float = ArcadeCar.REDLINE_RPM
	var mid := snappedf(lerpf(SoundNode.ENGINE_PITCH_IDLE, SoundNode.ENGINE_PITCH_LIMITER, 0.5), SoundNode.SNAP)
	var odd := SoundNode.engine_pitch_of(3333.3, idle, limiter)
	_check(
		idle == 900.0 and limiter == 7200.0 and SoundNode.engine_pitch_of(idle, idle, limiter) == _snap(SoundNode.ENGINE_PITCH_IDLE) and SoundNode.engine_pitch_of(limiter, idle, limiter) == _snap(SoundNode.ENGINE_PITCH_LIMITER)
			and SoundNode.engine_pitch_of((idle + limiter) * 0.5, idle, limiter) == mid and SoundNode.engine_pitch_of(limiter + 2000.0, idle, limiter) == _snap(SoundNode.ENGINE_PITCH_LIMITER)
			and SoundNode.engine_pitch_of(0.0, idle, limiter) < SoundNode.ENGINE_PITCH_IDLE and SoundNode.engine_pitch_of(0.0, idle, limiter) >= SoundNode.ENGINE_PITCH_MIN and SoundNode.engine_pitch_of(-1.0e6, idle, limiter) == _snap(SoundNode.ENGINE_PITCH_MIN)
			and odd == snappedf(odd, SoundNode.SNAP) and odd > SoundNode.ENGINE_PITCH_IDLE and odd < mid and SoundNode.engine_pitch_of(5000.0, idle, idle) == _snap(SoundNode.ENGINE_PITCH_IDLE)
			and absf(SoundNode.engine_pitch_of(idle, idle, limiter) - SoundNode.ENGINE_PITCH_IDLE) < 1.0e-9 and absf(SoundNode.engine_pitch_of(limiter, idle, limiter) - SoundNode.ENGINE_PITCH_LIMITER) < 1.0e-9,
		"ENGINE PITCH: %.1f at idle (%.0f rpm), %.1f at the redline (%.0f), a line between (%.3f halfway), clamped at the limiter, under idle it drops (%.3f at 0 rpm, never under %.2f), snapped to %.3f" % [SoundNode.ENGINE_PITCH_IDLE, idle, SoundNode.ENGINE_PITCH_LIMITER, limiter, mid, SoundNode.engine_pitch_of(0.0, idle, limiter), SoundNode.ENGINE_PITCH_MIN, SoundNode.SNAP],
	)
	var half := SoundNode.engine_db_of(3000.0, 0.5, true, idle, limiter)
	var full_load := _snap(SoundNode.ENGINE_DB_IDLE + SoundNode.ENGINE_DB_RPM_SPAN + SoundNode.ENGINE_DB_LOAD_SPAN)
	_check(
		SoundNode.engine_db_of(idle, 0.0, true, idle, limiter) == _snap(SoundNode.ENGINE_DB_IDLE) and SoundNode.engine_db_of(limiter, 1.0, true, idle, limiter) == full_load
			and SoundNode.engine_db_of(limiter, 0.0, true, idle, limiter) == _snap(SoundNode.ENGINE_DB_IDLE + SoundNode.ENGINE_DB_RPM_SPAN) and SoundNode.engine_db_of(idle, 1.0, true, idle, limiter) == _snap(SoundNode.ENGINE_DB_IDLE + SoundNode.ENGINE_DB_LOAD_SPAN)
			and SoundNode.engine_db_of(idle, 2.0, true, idle, limiter) == SoundNode.engine_db_of(idle, 1.0, true, idle, limiter) and SoundNode.engine_db_of(0.0, 0.0, true, idle, limiter) == _snap(SoundNode.ENGINE_DB_IDLE) and SoundNode.engine_db_of(limiter * 2.0, 0.0, true, idle, limiter) == _snap(SoundNode.ENGINE_DB_IDLE + SoundNode.ENGINE_DB_RPM_SPAN)
			and absf(SoundNode.engine_db_of(idle, 0.0, true, idle, limiter) - SoundNode.ENGINE_DB_IDLE) < 1.0e-9 and absf(full_load - -8.0) < 1.0e-9
			and half > SoundNode.ENGINE_DB_IDLE and half < SoundNode.ENGINE_DB_IDLE + SoundNode.ENGINE_DB_RPM_SPAN + SoundNode.ENGINE_DB_LOAD_SPAN and half == snappedf(half, SoundNode.SNAP)
			and SoundNode.engine_db_of(limiter, 1.0, false, idle, limiter) == SoundNode.MUTE_DB and SoundNode.engine_db_of(idle, 0.0, false, idle, limiter) == SoundNode.MUTE_DB,
		"ENGINE VOLUME: %.0f dB at idle with the pedal up, %.0f dB more at the limiter, %.0f dB more at full throttle (%.0f dB at full load; the pedal clamped to 1, the rpm share to 0..1), muted (%.0f dB) with the engine stopped" % [SoundNode.ENGINE_DB_IDLE, SoundNode.ENGINE_DB_RPM_SPAN, SoundNode.ENGINE_DB_LOAD_SPAN, SoundNode.ENGINE_DB_IDLE + SoundNode.ENGINE_DB_RPM_SPAN + SoundNode.ENGINE_DB_LOAD_SPAN, SoundNode.MUTE_DB],
	)
	_check(SoundNode.db_of(0.0, -4.0) == SoundNode.MUTE_DB and SoundNode.db_of(-1.0, -4.0) == SoundNode.MUTE_DB and SoundNode.db_of(1.0e-9, -4.0) == SoundNode.MUTE_DB and SoundNode.db_of(1.0, -4.0) == _snap(-4.0) and SoundNode.db_of(2.0, -4.0) == _snap(-4.0) and absf(SoundNode.db_of(1.0, -4.0) - -4.0) < 1.0e-9 and SoundNode.db_of(0.5, -4.0) == snappedf(-4.0 + linear_to_db(0.5), SoundNode.SNAP) and SoundNode.db_of(0.5, -4.0) > SoundNode.MUTE_DB and SoundNode.db_of(0.5, -4.0) < -4.0, "a channel's volume is its ceiling plus linear_to_db(level), snapped, never under %.0f dB (no level, a vanishing level: muted), never over the ceiling (a level over 1 is 1)" % SoundNode.MUTE_DB)
	var road10 := SoundNode.surface_db_of(0.0, 1.0, 10.0)
	var road10_expected := snappedf(SoundNode.SURFACE_DB_MAX + linear_to_db(10.0 / SoundNode.SURFACE_WASH_SPEED * SoundNode.SURFACE_WASH_LEVEL), SoundNode.SNAP)
	var gravel10 := SoundNode.surface_db_of(1.6, 0.6, 10.0)
	var gravel5 := SoundNode.surface_db_of(1.6, 0.6, 5.0)
	_check(
		SoundNode.surface_db_of(0.0, 1.0, 0.0) == SoundNode.MUTE_DB and SoundNode.surface_db_of(1.6, 0.6, 0.0) == SoundNode.MUTE_DB and SoundNode.surface_db_of(3.0, 0.0, 0.0) == SoundNode.MUTE_DB
			and road10 == road10_expected and road10 > SoundNode.MUTE_DB and SoundNode.surface_db_of(0.0, 1.0, -10.0) == road10 and SoundNode.surface_db_of(0.0, 1.0, 20.0) > road10
			and gravel10 > road10 and SoundNode.surface_db_of(1.6, 1.0, 10.0) > road10 and SoundNode.surface_db_of(0.0, 0.6, 10.0) > road10 and gravel10 > SoundNode.surface_db_of(1.6, 1.0, 10.0) and gravel10 > SoundNode.surface_db_of(0.0, 0.6, 10.0)
			and gravel5 < gravel10 and gravel5 > SoundNode.surface_db_of(0.0, 1.0, 5.0) and SoundNode.surface_db_of(SoundNode.SURFACE_DRAG_REF, 0.0, SoundNode.SURFACE_WASH_SPEED) == _snap(SoundNode.SURFACE_DB_MAX) and SoundNode.surface_db_of(100.0, -1.0, 1000.0) == _snap(SoundNode.SURFACE_DB_MAX) and absf(SoundNode.surface_db_of(100.0, -1.0, 1000.0) - SoundNode.SURFACE_DB_MAX) < 1.0e-9
			and gravel10 == snappedf(gravel10, SoundNode.SNAP) and absf(SoundNode.surface_level_of(0.0, 1.0, 10.0) - 10.0 / SoundNode.SURFACE_WASH_SPEED * SoundNode.SURFACE_WASH_LEVEL) < 1.0e-12,
		"SURFACE VOLUME: muted at rest on any surface (the rumble is the tyres rolling); on tarmac the speed wash alone (%.1f dB at 10 m/s, either way, more at 20); gravel's drag (1.6 m/s^2) and grip deficit (0.6) each louder at the same speed and together louder still (%.1f dB at 10 m/s, %.1f at 5); the ceiling %.0f dB at full drag, no grip and the wash's full speed" % [road10, gravel10, gravel5, SoundNode.SURFACE_DB_MAX],
	)
	_check(SoundNode.surface_pitch_of(0.0) == _snap(SoundNode.SURFACE_PITCH_SLOW) and SoundNode.surface_pitch_of(SoundNode.SURFACE_WASH_SPEED) == _snap(SoundNode.SURFACE_PITCH_FAST) and SoundNode.surface_pitch_of(-SoundNode.SURFACE_WASH_SPEED * 2.0) == _snap(SoundNode.SURFACE_PITCH_FAST) and absf(SoundNode.surface_pitch_of(0.0) - SoundNode.SURFACE_PITCH_SLOW) < 1.0e-9 and absf(SoundNode.surface_pitch_of(SoundNode.SURFACE_WASH_SPEED) - SoundNode.SURFACE_PITCH_FAST) < 1.0e-9 and SoundNode.surface_pitch_of(SoundNode.SURFACE_WASH_SPEED * 0.5) == snappedf((SoundNode.SURFACE_PITCH_SLOW + SoundNode.SURFACE_PITCH_FAST) * 0.5, SoundNode.SNAP), "SURFACE PITCH: %.2f at rest to %.2f at %.0f m/s either way, a line between, snapped" % [SoundNode.SURFACE_PITCH_SLOW, SoundNode.SURFACE_PITCH_FAST, SoundNode.SURFACE_WASH_SPEED])
	var rwd := ArcadeCar.DrivenWheels.RWD
	var fwd := ArcadeCar.DrivenWheels.FWD
	var awd := ArcadeCar.DrivenWheels.AWD
	var front: float = ArcadeCar.FRONT_PEAK_SLIP_ANGLE
	var rear: float = ArcadeCar.REAR_PEAK_SLIP_ANGLE
	var half_spin := SoundNode.rear_intensity(0.0, 0.5, rwd)
	_check(
		SoundNode.front_intensity(0.0, 0.0, rwd) == 0.0 and SoundNode.rear_intensity(0.0, 0.0, rwd) == 0.0 and SoundNode.front_intensity(0.0, -1.0, rwd) == 1.0 and SoundNode.rear_intensity(0.0, 2.0, rwd) == 1.0
			and SoundNode.front_intensity(0.0, 0.5, rwd) == 0.0 and SoundNode.front_intensity(0.0, 0.5, fwd) > 0.0 and SoundNode.front_intensity(0.0, 0.5, awd) > 0.0 and SoundNode.rear_intensity(0.0, 0.5, awd) > 0.0 and SoundNode.rear_intensity(0.0, 0.5, fwd) == 0.0
			and SoundNode.front_intensity(front * 3.0, 0.0, rwd) == 1.0 and SoundNode.rear_intensity(rear * 3.0, 0.0, rwd) == 1.0 and SoundNode.front_intensity(front * 1.5, 0.0, rwd) == 0.0 and SoundNode.rear_intensity(rear * 1.5, 0.0, rwd) == 0.0
			and half_spin == MarksLayer.axle_intensity(0.0, 0.5, rear, true) and half_spin == MarksLayer.spin_intensity(0.5) and half_spin > 0.0 and half_spin < 1.0
			and SoundNode.front_intensity(-0.5, -0.75, rwd) == MarksLayer.axle_intensity(-0.5, -0.75, front, false) and SoundNode.rear_intensity(0.2, 0.3, rwd) == MarksLayer.axle_intensity(0.2, 0.3, rear, true),
		"SKID TRIGGERS are MarksLayer's own, called: a locked front (-1) solid, a spinning rear (2.0) solid under RWD, a ratio of 0.5 nothing on an undriven axle (the front under RWD, the rear under FWD) and something on a driven one, 3 peaks of slip angle solid and 1.5 nothing, the same numbers MarksLayer.axle_intensity gives to the bit",
	)
	var quarter := SoundNode.skid_db_of(0.25, 10.0)
	var half_db := SoundNode.skid_db_of(0.5, 10.0)
	_check(
		SoundNode.skid_db_of(0.0, 10.0) == SoundNode.MUTE_DB and SoundNode.skid_db_of(1.0, 0.0) == SoundNode.MUTE_DB and SoundNode.skid_db_of(1.0, SoundNode.SKID_SPEED_MIN - 0.001) == SoundNode.MUTE_DB and SoundNode.skid_db_of(1.0, SoundNode.SKID_SPEED_MIN) == _snap(SoundNode.SKID_DB_MAX)
			and SoundNode.skid_db_of(1.0, 10.0) == _snap(SoundNode.SKID_DB_MAX) and SoundNode.skid_db_of(1.0, -10.0) == _snap(SoundNode.SKID_DB_MAX) and SoundNode.skid_db_of(2.0, 10.0) == _snap(SoundNode.SKID_DB_MAX)
			and quarter > SoundNode.MUTE_DB and quarter < half_db and half_db < SoundNode.SKID_DB_MAX and half_db == snappedf(SoundNode.SKID_DB_MAX + linear_to_db(0.5), SoundNode.SNAP),
		"SKID VOLUME: muted at no intensity and under %.1f m/s whatever the intensity (no squeal standing still), %.0f dB at solid from %.1f m/s either way, rising with the intensity between (%.1f dB at 0.25, %.1f at 0.5)" % [SoundNode.SKID_SPEED_MIN, SoundNode.SKID_DB_MAX, SoundNode.SKID_SPEED_MIN, quarter, half_db],
	)
	_check(SoundNode.skid_pitch_of(0.0) == _snap(SoundNode.SKID_PITCH_ONSET) and SoundNode.skid_pitch_of(1.0) == _snap(SoundNode.SKID_PITCH_SOLID) and SoundNode.skid_pitch_of(2.0) == _snap(SoundNode.SKID_PITCH_SOLID) and SoundNode.skid_pitch_of(-1.0) == _snap(SoundNode.SKID_PITCH_ONSET) and SoundNode.skid_pitch_of(0.5) == snappedf((SoundNode.SKID_PITCH_ONSET + SoundNode.SKID_PITCH_SOLID) * 0.5, SoundNode.SNAP) and absf(SoundNode.skid_pitch_of(1.0) - SoundNode.SKID_PITCH_SOLID) < 1.0e-9, "SKID PITCH: %.2f at the onset to %.2f at solid, a line between, snapped" % [SoundNode.SKID_PITCH_ONSET, SoundNode.SKID_PITCH_SOLID])


# =============================================================================
#  A bare car
# =============================================================================

## A car straight under the root: the node under the root, its players, the
## reads written on the car one by one and the mapped values following.
func _check_bare_car() -> void:
	var watch := SoundWatcher.of(self)
	var attached_before := _attached
	var car: ArcadeCar = (load(CAR_SCENE) as PackedScene).instantiate()
	root.add_child(car)
	await _step(SETTLE_FRAMES)
	var sound := watch.sound_for(car)
	var sounds := _sounds_under(root)
	if not _check(sound != null and sounds.size() == 1 and sounds[0] == sound and sound.get_parent() == root and sound.name == SoundNode.NODE_NAME and sound.car == car and sound.surfaces == null and sound.surface_at(0.0, 0.0) == &"road" and _attached == attached_before + 1 and watch.live_sounds().size() == 1 and watch.live_sounds()[0] == sound, "a bare car under the root gets one Sound node, under the root, no Surfaces node (all road to the squeal's gate), the watcher's own"):
		root.remove_child(car)
		car.free()
		return
	var streams := SoundNode.buffers()
	var players := _players_under(root)
	_check(sound.process_physics_priority == -1 and sound.get_child_count() == 3 and players.size() == 3 and sound.engine_player.name == SoundNode.ENGINE_PLAYER and sound.surface_player.name == SoundNode.SURFACE_PLAYER and sound.skid_player.name == SoundNode.SKID_PLAYER and sound.engine_player.get_parent() == sound and sound.surface_player.get_parent() == sound and sound.skid_player.get_parent() == sound, "it ticks at physics priority -1 (before the car's own tick) and holds three players, %s / %s / %s - the only audio players in the tree" % [SoundNode.ENGINE_PLAYER, SoundNode.SURFACE_PLAYER, SoundNode.SKID_PLAYER])
	_check(sound.engine_player.stream == streams[SoundNode.ENGINE_PLAYER] and sound.surface_player.stream == streams[SoundNode.SURFACE_PLAYER] and sound.skid_player.stream == streams[SoundNode.SKID_PLAYER] and sound.engine_player.playing and sound.surface_player.playing and sound.skid_player.playing, "each player loops its shared stream, playing from the start (the volume says what is heard)")
	var idle: float = ArcadeCar.IDLE_RPM
	var limiter: float = ArcadeCar.REDLINE_RPM
	_check(sound.ticks > 0 and sound.read_ticks == sound.ticks and sound.last_running and sound.last_speed == 0.0 and absf(sound.last_rpm - idle) < 100.0 and sound.engine_pitch == SoundNode.engine_pitch_of(sound.last_rpm, idle, limiter) and sound.engine_db == SoundNode.engine_db_of(sound.last_rpm, sound.last_throttle, true, idle, limiter) and sound.engine_db > SoundNode.MUTE_DB and sound.surface_db == SoundNode.MUTE_DB and sound.skid_db == SoundNode.MUTE_DB and sound.skid_intensity == 0.0 and _players_match(sound), "at rest after %d ticks: the engine idles (%.0f rpm read: pitch %.3f, %.1f dB), the rumble and the squeal muted, the players carrying the mapped values" % [sound.ticks, sound.last_rpm, sound.engine_pitch, sound.engine_db])
	print("  ", sound.describe())

	# The engine: rpm, throttle, stopped.
	var idle_pitch := sound.engine_pitch
	var idle_db := sound.engine_db
	car.engine_rpm = 5000.0
	car.throttle_pedal = 0.0
	await physics_frame
	_check(absf(sound.last_rpm - 5000.0) < 1.0e-6 and sound.engine_pitch == SoundNode.engine_pitch_of(sound.last_rpm, idle, limiter) and absf(sound.engine_pitch - SoundNode.engine_pitch_of(5000.0, idle, limiter)) <= SoundNode.SNAP and sound.engine_pitch > idle_pitch and _players_match(sound) and sound.engine_db > idle_db and sound.engine_db == SoundNode.engine_db_of(sound.last_rpm, 0.0, true, idle, limiter), "engine_rpm written 5000 on the car: the node read it before the car's tick (%.1f rpm) and the pitch followed (%.3f, from %.3f at idle), a little louder for the revs (%.1f dB)" % [sound.last_rpm, sound.engine_pitch, idle_pitch, sound.engine_db])
	car.engine_rpm = 5000.0
	car.throttle_pedal = 1.0
	await physics_frame
	var loaded_db := sound.engine_db
	_check(sound.last_throttle == 1.0 and absf(sound.last_rpm - 5000.0) < 1.0e-6 and loaded_db == SoundNode.engine_db_of(sound.last_rpm, 1.0, true, idle, limiter) and loaded_db > SoundNode.engine_db_of(sound.last_rpm, 0.0, true, idle, limiter) and loaded_db < SoundNode.ENGINE_DB_IDLE + SoundNode.ENGINE_DB_RPM_SPAN + SoundNode.ENGINE_DB_LOAD_SPAN and _players_match(sound), "throttle_pedal written 1 at 5000 rpm: the load component adds (%.1f dB; %.0f dB is the ceiling at the limiter)" % [loaded_db, SoundNode.ENGINE_DB_IDLE + SoundNode.ENGINE_DB_RPM_SPAN + SoundNode.ENGINE_DB_LOAD_SPAN])

	# The surface: gravel written on the car, at speed and at rest.
	_write_surface(car, 0.7, 0.6, 1.6, 10.0)
	await physics_frame
	var gravel := sound.surface_db
	_check(sound.last_grip_front == 0.7 and sound.last_grip_rear == 0.6 and sound.last_drag == 1.6 and sound.last_speed == 10.0 and gravel == SoundNode.surface_db_of(1.6, 0.6, 10.0) and gravel > SoundNode.surface_db_of(0.0, 1.0, 10.0) and gravel > SoundNode.MUTE_DB and sound.surface_pitch == SoundNode.surface_pitch_of(10.0) and _players_match(sound), "the three surface inputs written gravel (grip 0.7 / 0.6, drag 1.6) with forward_speed 10: the rumble follows (%.1f dB, pitch %.3f), louder than tarmac at that speed (%.1f dB)" % [gravel, sound.surface_pitch, SoundNode.surface_db_of(0.0, 1.0, 10.0)])
	_write_surface(car, 1.0, 1.0, 0.0, 10.0)
	await physics_frame
	var tarmac := sound.surface_db
	_write_surface(car, 0.7, 0.6, 1.6, 0.0)
	await physics_frame
	_check(tarmac == SoundNode.surface_db_of(0.0, 1.0, 10.0) and tarmac < gravel and tarmac > SoundNode.MUTE_DB and sound.last_drag == 1.6 and sound.last_speed == 0.0 and sound.surface_db == SoundNode.MUTE_DB and sound.surface_pitch == _snap(SoundNode.SURFACE_PITCH_SLOW), "tarmac at 10 m/s is the wash alone (%.1f dB); gravel standing still is silence" % tarmac)
	_write_surface(car, 1.0, 1.0, 0.0, 0.0)

	# The squeal: the slip numbers written on the car.
	_write_slips(car, 0.0, 0.0, 0.0, 2.0, 10.0)
	await physics_frame
	var rear_spin_ok: bool = car.driven_wheels == ArcadeCar.DrivenWheels.RWD and sound.last_rear_ratio == 2.0 and sound.last_speed == 10.0 and sound.skid_intensity == 1.0 and sound.skid_db == _snap(SoundNode.SKID_DB_MAX) and sound.skid_pitch == _snap(SoundNode.SKID_PITCH_SOLID) and _players_match(sound)
	_write_slips(car, 0.0, 0.5, 0.0, 0.0, 10.0)
	await physics_frame
	var front_spin_ok: bool = sound.last_front_ratio == 0.5 and sound.skid_intensity == 0.0 and sound.skid_db == SoundNode.MUTE_DB and sound.skid_pitch == _snap(SoundNode.SKID_PITCH_ONSET)
	_write_slips(car, 0.0, -1.0, 0.0, 0.0, 10.0)
	await physics_frame
	var lock_ok: bool = sound.skid_intensity == 1.0 and sound.skid_db == _snap(SoundNode.SKID_DB_MAX)
	_write_slips(car, 0.0, 0.0, ArcadeCar.REAR_PEAK_SLIP_ANGLE * 3.0, 0.0, 10.0)
	await physics_frame
	var lateral_ok: bool = sound.skid_intensity == 1.0 and sound.skid_db == _snap(SoundNode.SKID_DB_MAX)
	_check(rear_spin_ok and front_spin_ok and lock_ok and lateral_ok, "the slip numbers written at 10 m/s: a spinning rear (ratio 2.0, the driven axle under RWD) squeals solid (%.0f dB, pitch %.2f); a front ratio of 0.5 (undriven) is nothing; a locked front (-1) solid; the rear at 3 peaks of slip angle solid" % [SoundNode.SKID_DB_MAX, SoundNode.SKID_PITCH_SOLID])
	_write_slips(car, 0.0, 0.0, 0.0, 2.0, 1.0)
	await physics_frame
	var gate_ok: bool = sound.skid_intensity == 1.0 and sound.last_speed == 1.0 and sound.skid_db == SoundNode.MUTE_DB
	_write_slips(car, 0.0, 0.0, 0.0, 0.5, 10.0)
	await physics_frame
	var part := sound.skid_intensity
	_check(gate_ok and part > 0.0 and part < 1.0 and part == MarksLayer.spin_intensity(0.5) and sound.skid_db == SoundNode.skid_db_of(part, 10.0) and sound.skid_db > SoundNode.MUTE_DB and sound.skid_db < SoundNode.SKID_DB_MAX and sound.skid_pitch == SoundNode.skid_pitch_of(part) and sound.skid_pitch > SoundNode.SKID_PITCH_ONSET and sound.skid_pitch < SoundNode.SKID_PITCH_SOLID and sound.skid_db == snappedf(sound.skid_db, SoundNode.SNAP) and sound.skid_pitch == snappedf(sound.skid_pitch, SoundNode.SNAP), "the same spinning rear at 1 m/s is muted (the speed gate); a rear ratio of 0.5 is a part squeal (intensity %.3f, MarksLayer's own: %.1f dB, pitch %.3f), snapped" % [part, sound.skid_db, sound.skid_pitch])
	_write_slips(car, 0.0, 0.0, 0.0, 0.0, 0.0)

	# Never double-attached.
	watch._attach(car.get_instance_id())
	await physics_frame
	_check(_sounds_under(root).size() == 1 and watch.sound_for(car) == sound and _attached == attached_before + 1 and _players_under(root).size() == 3, "a second attach for the same car is nothing: one node, one signal")

	# The engine stopped, last: the note goes.
	car.engine_running = false
	await physics_frame
	_check(not sound.last_running and sound.engine_db == SoundNode.MUTE_DB and _players_match(sound), "engine_running written false: the note is muted")
	print("  ", sound.describe())

	# The car out of the tree: the node goes with it.
	root.remove_child(car)
	await _step(1)
	_check(not is_instance_valid(sound) and watch.sound_for(car) == null and watch.live_sounds().is_empty() and _sounds_under(root).is_empty() and _players_under(root).is_empty(), "the car out of the tree: its node freed, sound_for null, the watcher holds none, no player left")
	car.free()

	# A car added and freed in the same frame: the deferred attach finds
	# nothing, and nothing goes wrong.
	var brief: ArcadeCar = (load(CAR_SCENE) as PackedScene).instantiate()
	root.add_child(brief)
	root.remove_child(brief)
	brief.free()
	await _step(2)
	_check(watch.live_sounds().is_empty() and _sounds_under(root).is_empty() and _attached == attached_before + 1, "a car added and freed within the frame gets no node (the instance-id pattern: the deferred attach finds no car) and no error")


## Two cars under the root fed the same reads: the same mapped values to the bit.
func _check_determinism() -> void:
	var watch := SoundWatcher.of(self)
	var a: ArcadeCar = (load(CAR_SCENE) as PackedScene).instantiate()
	var b: ArcadeCar = (load(CAR_SCENE) as PackedScene).instantiate()
	root.add_child(a)
	root.add_child(b)
	await _step(SETTLE_FRAMES)
	var sound_a := watch.sound_for(a)
	var sound_b := watch.sound_for(b)
	if not _check(sound_a != null and sound_b != null and sound_a != sound_b and _sounds_under(root).size() == 2 and watch.live_sounds().size() == 2, "two bare cars: two nodes, one each"):
		root.remove_child(a)
		root.remove_child(b)
		a.free()
		b.free()
		return
	_write_reads(a, SAME_READS)
	_write_reads(b, SAME_READS)
	await physics_frame
	var state_a := sound_a.state()
	var state_b := sound_b.state()
	var snapped := true
	var live := true
	for key: String in state_a:
		var value: float = state_a[key]
		# The skid intensity is the marks-style raw intermediate (marks.gd's
		# _streak_intensity rule: the intermediate is raw, the written values
		# around it snapped); the six db / pitch values carry the snap.
		if key != "skid_intensity":
			snapped = snapped and value == snappedf(value, SoundNode.SNAP) and is_finite(value)
		else:
			snapped = snapped and is_finite(value)
		if key.ends_with("_db"):
			live = live and value > SoundNode.MUTE_DB
	_check(state_a == state_b and state_a.size() == 7 and snapped and live and _players_match(sound_a) and _players_match(sound_b) and sound_a.skid_intensity > 0.0 and sound_a.skid_intensity < 1.0, "DETERMINISM: fed the same reads (%.1f rpm, throttle %.2f, grip %.2f / %.2f, drag %.1f, %.1f m/s, slips %.2f / %.2f / %.2f / %.2f) both nodes carry the same seven mapped values to the bit, the six db / pitch values snapped to %.3f (the intensity the raw marks intermediate), every channel live: %s" % [SAME_READS.rpm, SAME_READS.throttle, SAME_READS.grip_front, SAME_READS.grip_rear, SAME_READS.drag, SAME_READS.speed, SAME_READS.front_angle, SAME_READS.front_ratio, SAME_READS.rear_angle, SAME_READS.rear_ratio, SoundNode.SNAP, state_a])
	_write_reads(a, SAME_READS)
	await physics_frame
	_check(sound_a.state() == state_a, "the same reads a tick later map to the same values again")
	root.remove_child(a)
	root.remove_child(b)
	await _step(1)
	_check(watch.live_sounds().is_empty() and _sounds_under(root).is_empty(), "both cars out: both nodes gone")
	a.free()
	b.free()


## FD_SOUND "0" and unset (headless) give a car no node; "1" does.
func _check_switch() -> void:
	var watch := SoundWatcher.of(self)
	var attached_before := _attached
	OS.set_environment(SoundWatcher.ENV_VAR, "0")
	var off := await _bare_car_gets_node()
	OS.set_environment(SoundWatcher.ENV_VAR, "")
	var unset := await _bare_car_gets_node()
	OS.set_environment(SoundWatcher.ENV_VAR, "1")
	var on := await _bare_car_gets_node()
	_check(not off and not unset and on and _attached == attached_before + 1 and watch.live_sounds().is_empty() and _sounds_under(root).is_empty(), "read at each attach: FD_SOUND=0 gives a car no node, unset (headless) none, 1 one - the switch toggles between scenes")


## Adds a bare car, settles, says whether it got a node, removes it.
func _bare_car_gets_node() -> bool:
	var watch := SoundWatcher.of(self)
	var car: ArcadeCar = (load(CAR_SCENE) as PackedScene).instantiate()
	root.add_child(car)
	await _step(3)
	var got := watch.sound_for(car) != null and _sounds_under(root).size() == 1
	var none := watch.sound_for(car) == null and _sounds_under(root).is_empty()
	root.remove_child(car)
	await _step(1)
	car.free()
	return got and not none


# =============================================================================
#  The pad
# =============================================================================

## main.tscn as shipped: the node's place, the slide recorded. Returns the
## recorder's sample lines and the car's end transform for the off scene.
func _check_pad() -> Dictionary:
	var out := {"samples": PackedStringArray(), "end": Transform3D.IDENTITY}
	var scene := await _load_pad()
	if scene == null:
		return out
	var car: ArcadeCar = scene.get_node("Car")
	var watch := SoundWatcher.of(self)
	var sound := watch.sound_for(car)
	var sounds := _sounds_under(root)
	var cars: Array[ArcadeCar] = []
	_cars_under(scene, cars)
	if not _check(sound != null and sounds.size() == cars.size() and sounds.has(sound) and sound.get_parent() == scene and sound.name == SoundNode.NODE_NAME and sound.car == car and watch.live_sounds().size() == cars.size() and not paused, "the pad: one Sound node per car in the whole tree (%d), under the scene root, the watcher's own for the HUD's car; the tree not paused (the world map does not auto-open with the store off)" % cars.size()):
		_drop(scene)
		return out
	var recorder := TelemetryWatcher.of(self).recorder_for(car)
	var last := scene.get_child(scene.get_child_count() - 1)
	_check(recorder != null and last is TelemetryRecorder and sound.get_index() == recorder.get_index() - 1, "it stands right in front of the TelemetryRecorder, which stays the scene root's LAST child (index %d of %d)" % [sound.get_index(), scene.get_child_count()])
	_check(SoundWatcher.has_own_sound(scene, car) and _players_under(scene).size() == 3 * cars.size() and _players_under(root).size() == 3 * cars.size(), "the shipped pad carries no audio of its own: the only players under it are the watcher's node's (has_own_sound sees that node now - the guard for a scene that ships its own is future-proofing)")
	_check(sound.surfaces == null and watch.surfaces_of(car) == null and sound.surface_at(car.global_position.x, car.global_position.z) == &"road" and sound.engine_player.stream == SoundNode.buffers()[SoundNode.ENGINE_PLAYER], "no Surfaces node on the pad: all road to the squeal's gate; the streams the shared ones")
	var idle: float = ArcadeCar.IDLE_RPM
	var limiter: float = ArcadeCar.REDLINE_RPM
	_check(sound.read_ticks > 0 and sound.skid_db == SoundNode.MUTE_DB and sound.surface_db == SoundNode.MUTE_DB and sound.engine_db == SoundNode.engine_db_of(sound.last_rpm, sound.last_throttle, true, idle, limiter) and absf(sound.last_rpm - idle) < 100.0, "at rest on the pad: the engine idles, the rumble and the squeal muted")

	# The slide, recorded.
	var file := _tmp_dir.path_join("pad_slide_sound_on.jsonl")
	recorder.record_to_file(file)
	var slide := await _slide(car, sound)
	recorder.stop()
	out.samples = _sample_lines(file)
	out.end = car.global_transform
	_check(slide.peak_rear_ratio <= -MarksLayer.LOCK_SOLID_RATIO and slide.max_skid_db == _snap(SoundNode.SKID_DB_MAX) and slide.skid_ticks > 0 and slide.skid_ticks < slide.ticks and out.samples.size() >= slide.ticks, "a handbrake slide from %.0f km/h: the locked rears (slip ratio %.2f) squeal solid (%.0f dB) on %d of %d ticks, muted on the rest; %d samples recorded" % [slide.entry_speed * 3.6, slide.peak_rear_ratio, slide.max_skid_db, slide.skid_ticks, slide.ticks, out.samples.size()])
	_check(slide.max_engine_pitch > SoundNode.engine_pitch_of(idle, idle, limiter) and slide.max_rpm > idle + 1000.0 and slide.engine_live and slide.players_match, "the engine note rose through the run-up (%.0f rpm at most, pitch %.3f), never muted, the players carrying the mapped values every tick" % [slide.max_rpm, slide.max_engine_pitch])
	_check(slide.surface_wash_only and slide.max_surface_db > SoundNode.MUTE_DB and slide.max_surface_db < SoundNode.surface_db_of(1.6, 0.6, slide.max_speed), "the surface channel is the speed wash alone every tick (the pad is all tarmac: %.1f dB at most at %.1f m/s), under what gravel would be at that speed (%.1f dB)" % [slide.max_surface_db, slide.max_speed, SoundNode.surface_db_of(1.6, 0.6, slide.max_speed)])
	print("  ", sound.describe())
	_drop(scene)
	await _step(1)
	_check(not is_instance_valid(sound) and watch.live_sounds().is_empty() and _sounds_under(root).is_empty() and _players_under(root).is_empty(), "the scene freed, its node is gone and the watcher holds none")
	return out


## FD_SOUND=0: a scene without a node, the same slide recorded: the same
## samples, byte for byte.
func _check_switched_off(first: Dictionary) -> void:
	var attached_before := _attached
	var scene := await _load_pad()
	if scene == null:
		return
	var car: ArcadeCar = scene.get_node("Car")
	var watch := SoundWatcher.of(self)
	_check(watch.sound_for(car) == null and _sounds_under(root).is_empty() and _players_under(root).is_empty() and watch.live_sounds().is_empty() and _attached == attached_before and scene.get_child(scene.get_child_count() - 1) is TelemetryRecorder and not paused, "FD_SOUND=0: no Sound node and no player anywhere, the watcher holds none, the recorder still the scene root's last child")
	var recorder := TelemetryWatcher.of(self).recorder_for(car)
	var file := _tmp_dir.path_join("pad_slide_sound_off.jsonl")
	recorder.record_to_file(file)
	var slide := await _slide(car, null)
	recorder.stop()
	var samples := _sample_lines(file)
	var first_samples: PackedStringArray = first.samples
	for index in mini(samples.size(), first_samples.size()):
		if samples[index] != first_samples[index]:
			print("  the first differing sample is %d of %d / %d:\n    with the node: %s\n    without:       %s" % [index, first_samples.size(), samples.size(), first_samples[index], samples[index]])
			break
	_check(samples.size() == first_samples.size() and samples.size() > 100 and samples == first_samples and car.global_transform == first.end, "NO PHYSICS IMPACT: the same slide with no node writes the same %d telemetry samples byte for byte (the car's position, speed, slips, yaw rate every tick), the car ending where it ended (%.3f, %.3f)" % [samples.size(), car.global_position.x, car.global_position.z])
	_check(slide.ticks > 0 and slide.peak_rear_ratio <= -MarksLayer.LOCK_SOLID_RATIO, "and the rears locked the same (%.2f)" % slide.peak_rear_ratio)
	_drop(scene)
	await _step(1)


# =============================================================================
#  The drives
# =============================================================================

## The slide: up to SLIDE_SPEED, SLIDE_STEER left and the handbrake for
## SLIDE_FRAMES, everything let go for SLIDE_WATCH_FRAMES. Returns the entry
## speed, the rears' peak slip ratio (the most negative), the ticks run and,
## with a node, what its channels did over the run-up and the slide.
func _slide(car: ArcadeCar, sound: SoundNode) -> Dictionary:
	var out := {"entry_speed": 0.0, "peak_rear_ratio": 0.0, "ticks": 0, "max_skid_db": SoundNode.MUTE_DB, "skid_ticks": 0, "max_engine_pitch": 0.0, "max_rpm": 0.0, "engine_live": true, "players_match": true, "surface_wash_only": true, "max_surface_db": SoundNode.MUTE_DB, "max_speed": 0.0}
	Input.action_press(&"accelerate")
	for frame in SPEED_UP_FRAMES_MAX:
		if car.forward_speed >= SLIDE_SPEED:
			break
		await physics_frame
		_watch_sound(out, sound)
	Input.action_release(&"accelerate")
	out.entry_speed = car.forward_speed
	Input.action_press(&"steer_left", SLIDE_STEER)
	Input.action_press(&"handbrake")
	for frame in SLIDE_FRAMES + SLIDE_WATCH_FRAMES:
		if frame == SLIDE_FRAMES:
			Input.action_release(&"handbrake")
			Input.action_release(&"steer_left")
		await physics_frame
		out.ticks += 1
		out.peak_rear_ratio = minf(out.peak_rear_ratio, car.rear_slip_ratio)
		_watch_sound(out, sound)
	await _step(2)
	out.ticks += 2
	return out


## What the node's channels did on this tick, folded into `out`.
func _watch_sound(out: Dictionary, sound: SoundNode) -> void:
	if sound == null:
		return
	out.max_skid_db = maxf(out.max_skid_db, sound.skid_db)
	if sound.skid_db > SoundNode.MUTE_DB:
		out.skid_ticks += 1
	out.max_engine_pitch = maxf(out.max_engine_pitch, sound.engine_pitch)
	out.max_rpm = maxf(out.max_rpm, sound.last_rpm)
	out.engine_live = out.engine_live and sound.engine_db > SoundNode.MUTE_DB
	out.players_match = out.players_match and _players_match(sound)
	out.surface_wash_only = out.surface_wash_only and sound.last_drag == 0.0 and sound.last_grip_front == 1.0 and sound.last_grip_rear == 1.0 and sound.surface_db == SoundNode.surface_db_of(0.0, 1.0, sound.last_speed)
	out.max_surface_db = maxf(out.max_surface_db, sound.surface_db)
	out.max_speed = maxf(out.max_speed, absf(sound.last_speed))


# =============================================================================
#  Helpers
# =============================================================================

## main.tscn as shipped, entered from the same phase of a physics frame (the
## marks test's idiom), settled. One at a time: the caller frees it before
## the next load.
func _load_pad() -> Node:
	var packed: PackedScene = load(PAD_SCENE)
	if not _check(packed != null, "main.tscn loads"):
		return null
	await physics_frame
	var scene := packed.instantiate()
	root.add_child(scene)
	await _step(SETTLE_FRAMES)
	return scene


## Writes the three surface inputs and the speed on a car (public fields the
## Surfaces node feeds; nothing feeds them on a bare car or the pad).
func _write_surface(car: ArcadeCar, grip_front: float, grip_rear: float, drag: float, speed: float) -> void:
	car.front_surface_grip = grip_front
	car.rear_surface_grip = grip_rear
	car.surface_rolling_decel = drag
	car.forward_speed = speed


## Writes the four slip numbers and the speed on a car (the car's own tick
## overwrites them after the node has read them).
func _write_slips(car: ArcadeCar, front_angle: float, front_ratio: float, rear_angle: float, rear_ratio: float, speed: float) -> void:
	car.front_slip_angle = front_angle
	car.front_slip_ratio = front_ratio
	car.rear_slip_angle = rear_angle
	car.rear_slip_ratio = rear_ratio
	car.forward_speed = speed


## Writes every read the node makes on a car.
func _write_reads(car: ArcadeCar, reads: Dictionary) -> void:
	car.engine_rpm = reads.rpm
	car.throttle_pedal = reads.throttle
	car.engine_running = reads.running
	_write_surface(car, reads.grip_front, reads.grip_rear, reads.drag, reads.speed)
	_write_slips(car, reads.front_angle, reads.front_ratio, reads.rear_angle, reads.rear_ratio, reads.speed)


## Whether the three players carry the node's mapped values: the node holds
## snapped doubles, a player's pitch_scale and volume_db are the engine's
## 32-bit floats of them (PLAYER_TOLERANCE: a float's step at 60 is 4e-6).
func _players_match(sound: SoundNode) -> bool:
	return absf(sound.engine_player.pitch_scale - sound.engine_pitch) < PLAYER_TOLERANCE and absf(sound.engine_player.volume_db - sound.engine_db) < PLAYER_TOLERANCE and absf(sound.surface_player.pitch_scale - sound.surface_pitch) < PLAYER_TOLERANCE and absf(sound.surface_player.volume_db - sound.surface_db) < PLAYER_TOLERANCE and absf(sound.skid_player.pitch_scale - sound.skid_pitch) < PLAYER_TOLERANCE and absf(sound.skid_player.volume_db - sound.skid_db) < PLAYER_TOLERANCE


## A value through the node's own snap: a mapped value equals a constant
## only through it (snappedf(1.15, 0.001) is not the double 1.15; the marks
## test's alpha_of precedent).
func _snap(value: float) -> float:
	return snappedf(value, SoundNode.SNAP)


## Every ArcadeCar under `node`, `node` itself included.
func _cars_under(node: Node, out: Array[ArcadeCar]) -> void:
	if node is ArcadeCar:
		out.append(node)
	for child in node.get_children():
		_cars_under(child, out)


## Every SoundNode under `node`, `node` itself included.
func _sounds_under(node: Node) -> Array[SoundNode]:
	var out: Array[SoundNode] = []
	_collect_sounds(node, out)
	return out


func _collect_sounds(node: Node, out: Array[SoundNode]) -> void:
	if node is SoundNode:
		out.append(node)
	for child in node.get_children():
		_collect_sounds(child, out)


## Every audio player under `node`, `node` itself included.
func _players_under(node: Node) -> Array[Node]:
	var out: Array[Node] = []
	_collect_players(node, out)
	return out


func _collect_players(node: Node, out: Array[Node]) -> void:
	if node is AudioStreamPlayer or node is AudioStreamPlayer2D or node is AudioStreamPlayer3D:
		out.append(node)
	for child in node.get_children():
		_collect_players(child, out)


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
		print("SOUND TEST PASSED")
	else:
		print("SOUND TEST FAILED: %d check(s) failed" % _failures)
	quit(1 if _failures > 0 else 0)

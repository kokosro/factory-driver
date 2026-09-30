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
## 16-bit mono loops of BUFFER_SAMPLES at MIX_RATE - 2 s on a 0.5 Hz grid
## (was-> 0.5 s on 2 Hz) - looped end to end, built once and shared, the
## same bytes when built again, normalised to the peak: the engine a flat-6's
## order stack from 45 Hz with half-order sidebands (was-> 56 Hz and its
## harmonics), the rumble the 62..226 Hz body primes under a 500..2000 Hz
## noise layer (was-> the primes alone), the squeal a 2000 Hz tone with a
## 2800 Hz overtone, 1500..4000 Hz grit and a baked 9 Hz amplitude modulation
## (was-> an 800 Hz chord) - SOUND-2, scratch/sound-2-references.md, after
## the driver's "unbearable, very high"; every partial whole cycles over the
## buffer, the engine starting at zero, the zero-crossing rates and the AM
## measured on the built PCM. THE MAPPING, pure and snapped to 0.001: the
## engine's pitch 1 at idle and 8 at the redline (was-> 2.5; ArcadeCar's own
## rpm numbers) and its volume -18 dB at idle with the pedal up
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
## SOUND-3 (the driver's "it matters in which environment the car is"):
## THE WIND, a fourth loop (31 partials every 20 Hz over 100..700 Hz, whole
## cycles, the golden spread; distinct, byte-identical when rebuilt), its
## level the AUTHORED quadratic of the speed - muted under 5 m/s, 0.25 at
## half of 50 m/s, -10 dB at the ceiling, snapped, the same whatever the
## surface. THE IMPACTS: the pure corners (a nudge under 1 m/s nothing, full
## at 20 m/s, an UP normal the floor and a wall normal an impact, the 15
## frame cooldown), the burst (8192 samples, non-looping, starting at zero,
## decayed to nothing by its end, byte-identical when rebuilt), and ONE REAL
## DRIVE on the pad: the car placed 46 m short of shed 0 facing +X and
## driven into it at speed - impacts_fired rises to 1, the thump's normal is
## the shed's -X face, its intensity the closing speed's share of 20 m/s
## (the velocity read a tick before the move: this tick's is already slid,
## its normal component 0), the pool's first player playing at the mapped
## volume; and, leaning on the wall under throttle, no second thump (the
## slid velocity closes on nothing). THE ENVIRONMENT: the pure corners
## (openness 0 / 1 and from a distance, the trims -4 / +1.5 dB closed in
## and 0 open, a muted base staying muted), and a bare car under the root
## next to an inert BuildingsShells node named "Buildings" (build_deferred,
## its shells written by hand): the nearest shell's distance scanned every
## 30 ticks and the two trims on the written volumes, the car moved away and
## the scan catching up within a cadence, shells that appear later seen at
## the next scan, no node created or written; the pad (no Buildings node)
## fully open, its trims 0, its rumble bit-identical to SOUND-2's; the
## state dictionary twelve values (was-> seven) under the determinism pin.
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

## SOUND-3, the impact drive: the car is placed at (IMPACT_START_X, y,
## IMPACT_SHED_Z) facing +X - the pad's shed 0 (scripts/test_pad.gd: SHED_X
## 80, SHED_SIZE 24 x 9 x 48, centre z -80) has its -X face at
## IMPACT_SHED_FACE_X - and driven flat out; the approach must reach
## IMPACT_SPEED_FULL_APPROACH_MIN m/s (the rehearsal gave 19.75); then it
## leans on the wall IMPACT_LEAN_FRAMES under throttle.
const IMPACT_START_X := 20.0
const IMPACT_SHED_Z := -80.0
const IMPACT_SHED_FACE_X := 68.0
const IMPACT_SPEED_FULL_APPROACH_MIN := 15.0
const IMPACT_LEAN_FRAMES := 60

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
	print("-- the environment: a Buildings node's shells trim the wind and the rumble")
	await _check_environment()
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
	# was-> three names, three streams (SOUND-3: the wind loop and the thump
	# burst joined; `names` are the four loops, the burst is checked apart).
	var names: Array[String] = [SoundNode.ENGINE_PLAYER, SoundNode.SURFACE_PLAYER, SoundNode.SKID_PLAYER, SoundNode.WIND_PLAYER]
	var all_names: Array[String] = names.duplicate()
	all_names.append(SoundNode.THUMP_STREAM)
	var shared := streams.size() == 5 and again.size() == 5
	for player_name in all_names:
		shared = shared and streams.has(player_name) and streams[player_name] is AudioStreamWAV and again[player_name] == streams[player_name]
	_check(shared, "five streams (%s; was-> three), built once and shared: buffers() hands out the same instances again" % ", ".join(all_names))
	var shape := true
	var peaks := {}
	for player_name in names:
		var stream: AudioStreamWAV = streams[player_name]
		shape = shape and stream.format == AudioStreamWAV.FORMAT_16_BITS and stream.mix_rate == SoundNode.MIX_RATE and not stream.stereo and stream.loop_mode == AudioStreamWAV.LOOP_FORWARD and stream.loop_begin == 0 and stream.loop_end == SoundNode.BUFFER_SAMPLES and stream.data.size() == SoundNode.BUFFER_SAMPLES * 2
		var peak := 0
		for n in SoundNode.BUFFER_SAMPLES:
			peak = maxi(peak, absi(stream.data.decode_s16(n * 2)))
		peaks[player_name] = peak
	_check(shape, "each of the four loops is 16-bit mono PCM at %d Hz, %d samples (%.1f s), looped forward end to end (loop_begin 0, loop_end %d)" % [SoundNode.MIX_RATE, SoundNode.BUFFER_SAMPLES, SoundNode.BUFFER_SAMPLES / float(SoundNode.MIX_RATE), SoundNode.BUFFER_SAMPLES])
	var full := roundi(SoundNode.BUFFER_PEAK * 32767.0)
	_check(absi(int(peaks[SoundNode.ENGINE_PLAYER]) - full) <= 1 and absi(int(peaks[SoundNode.SURFACE_PLAYER]) - full) <= 1 and absi(int(peaks[SoundNode.SKID_PLAYER]) - full) <= 1 and absi(int(peaks[SoundNode.WIND_PLAYER]) - full) <= 1, "each is normalised to %.2f of full scale (peaks %d / %d / %d / %d, %d expected)" % [SoundNode.BUFFER_PEAK, peaks[SoundNode.ENGINE_PLAYER], peaks[SoundNode.SURFACE_PLAYER], peaks[SoundNode.SKID_PLAYER], peaks[SoundNode.WIND_PLAYER], full])
	# SOUND-3: the burst - non-looping, IMPACT_BUFFER_SAMPLES long, the same
	# rate and format, normalised, starting at exactly zero (the attack) and
	# decayed to nothing by its end (the tail's RMS against the head's).
	var thump: AudioStreamWAV = streams[SoundNode.THUMP_STREAM]
	var thump_peak := 0
	for n in SoundNode.IMPACT_BUFFER_SAMPLES:
		thump_peak = maxi(thump_peak, absi(thump.data.decode_s16(n * 2)))
	var tenth := SoundNode.IMPACT_BUFFER_SAMPLES / 10
	var thump_head := _rms_of(thump, 0, tenth)
	var thump_tail := _rms_of(thump, SoundNode.IMPACT_BUFFER_SAMPLES - tenth, tenth)
	var thump_zcr := _zero_crossings_per_second(thump)
	_check(thump.format == AudioStreamWAV.FORMAT_16_BITS and thump.mix_rate == SoundNode.MIX_RATE and not thump.stereo and thump.loop_mode == AudioStreamWAV.LOOP_DISABLED and thump.data.size() == SoundNode.IMPACT_BUFFER_SAMPLES * 2 and absi(thump_peak - full) <= 1 and thump.data.decode_s16(0) == 0 and thump_tail < 0.02 * thump_head and thump_head > 0.1 and thump_zcr >= 150.0 and thump_zcr <= 400.0 and SoundNode.IMPACT_PARTIAL_HZ.size() == SoundNode.IMPACT_PARTIAL_AMPLITUDES.size() and SoundNode.IMPACT_DECAY_S > 0.0 and SoundNode.IMPACT_BUFFER_SAMPLES / float(SoundNode.MIX_RATE) > 5.0 * SoundNode.IMPACT_DECAY_S, "THE THUMP BURST (SOUND-3): 16-bit mono at %d Hz, %d samples (%.0f ms), NOT looping (it plays once and stops - the whole-cycles rule is the loops' alone), normalised to the same peak (%d), its first sample exactly 0 (the 2 ms attack), its last tenth's RMS %.4f of full scale against its first tenth's %.3f (under 2%%: a %.0f ms decay is spent over five times by the end), %.1f zero crossings a second (the %.0f Hz thud's own %.0f under the knock partials, between 150 and 400)" % [SoundNode.MIX_RATE, SoundNode.IMPACT_BUFFER_SAMPLES, SoundNode.IMPACT_BUFFER_SAMPLES * 1000.0 / SoundNode.MIX_RATE, thump_peak, thump_tail, thump_head, SoundNode.IMPACT_DECAY_S * 1000.0, thump_zcr, SoundNode.IMPACT_TONE_HZ, SoundNode.IMPACT_TONE_HZ * 2.0])
	var engine: AudioStreamWAV = streams[SoundNode.ENGINE_PLAYER]
	var surface: AudioStreamWAV = streams[SoundNode.SURFACE_PLAYER]
	var skid: AudioStreamWAV = streams[SoundNode.SKID_PLAYER]
	var wind: AudioStreamWAV = streams[SoundNode.WIND_PLAYER]
	var hz := float(SoundNode.MIX_RATE) / float(SoundNode.BUFFER_SAMPLES)
	# was-> ENGINE_CYCLES + SURFACE_CYCLES + SKID_CYCLES, three tables (SOUND-2:
	# seven tables and the AM carrier - the sidebands, the rumble's noise layer
	# and the squeal's grit joined the whole-cycles rule; SOUND-3: the wind's
	# table too, eight tables and the carrier).
	var tables: Array = [SoundNode.ENGINE_CYCLES, SoundNode.ENGINE_SIDEBAND_CYCLES, SoundNode.SURFACE_BODY_CYCLES, SoundNode.SURFACE_NOISE_CYCLES, SoundNode.SKID_TONE_CYCLES, SoundNode.SKID_NOISE_CYCLES, [SoundNode.SKID_AM_CYCLES], SoundNode.WIND_CYCLES]
	var whole := true
	var partials := 0
	for table: Array in tables:
		for cycles: int in table:
			whole = whole and cycles > 0
			partials += 1
	var orders := SoundNode.ENGINE_CYCLES.size() == 4 and SoundNode.ENGINE_SIDEBAND_CYCLES.size() == 3 and SoundNode.ENGINE_AMPLITUDES.size() == 4 and SoundNode.ENGINE_SIDEBAND_AMPLITUDES.size() == 3
	for k in SoundNode.ENGINE_CYCLES.size():
		orders = orders and SoundNode.ENGINE_CYCLES[k] == SoundNode.ENGINE_CYCLES[0] * (k + 1)
	for k in SoundNode.ENGINE_SIDEBAND_CYCLES.size():
		orders = orders and SoundNode.ENGINE_SIDEBAND_CYCLES[k] * 2 == SoundNode.ENGINE_CYCLES[0] * (2 * k + 1) and SoundNode.ENGINE_SIDEBAND_AMPLITUDES[k] < SoundNode.ENGINE_AMPLITUDES[3]
	var body_lo := SoundNode.SURFACE_BODY_CYCLES[0] * hz
	var body_hi := SoundNode.SURFACE_BODY_CYCLES[-1] * hz
	var noise_lo := SoundNode.SURFACE_NOISE_CYCLES[0] * hz
	var noise_hi := SoundNode.SURFACE_NOISE_CYCLES[-1] * hz
	var grit_lo := SoundNode.SKID_NOISE_CYCLES[0] * hz
	var grit_hi := SoundNode.SKID_NOISE_CYCLES[-1] * hz
	var wind_lo := SoundNode.WIND_CYCLES[0] * hz
	var wind_hi := SoundNode.WIND_CYCLES[-1] * hz
	# was-> the engine's stack from 56.0 Hz, the squeal's from 800.0 Hz, one
	# rumble table over 60..230 Hz, the grid 2 Hz, the engine AND the squeal
	# starting at zero (SOUND-2: the root is the flat-6's 3rd order at idle,
	# 45 Hz, the squeal's tone 2000 Hz where a real squeal peaks, the grid
	# 0.5 Hz; the squeal's grit carries spread phases, so its first sample is
	# wherever the sum starts - the wrap is seamless regardless: every partial
	# and the AM carrier are whole cycles over the buffer, so sample N would
	# equal sample 0 whatever the phases).
	# was-> partials == 4 + 3 + 20 + 61 + 2 + 51 + 1 (SOUND-3: + 31, the wind's).
	_check(whole and partials == 4 + 3 + 20 + 61 + 2 + 51 + 1 + 31 and wind_lo >= 100.0 and wind_hi <= 700.0 and SoundNode.WIND_CYCLES.size() >= 16 and absf(hz - 0.5) < 1.0e-9 and orders and engine.data.decode_s16(0) == 0 and absf(SoundNode.ENGINE_CYCLES[0] * hz - 45.0) < 1.0e-9 and absf(SoundNode.ENGINE_SIDEBAND_CYCLES[0] * hz - 22.5) < 1.0e-9 and absf(SoundNode.SKID_TONE_CYCLES[0] * hz - 2000.0) < 1.0e-9 and SoundNode.SKID_TONE_CYCLES[1] * 5 == SoundNode.SKID_TONE_CYCLES[0] * 7 and SoundNode.SKID_TONE_AMPLITUDES[1] < SoundNode.SKID_TONE_AMPLITUDES[0] and body_lo >= 60.0 and body_hi <= 230.0 and SoundNode.SURFACE_BODY_CYCLES.size() >= 16 and noise_lo >= 500.0 and noise_hi <= 2000.0 and SoundNode.SURFACE_NOISE_CYCLES.size() >= 16 and grit_lo >= 1500.0 and grit_hi <= 4000.0 and SoundNode.SKID_NOISE_CYCLES.size() >= 16 and absf(SoundNode.SKID_AM_CYCLES * hz - 9.0) < 1.0e-9 and SoundNode.SKID_AM_DEPTH > 0.0 and SoundNode.SKID_AM_DEPTH < 1.0, "every one of the %d partials over the eight tables (was-> seven) is a whole number of cycles over the buffer (the grid %.1f Hz), the AM carrier among them (%.1f Hz, depth %.2f in (0, 1)): the engine's root at %.1f Hz with its 2nd, 3rd and 4th multiples above and the half-order sidebands from %.1f Hz, weaker than the weakest order; the squeal's tone at %.0f Hz with the 7/5 overtone at %.0f, weaker, its grit %d partials over %.0f..%.0f Hz; the rumble's body %d partials over %.0f..%.0f Hz under %d noise partials over %.0f..%.0f Hz; the wind's %d partials over %.0f..%.0f Hz (SOUND-3); the engine starts at zero (its phases 0), and every loop wraps seamlessly whatever its phases" % [partials, hz, SoundNode.SKID_AM_CYCLES * hz, SoundNode.SKID_AM_DEPTH, SoundNode.ENGINE_CYCLES[0] * hz, SoundNode.ENGINE_SIDEBAND_CYCLES[0] * hz, SoundNode.SKID_TONE_CYCLES[0] * hz, SoundNode.SKID_TONE_CYCLES[1] * hz, SoundNode.SKID_NOISE_CYCLES.size(), grit_lo, grit_hi, SoundNode.SURFACE_BODY_CYCLES.size(), body_lo, body_hi, SoundNode.SURFACE_NOISE_CYCLES.size(), noise_lo, noise_hi, SoundNode.WIND_CYCLES.size(), wind_lo, wind_hi])
	var rebuilt := SoundNode.build_buffers()
	# was-> rebuilt.size() == 3 and three buffers distinct (SOUND-3: five, every
	# pair distinct).
	var same := rebuilt.size() == 5
	var distinct := true
	for player_name in all_names:
		same = same and rebuilt[player_name] != streams[player_name] and (rebuilt[player_name] as AudioStreamWAV).data == (streams[player_name] as AudioStreamWAV).data
	for i in all_names.size():
		for j in all_names.size():
			if i < j:
				distinct = distinct and (streams[all_names[i]] as AudioStreamWAV).data != (streams[all_names[j]] as AudioStreamWAV).data
	_check(same and distinct, "DETERMINISM: built again, five new streams (was-> three) carry the same bytes; the five buffers differ from each other pairwise")
	# MEASURED on the built PCM, not the constants (SOUND-2; character pins,
	# wide and honest: the probe's build gave 90.0 / 792.0 / 4000.0 crossings a
	# second - the old buffers 112.0 / 324.0 / 1600.0 - and a skid crest /
	# trough ratio over the envelope's periods of 1.454..1.486, the engine's
	# 0.967..1.034).
	var engine_zcr := _zero_crossings_per_second(engine)
	var surface_zcr := _zero_crossings_per_second(surface)
	var skid_zcr := _zero_crossings_per_second(skid)
	var wind_zcr := _zero_crossings_per_second(wind)
	_check(engine_zcr >= 60.0 and engine_zcr <= 140.0 and surface_zcr >= 400.0 and surface_zcr <= 1600.0 and skid_zcr >= 3000.0 and skid_zcr <= 5000.0 and skid_zcr > surface_zcr and surface_zcr > engine_zcr, "ZERO-CROSSING RATES of the built PCM: the engine's %.1f a second (the 45 Hz root's own 90, between 60 and 140), the rumble's %.1f (the noise layer over the body: between 400 and 1600, the old primes alone gave 324), the squeal's %.1f (the 2000 Hz tone's own 4000, between 3000 and 5000: two and a half times the old 800 Hz chord's 1600 - the note is where a squeal lives, not a howl)" % [engine_zcr, surface_zcr, skid_zcr])
	_check(wind_zcr >= 800.0 and wind_zcr <= 2000.0 and wind.data.decode_s16(0) != 0, "the wind's %.1f a second (SOUND-3: 31 equal partials over 100..700 Hz with spread phases - between 800 and 2000, the probe's build gave 1340; its first sample is wherever the spread sum starts, %d, the wrap seamless regardless)" % [wind_zcr, wind.data.decode_s16(0)])
	var skid_am := _crest_trough_ratios(skid)
	var engine_am := _crest_trough_ratios(engine)
	_check(skid_am.min >= 1.2 and skid_am.max <= 2.0 and engine_am.min >= 0.9 and engine_am.max <= 1.1, "THE AM SHOWS IN THE BUFFER: over each of the %d envelope periods the squeal's crest half is louder than its trough half, an RMS ratio of %.3f..%.3f (between 1.2 and 2.0: a depth of %.2f gives about 1.47), while the engine's, built with no envelope, stays %.3f..%.3f (between 0.9 and 1.1) - the squeal breathes at the wheel's rate, the note does not" % [SoundNode.SKID_AM_CYCLES, skid_am.min, skid_am.max, SoundNode.SKID_AM_DEPTH, engine_am.min, engine_am.max])


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
	_check_sound3_mapping()


## SOUND-3: the wind, the impact and the environment functions at their corners.
func _check_sound3_mapping() -> void:
	# THE WIND: the authored quadratic.
	var half_speed := SoundNode.WIND_SPEED_FULL * 0.5
	var quarter_db := SoundNode.wind_db_of(half_speed)
	var just_under := SoundNode.WIND_SPEED_MIN - 0.001
	_check(
		SoundNode.wind_level_of(0.0) == 0.0 and SoundNode.wind_level_of(just_under) == 0.0 and SoundNode.wind_level_of(-just_under) == 0.0 and SoundNode.wind_db_of(just_under) == SoundNode.MUTE_DB
			and SoundNode.wind_level_of(SoundNode.WIND_SPEED_MIN) > 0.0 and SoundNode.wind_db_of(SoundNode.WIND_SPEED_MIN) > SoundNode.MUTE_DB
			and SoundNode.wind_level_of(half_speed) == 0.25 and SoundNode.wind_level_of(-half_speed) == 0.25 and SoundNode.wind_level_of(SoundNode.WIND_SPEED_FULL) == 1.0 and SoundNode.wind_level_of(SoundNode.WIND_SPEED_FULL * 2.0) == 1.0
			and SoundNode.wind_db_of(SoundNode.WIND_SPEED_FULL) == _snap(SoundNode.WIND_DB_MAX) and absf(SoundNode.wind_db_of(SoundNode.WIND_SPEED_FULL) - SoundNode.WIND_DB_MAX) < 1.0e-9 and SoundNode.wind_db_of(1000.0) == _snap(SoundNode.WIND_DB_MAX)
			and quarter_db == snappedf(SoundNode.WIND_DB_MAX + linear_to_db(0.25), SoundNode.SNAP) and quarter_db == SoundNode.wind_db_of(-half_speed) and quarter_db > SoundNode.MUTE_DB and quarter_db < SoundNode.WIND_DB_MAX
			and SoundNode.wind_db_of(17.3) == snappedf(SoundNode.wind_db_of(17.3), SoundNode.SNAP) and SoundNode.wind_db_of(10.0) < SoundNode.wind_db_of(20.0) and SoundNode.wind_level_of(20.0) == 4.0 * SoundNode.wind_level_of(10.0)
			and SoundNode.WIND_DB_MAX < SoundNode.SURFACE_DB_MAX and SoundNode.WIND_DB_MAX < SoundNode.ENGINE_DB_IDLE + SoundNode.ENGINE_DB_RPM_SPAN + SoundNode.ENGINE_DB_LOAD_SPAN,
		"WIND (SOUND-3, the AUTHORED quadratic law - the references carry tyre-noise speed laws only): muted under %.0f m/s either way, alive from it, the level the square of the speed's share of %.0f m/s (0.25 at %.0f m/s: %.1f dB, four times the level for twice the speed), 1 at and beyond it (%.0f dB at the ceiling, under the rumble's %.0f and the engine's full-load %.0f), snapped" % [SoundNode.WIND_SPEED_MIN, SoundNode.WIND_SPEED_FULL, half_speed, quarter_db, SoundNode.WIND_DB_MAX, SoundNode.SURFACE_DB_MAX, SoundNode.ENGINE_DB_IDLE + SoundNode.ENGINE_DB_RPM_SPAN + SoundNode.ENGINE_DB_LOAD_SPAN],
	)
	# THE IMPACTS: the floor filter, the closing speed, the intensity, the cooldown.
	var wall := Vector3(-1.0, 0.0, 0.0)
	var v := Vector3(15.0, 0.0, -8.0)
	_check(
		not SoundNode.impact_is_wall(Vector3.UP) and SoundNode.impact_is_wall(wall) and SoundNode.impact_is_wall(Vector3(0.0, 0.0, 1.0)) and SoundNode.impact_is_wall(Vector3.DOWN) and SoundNode.impact_is_wall(Vector3(0.0, SoundNode.IMPACT_UP_NORMAL_MAX, 0.0)) and not SoundNode.impact_is_wall(Vector3(0.0, SoundNode.IMPACT_UP_NORMAL_MAX + 0.001, 0.0)) and not SoundNode.impact_is_wall(Vector3(0.6, 0.8, 0.0).normalized()) and SoundNode.impact_is_wall(Vector3(0.8, 0.6, 0.0).normalized())
			and SoundNode.impact_closing_of(wall, v) == 15.0 and SoundNode.impact_closing_of(Vector3(1.0, 0.0, 0.0), v) == 15.0 and SoundNode.impact_closing_of(Vector3(0.0, 0.0, 1.0), v) == 8.0 and SoundNode.impact_closing_of(Vector3(0.0, 0.0, 1.0), Vector3.ZERO) == 0.0,
		"IMPACT FILTER: a normal whose dot with UP is over %.1f is the floor (UP itself, a %.0f-degree slope), not an impact; at or under it a wall (-X, +Z, DOWN, a %.0f-degree face); the closing speed is |n . v| (%.0f against -X for a velocity of %s, %.0f against +Z)" % [SoundNode.IMPACT_UP_NORMAL_MAX, rad_to_deg(acos(0.8)), rad_to_deg(acos(0.6)), SoundNode.impact_closing_of(wall, v), v, SoundNode.impact_closing_of(Vector3(0.0, 0.0, 1.0), v)],
	)
	var half_hit := SoundNode.impact_intensity_of(SoundNode.IMPACT_SPEED_FULL * 0.5)
	_check(
		SoundNode.impact_intensity_of(0.0) == 0.0 and SoundNode.impact_intensity_of(SoundNode.IMPACT_SPEED_MIN - 0.001) == 0.0 and SoundNode.impact_intensity_of(SoundNode.IMPACT_SPEED_MIN) > 0.0 and SoundNode.impact_intensity_of(SoundNode.IMPACT_SPEED_MIN) == _snap(SoundNode.IMPACT_SPEED_MIN / SoundNode.IMPACT_SPEED_FULL)
			and SoundNode.impact_intensity_of(SoundNode.IMPACT_SPEED_FULL) == 1.0 and SoundNode.impact_intensity_of(SoundNode.IMPACT_SPEED_FULL * 3.0) == 1.0 and half_hit == 0.5 and SoundNode.impact_intensity_of(19.7) == _snap(0.985) and SoundNode.impact_intensity_of(3.3333) == snappedf(3.3333 / SoundNode.IMPACT_SPEED_FULL, SoundNode.SNAP)
			and SoundNode.impact_db_of(0.0) == SoundNode.MUTE_DB and SoundNode.impact_db_of(1.0) == _snap(SoundNode.IMPACT_DB_MAX) and absf(SoundNode.impact_db_of(1.0) - SoundNode.IMPACT_DB_MAX) < 1.0e-9 and SoundNode.impact_db_of(2.0) == _snap(SoundNode.IMPACT_DB_MAX) and SoundNode.impact_db_of(0.5) == snappedf(SoundNode.IMPACT_DB_MAX + linear_to_db(0.5), SoundNode.SNAP) and SoundNode.impact_db_of(0.5) < SoundNode.IMPACT_DB_MAX and SoundNode.impact_db_of(0.5) > SoundNode.MUTE_DB
			and SoundNode.impact_ready(SoundNode.IMPACT_COOLDOWN_FRAMES, 0) and not SoundNode.impact_ready(SoundNode.IMPACT_COOLDOWN_FRAMES - 1, 0) and SoundNode.impact_ready(1000, 0) and SoundNode.impact_ready(0, -SoundNode.IMPACT_COOLDOWN_FRAMES) and not SoundNode.impact_ready(114, 100) and SoundNode.impact_ready(115, 100) and SoundNode.IMPACT_COOLDOWN_FRAMES == 15,
		"IMPACT INTENSITY: nothing under a closing speed of %.0f m/s (a nudge is silent), from it the speed's share of %.0f m/s, 0.5 at half, 1 at and beyond, snapped; the thump %.0f dB at 1 (%.1f at 0.5), muted at 0; THE COOLDOWN: a thump may fire %d frames or more after the last (0.25 s at 60 Hz - a sustained scrape thumps at most four times a second), not sooner, and on the first tick" % [SoundNode.IMPACT_SPEED_MIN, SoundNode.IMPACT_SPEED_FULL, SoundNode.IMPACT_DB_MAX, SoundNode.impact_db_of(0.5), SoundNode.IMPACT_COOLDOWN_FRAMES],
	)
	# THE ENVIRONMENT: the openness, the trims, the trimmed volume.
	var closed_wind := SoundNode.wind_offset_of(0.0)
	var closed_surface := SoundNode.surface_offset_of(0.0)
	_check(
		SoundNode.openness_of(INF) == 1.0 and SoundNode.openness_of(SoundNode.ENV_OPEN_RADIUS) == 1.0 and SoundNode.openness_of(SoundNode.ENV_OPEN_RADIUS * 5.0) == 1.0 and SoundNode.openness_of(0.0) == 0.0 and SoundNode.openness_of(SoundNode.ENV_OPEN_RADIUS * 0.5) == 0.5 and SoundNode.openness_of(30.0) == 0.5 and SoundNode.openness_of(-5.0) == 0.0 and SoundNode.openness_of(12.3456) == snappedf(12.3456 / SoundNode.ENV_OPEN_RADIUS, SoundNode.SNAP)
			and closed_wind == _snap(-SoundNode.WIND_SHELTER_DB) and absf(closed_wind - -4.0) < 1.0e-9 and closed_surface == _snap(SoundNode.SURFACE_REFLECT_DB) and absf(closed_surface - 1.5) < 1.0e-9 and SoundNode.wind_offset_of(1.0) == 0.0 and SoundNode.surface_offset_of(1.0) == 0.0 and SoundNode.wind_offset_of(0.5) == _snap(-2.0) and SoundNode.surface_offset_of(0.5) == _snap(0.75) and SoundNode.wind_offset_of(2.0) == 0.0 and SoundNode.surface_offset_of(-1.0) == closed_surface
			and SoundNode.trimmed_db(-20.0, 0.0) == -20.0 and SoundNode.trimmed_db(-20.0, 0.75) == _snap(-19.25) and SoundNode.trimmed_db(-20.0, -2.0) == _snap(-22.0) and SoundNode.trimmed_db(SoundNode.MUTE_DB, 1.5) == SoundNode.MUTE_DB and SoundNode.trimmed_db(SoundNode.MUTE_DB, -4.0) == SoundNode.MUTE_DB and SoundNode.trimmed_db(SoundNode.MUTE_DB + 1.0, -4.0) == SoundNode.MUTE_DB and SoundNode.trimmed_db(-10.329, 0.0) == -10.329 and SoundNode.trimmed_db(SoundNode.SURFACE_DB_MAX, closed_surface) == _snap(SoundNode.SURFACE_DB_MAX + SoundNode.SURFACE_REFLECT_DB),
		"ENVIRONMENT (SOUND-3): the openness is the nearest shell's distance over %.0f m, clamped and snapped (0 on a shell, 0.5 at %.0f m, 1 at and beyond, 1 for no shell at all); the trims a line in it - the wind %.0f dB closed in, the rumble %+.1f dB, both 0 open, %.0f / %+.2f halfway; the written volume is the base plus the trim, snapped, a muted base staying muted whatever the trim (a trim never wakes a silent channel), the base itself to the bit at a trim of 0, and the rumble's ceiling may rise to %.1f dB closed in" % [SoundNode.ENV_OPEN_RADIUS, SoundNode.ENV_OPEN_RADIUS * 0.5, closed_wind, closed_surface, SoundNode.wind_offset_of(0.5), SoundNode.surface_offset_of(0.5), SoundNode.SURFACE_DB_MAX + SoundNode.SURFACE_REFLECT_DB],
	)
	var points := PackedVector2Array([Vector2(30.0, 0.0), Vector2(100.0, 100.0), Vector2(-3.0, -4.0)])
	var shells: Array[Dictionary] = [{"position": Vector2(30.0, 0.0)}, {"id": "x"}, {"position": Vector2(100.0, 100.0)}, {"position": Vector3.ZERO}, {"position": Vector2(-3.0, -4.0)}]
	_check(SoundNode.nearest_distance(PackedVector2Array(), Vector2.ZERO) == INF and SoundNode.nearest_distance(points, Vector2.ZERO) == 5.0 and SoundNode.nearest_distance(points, Vector2(31.0, 0.0)) == 1.0 and SoundNode.nearest_distance(points, Vector2(100.0, 100.0)) == 0.0 and absf(SoundNode.nearest_distance(points, Vector2(200.0, 200.0)) - sqrt(20000.0)) < 1.0e-9 and SoundNode.shell_positions(shells) == points and SoundNode.shell_positions([]).is_empty(), "the nearest distance is a linear scan over the (x, z) shell positions (INF over none; 5 from the origin to (-3, -4) among three, 0 on a shell); shell_positions takes every shell's Vector2 position and nothing else")


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
	# was-> get_child_count() == 3 and players.size() == 3, the three players
	# (SOUND-3: PLAYER_COUNT, 8 - the wind loop and the four pooled thumps).
	var pool_ok := sound.thump_players.size() == SoundNode.THUMP_PLAYERS and SoundNode.PLAYER_COUNT == 8
	for i in sound.thump_players.size():
		var thump: AudioStreamPlayer = sound.thump_players[i]
		pool_ok = pool_ok and thump.name == SoundNode.THUMP_PREFIX + str(i) and thump.get_parent() == sound and thump.stream == streams[SoundNode.THUMP_STREAM] and not thump.playing and thump.volume_db == SoundNode.MUTE_DB
	_check(sound.process_physics_priority == -1 and sound.get_child_count() == SoundNode.PLAYER_COUNT and players.size() == SoundNode.PLAYER_COUNT and sound.engine_player.name == SoundNode.ENGINE_PLAYER and sound.surface_player.name == SoundNode.SURFACE_PLAYER and sound.skid_player.name == SoundNode.SKID_PLAYER and sound.wind_player.name == SoundNode.WIND_PLAYER and sound.engine_player.get_parent() == sound and sound.surface_player.get_parent() == sound and sound.skid_player.get_parent() == sound and sound.wind_player.get_parent() == sound and pool_ok, "it ticks at physics priority -1 (before the car's own tick) and holds %d players (was-> three), %s / %s / %s / %s and the pool %s0..%d, every one the node's own child (the scene root carries no audio of its own) - the only audio players in the tree; the pooled thumps carry the burst, muted and not playing" % [SoundNode.PLAYER_COUNT, SoundNode.ENGINE_PLAYER, SoundNode.SURFACE_PLAYER, SoundNode.SKID_PLAYER, SoundNode.WIND_PLAYER, SoundNode.THUMP_PREFIX, SoundNode.THUMP_PLAYERS - 1])
	_check(sound.engine_player.stream == streams[SoundNode.ENGINE_PLAYER] and sound.surface_player.stream == streams[SoundNode.SURFACE_PLAYER] and sound.skid_player.stream == streams[SoundNode.SKID_PLAYER] and sound.wind_player.stream == streams[SoundNode.WIND_PLAYER] and sound.engine_player.playing and sound.surface_player.playing and sound.skid_player.playing and sound.wind_player.playing, "each looping player loops its shared stream, playing from the start (the volume says what is heard)")
	var idle: float = ArcadeCar.IDLE_RPM
	var limiter: float = ArcadeCar.REDLINE_RPM
	_check(sound.ticks > 0 and sound.read_ticks == sound.ticks and sound.last_running and sound.last_speed == 0.0 and absf(sound.last_rpm - idle) < 100.0 and sound.engine_pitch == SoundNode.engine_pitch_of(sound.last_rpm, idle, limiter) and sound.engine_db == SoundNode.engine_db_of(sound.last_rpm, sound.last_throttle, true, idle, limiter) and sound.engine_db > SoundNode.MUTE_DB and sound.surface_db == SoundNode.MUTE_DB and sound.skid_db == SoundNode.MUTE_DB and sound.skid_intensity == 0.0 and sound.wind_db == SoundNode.MUTE_DB and sound.impacts_fired == 0 and sound.impact_intensity == 0.0 and sound.openness == 1.0 and sound.wind_offset_db == 0.0 and sound.surface_offset_db == 0.0 and sound.nearest_shell_m == INF and root.get_node_or_null(SoundNode.BUILDINGS_NODE) == null and _players_match(sound), "at rest after %d ticks: the engine idles (%.0f rpm read: pitch %.3f, %.1f dB), the rumble, the squeal and the wind muted, no thump, fully open (no Buildings node under the root: none created, the openness 1, the trims 0), the players carrying the mapped values" % [sound.ticks, sound.last_rpm, sound.engine_pitch, sound.engine_db])
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

	# SOUND-3, the wind: the speed written, on tarmac and on gravel alike.
	_write_surface(car, 1.0, 1.0, 0.0, SoundNode.WIND_SPEED_FULL * 0.5)
	await physics_frame
	var wind_tarmac := sound.wind_db
	_write_surface(car, 0.7, 0.6, 1.6, SoundNode.WIND_SPEED_FULL * 0.5)
	await physics_frame
	var wind_gravel := sound.wind_db
	_write_surface(car, 1.0, 1.0, 0.0, -(SoundNode.WIND_SPEED_MIN - 0.5))
	await physics_frame
	var wind_slow := sound.wind_db
	_write_surface(car, 1.0, 1.0, 0.0, -SoundNode.WIND_SPEED_FULL)
	await physics_frame
	_check(wind_tarmac == SoundNode.wind_db_of(SoundNode.WIND_SPEED_FULL * 0.5) and wind_tarmac == snappedf(SoundNode.WIND_DB_MAX + linear_to_db(0.25), SoundNode.SNAP) and wind_gravel == wind_tarmac and wind_slow == SoundNode.MUTE_DB and sound.wind_db == _snap(SoundNode.WIND_DB_MAX) and sound.wind_base_db == sound.wind_db and sound.last_speed == -SoundNode.WIND_SPEED_FULL and absf(sound.wind_player.pitch_scale - SoundNode.WIND_PITCH) < PLAYER_TOLERANCE and _players_match(sound), "THE WIND (SOUND-3) follows forward_speed alone: %.1f dB at %.0f m/s on tarmac and the same to the bit on gravel (grip 0.7 / 0.6, drag 1.6: never a surface term), muted at %.1f m/s in reverse, the ceiling %.0f dB at %.0f m/s in reverse, the pitch fixed at %.1f, the trim 0 here (the base is the written value)" % [wind_tarmac, SoundNode.WIND_SPEED_FULL * 0.5, SoundNode.WIND_SPEED_MIN - 0.5, SoundNode.WIND_DB_MAX, SoundNode.WIND_SPEED_FULL, SoundNode.WIND_PITCH])
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
	# was-> _players_under(root).size() == 3 (SOUND-3: PLAYER_COUNT).
	_check(_sounds_under(root).size() == 1 and watch.sound_for(car) == sound and _attached == attached_before + 1 and _players_under(root).size() == SoundNode.PLAYER_COUNT, "a second attach for the same car is nothing: one node, one signal")

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
	# was-> state_a.size() == 7, "the same seven mapped values", "the six db /
	# pitch values snapped" (SOUND-3: twelve - the wind's written volume, the
	# openness, the two trims and the impact intensity joined, all snapped).
	# The two bare cars stand in each other on the origin, so their
	# move_and_slide pairs them: a REAL slide collision with a wall-like
	# normal, the same on both - the impact intensity is not 0 here, and
	# thumps fire on both nodes alike.
	_check(state_a == state_b and state_a.size() == 12 and snapped and live and _players_match(sound_a) and _players_match(sound_b) and sound_a.skid_intensity > 0.0 and sound_a.skid_intensity < 1.0 and state_a.wind_db == SoundNode.wind_db_of(SAME_READS.speed) and state_a.openness == 1.0 and state_a.wind_offset_db == 0.0 and state_a.surface_offset_db == 0.0 and sound_a.impacts_fired == sound_b.impacts_fired and sound_a.thump_intensity == sound_b.thump_intensity and sound_a.thump_db == sound_b.thump_db, "DETERMINISM: fed the same reads (%.1f rpm, throttle %.2f, grip %.2f / %.2f, drag %.1f, %.1f m/s, slips %.2f / %.2f / %.2f / %.2f) both nodes carry the same twelve mapped values to the bit (was-> seven), the eleven db / pitch / openness / trim / impact values snapped to %.3f (the skid intensity the raw marks intermediate), every channel live, both fully open (no Buildings under the root), the two cars standing in each other on the origin colliding alike (%d thumps each, intensity %.3f): %s" % [SAME_READS.rpm, SAME_READS.throttle, SAME_READS.grip_front, SAME_READS.grip_rear, SAME_READS.drag, SAME_READS.speed, SAME_READS.front_angle, SAME_READS.front_ratio, SAME_READS.rear_angle, SAME_READS.rear_ratio, SoundNode.SNAP, sound_a.impacts_fired, sound_a.thump_intensity, state_a])
	_write_reads(a, SAME_READS)
	await physics_frame
	_check(sound_a.state() == state_a, "the same reads a tick later map to the same values again")
	root.remove_child(a)
	root.remove_child(b)
	await _step(1)
	_check(watch.live_sounds().is_empty() and _sounds_under(root).is_empty(), "both cars out: both nodes gone")
	a.free()
	b.free()


## SOUND-3: a bare car under the root beside an inert BuildingsShells node
## named "Buildings" (build_deferred: its _ready does nothing, no terrain,
## no build) whose shells are written by hand: the node's read-only scan.
func _check_environment() -> void:
	var watch := SoundWatcher.of(self)
	var buildings := BuildingsShells.new()
	buildings.build_deferred = true
	buildings.name = SoundNode.BUILDINGS_NODE
	root.add_child(buildings)
	var car: ArcadeCar = (load(CAR_SCENE) as PackedScene).instantiate()
	root.add_child(car)
	await _step(SETTLE_FRAMES)
	var sound := watch.sound_for(car)
	if not _check(sound != null and buildings.shells.is_empty() and root.get_node_or_null(SoundNode.BUILDINGS_NODE) == buildings, "a bare car under the root beside an inert Buildings node (build_deferred, no shells yet): the node attached"):
		root.remove_child(car)
		car.free()
		root.remove_child(buildings)
		buildings.free()
		return
	_check(sound.nearest_shell_m == INF and sound.openness == 1.0 and sound.wind_offset_db == 0.0 and sound.surface_offset_db == 0.0 and sound.shell_points.is_empty() and sound.read_ticks > 0, "EMPTY SHELLS ARE FULLY OPEN (the Ring while its build still runs): after %d read ticks (the first one scans) the openness is 1, the trims 0, no positions copied" % sound.read_ticks)
	# The shells appear (as the Ring's build places them): the next scan sees
	# them, the positions copied once.
	var near := Vector2(SoundNode.ENV_OPEN_RADIUS * 0.5, 0.0)
	var far := Vector2(100.0, 100.0)
	buildings.shells.append({"id": "a", "position": near, "polygon": PackedVector2Array(), "height": 6.0, "solid": true})
	buildings.shells.append({"id": "b", "position": far, "polygon": PackedVector2Array(), "height": 6.0, "solid": false})
	var shells_size := buildings.shells.size()
	# The scan within a cadence; the reads written the tick before the look
	# (the car's own tick overwrites them after the node has read them).
	await _step(SoundNode.ENV_SCAN_TICKS - 1)
	_write_surface(car, 0.7, 0.6, 1.6, 10.0)
	await physics_frame
	var half_open := sound.openness
	var base := sound.surface_base_db
	var written := sound.surface_db
	var wind_base := sound.wind_base_db
	var wind_written := sound.wind_db
	_check(absf(car.global_position.x) < 0.01 and absf(car.global_position.z) < 0.01 and sound.shell_points == PackedVector2Array([near, far]) and sound.shells_source_id == buildings.get_instance_id() and absf(sound.nearest_shell_m - SoundNode.ENV_OPEN_RADIUS * 0.5) < 1.0e-6 and half_open == 0.5 and sound.wind_offset_db == _snap(-2.0) and sound.surface_offset_db == _snap(0.75), "two shells written on the node, the nearest %.0f m from the car on the origin: within a scan cadence (%d ticks) the positions are copied once (both, in order, from this node) and the openness is 0.5, the trims %.1f / %+.2f dB" % [SoundNode.ENV_OPEN_RADIUS * 0.5, SoundNode.ENV_SCAN_TICKS, sound.wind_offset_db, sound.surface_offset_db])
	_check(base == SoundNode.surface_db_of(1.6, 0.6, 10.0) and written == SoundNode.trimmed_db(base, 0.75) and written == snappedf(base + 0.75, SoundNode.SNAP) and written > base and wind_base == SoundNode.wind_db_of(10.0) and wind_written == SoundNode.trimmed_db(wind_base, -2.0) and wind_written == snappedf(wind_base - 2.0, SoundNode.SNAP) and wind_written < wind_base and _players_match(sound), "THE TRIMS ARE WRITTEN: gravel at 10 m/s maps to a rumble base of %.3f dB and the player carries %.3f (the base plus 0.75), the wind's base %.3f and the player %.3f (the base less 2); the three earlier mapping functions untouched (the base IS surface_db_of)" % [base, written, wind_base, wind_written])
	_write_surface(car, 0.7, 0.6, 1.6, 0.0)
	await physics_frame
	_check(sound.surface_base_db == SoundNode.MUTE_DB and sound.surface_db == SoundNode.MUTE_DB and sound.surface_offset_db == _snap(0.75) and sound.wind_db == SoundNode.MUTE_DB, "standing still among the shells the rumble and the wind stay MUTED: a trim never wakes a silent channel")
	# The car moved away: the scan catches up within a cadence, not before.
	car.global_position = Vector3(200.0, car.global_position.y, 200.0)
	await physics_frame
	var stale_openness := sound.openness
	var caught := -1
	for i in SoundNode.ENV_SCAN_TICKS:
		if sound.openness == 1.0:
			caught = i
			break
		await physics_frame
	_write_surface(car, 0.7, 0.6, 1.6, 10.0)
	await physics_frame
	_check(stale_openness == 0.5 and caught >= 0 and caught < SoundNode.ENV_SCAN_TICKS and sound.openness == 1.0 and absf(sound.nearest_shell_m - far.distance_to(Vector2(200.0, 200.0))) < 0.01 and sound.wind_offset_db == 0.0 and sound.surface_offset_db == 0.0 and sound.surface_db == sound.surface_base_db and sound.surface_db == base and sound.wind_db == sound.wind_base_db and sound.wind_db == wind_base and sound.shell_points.size() == 2, "the car moved to (200, 200), %.0f m from the nearest shell: the tick after, the openness is still the last scan's 0.5 (tick counting, no wall clock); %d ticks later the scan has it at 1 and the trims at 0, the same gravel at 10 m/s written the bases again to the bit (%.3f / %.3f dB), the positions not copied again" % [far.distance_to(Vector2(200.0, 200.0)), caught, sound.surface_db, sound.wind_db])
	_check(buildings.shells.size() == shells_size and buildings.shells[0].position == near and buildings.shells[1].position == far and root.get_node_or_null(SoundNode.BUILDINGS_NODE) == buildings and buildings.get_child_count() == 0 and buildings.bodies.is_empty(), "the Buildings node is read only: its shells as written, no child, no body, the node the same one (never created, never written)")
	print("  ", sound.describe())
	_write_surface(car, 1.0, 1.0, 0.0, 0.0)
	root.remove_child(car)
	root.remove_child(buildings)
	await _step(1)
	_check(watch.live_sounds().is_empty() and _sounds_under(root).is_empty() and root.get_node_or_null(SoundNode.BUILDINGS_NODE) == null, "the car and the Buildings node out: the sound node gone, nothing left under the root")
	car.free()
	buildings.free()


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
	# was-> 3 * cars.size() (SOUND-3: PLAYER_COUNT per node).
	_check(SoundWatcher.has_own_sound(scene, car) and _players_under(scene).size() == SoundNode.PLAYER_COUNT * cars.size() and _players_under(root).size() == SoundNode.PLAYER_COUNT * cars.size() and scene.get_node_or_null(SoundNode.BUILDINGS_NODE) == null, "the shipped pad carries no audio of its own: the only players under it are the watcher's node's, every one a child of the node (has_own_sound sees that node now - the guard for a scene that ships its own is future-proofing); no Buildings node on the pad")
	_check(sound.surfaces == null and watch.surfaces_of(car) == null and sound.surface_at(car.global_position.x, car.global_position.z) == &"road" and sound.engine_player.stream == SoundNode.buffers()[SoundNode.ENGINE_PLAYER], "no Surfaces node on the pad: all road to the squeal's gate; the streams the shared ones")
	var idle: float = ArcadeCar.IDLE_RPM
	var limiter: float = ArcadeCar.REDLINE_RPM
	_check(sound.read_ticks > 0 and sound.skid_db == SoundNode.MUTE_DB and sound.surface_db == SoundNode.MUTE_DB and sound.wind_db == SoundNode.MUTE_DB and sound.engine_db == SoundNode.engine_db_of(sound.last_rpm, sound.last_throttle, true, idle, limiter) and absf(sound.last_rpm - idle) < 100.0 and sound.openness == 1.0 and sound.impacts_fired == 0, "at rest on the pad: the engine idles, the rumble, the squeal and the wind muted, fully open, no thump")

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
	_check(slide.env_open and slide.wind_follows and slide.max_wind_db == SoundNode.wind_db_of(slide.max_speed) and slide.max_wind_db > SoundNode.MUTE_DB and slide.max_wind_db < SoundNode.WIND_DB_MAX and sound.impacts_fired == 0, "SOUND-3 on the pad: fully open every tick (no Buildings node: openness 1, trims 0, the rumble's written volume its base to the bit - SOUND-2's behaviour), the wind following the speed every tick (%.1f dB at most at %.1f m/s, under its %.0f dB ceiling; tarmac's thin wash sits at %.1f there - at this speed the wind is the louder of the two), and the slide touches nothing: no thump" % [slide.max_wind_db, slide.max_speed, SoundNode.WIND_DB_MAX, slide.max_surface_db])
	print("  ", sound.describe())
	await _impact_drive(car, sound)
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
	var out := {"entry_speed": 0.0, "peak_rear_ratio": 0.0, "ticks": 0, "max_skid_db": SoundNode.MUTE_DB, "skid_ticks": 0, "max_engine_pitch": 0.0, "max_rpm": 0.0, "engine_live": true, "players_match": true, "surface_wash_only": true, "max_surface_db": SoundNode.MUTE_DB, "max_speed": 0.0, "env_open": true, "wind_follows": true, "max_wind_db": SoundNode.MUTE_DB}
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


## SOUND-3, the impact drive: the car placed IMPACT_START_X m along the
## shed row's line facing +X (shed 0 stands at x 68..92, z -104..-56: its -X
## face at x = 68, the car's nose 46 m short of it) and driven flat out into
## it. The thump fires on the tick after the move that hit; then the car
## leans on the wall under throttle and nothing thumps again.
func _impact_drive(car: ArcadeCar, sound: SoundNode) -> void:
	var fired_before := sound.impacts_fired
	car.global_transform = Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(IMPACT_START_X, car.global_position.y, IMPACT_SHED_Z))
	await physics_frame
	var placed := absf(car.global_position.x - IMPACT_START_X) < 0.5 and absf(car.global_position.z - IMPACT_SHED_Z) < 0.5 and (-car.global_basis.z).dot(Vector3.RIGHT) > 0.99
	Input.action_press(&"accelerate")
	var approach := 0.0
	var hit_frame := -1
	var thump_playing := false
	var thump_volume := 0.0
	var next_after := -1
	for frame in SPEED_UP_FRAMES_MAX:
		await physics_frame
		if sound.impacts_fired > fired_before:
			hit_frame = frame
			thump_playing = sound.thump_players[0].playing
			thump_volume = sound.thump_players[0].volume_db
			next_after = sound.next_thump
			break
		approach = maxf(approach, absf(sound.last_speed))
	var at_hit := sound.describe()
	var fired_at_hit := sound.impacts_fired
	var intensity := sound.thump_intensity
	var closing := sound.impact_closing
	var normal := sound.impact_normal
	var wall_x := car.global_position.x
	# Leaning on the wall under throttle for a second: the slid velocity
	# closes on nothing, no second thump.
	await _step(IMPACT_LEAN_FRAMES)
	Input.action_release(&"accelerate")
	await _step(2)
	_check(placed and hit_frame >= 0 and fired_at_hit == fired_before + 1 and approach >= IMPACT_SPEED_FULL_APPROACH_MIN and closing >= IMPACT_SPEED_FULL_APPROACH_MIN and closing <= approach + 0.5 and normal.dot(Vector3.LEFT) > 0.99 and absf(wall_x - IMPACT_SHED_FACE_X) < 3.0, "THE IMPACT DRIVE (SOUND-3): placed at x %.0f facing +X and driven at shed 0, the car reaches %.2f m/s and hits its -X face (x %.2f, the normal %s) on frame %d: impacts_fired rose by one, the closing speed %.2f m/s - the velocity read a tick before the move (this tick's is already slid, its normal component 0)" % [IMPACT_START_X, approach, wall_x, normal, hit_frame, closing])
	_check(intensity == SoundNode.impact_intensity_of(closing) and intensity > 0.5 and intensity <= 1.0 and sound.thump_db == SoundNode.impact_db_of(intensity) and thump_playing and absf(thump_volume - sound.thump_db) < PLAYER_TOLERANCE and next_after == 1, "the thump's intensity %.3f is the closing speed's share of %.0f m/s, the pool's first player (%s0) playing at %.2f dB the tick it fired, the pool's next the second (round-robin)" % [intensity, SoundNode.IMPACT_SPEED_FULL, SoundNode.THUMP_PREFIX, sound.thump_db])
	_check(sound.impacts_fired == fired_at_hit and absf(car.global_position.x - wall_x) < 0.5 and absf(sound.last_speed) < 1.0, "leaning on the wall under throttle for %d frames: the car stays on the face (x %.2f, %.2f m/s), the slid velocity closes on nothing, no second thump (%d in all)" % [IMPACT_LEAN_FRAMES, car.global_position.x, sound.last_speed, sound.impacts_fired])
	print("  ", at_hit)


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
	out.env_open = out.env_open and sound.openness == 1.0 and sound.wind_offset_db == 0.0 and sound.surface_offset_db == 0.0 and sound.surface_db == sound.surface_base_db and sound.nearest_shell_m == INF
	out.wind_follows = out.wind_follows and sound.wind_db == SoundNode.wind_db_of(sound.last_speed)
	out.max_wind_db = maxf(out.max_wind_db, sound.wind_db)


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


## Whether the four looping players carry the node's mapped values (was->
## the three; SOUND-3 added the wind): the node holds
## snapped doubles, a player's pitch_scale and volume_db are the engine's
## 32-bit floats of them (PLAYER_TOLERANCE: a float's step at 60 is 4e-6).
func _players_match(sound: SoundNode) -> bool:
	return absf(sound.engine_player.pitch_scale - sound.engine_pitch) < PLAYER_TOLERANCE and absf(sound.engine_player.volume_db - sound.engine_db) < PLAYER_TOLERANCE and absf(sound.surface_player.pitch_scale - sound.surface_pitch) < PLAYER_TOLERANCE and absf(sound.surface_player.volume_db - sound.surface_db) < PLAYER_TOLERANCE and absf(sound.skid_player.pitch_scale - sound.skid_pitch) < PLAYER_TOLERANCE and absf(sound.skid_player.volume_db - sound.skid_db) < PLAYER_TOLERANCE and absf(sound.wind_player.pitch_scale - SoundNode.WIND_PITCH) < PLAYER_TOLERANCE and absf(sound.wind_player.volume_db - sound.wind_db) < PLAYER_TOLERANCE


## Sign changes a second across a buffer's samples, the wrap counted (a
## sample under 0 against one at or over 0).
func _zero_crossings_per_second(stream: AudioStreamWAV) -> float:
	var count := stream.data.size() / 2
	var crossings := 0
	var previous_negative := stream.data.decode_s16((count - 1) * 2) < 0
	for n in count:
		var negative := stream.data.decode_s16(n * 2) < 0
		if negative != previous_negative:
			crossings += 1
		previous_negative = negative
	return float(crossings) / (float(count) / float(SoundNode.MIX_RATE))


## The buffer cut into SKID_AM_CYCLES periods of the envelope, each into its
## crest half (the envelope's sine positive) and its trough half: the least
## and the greatest crest / trough RMS ratio over the periods.
func _crest_trough_ratios(stream: AudioStreamWAV) -> Dictionary:
	var half := SoundNode.BUFFER_SAMPLES / SoundNode.SKID_AM_CYCLES / 2
	var out := {"min": INF, "max": 0.0}
	for period in SoundNode.SKID_AM_CYCLES:
		var ratio := _rms_of(stream, 2 * period * half, half) / _rms_of(stream, (2 * period + 1) * half, half)
		out.min = minf(out.min, ratio)
		out.max = maxf(out.max, ratio)
	return out


## The RMS of `count` samples from `start`, of full scale.
func _rms_of(stream: AudioStreamWAV, start: int, count: int) -> float:
	var acc := 0.0
	for n in count:
		var value := float(stream.data.decode_s16((start + n) * 2))
		acc += value * value
	return sqrt(acc / float(count)) / 32767.0


## A value through the node's own snap: a mapped value equals a constant
## only through it (snappedf(1.15, 0.001) is not the double 1.15 - SOUND-1's
## SKID_PITCH_SOLID, kept as the example; the marks test's alpha_of
## precedent).
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

class_name SoundNode
extends Node
## SOUND-1 (2026-09-30): the first sound the game makes - an engine note, a
## surface rumble and a tyre squeal, for every car in every scene. Backlog
## U-1: the game was completely silent. One of these per car, made and
## placed by the SoundWatch autoload (scripts/sound_watch.gd; the
## SKIDMARKS-1 MarksWatch precedent, line for line where it fits), named
## "Sound" under the car's scene root, in front of the TelemetryRecorder.
##
## THREE PLAYERS, THREE LOOPS: the node holds three AudioStreamPlayer
## children (ENGINE_PLAYER, SURFACE_PLAYER, SKID_PLAYER), each looping one
## short buffer built IN CODE at first need (no asset, no scene: AudioStreamWAV
## from generated 16-bit PCM at MIX_RATE, looped end to end through
## loop_begin / loop_end). Every buffer is BUFFER_SAMPLES long and every
## partial in it is a whole number of cycles over that length (the cycle
## tables below), so the loop point is seamless and the first sample is
## zero. The engine is a low harmonic stack (ENGINE_CYCLES: 56 Hz and its
## first harmonics at pitch 1); the rumble is a dense sum of partials at
## prime cycle counts with spread phases - a deterministic pseudo-noise
## that repeats only once per buffer, not a click; the squeal is a stack
## around 800 Hz (SKID_CYCLES). Deterministic: sums of sines, no random, no
## wall clock; the three streams are shared by every node (built once).
##
## THE MAPPING, every physics tick (process_physics_priority -1: after the
## bubble's -2, with the Surfaces node, before the car's 0 - one state, the
## one the car's last tick left, exactly as MarksLayer reads it):
##   - ENGINE: pitch_scale from engine_rpm - ENGINE_PITCH_IDLE (1.0) at
##     ArcadeCar.IDLE_RPM to ENGINE_PITCH_LIMITER (2.5) at REDLINE_RPM, a line
##     between, clamped to [ENGINE_PITCH_MIN, ENGINE_PITCH_LIMITER] (a run-down
##     engine below idle drops below 1); volume_db from the rpm share and the
##     throttle_pedal load: ENGINE_DB_IDLE (-18) at idle with the pedal up,
##     plus ENGINE_DB_RPM_SPAN (4) at the limiter, plus ENGINE_DB_LOAD_SPAN
##     (6) at full throttle - -8 dB at full load; MUTE_DB when engine_running
##     is false (a stalled engine makes no note).
##   - SURFACE: a level 0..1 from the car's three surface inputs, the ones the
##     Surfaces node feeds (front_surface_grip / rear_surface_grip /
##     surface_rolling_decel; 1 / 1 / 0 on road, and on a scene without the
##     node - the pad): a speed WASH (|forward_speed| / SURFACE_WASH_SPEED
##     times SURFACE_WASH_LEVEL - the only term on tarmac) plus the ROUGHNESS
##     (the rolling drag over SURFACE_DRAG_REF times SURFACE_DRAG_LEVEL, plus
##     the grip deficit 1 - min(front, rear) times SURFACE_DEFICIT_LEVEL)
##     scaled by MOTION (|forward_speed| / SURFACE_SPEED_FULL, 0 at rest: a
##     car standing on gravel rumbles no more than one on tarmac - the rumble
##     is the tyres rolling); volume_db = SURFACE_DB_MAX + linear_to_db(level),
##     MUTE_DB at a level of 0; pitch_scale mildly speed-mapped,
##     SURFACE_PITCH_SLOW at rest to SURFACE_PITCH_FAST at SURFACE_WASH_SPEED.
##   - SKID: the intensity is MarksLayer's OWN triggers, called, never
##     re-declared (a future threshold change moves marks and squeal
##     together): per axle MarksLayer.axle_intensity(slip angle, slip ratio,
##     the axle's peak angle, MarksLayer.axle_driven(front, driven_wheels)),
##     per wheel gated by the wheel's surface exactly as the marks are (only
##     road squeals; a scene without a Surfaces node is all road), the node's
##     intensity the largest wheel's; volume_db = SKID_DB_MAX +
##     linear_to_db(intensity), MUTE_DB at 0 and under SKID_SPEED_MIN (no
##     squeal standing still); pitch_scale rises with the intensity,
##     SKID_PITCH_ONSET to SKID_PITCH_SOLID.
## Every mapped value is snapped to SNAP (0.001) - the same reads give the
## same volume_db / pitch_scale to the bit (tests/sound_test.gd holds two
## nodes to it); the mapping functions are static and pure, the tests pin
## them at their corners. The node's own fields hold the snapped doubles;
## the players' properties are the engine's 32-bit floats of them.
##
## PURELY A READER: nothing here writes the car, the Surfaces node or the
## profile - the reads are engine_rpm, throttle_pedal, engine_running,
## forward_speed, the three surface inputs, the four slip numbers,
## driven_wheels, global_transform (the wheel contact points under a Surfaces
## node) and the ArcadeCar statics; the writes are the three players'
## volume_db and pitch_scale. The car's samples are byte-identical with and
## without the node (the sound test's pin). Non-positional players: the
## camera rides with the car, the car is the listener's subject.

# --- Tuning ------------------------------------------------------------------

## The node's name under the scene root (SoundWatcher gives it) and the
## three players' names under the node.
const NODE_NAME := "Sound"
const ENGINE_PLAYER := "Engine"
const SURFACE_PLAYER := "Surface"
const SKID_PLAYER := "Skid"

## The buffers: sample rate [Hz], length [samples] (half a second: every
## partial's cycle count below is whole over it, so 2 Hz is the grid), the
## peak the PCM is normalised to (of full scale).
const MIX_RATE := 22050
const BUFFER_SAMPLES := 11025
const BUFFER_PEAK := 0.9

## ENGINE: cycles per buffer and amplitude per partial - 56 Hz and its
## first three harmonics at pitch 1 (28 cycles x 2 Hz).
const ENGINE_CYCLES: Array[int] = [28, 56, 84, 112]
const ENGINE_AMPLITUDES: Array[float] = [1.0, 0.5, 0.3, 0.15]

## SURFACE: prime cycle counts (62..226 Hz), equal amplitudes, the phases
## spread by the golden ratio - a rumble that repeats once per buffer.
const SURFACE_CYCLES: Array[int] = [31, 37, 41, 43, 47, 53, 59, 61, 67, 71, 73, 79, 83, 89, 97, 101, 103, 107, 109, 113]
const SURFACE_PHASE_STEP := 0.6180339887498949

## SKID: 800 Hz with a 700, a 900 and a 1600 Hz partial - a squeal.
const SKID_CYCLES: Array[int] = [400, 350, 450, 800]
const SKID_AMPLITUDES: Array[float] = [1.0, 0.3, 0.4, 0.2]

## Silence [dB]: no mapped volume goes under it, a muted channel sits on it.
const MUTE_DB := -60.0

## Every mapped volume_db and pitch_scale is snapped to this.
const SNAP := 0.001

## ENGINE: pitch 1 at idle, ENGINE_PITCH_LIMITER at the redline (both read
## live from ArcadeCar: a config sets them), never under ENGINE_PITCH_MIN;
## ENGINE_DB_IDLE at idle with the pedal up, ENGINE_DB_RPM_SPAN more at the
## limiter, ENGINE_DB_LOAD_SPAN more at full throttle.
const ENGINE_PITCH_IDLE := 1.0
const ENGINE_PITCH_LIMITER := 2.5
const ENGINE_PITCH_MIN := 0.25
const ENGINE_DB_IDLE := -18.0
const ENGINE_DB_RPM_SPAN := 4.0
const ENGINE_DB_LOAD_SPAN := 6.0

## SURFACE: the wash's full speed [m/s] and level, the roughness's full-motion
## speed [m/s], the rolling drag [m/s^2] that is a full drag share and its
## level, the grip deficit's level, the channel's ceiling [dB], the pitch at
## rest and at the wash's full speed.
const SURFACE_WASH_SPEED := 50.0
const SURFACE_WASH_LEVEL := 0.12
const SURFACE_SPEED_FULL := 10.0
const SURFACE_DRAG_REF := 3.0
const SURFACE_DRAG_LEVEL := 0.6
const SURFACE_DEFICIT_LEVEL := 0.28
const SURFACE_DB_MAX := -6.0
const SURFACE_PITCH_SLOW := 0.8
const SURFACE_PITCH_FAST := 1.2

## SKID: the ceiling [dB] at an intensity of 1, the speed gate [m/s] under
## which nothing squeals, the pitch at the onset and at solid.
const SKID_DB_MAX := -4.0
const SKID_SPEED_MIN := 1.5
const SKID_PITCH_ONSET := 0.9
const SKID_PITCH_SOLID := 1.15

## The three streams, built once for every node (buffers()).
static var _buffers: Dictionary = {}

# --- State -------------------------------------------------------------------

## The car whose sound this is (attach()).
var car: ArcadeCar = null

## The scene's Surfaces node, null where it has none (the pad): the squeal's gate.
var surfaces: Surfaces = null

## The players (made in _ready).
var engine_player: AudioStreamPlayer = null
var surface_player: AudioStreamPlayer = null
var skid_player: AudioStreamPlayer = null

## The reads of the last tick (what the mapping saw) and the mapped values
## written to the players, snapped: the tests pin them.
var last_rpm := 0.0
var last_throttle := 0.0
var last_running := true
var last_speed := 0.0
var last_grip_front := 1.0
var last_grip_rear := 1.0
var last_drag := 0.0
var last_front_angle := 0.0
var last_front_ratio := 0.0
var last_rear_angle := 0.0
var last_rear_ratio := 0.0
var engine_pitch := ENGINE_PITCH_IDLE
var engine_db := MUTE_DB
var surface_pitch := SURFACE_PITCH_SLOW
var surface_db := MUTE_DB
var skid_intensity := 0.0
var skid_pitch := SKID_PITCH_ONSET
var skid_db := MUTE_DB

## Ticks run and ticks with a car to read.
var ticks := 0
var read_ticks := 0


func _ready() -> void:
	process_physics_priority = -1
	var streams := buffers()
	engine_player = _make_player(ENGINE_PLAYER, streams[ENGINE_PLAYER])
	surface_player = _make_player(SURFACE_PLAYER, streams[SURFACE_PLAYER])
	skid_player = _make_player(SKID_PLAYER, streams[SKID_PLAYER])
	_write_players()


## Takes the car to sound and the scene's Surfaces node (null for none).
func attach(target_car: ArcadeCar, scene_surfaces: Surfaces) -> void:
	car = target_car
	surfaces = scene_surfaces


func _physics_process(_delta: float) -> void:
	ticks += 1
	if car == null or not is_instance_valid(car) or not car.is_inside_tree():
		return
	read_ticks += 1
	_read()
	_map()
	_write_players()


# =============================================================================
#  The mapping (pure functions of the reads: the tests pin them)
# =============================================================================

## A channel's volume [dB] at a linear `level` under a `top` [dB]: top +
## linear_to_db(level) between MUTE_DB and top, MUTE_DB at no level, snapped.
static func db_of(level: float, top: float) -> float:
	if level <= 0.0:
		return MUTE_DB
	return snappedf(clampf(top + linear_to_db(minf(level, 1.0)), MUTE_DB, top), SNAP)


## The engine's pitch at `rpm`: ENGINE_PITCH_IDLE at `idle`, ENGINE_PITCH_LIMITER
## at `limiter`, a line between and beyond, clamped, snapped.
static func engine_pitch_of(rpm: float, idle: float, limiter: float) -> float:
	var share := (rpm - idle) / (limiter - idle) if limiter > idle else 0.0
	return snappedf(clampf(lerpf(ENGINE_PITCH_IDLE, ENGINE_PITCH_LIMITER, share), ENGINE_PITCH_MIN, ENGINE_PITCH_LIMITER), SNAP)


## The engine's volume [dB]: MUTE_DB when not `running`; else ENGINE_DB_IDLE
## plus the rpm share of ENGINE_DB_RPM_SPAN plus the throttle's share of
## ENGINE_DB_LOAD_SPAN, snapped.
static func engine_db_of(rpm: float, throttle: float, running: bool, idle: float, limiter: float) -> float:
	if not running:
		return MUTE_DB
	var share := clampf((rpm - idle) / (limiter - idle), 0.0, 1.0) if limiter > idle else 0.0
	return snappedf(ENGINE_DB_IDLE + ENGINE_DB_RPM_SPAN * share + ENGINE_DB_LOAD_SPAN * clampf(throttle, 0.0, 1.0), SNAP)


## The rumble's linear level 0..1 at a rolling drag [m/s^2], the lesser axle
## grip and a speed [m/s]: the speed wash plus the roughness scaled by motion.
static func surface_level_of(rolling_decel: float, grip_min: float, speed: float) -> float:
	var motion := clampf(absf(speed) / SURFACE_SPEED_FULL, 0.0, 1.0)
	var wash := clampf(absf(speed) / SURFACE_WASH_SPEED, 0.0, 1.0) * SURFACE_WASH_LEVEL
	var rough := clampf(rolling_decel / SURFACE_DRAG_REF, 0.0, 1.0) * SURFACE_DRAG_LEVEL + clampf(1.0 - grip_min, 0.0, 1.0) * SURFACE_DEFICIT_LEVEL
	return clampf(wash + rough * motion, 0.0, 1.0)


## The rumble's volume [dB]: db_of the level under SURFACE_DB_MAX.
static func surface_db_of(rolling_decel: float, grip_min: float, speed: float) -> float:
	return db_of(surface_level_of(rolling_decel, grip_min, speed), SURFACE_DB_MAX)


## The rumble's pitch: SURFACE_PITCH_SLOW at rest to SURFACE_PITCH_FAST at
## SURFACE_WASH_SPEED, snapped.
static func surface_pitch_of(speed: float) -> float:
	return snappedf(lerpf(SURFACE_PITCH_SLOW, SURFACE_PITCH_FAST, clampf(absf(speed) / SURFACE_WASH_SPEED, 0.0, 1.0)), SNAP)


## The front axle's intensity: MarksLayer's own triggers at the front peak
## slip angle, wheelspin counting where `layout` drives the fronts. (Two
## plain floats, not a Vector2: a Vector2 holds 32-bit floats and the tests
## pin these to the bit against MarksLayer's doubles.)
static func front_intensity(slip_angle: float, slip_ratio: float, layout: ArcadeCar.DrivenWheels) -> float:
	return MarksLayer.axle_intensity(slip_angle, slip_ratio, ArcadeCar.FRONT_PEAK_SLIP_ANGLE, MarksLayer.axle_driven(true, layout))


## The rear axle's intensity, the same way at the rear peak.
static func rear_intensity(slip_angle: float, slip_ratio: float, layout: ArcadeCar.DrivenWheels) -> float:
	return MarksLayer.axle_intensity(slip_angle, slip_ratio, ArcadeCar.REAR_PEAK_SLIP_ANGLE, MarksLayer.axle_driven(false, layout))


## The squeal's volume [dB] at `intensity` and `speed`: MUTE_DB under
## SKID_SPEED_MIN or at no intensity, else db_of under SKID_DB_MAX.
static func skid_db_of(intensity: float, speed: float) -> float:
	if absf(speed) < SKID_SPEED_MIN:
		return MUTE_DB
	return db_of(clampf(intensity, 0.0, 1.0), SKID_DB_MAX)


## The squeal's pitch at `intensity`: SKID_PITCH_ONSET to SKID_PITCH_SOLID, snapped.
static func skid_pitch_of(intensity: float) -> float:
	return snappedf(lerpf(SKID_PITCH_ONSET, SKID_PITCH_SOLID, clampf(intensity, 0.0, 1.0)), SNAP)


## The surface under (x, z) as the gate sees it: the Surfaces node's read
## where the scene has one, road everywhere on a scene without (MarksLayer's
## surface_at, the same rule).
func surface_at(x: float, z: float) -> StringName:
	if surfaces == null or not is_instance_valid(surfaces):
		return TerrainBuilder.SURFACE_ROAD
	return surfaces.classify(x, z)


# =============================================================================
#  The buffers
# =============================================================================

## The three streams, keyed by player name, built at first need and shared.
static func buffers() -> Dictionary:
	if _buffers.is_empty():
		_buffers = build_buffers()
	return _buffers


## Builds the three streams anew (pure: the same bytes every time).
static func build_buffers() -> Dictionary:
	var engine_phases: Array[float] = []
	var skid_phases: Array[float] = []
	var surface_amplitudes: Array[float] = []
	var surface_phases: Array[float] = []
	for i in ENGINE_CYCLES.size():
		engine_phases.append(0.0)
	for i in SKID_CYCLES.size():
		skid_phases.append(0.0)
	for i in SURFACE_CYCLES.size():
		surface_amplitudes.append(1.0)
		surface_phases.append(fmod(float(i + 1) * SURFACE_PHASE_STEP, 1.0) * TAU)
	return {
		ENGINE_PLAYER: make_stream(ENGINE_CYCLES, ENGINE_AMPLITUDES, engine_phases),
		SURFACE_PLAYER: make_stream(SURFACE_CYCLES, surface_amplitudes, surface_phases),
		SKID_PLAYER: make_stream(SKID_CYCLES, SKID_AMPLITUDES, skid_phases),
	}


## A looping 16-bit mono stream of BUFFER_SAMPLES at MIX_RATE: the sum of
## one sine per entry of `cycles` (whole cycles over the buffer) at its
## amplitude and phase, normalised to BUFFER_PEAK.
static func make_stream(cycles: Array[int], amplitudes: Array[float], phases: Array[float]) -> AudioStreamWAV:
	var samples := pcm(cycles, amplitudes, phases)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_FORWARD
	stream.loop_begin = 0
	stream.loop_end = BUFFER_SAMPLES
	var bytes := PackedByteArray()
	bytes.resize(BUFFER_SAMPLES * 2)
	for n in BUFFER_SAMPLES:
		bytes.encode_s16(n * 2, samples[n])
	stream.data = bytes
	return stream


## The samples of such a buffer as 16-bit integers.
static func pcm(cycles: Array[int], amplitudes: Array[float], phases: Array[float]) -> PackedInt32Array:
	var values := PackedFloat64Array()
	values.resize(BUFFER_SAMPLES)
	var peak := 0.0
	for n in BUFFER_SAMPLES:
		var value := 0.0
		for k in cycles.size():
			value += amplitudes[k] * sin(TAU * float(cycles[k]) * float(n) / float(BUFFER_SAMPLES) + phases[k])
		values[n] = value
		peak = maxf(peak, absf(value))
	var scale := BUFFER_PEAK * 32767.0 / peak if peak > 0.0 else 0.0
	var out := PackedInt32Array()
	out.resize(BUFFER_SAMPLES)
	for n in BUFFER_SAMPLES:
		out[n] = clampi(roundi(values[n] * scale), -32768, 32767)
	return out


# =============================================================================
#  The tick
# =============================================================================

## The reads of this tick, in one state, from the car's public fields.
func _read() -> void:
	last_rpm = car.engine_rpm
	last_throttle = car.throttle_pedal
	last_running = car.engine_running
	last_speed = car.forward_speed
	last_grip_front = car.front_surface_grip
	last_grip_rear = car.rear_surface_grip
	last_drag = car.surface_rolling_decel
	last_front_angle = car.front_slip_angle
	last_front_ratio = car.front_slip_ratio
	last_rear_angle = car.rear_slip_angle
	last_rear_ratio = car.rear_slip_ratio


## The mapped values from the reads.
func _map() -> void:
	var idle: float = ArcadeCar.IDLE_RPM
	var limiter: float = ArcadeCar.REDLINE_RPM
	engine_pitch = engine_pitch_of(last_rpm, idle, limiter)
	engine_db = engine_db_of(last_rpm, last_throttle, last_running, idle, limiter)
	surface_db = surface_db_of(last_drag, minf(last_grip_front, last_grip_rear), last_speed)
	surface_pitch = surface_pitch_of(last_speed)
	skid_intensity = _skid_intensity()
	skid_db = skid_db_of(skid_intensity, last_speed)
	skid_pitch = skid_pitch_of(skid_intensity)


## The largest wheel intensity on road: the axle's trigger intensity for each
## of its wheels whose contact point the gate reads as road (the marks' rule).
func _skid_intensity() -> float:
	var front := front_intensity(last_front_angle, last_front_ratio, car.driven_wheels)
	var rear := rear_intensity(last_rear_angle, last_rear_ratio, car.driven_wheels)
	if front <= 0.0 and rear <= 0.0:
		return 0.0
	if surfaces == null or not is_instance_valid(surfaces):
		return maxf(front, rear)
	var points: Array[Vector3] = ArcadeCar.WHEEL_CONTACT_POINTS
	var lie := car.global_transform
	var intensity := 0.0
	for i in points.size():
		var axle := front if i < 2 else rear
		if axle <= intensity:
			continue
		var contact := lie * points[i]
		if surface_at(contact.x, contact.z) == TerrainBuilder.SURFACE_ROAD:
			intensity = axle
	return intensity


func _write_players() -> void:
	if engine_player == null:
		return
	engine_player.pitch_scale = engine_pitch
	engine_player.volume_db = engine_db
	surface_player.pitch_scale = surface_pitch
	surface_player.volume_db = surface_db
	skid_player.pitch_scale = skid_pitch
	skid_player.volume_db = skid_db


func _make_player(player_name: String, stream: AudioStreamWAV) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = player_name
	player.stream = stream
	player.volume_db = MUTE_DB
	add_child(player)
	player.play()
	return player


## The mapped state as a dictionary, the tests' determinism pin.
func state() -> Dictionary:
	return {
		"engine_pitch": engine_pitch, "engine_db": engine_db,
		"surface_pitch": surface_pitch, "surface_db": surface_db,
		"skid_intensity": skid_intensity, "skid_pitch": skid_pitch, "skid_db": skid_db,
	}


## One line for the eye.
func describe() -> String:
	return "sound: engine %.3f x / %.1f dB (%.0f rpm, throttle %.2f), surface %.3f x / %.1f dB (drag %.2f, grip %.2f / %.2f, %.1f m/s), skid %.3f x / %.1f dB (intensity %.3f), %d ticks" % [engine_pitch, engine_db, last_rpm, last_throttle, surface_pitch, surface_db, last_drag, last_grip_front, last_grip_rear, last_speed, skid_pitch, skid_db, skid_intensity, ticks]

class_name SoundNode
extends Node
## SOUND-1 (2026-09-30): the first sound the game makes - an engine note, a
## surface rumble and a tyre squeal, for every car in every scene. Backlog
## U-1: the game was completely silent. One of these per car, made and
## placed by the SoundWatch autoload (scripts/sound_watch.gd; the
## SKIDMARKS-1 MarksWatch precedent, line for line where it fits), named
## "Sound" under the car's scene root, in front of the TelemetryRecorder.
##
## SOUND-2 (2026-09-30): the three buffers re-tuned against real-world
## acoustics - scratch/sound-2-references.md, the verified research file:
## real recordings, the engine order analysis, the tyre-noise and squeal
## literature - after the driver's verdict on the first drive: "The tires
## sound is unbearable, very high... otherwise the game is unplayable." The
## architecture is SOUND-1's to the letter (the watcher, the reads, the
## writes, the switch, the determinism rules); only the buffers' content and
## the mapping's pitch constants changed, every old number kept below as a
## was-> note.
##
## THREE PLAYERS, THREE LOOPS: the node holds three AudioStreamPlayer
## children (ENGINE_PLAYER, SURFACE_PLAYER, SKID_PLAYER), each looping one
## two-second buffer built IN CODE at first need (no asset, no scene:
## AudioStreamWAV from generated 16-bit PCM at MIX_RATE, looped end to end
## through loop_begin / loop_end). Every buffer is BUFFER_SAMPLES long (2 s:
## the grid is 0.5 Hz) and every partial in it is a whole number of cycles
## over that length (the cycle tables below), so the loop point is seamless.
## The engine is a flat-6's order stack (ENGINE_CYCLES: the crank's 3rd / 6th
## / 9th / 12th orders - a four-stroke's firing frequency, rpm / 60 x
## cylinders / 2, is the root, 45 / 90 / 135 / 180 Hz at pitch 1 = idle -
## with weak half-order sidebands, ENGINE_SIDEBAND_CYCLES, the boxer's
## unequal exhaust paths between the banks: 22.5 / 67.5 / 112.5 Hz; every
## phase 0, the pulses phase-locked to the crank, so the first sample is
## zero); the rumble is a body layer (SURFACE_BODY_CYCLES: twenty
## prime-spaced partials over 62..226 Hz, the structure-borne band the cabin
## hears through the suspension) under a broadband noise layer
## (SURFACE_NOISE_CYCLES: 61 partials every 25 Hz over 500..2000 Hz, the
## tread-impact / air-pumping band of rolling noise, each at
## SURFACE_NOISE_AMPLITUDE - the layer's RMS 0.8 of the body's), both with
## phases spread by the golden ratio - a deterministic pseudo-noise that
## repeats only once per buffer, not a click; the squeal is one self-excited
## tone at 2000 Hz with an inharmonic 2800 Hz overtone (SKID_TONE_CYCLES,
## ratio 1.4: the friction-mode region), band-limited grit (SKID_NOISE_CYCLES:
## 51 partials every 50 Hz over 1500..4000 Hz, RMS 0.15 of the tone) and,
## baked into the buffer, an amplitude modulation at SKID_AM_CYCLES (9 Hz at
## pitch 1: the tread blocks through the contact patch at the wheel's
## rotation rate) of SKID_AM_DEPTH, mean-preserving, whole cycles too.
## Deterministic: sums of sines, no random, no wall clock; the three streams
## are shared by every node (built once).
##
## THE MAPPING, every physics tick (process_physics_priority -1: after the
## bubble's -2, with the Surfaces node, before the car's 0 - one state, the
## one the car's last tick left, exactly as MarksLayer reads it):
##   - ENGINE: pitch_scale from engine_rpm - ENGINE_PITCH_IDLE (1.0) at
##     ArcadeCar.IDLE_RPM to ENGINE_PITCH_LIMITER (8.0) at REDLINE_RPM - the
##     3rd order's true span, 45 Hz at idle to 360 Hz at the redline - a line
##     between, clamped to [ENGINE_PITCH_MIN, ENGINE_PITCH_LIMITER] (a run-down
##     engine below idle drops below 1, to half the idle root at the least);
##     volume_db from the rpm share and the
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
##     SURFACE_PITCH_SLOW at rest to SURFACE_PITCH_FAST at SURFACE_WASH_SPEED
##     (0.9 to 1.1: broadband rolling noise is barely pitched).
##   - SKID: the intensity is MarksLayer's OWN triggers, called, never
##     re-declared (a future threshold change moves marks and squeal
##     together): per axle MarksLayer.axle_intensity(slip angle, slip ratio,
##     the axle's peak angle, MarksLayer.axle_driven(front, driven_wheels)),
##     per wheel gated by the wheel's surface exactly as the marks are (only
##     road squeals; a scene without a Surfaces node is all road), the node's
##     intensity the largest wheel's; volume_db = SKID_DB_MAX +
##     linear_to_db(intensity), MUTE_DB at 0 and under SKID_SPEED_MIN (no
##     squeal standing still); pitch_scale rises with the intensity,
##     SKID_PITCH_ONSET to SKID_PITCH_SOLID (0.85 to 1.5, nearly an octave -
##     the real squeal's span; across it the baked AM plays 7.65 to 13.5 Hz,
##     inside the real 3..15 Hz wheel-rotation band).
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

## The buffers: sample rate [Hz], length [samples] (two seconds: every
## partial's cycle count below is whole over it, so 0.5 Hz is the grid), the
## peak the PCM is normalised to (of full scale).
## was-> BUFFER_SAMPLES 11025, half a second on a 2 Hz grid (SOUND-2: the
## flat-6's 3rd-order root at idle, 45 Hz, is 22.5 cycles on that grid, and
## the half-order sidebands 22.5 / 67.5 / 112.5 Hz are whole on no grid
## coarser than 0.5 Hz; on 0.5 Hz every prescribed partial is whole and
## every loop stays seamless).
const MIX_RATE := 22050
const BUFFER_SAMPLES := 44100
const BUFFER_PEAK := 0.9

## ENGINE: cycles per buffer and amplitude per partial - the crank's 3rd,
## 6th, 9th and 12th orders (45 / 90 / 135 / 180 Hz at pitch 1 = idle, 900
## rpm: a four-stroke's firing frequency is rpm / 60 x cylinders / 2, and a
## flat-6's exhaust energy sits at that order's multiples), and the
## half-order sidebands 1.5 / 4.5 / 7.5 (22.5 / 67.5 / 112.5 Hz: the boxer's
## unequal header paths between the banks) at low amplitude. Every phase 0:
## the firing pulses are phase-locked to the crank.
## was-> ENGINE_CYCLES [28, 56, 84, 112] with amplitudes [1.0, 0.5, 0.3,
## 0.15], no sidebands (56 Hz and its first three harmonics: a single
## cylinder's stack, "an organ" - scratch/sound-2-references.md; the 6th
## order is stronger in the recordings, so 0.6).
const ENGINE_CYCLES: Array[int] = [90, 180, 270, 360]
const ENGINE_AMPLITUDES: Array[float] = [1.0, 0.6, 0.3, 0.15]
const ENGINE_SIDEBAND_CYCLES: Array[int] = [45, 135, 225]
const ENGINE_SIDEBAND_AMPLITUDES: Array[float] = [0.08, 0.06, 0.04]

## SURFACE: the body layer - prime-spaced cycle counts (62..226 Hz, the
## structure-borne band the cabin hears through the suspension), equal
## amplitudes of 1, the phases spread by the golden ratio - under the noise
## layer: a partial every 25 Hz over 500..2000 Hz (the tread-impact /
## air-pumping band of rolling noise), every one at SURFACE_NOISE_AMPLITUDE
## (0.8 x sqrt(20 / 61) = 0.458: the layer's RMS 0.8 of the body's), its own
## golden spread. A rumble that repeats once per buffer.
## was-> SURFACE_CYCLES [31, 37, 41, 43, 47, 53, 59, 61, 67, 71, 73, 79, 83,
## 89, 97, 101, 103, 107, 109, 113] on the 2 Hz grid (the same 62..226 Hz
## body, x4 on the 0.5 Hz grid), and no noise layer (rolling noise is
## broadband mechanical noise, 500..2000 Hz dominant; twenty low tones alone
## are a drone - scratch/sound-2-references.md).
const SURFACE_BODY_CYCLES: Array[int] = [124, 148, 164, 172, 188, 212, 236, 244, 268, 284, 292, 316, 332, 356, 388, 404, 412, 428, 436, 452]
const SURFACE_NOISE_CYCLES: Array[int] = [1000, 1050, 1100, 1150, 1200, 1250, 1300, 1350, 1400, 1450, 1500, 1550, 1600, 1650, 1700, 1750, 1800, 1850, 1900, 1950, 2000, 2050, 2100, 2150, 2200, 2250, 2300, 2350, 2400, 2450, 2500, 2550, 2600, 2650, 2700, 2750, 2800, 2850, 2900, 2950, 3000, 3050, 3100, 3150, 3200, 3250, 3300, 3350, 3400, 3450, 3500, 3550, 3600, 3650, 3700, 3750, 3800, 3850, 3900, 3950, 4000]
const SURFACE_NOISE_AMPLITUDE := 0.458
const SURFACE_PHASE_STEP := 0.6180339887498949

## SKID: one self-excited tone at 2000 Hz with an inharmonic overtone at
## 2800 Hz (ratio 1.4, the friction-mode region), band-limited grit - a
## partial every 50 Hz over 1500..4000 Hz at SKID_NOISE_AMPLITUDE (0.15 x
## sqrt(2 / 51) = 0.0297: the layer's RMS 0.15 of the tone's amplitude), the
## golden spread - and an amplitude modulation baked into the buffer:
## SKID_AM_CYCLES (9 Hz at pitch 1, the tread blocks through the contact
## patch at the wheel's rotation rate; 7.65..13.5 Hz across the pitch range,
## inside the real 3..15 Hz band) at SKID_AM_DEPTH, mean-preserving
## (1 + depth x sin, 1 exactly at the first sample).
## was-> SKID_CYCLES [400, 350, 450, 800] with amplitudes [1.0, 0.3, 0.4,
## 0.2] (an 800 Hz chord with a 700, a 900 and a 1600: a steady "howl" an
## octave under where a squeal lives, 1500..4000 Hz peaking near 2 kHz - the
## driver's "unbearable, very high"), no grit, no modulation (a constant
## alarm - scratch/sound-2-references.md).
const SKID_TONE_CYCLES: Array[int] = [4000, 5600]
const SKID_TONE_AMPLITUDES: Array[float] = [1.0, 0.25]
const SKID_NOISE_CYCLES: Array[int] = [3000, 3100, 3200, 3300, 3400, 3500, 3600, 3700, 3800, 3900, 4000, 4100, 4200, 4300, 4400, 4500, 4600, 4700, 4800, 4900, 5000, 5100, 5200, 5300, 5400, 5500, 5600, 5700, 5800, 5900, 6000, 6100, 6200, 6300, 6400, 6500, 6600, 6700, 6800, 6900, 7000, 7100, 7200, 7300, 7400, 7500, 7600, 7700, 7800, 7900, 8000]
const SKID_NOISE_AMPLITUDE := 0.0297
const SKID_AM_CYCLES := 18
const SKID_AM_DEPTH := 0.30

## Silence [dB]: no mapped volume goes under it, a muted channel sits on it.
const MUTE_DB := -60.0

## Every mapped volume_db and pitch_scale is snapped to this.
const SNAP := 0.001

## ENGINE: pitch 1 at idle, ENGINE_PITCH_LIMITER at the redline (both read
## live from ArcadeCar: a config sets them), never under ENGINE_PITCH_MIN;
## ENGINE_DB_IDLE at idle with the pedal up, ENGINE_DB_RPM_SPAN more at the
## limiter, ENGINE_DB_LOAD_SPAN more at full throttle.
## was-> ENGINE_PITCH_LIMITER 2.5, ENGINE_PITCH_MIN 0.25 (SOUND-2: the 3rd
## order runs 45 Hz at idle to 360 Hz at the redline, 8:1 - the true span;
## a run-down or cranking engine dips to at most half the idle root).
const ENGINE_PITCH_IDLE := 1.0
const ENGINE_PITCH_LIMITER := 8.0
const ENGINE_PITCH_MIN := 0.5
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
## was-> SURFACE_PITCH_SLOW 0.8, SURFACE_PITCH_FAST 1.2 (SOUND-2: broadband
## rolling noise is not meaningfully pitched; the research proposed no pitch
## modulation at all, the narrowed range is the smaller change).
const SURFACE_PITCH_SLOW := 0.9
const SURFACE_PITCH_FAST := 1.1

## SKID: the ceiling [dB] at an intensity of 1, the speed gate [m/s] under
## which nothing squeals, the pitch at the onset and at solid.
const SKID_DB_MAX := -4.0
const SKID_SPEED_MIN := 1.5
## was-> SKID_PITCH_ONSET 0.9, SKID_PITCH_SOLID 1.15 (SOUND-2: a real squeal
## spans nearly an octave as the contact resonance shifts with speed and
## load; the pitch stays a function of the intensity alone - the research's
## "intensity AND speed" would change the pure function's signature, and in
## a slide the intensity already runs with the speed).
const SKID_PITCH_ONSET := 0.85
const SKID_PITCH_SOLID := 1.5

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


## Builds the three streams anew (pure: the same bytes every time). The
## engine: the order stack and the sidebands, every phase 0. The surface: the
## body layer at 1 and the noise layer at SURFACE_NOISE_AMPLITUDE, each with
## its own golden spread of phases. The skid: the two tones at phase 0, the
## grit at SKID_NOISE_AMPLITUDE with the golden spread, the AM envelope over
## the sum.
static func build_buffers() -> Dictionary:
	var engine_cycles: Array[int] = []
	var engine_amplitudes: Array[float] = []
	engine_cycles.append_array(ENGINE_CYCLES)
	engine_cycles.append_array(ENGINE_SIDEBAND_CYCLES)
	engine_amplitudes.append_array(ENGINE_AMPLITUDES)
	engine_amplitudes.append_array(ENGINE_SIDEBAND_AMPLITUDES)
	var surface_cycles: Array[int] = []
	var surface_amplitudes: Array[float] = []
	var surface_phases: Array[float] = []
	surface_cycles.append_array(SURFACE_BODY_CYCLES)
	surface_cycles.append_array(SURFACE_NOISE_CYCLES)
	surface_amplitudes.append_array(level_amplitudes(SURFACE_BODY_CYCLES.size(), 1.0))
	surface_amplitudes.append_array(level_amplitudes(SURFACE_NOISE_CYCLES.size(), SURFACE_NOISE_AMPLITUDE))
	surface_phases.append_array(golden_phases(SURFACE_BODY_CYCLES.size()))
	surface_phases.append_array(golden_phases(SURFACE_NOISE_CYCLES.size()))
	var skid_cycles: Array[int] = []
	var skid_amplitudes: Array[float] = []
	var skid_phases: Array[float] = []
	skid_cycles.append_array(SKID_TONE_CYCLES)
	skid_cycles.append_array(SKID_NOISE_CYCLES)
	skid_amplitudes.append_array(SKID_TONE_AMPLITUDES)
	skid_amplitudes.append_array(level_amplitudes(SKID_NOISE_CYCLES.size(), SKID_NOISE_AMPLITUDE))
	skid_phases.append_array(level_amplitudes(SKID_TONE_CYCLES.size(), 0.0))
	skid_phases.append_array(golden_phases(SKID_NOISE_CYCLES.size()))
	return {
		ENGINE_PLAYER: make_stream(engine_cycles, engine_amplitudes, level_amplitudes(engine_cycles.size(), 0.0)),
		SURFACE_PLAYER: make_stream(surface_cycles, surface_amplitudes, surface_phases),
		SKID_PLAYER: make_stream(skid_cycles, skid_amplitudes, skid_phases, SKID_AM_CYCLES, SKID_AM_DEPTH),
	}


## `count` copies of `level` (a table's equal amplitudes, or its zero phases).
static func level_amplitudes(count: int, level: float) -> Array[float]:
	var out: Array[float] = []
	out.resize(count)
	out.fill(level)
	return out


## `count` phases spread by the golden ratio [rad]: the k-th (from 1) is
## fmod(k x SURFACE_PHASE_STEP, 1) turns - deterministic, never two alike,
## the pseudo-noise's spread.
static func golden_phases(count: int) -> Array[float]:
	var out: Array[float] = []
	out.resize(count)
	for i in count:
		out[i] = fmod(float(i + 1) * SURFACE_PHASE_STEP, 1.0) * TAU
	return out


## A looping 16-bit mono stream of BUFFER_SAMPLES at MIX_RATE: the sum of
## one sine per entry of `cycles` (whole cycles over the buffer) at its
## amplitude and phase, under the optional envelope (pcm), normalised to
## BUFFER_PEAK.
static func make_stream(cycles: Array[int], amplitudes: Array[float], phases: Array[float], envelope_cycles: int = 0, envelope_depth: float = 0.0) -> AudioStreamWAV:
	var samples := pcm(cycles, amplitudes, phases, envelope_cycles, envelope_depth)
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


## The samples of such a buffer as 16-bit integers. With `envelope_cycles`
## over 0 the sum is multiplied, before the normalisation, by the
## mean-preserving envelope 1 + envelope_depth x sin(TAU x envelope_cycles x
## n / BUFFER_SAMPLES) - whole cycles too, 1 exactly at the first sample, so
## the loop stays seamless (the skid's AM; the engine and the surface pass
## none).
static func pcm(cycles: Array[int], amplitudes: Array[float], phases: Array[float], envelope_cycles: int = 0, envelope_depth: float = 0.0) -> PackedInt32Array:
	var values := PackedFloat64Array()
	values.resize(BUFFER_SAMPLES)
	var peak := 0.0
	for n in BUFFER_SAMPLES:
		var value := 0.0
		for k in cycles.size():
			value += amplitudes[k] * sin(TAU * float(cycles[k]) * float(n) / float(BUFFER_SAMPLES) + phases[k])
		if envelope_cycles > 0:
			value *= 1.0 + envelope_depth * sin(TAU * float(envelope_cycles) * float(n) / float(BUFFER_SAMPLES))
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

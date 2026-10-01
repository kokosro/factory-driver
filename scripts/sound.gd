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
## SOUND-3 (2026-10-01): three more layers, the smallest honest version of
## each, after the driver's line (docs/design/user-thoughts-economy.org:
## "the sound: real sim data, also, it matters in which environment the car
## is, if it's in a tunel, within the buildings or in open nature, the sound
## is different"): a WIND layer (a fourth loop, its level a quadratic of the
## speed), IMPACT thumps (one-shot bursts on the car's real slide collisions
## - the move_and_slide seam, below) and an ENVIRONMENT trim (the nearest
## building shell trims the wind down and the rumble up). The SOUND-1/2
## architecture stays to the letter; the three earlier channels' mapping
## functions keep their signatures, the environment is its own offset layer
## on top of them.
##
## CAT-AWARE-1 (2026-10-01): the cat-aware mix, after the driver's ruling
## (decisions.org 679E66EC): "the tire squeke is still scaring my cat. can we
## try to do all sounds with cat awareness / wellbeing in mind." All sounds
## are henceforth designed with cat wellbeing in mind; the SOUND-2/3
## realistic mix stays the default and FD_CAT=1 (CAT_ENV_VAR, read ONCE per
## node in _ready, the FD_SOUND convention; anything but "1" is off) switches
## a node to the cat mix. THE MECHANISM: one shared audio bus, CAT_BUS_NAME,
## that this class creates and owns - the AudioServer is global, its buses
## are saved nowhere, so the first cat-mode node creates the bus (one
## AudioEffectLowPassFilter on it, cutoff CAT_LOWPASS_HZ, set once and never
## touched per tick) and the last cat-mode node leaving the tree removes it
## (cat_nodes counts them); every player of a cat-mode node is routed to it
## at creation. On top of the bus, two channels are treated per tick, pure
## functions over the unchanged mapping: the squeal's written pitch is the
## mapped one x CAT_SKID_PITCH (the 2000 Hz fundamental at 1200 Hz) and its
## volume the mapped one + CAT_SKID_DB_TRIM; a thump's volume is the mapped
## one + CAT_THUMP_DB_TRIM and the burst plays at CAT_THUMP_PITCH (the 2 ms
## attack stretched to 2.5 ms: a softer edge). The engine, the rumble and
## the wind keep their mapping to the bit and sit under the cutoff (the
## engine's orders reach 1440 Hz at the redline, the rumble's noise 2200
## Hz); what the low-pass cuts is the top of the squeal's grit.
## THE REASONING: the domestic cat's audiogram (Heffner & Heffner 1985,
## Hearing Research 19:85-88) puts the best sensitivity in the low-to-mid
## kHz with high-frequency hearing reaching tens of kHz; the squeal's 2000 /
## 2800 Hz tones and 1500..4000 Hz grit sit right in that most sensitive
## region, and sudden loud transients startle. THE GUARANTEE: with FD_CAT
## unset (or anything but "1") every written value, every state() value the
## SOUND-3 pin read, every buffer byte and every player's bus is what it
## was - the cat branch of each cat function is dead, no bus is created, no
## AudioServer call is made. HONESTY: v1's shape is authored from the
## literature's shape, not measured on a cat; the five CAT_ constants are
## one-line knobs.
##
## FOUR LOOPING PLAYERS AND A BURST POOL (was-> THREE PLAYERS, THREE LOOPS:
## SOUND-3 added the wind loop and the thump pool): the node holds four
## looping AudioStreamPlayer children (ENGINE_PLAYER, SURFACE_PLAYER,
## SKID_PLAYER, WIND_PLAYER), each looping one two-second buffer built IN
## CODE at first need (no asset, no scene: AudioStreamWAV from generated
## 16-bit PCM at MIX_RATE, looped end to end through loop_begin / loop_end),
## and THUMP_PLAYERS more (THUMP_PREFIX + 0..3, the pool) that each play the
## one shared non-looping impact burst on demand. Every loop buffer is
## BUFFER_SAMPLES long (2 s: the grid is 0.5 Hz) and every partial in it is
## a whole number of cycles over that length (the cycle tables below), so
## the loop point is seamless.
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
## rotation rate) of SKID_AM_DEPTH, mean-preserving, whole cycles too; the
## wind is broadband pseudo-noise alone (WIND_CYCLES: 31 partials every 20
## Hz over 100..700 Hz, equal amplitudes, the golden spread - the
## low-passed roar a cabin hears, no tone in it); the thump is a short
## decaying burst (IMPACT_BUFFER_SAMPLES, 371 ms: a low sine at
## IMPACT_TONE_HZ, 90 Hz, phase 0, under IMPACT_PARTIAL_HZ knock partials
## with the golden spread, the sum under an exponential decay of
## IMPACT_DECAY_S and a 2 ms linear attack - it plays once and stops, so the
## whole-cycles rule does not apply to it: nothing wraps).
## Deterministic: sums of sines, no random, no wall clock; the five streams
## (was-> three) are shared by every node (built once).
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
##   - WIND (SOUND-3): a level 0..1 from |forward_speed| alone - AUTHORED
##     LAW: clamp((speed / WIND_SPEED_FULL)^2, 0, 1), muted under
##     WIND_SPEED_MIN. scratch/sound-2-references.md carries speed laws for
##     TYRE noise only (tread impact ~ speed^2, air pumping ~ speed^4, its
##     lines 23-24) and nothing for aerodynamic noise; the quadratic is the
##     implementer's choice (a sound-pressure ~ dynamic-pressure shape), not
##     a measured one. Never surface-dependent: the same on tarmac, gravel
##     or in the air - the wind reads no surface field. volume_db = db_of the
##     level under WIND_DB_MAX (-10: ambience, under the engine and the
##     rumble); pitch_scale fixed at WIND_PITCH (1.0).
##   - IMPACTS (SOUND-3): one-shot thumps on the car's REAL collisions, read
##     through the only honest seam: the car (scripts/car.gd, frozen) calls
##     move_and_slide() once per tick and reads velocity back, so at this
##     node's tick (priority -1, before the car's 0) get_slide_collision_count
##     / get_slide_collision(i) hold the car's PREVIOUS tick's slide - one
##     tick stale, deterministic. Real contact, not a deceleration proxy.
##     Per collision: the normal n = get_normal(); n . UP over
##     IMPACT_UP_NORMAL_MAX is the floor (the pad's WorldBoundaryShape3D, the
##     ring's slab), not an impact, skipped; the CLOSING SPEED is |n . v|
##     where v is the velocity THIS NODE READ ONE TICK EARLIER (last tick's
##     car.velocity: the velocity the car carried into the tick of the move,
##     up to that tick's own force integration - measured on the pad 19.70
##     against a 19.75 m/s approach). NOT this tick's car.velocity: after
##     move_and_slide the velocity is already slid along the wall and its
##     normal component is exactly 0 at every impact (the rehearsal probe
##     measured 0.000 on the shed), so a closing speed off it would never
##     thump. intensity = clamp(closing / IMPACT_SPEED_FULL, 0, 1), nothing
##     under IMPACT_SPEED_MIN (a gentle nudge is silent), the largest wall
##     contact of the tick; a cooldown of IMPACT_COOLDOWN_FRAMES physics
##     frames since the last fired thump (0.25 s at 60 Hz: a sustained rail
##     scrape thumps at most every 0.25 s, and only when the car pushes into
##     the rail again with a normal component over the gate - the slid
##     velocity of a scrape has none). volume_db = db_of the intensity under
##     IMPACT_DB_MAX (-2), snapped, on the next pooled player round-robin
##     (next_thump = (next_thump + 1) % THUMP_PLAYERS: deterministic), and
##     play(); impacts_fired counts them. THE CONES NEVER THUMP AND THAT IS
##     RIGHT: the pad's cones (scripts/pad_cone.gd) are RigidBody3D on layer
##     4 (1 << 2), the car's mask is 1, the server never pairs them -
##     "move_and_slide neither slows nor deflects for a cone", the pad
##     drives them through TestPad's own bump() - so a cone nudge is no slide
##     collision and no thump, correct by the physics, not a gap. The rails
##     (the PhysicsBubble's F1 rail chunk bodies on layer 1 when active,
##     scripts/physics_bubble.gd), the trunk chunk bodies and the pad's
##     sheds (layer 1) DO pair, and thump.
##   - ENVIRONMENT v1 (SOUND-3): "within the buildings vs open nature", the
##     simplest honest version - read-only over the ring's building shells
##     (scripts/buildings_shells.gd, BuildingsShells.shells: one Dictionary
##     per building with "position" a Vector2 (x, z) - 2839 of them on the
##     Ring, under the scene root's child named "Buildings"). The node looks
##     the child up by name (get_node_or_null(BUILDINGS_NODE) on the scene
##     root, its parent) - NEVER BuildingsShells.of(): that static CREATES
##     the node where Road, Terrain and Forest exist and would start a heavy
##     build in a scene that was never to have buildings; nothing here
##     creates or writes anything. Every ENV_SCAN_TICKS physics ticks (0.5 s
##     at 60 Hz, tick counting, never the wall clock) the horizontal distance
##     from the car to the NEAREST shell position is scanned linearly over a
##     PackedVector2Array of the shell positions built once when the shells
##     are first seen non-empty (no allocation per scan, no spatial index:
##     2839 distances every half second is trivial); an empty or absent
##     shells array (the pad, a bare car, the Ring while its build still
##     runs) is fully open. openness = clamp(d / ENV_OPEN_RADIUS, 0, 1),
##     and two trims, pure functions: the wind down by WIND_SHELTER_DB x (1 -
##     openness) (sheltered among buildings), the rumble up by
##     SURFACE_REFLECT_DB x (1 - openness) (walls throw some of it back); the
##     written volume_db is trimmed_db(base, offset): the base plus the
##     offset, snapped, never under MUTE_DB, and a MUTED base stays muted (a
##     trim never wakes a silent channel). On a scene without a Buildings
##     node the openness is 1 and both offsets 0: the pad's sound is
##     bit-identical to SOUND-2's. NOT IN v1, honestly: no low-pass or
##     equalisation, no reverb bus (a real early-reflection tail is future
##     work); and TUNNELS DO NOT EXIST anywhere in the world yet (no tunnel
##     geometry is built), so the driver's "in a tunnel" case is documented
##     as not-yet-existing rather than faked.
## Every mapped value is snapped to SNAP (0.001) - the same reads give the
## same volume_db / pitch_scale to the bit (tests/sound_test.gd holds two
## nodes to it); the mapping functions are static and pure, the tests pin
## them at their corners. The node's own fields hold the snapped doubles;
## the players' properties are the engine's 32-bit floats of them.
##
## PURELY A READER: nothing here writes the car, the Surfaces node, the
## Buildings node or the profile - the reads are engine_rpm, throttle_pedal,
## engine_running, forward_speed, the three surface inputs, the four slip
## numbers, driven_wheels, global_transform (the wheel contact points under a
## Surfaces node; the position for the environment scan), the ArcadeCar
## statics and, since SOUND-3, the CharacterBody3D engine API velocity,
## get_slide_collision_count() and get_slide_collision(i).get_normal() (all
## read-only) plus BuildingsShells.shells on a scene that has the node; the
## writes are the players' volume_db and pitch_scale plus play() on the
## pooled thump players (was-> the three players' volume_db and pitch_scale)
## and, in cat mode only (CAT-AWARE-1), the players' bus at creation, the
## pooled thump players' pitch_scale and the one shared audio bus this class
## creates and removes (was-> no audio bus touched; still none with FD_CAT
## off).
## The car's samples are byte-identical with and without the node (the
## sound test's pin). Non-positional players: the camera rides with the car,
## the car is the listener's subject.

# --- Tuning ------------------------------------------------------------------

## The node's name under the scene root (SoundWatcher gives it) and the
## players' names under the node: the four loops, and the thump pool
## THUMP_PREFIX + 0..THUMP_PLAYERS-1 (was-> the three players' names:
## SOUND-3 added the wind and the pool). THUMP_STREAM keys the burst in
## buffers(). PLAYER_COUNT is what one node holds (the tests count them).
const NODE_NAME := "Sound"
const ENGINE_PLAYER := "Engine"
const SURFACE_PLAYER := "Surface"
const SKID_PLAYER := "Skid"
const WIND_PLAYER := "Wind"
const THUMP_PREFIX := "Thump"
const THUMP_STREAM := "Thump"
const THUMP_PLAYERS := 4
const PLAYER_COUNT := 4 + THUMP_PLAYERS

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

## WIND (SOUND-3): broadband pseudo-noise alone - a partial every 20 Hz
## over 100..700 Hz (cycles 200..1400 step 40 on the 0.5 Hz grid: 31
## partials, every one whole cycles, the loop seamless), equal amplitudes
## of 1, the golden spread of phases. The low-passed roar a cabin hears at
## speed: no tone, no modulation. AUTHORED (no recording analysed for it;
## scratch/sound-2-references.md covers the engine, the tyres and the
## squeal only).
const WIND_CYCLES: Array[int] = [200, 240, 280, 320, 360, 400, 440, 480, 520, 560, 600, 640, 680, 720, 760, 800, 840, 880, 920, 960, 1000, 1040, 1080, 1120, 1160, 1200, 1240, 1280, 1320, 1360, 1400]

## IMPACT BURST (SOUND-3): IMPACT_BUFFER_SAMPLES at MIX_RATE (8192: 371 ms),
## non-looping - a low sine at IMPACT_TONE_HZ (90 Hz, phase 0, amplitude 1:
## the body's thud) under knock partials IMPACT_PARTIAL_HZ at
## IMPACT_PARTIAL_AMPLITUDES with the golden spread, the sum under
## exp(-t / IMPACT_DECAY_S) (60 ms: at the buffer's end the envelope is
## exp(-6.2), 0.002 - no tail left to cut) and a linear attack over
## IMPACT_ATTACK_SAMPLES (44: 2 ms, so the spread phases open without a
## step). Frequencies in Hz, not cycles: the burst plays once and stops,
## nothing wraps, the whole-cycles rule is the loops' alone. AUTHORED.
const IMPACT_BUFFER_SAMPLES := 8192
const IMPACT_TONE_HZ := 90.0
const IMPACT_PARTIAL_HZ: Array[float] = [135.0, 200.0, 290.0, 420.0, 610.0]
const IMPACT_PARTIAL_AMPLITUDES: Array[float] = [0.5, 0.35, 0.25, 0.18, 0.12]
const IMPACT_DECAY_S := 0.06
const IMPACT_ATTACK_SAMPLES := 44

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

## WIND (SOUND-3): the speed [m/s] of a full level (the level is the square
## of the speed's share of it - the AUTHORED law, see the header: the
## references carry tyre-noise speed laws only, nothing for aero), the speed
## under which it is muted, the ceiling [dB] (ambience: under the engine's
## -8..-18 and the rumble's -6), the fixed pitch.
const WIND_SPEED_FULL := 50.0
const WIND_SPEED_MIN := 5.0
const WIND_DB_MAX := -10.0
const WIND_PITCH := 1.0

## IMPACTS (SOUND-3): a contact whose normal's dot with UP is over
## IMPACT_UP_NORMAL_MAX is the floor (a slope under 45.6 degrees), not a
## wall; the closing speed [m/s] of a full thump, the one under which a
## contact is a silent nudge, the frames between two thumps, the ceiling
## [dB] at a full one.
const IMPACT_UP_NORMAL_MAX := 0.7
const IMPACT_SPEED_FULL := 20.0
const IMPACT_SPEED_MIN := 1.0
const IMPACT_COOLDOWN_FRAMES := 15
const IMPACT_DB_MAX := -2.0

## ENVIRONMENT v1 (SOUND-3): the scene root's child that holds the shells,
## the ticks between two nearest-shell scans, the distance [m] to the
## nearest shell at and beyond which the car is fully open, the wind's cut
## [dB] and the rumble's lift [dB] when fully closed in (openness 0).
const BUILDINGS_NODE := "Buildings"
const ENV_SCAN_TICKS := 30
const ENV_OPEN_RADIUS := 60.0
const WIND_SHELTER_DB := 4.0
const SURFACE_REFLECT_DB := 1.5

## CAT-AWARE-1, the cat-aware mix (the driver's ruling, 2026-10-01: "the
## tire squeke is still scaring my cat. can we try to do all sounds with cat
## awareness / wellbeing in mind."). The environment variable that switches
## it ("1" on, anything else off; read once per node in _ready) and the name
## of the one shared audio bus the cat-mode nodes create, play through and
## remove.
const CAT_ENV_VAR := "FD_CAT"
const CAT_BUS_NAME := "Cat"
## The cutoff [Hz] of the one gentle low-pass on the cat bus. The domestic
## cat's audiogram (Heffner & Heffner 1985, Hearing Research 19:85-88) puts
## the best sensitivity in the low-to-mid kHz, with high-frequency hearing
## reaching tens of kHz (to about 79 kHz measured); the 2..8 kHz band is the
## peak-sensitivity region, and the squeal's 2000 / 2800 Hz tones and
## 1500..4000 Hz grit sit right in it. What passes substantially: the
## engine's orders (45 / 90 / 135 / 180 Hz at idle, x8 at the redline: 360
## .. 1440 Hz - all under the cutoff; the brief's "up to 2880 Hz" was 360 x
## 8, the root's redline pitch multiplied twice), the wind (100..700 Hz),
## the rumble (the body 62..226 Hz whole, the 500..2000 Hz noise layer, to
## 2200 Hz at its fastest pitch). What it cuts: the top of the cat-pitched
## squeal's grit (900..2400 Hz at pitch 1, to 3600 Hz at solid) and
## whatever else would sit above - a gentle slope, not a wall.
const CAT_LOWPASS_HZ := 3000.0
## The squeal's pitch multiplier in cat mode: the 2000 Hz fundamental plays
## at 1200 Hz at pitch 1 (1020..1800 Hz across the mapped 0.85..1.5), under
## the cat's peak band, still unambiguously a slide cue. And its ceiling's
## trim [dB].
const CAT_SKID_PITCH := 0.6
const CAT_SKID_DB_TRIM := -6.0
## The thump in cat mode: the burst plays slower (the 2 ms attack stretches
## to 2.5 ms, the transient's edge softens, the 90 Hz thud sits at 72 Hz)
## and its ceiling is trimmed [dB] - sudden loud transients startle.
const CAT_THUMP_PITCH := 0.8
const CAT_THUMP_DB_TRIM := -8.0
## HONESTY: v1's shape is authored from the literature's shape, not measured
## on a cat; each of the five constants above is a one-line knob the driver
## can re-tune.

## The five streams (was-> three), built once for every node (buffers()).
static var _buffers: Dictionary = {}

## CAT-AWARE-1: the live cat-mode nodes (the bus's owners: the first creates
## it, the last one leaving the tree removes it). 0 with FD_CAT off.
static var cat_nodes := 0

# --- State -------------------------------------------------------------------

## The car whose sound this is (attach()).
var car: ArcadeCar = null

## The scene's Surfaces node, null where it has none (the pad): the squeal's gate.
var surfaces: Surfaces = null

## The players (made in _ready): the four loops and the thump pool.
var engine_player: AudioStreamPlayer = null
var surface_player: AudioStreamPlayer = null
var skid_player: AudioStreamPlayer = null
var wind_player: AudioStreamPlayer = null
var thump_players: Array[AudioStreamPlayer] = []

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

## SOUND-3. The wind: its base volume from the speed, and the written one
## (the base under the environment's trim). The rumble's base likewise
## (surface_db above is the WRITTEN one, trimmed; was-> the base itself, the
## two equal wherever the offset is 0 - every scene without buildings).
var wind_base_db := MUTE_DB
var wind_db := MUTE_DB
var surface_base_db := MUTE_DB

## SOUND-3, the impacts: this tick's and the previous tick's read of the
## car's velocity (the closing speed is against the PREVIOUS: see the
## header), the largest wall contact's closing speed and normal this tick
## (0 / ZERO for none), the intensity it maps to, the last fired thump's
## intensity and volume, the tick it fired on, the pool's next player, the
## count of thumps fired (the tests read it).
var last_velocity := Vector3.ZERO
var prev_velocity := Vector3.ZERO
var impact_closing := 0.0
var impact_normal := Vector3.ZERO
var impact_intensity := 0.0
var thump_intensity := 0.0
var thump_db := MUTE_DB
var last_impact_tick := -IMPACT_COOLDOWN_FRAMES
var next_thump := 0
var impacts_fired := 0

## SOUND-3, the environment: the car's position this tick, the shell
## positions (x, z) built once from the first non-empty shells seen and the
## instance id of the Buildings node they came from, the ticks until the
## next scan (0: this tick scans), the last scan's nearest distance [m]
## (INF: no shell), the openness and the two trims.
var last_position := Vector3.ZERO
var shell_points := PackedVector2Array()
var shells_source_id := 0
var env_ticks_to_scan := 0
var nearest_shell_m := INF
var openness := 1.0
var wind_offset_db := 0.0
var surface_offset_db := 0.0

## Ticks run and ticks with a car to read.
var ticks := 0
var read_ticks := 0

## CAT-AWARE-1: whether this node plays the cat-aware mix (FD_CAT read once,
## in _ready; false: the SOUND-2/3 realistic mix to the bit).
var cat_mode := false


func _ready() -> void:
	process_physics_priority = -1
	# CAT-AWARE-1: the switch read once (the FD_SOUND convention), and in cat
	# mode the bus made BEFORE the players, which are routed to it at creation.
	cat_mode = cat_mode_of(OS.get_environment(CAT_ENV_VAR))
	if cat_mode:
		cat_nodes += 1
		_ensure_cat_bus()
		tree_exiting.connect(_on_cat_node_exiting, CONNECT_ONE_SHOT)
	var streams := buffers()
	engine_player = _make_player(ENGINE_PLAYER, streams[ENGINE_PLAYER])
	surface_player = _make_player(SURFACE_PLAYER, streams[SURFACE_PLAYER])
	skid_player = _make_player(SKID_PLAYER, streams[SKID_PLAYER])
	wind_player = _make_player(WIND_PLAYER, streams[WIND_PLAYER])
	for i in THUMP_PLAYERS:
		thump_players.append(_make_thump_player(THUMP_PREFIX + str(i), streams[THUMP_STREAM]))
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
	_scan_environment()
	_map()
	_write_players()
	_fire_thump()


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


## SOUND-3, the wind's linear level 0..1 at `speed` [m/s], either way: 0
## under WIND_SPEED_MIN, else the square of the speed's share of
## WIND_SPEED_FULL, clamped - the AUTHORED quadratic law (the references
## carry tyre-noise speed laws only). No surface term: the wind is the same
## on every surface and in the air.
static func wind_level_of(speed: float) -> float:
	var v := absf(speed)
	if v < WIND_SPEED_MIN:
		return 0.0
	var share := v / WIND_SPEED_FULL
	return clampf(share * share, 0.0, 1.0)


## The wind's base volume [dB]: db_of the level under WIND_DB_MAX.
static func wind_db_of(speed: float) -> float:
	return db_of(wind_level_of(speed), WIND_DB_MAX)


## SOUND-3, whether a slide collision's `normal` is a wall (an impact) and
## not the floor: its dot with UP at or under IMPACT_UP_NORMAL_MAX.
static func impact_is_wall(normal: Vector3) -> bool:
	return normal.dot(Vector3.UP) <= IMPACT_UP_NORMAL_MAX


## The closing speed [m/s] of `velocity` against a contact `normal`: |n . v|.
static func impact_closing_of(normal: Vector3, velocity: Vector3) -> float:
	return absf(normal.dot(velocity))


## The thump's intensity 0..1 at a closing speed [m/s]: 0 under
## IMPACT_SPEED_MIN, else the speed's share of IMPACT_SPEED_FULL, clamped,
## snapped.
static func impact_intensity_of(closing: float) -> float:
	if closing < IMPACT_SPEED_MIN:
		return 0.0
	return snappedf(clampf(closing / IMPACT_SPEED_FULL, 0.0, 1.0), SNAP)


## The thump's volume [dB] at `intensity`: db_of under IMPACT_DB_MAX.
static func impact_db_of(intensity: float) -> float:
	return db_of(clampf(intensity, 0.0, 1.0), IMPACT_DB_MAX)


## Whether a thump may fire on `tick` after one fired on `last_tick`:
## IMPACT_COOLDOWN_FRAMES or more frames between them.
static func impact_ready(tick: int, last_tick: int) -> bool:
	return tick - last_tick >= IMPACT_COOLDOWN_FRAMES


## SOUND-3, the openness 0..1 at a nearest-shell distance [m]: the
## distance's share of ENV_OPEN_RADIUS, clamped, snapped; INF (no shell) is
## 1.
static func openness_of(distance: float) -> float:
	if not is_finite(distance):
		return 1.0
	return snappedf(clampf(distance / ENV_OPEN_RADIUS, 0.0, 1.0), SNAP)


## The wind's trim [dB] at `openness`: -WIND_SHELTER_DB at 0 (closed in), 0
## at 1 (open), a line between, snapped.
static func wind_offset_of(openness_value: float) -> float:
	return snappedf(-WIND_SHELTER_DB * (1.0 - clampf(openness_value, 0.0, 1.0)), SNAP)


## The rumble's trim [dB] at `openness`: +SURFACE_REFLECT_DB at 0, 0 at 1,
## a line between, snapped.
static func surface_offset_of(openness_value: float) -> float:
	return snappedf(SURFACE_REFLECT_DB * (1.0 - clampf(openness_value, 0.0, 1.0)), SNAP)


## A channel's written volume [dB]: `base` plus `offset`, snapped, never
## under MUTE_DB; a muted base stays MUTE_DB whatever the offset (a trim
## never wakes a silent channel). At an offset of 0 the base itself, to the
## bit (snappedf is idempotent on a snapped value).
static func trimmed_db(base: float, offset: float) -> float:
	if base <= MUTE_DB:
		return MUTE_DB
	return snappedf(maxf(base + offset, MUTE_DB), SNAP)


## CAT-AWARE-1, whether an FD_CAT `setting` asks for the cat mix: "1" does,
## anything else (unset, "0", any other text) does not.
static func cat_mode_of(setting: String) -> bool:
	return setting == "1"


## The squeal's written pitch: in `cat` mode the mapped `base_pitch` times
## CAT_SKID_PITCH, snapped; otherwise `base_pitch` itself, to the bit.
static func cat_skid_pitch_of(base_pitch: float, cat: bool) -> float:
	if not cat:
		return base_pitch
	return snappedf(base_pitch * CAT_SKID_PITCH, SNAP)


## The squeal's written volume [dB]: in `cat` mode the mapped `base_db` plus
## CAT_SKID_DB_TRIM, snapped, never under MUTE_DB, a muted base staying
## muted (trimmed_db's rule: a trim never wakes a silent channel); otherwise
## `base_db` itself, to the bit.
static func cat_skid_db_of(base_db: float, cat: bool) -> float:
	if not cat or base_db <= MUTE_DB:
		return base_db
	return snappedf(maxf(base_db + CAT_SKID_DB_TRIM, MUTE_DB), SNAP)


## The thump's pitch: CAT_THUMP_PITCH in `cat` mode, 1 otherwise.
static func cat_thump_pitch_of(cat: bool) -> float:
	return CAT_THUMP_PITCH if cat else 1.0


## The thump's written volume [dB]: in `cat` mode the mapped `base_db` plus
## CAT_THUMP_DB_TRIM, snapped, never under MUTE_DB, a muted base staying
## muted; otherwise `base_db` itself, to the bit.
static func cat_thump_db_of(base_db: float, cat: bool) -> float:
	if not cat or base_db <= MUTE_DB:
		return base_db
	return snappedf(maxf(base_db + CAT_THUMP_DB_TRIM, MUTE_DB), SNAP)


## Whether the cat bus exists on the AudioServer.
static func cat_bus_ready() -> bool:
	return AudioServer.get_bus_index(CAT_BUS_NAME) != -1


## Makes the cat bus where there is none: a new bus at the end of the
## layout (it sends to Master), named CAT_BUS_NAME, with the one low-pass at
## CAT_LOWPASS_HZ - set here once, never touched again. Called by cat-mode
## nodes only.
static func _ensure_cat_bus() -> bool:
	if AudioServer.get_bus_index(CAT_BUS_NAME) != -1:
		return true
	AudioServer.add_bus()
	AudioServer.set_bus_name(AudioServer.bus_count - 1, CAT_BUS_NAME)
	var lowpass := AudioEffectLowPassFilter.new()
	lowpass.cutoff_hz = CAT_LOWPASS_HZ
	AudioServer.add_bus_effect(AudioServer.get_bus_index(CAT_BUS_NAME), lowpass)
	return true


## Removes the cat bus once no cat-mode node is left (cat_nodes 0); nothing
## while one lives, nothing where there is no such bus.
static func _release_cat_bus() -> void:
	if cat_nodes > 0:
		return
	var index := AudioServer.get_bus_index(CAT_BUS_NAME)
	if index != -1:
		AudioServer.remove_bus(index)


## A cat-mode node leaving the tree (connected in _ready, in cat mode only,
## one shot): one owner fewer, the bus removed with the last.
func _on_cat_node_exiting() -> void:
	cat_nodes = maxi(cat_nodes - 1, 0)
	_release_cat_bus()


## The distance [m] from `at` (x, z) to the nearest of `points`, a linear
## scan; INF for none.
static func nearest_distance(points: PackedVector2Array, at: Vector2) -> float:
	if points.is_empty():
		return INF
	var least := INF
	for p in points:
		least = minf(least, at.distance_squared_to(p))
	return sqrt(least)


## The (x, z) positions of `shells` (BuildingsShells.shells: one Dictionary
## per building, "position" a Vector2), the ones that carry one.
static func shell_positions(shells: Array[Dictionary]) -> PackedVector2Array:
	var out := PackedVector2Array()
	for shell in shells:
		var p: Variant = shell.get("position")
		if p is Vector2:
			out.append(p)
	return out


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

## The five streams (was-> three), keyed by player name (the burst by
## THUMP_STREAM), built at first need and shared.
static func buffers() -> Dictionary:
	if _buffers.is_empty():
		_buffers = build_buffers()
	return _buffers


## Builds the five streams anew (pure: the same bytes every time; was->
## three). The engine: the order stack and the sidebands, every phase 0. The
## surface: the body layer at 1 and the noise layer at
## SURFACE_NOISE_AMPLITUDE, each with its own golden spread of phases. The
## skid: the two tones at phase 0, the grit at SKID_NOISE_AMPLITUDE with the
## golden spread, the AM envelope over the sum. The wind (SOUND-3): the
## noise table at 1 with the golden spread. The thump (SOUND-3): the burst,
## impact_stream().
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
		WIND_PLAYER: make_stream(WIND_CYCLES, level_amplitudes(WIND_CYCLES.size(), 1.0), golden_phases(WIND_CYCLES.size())),
		THUMP_STREAM: impact_stream(),
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


## SOUND-3: the impact burst as a non-looping 16-bit mono stream of
## IMPACT_BUFFER_SAMPLES at MIX_RATE (impact_pcm), normalised to BUFFER_PEAK.
static func impact_stream() -> AudioStreamWAV:
	var samples := impact_pcm()
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = MIX_RATE
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	var bytes := PackedByteArray()
	bytes.resize(IMPACT_BUFFER_SAMPLES * 2)
	for n in IMPACT_BUFFER_SAMPLES:
		bytes.encode_s16(n * 2, samples[n])
	stream.data = bytes
	return stream


## The burst's samples as 16-bit integers: the IMPACT_TONE_HZ sine at phase
## 0 and amplitude 1 plus the IMPACT_PARTIAL_HZ partials at their amplitudes
## with the golden spread, times exp(-t / IMPACT_DECAY_S), times the linear
## attack n / IMPACT_ATTACK_SAMPLES over the first IMPACT_ATTACK_SAMPLES (so
## the first sample is 0), normalised to BUFFER_PEAK. Deterministic, no
## random; frequencies in Hz (nothing wraps).
static func impact_pcm() -> PackedInt32Array:
	var phases := golden_phases(IMPACT_PARTIAL_HZ.size())
	var values := PackedFloat64Array()
	values.resize(IMPACT_BUFFER_SAMPLES)
	var peak := 0.0
	for n in IMPACT_BUFFER_SAMPLES:
		var t := float(n) / float(MIX_RATE)
		var value := sin(TAU * IMPACT_TONE_HZ * t)
		for k in IMPACT_PARTIAL_HZ.size():
			value += IMPACT_PARTIAL_AMPLITUDES[k] * sin(TAU * IMPACT_PARTIAL_HZ[k] * t + phases[k])
		value *= exp(-t / IMPACT_DECAY_S)
		if n < IMPACT_ATTACK_SAMPLES:
			value *= float(n) / float(IMPACT_ATTACK_SAMPLES)
		values[n] = value
		peak = maxf(peak, absf(value))
	var scale := BUFFER_PEAK * 32767.0 / peak if peak > 0.0 else 0.0
	var out := PackedInt32Array()
	out.resize(IMPACT_BUFFER_SAMPLES)
	for n in IMPACT_BUFFER_SAMPLES:
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
	# SOUND-3: the position (the environment scan), the velocity (this tick's
	# read becomes next tick's closing-speed reference) and the previous
	# tick's slide, the largest wall contact's closing speed against the
	# velocity read a tick ago (see the header: this tick's velocity is
	# already slid along the wall, its normal component 0).
	last_position = car.global_position
	prev_velocity = last_velocity
	last_velocity = car.velocity
	impact_closing = 0.0
	impact_normal = Vector3.ZERO
	for i in car.get_slide_collision_count():
		var normal := car.get_slide_collision(i).get_normal()
		if not impact_is_wall(normal):
			continue
		var closing := impact_closing_of(normal, prev_velocity)
		if closing > impact_closing:
			impact_closing = closing
			impact_normal = normal


## SOUND-3: every ENV_SCAN_TICKS read ticks (the first one included) the
## nearest shell of the scene's Buildings node - looked up by name on the
## scene root, never created - and the openness and the two trims from it.
## The shell positions are copied once, from the first non-empty shells seen
## on a given node; an absent node, or one whose build has not placed its
## shells yet, is fully open.
func _scan_environment() -> void:
	if env_ticks_to_scan > 0:
		env_ticks_to_scan -= 1
		return
	env_ticks_to_scan = ENV_SCAN_TICKS - 1
	var scene_root := get_parent()
	var buildings: BuildingsShells = null
	if scene_root != null:
		buildings = scene_root.get_node_or_null(BUILDINGS_NODE) as BuildingsShells
	if buildings == null:
		shell_points = PackedVector2Array()
		shells_source_id = 0
	elif shell_points.is_empty() or shells_source_id != buildings.get_instance_id():
		shell_points = shell_positions(buildings.shells)
		shells_source_id = buildings.get_instance_id()
	nearest_shell_m = nearest_distance(shell_points, Vector2(last_position.x, last_position.z))
	openness = openness_of(nearest_shell_m)
	wind_offset_db = wind_offset_of(openness)
	surface_offset_db = surface_offset_of(openness)


## The mapped values from the reads.
func _map() -> void:
	var idle: float = ArcadeCar.IDLE_RPM
	var limiter: float = ArcadeCar.REDLINE_RPM
	engine_pitch = engine_pitch_of(last_rpm, idle, limiter)
	engine_db = engine_db_of(last_rpm, last_throttle, last_running, idle, limiter)
	# was-> surface_db = surface_db_of(...) written as is (SOUND-3: the base,
	# then the environment's trim on it; the same value wherever the trim is 0).
	surface_base_db = surface_db_of(last_drag, minf(last_grip_front, last_grip_rear), last_speed)
	surface_db = trimmed_db(surface_base_db, surface_offset_db)
	surface_pitch = surface_pitch_of(last_speed)
	skid_intensity = _skid_intensity()
	# was-> skid_db = skid_db_of(...) / skid_pitch = skid_pitch_of(...) written
	# as is (CAT-AWARE-1: the cat functions on top; with cat_mode false they
	# return the mapped value itself, to the bit).
	skid_db = cat_skid_db_of(skid_db_of(skid_intensity, last_speed), cat_mode)
	skid_pitch = cat_skid_pitch_of(skid_pitch_of(skid_intensity), cat_mode)
	wind_base_db = wind_db_of(last_speed)
	wind_db = trimmed_db(wind_base_db, wind_offset_db)
	impact_intensity = impact_intensity_of(impact_closing)


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
	wind_player.pitch_scale = WIND_PITCH
	wind_player.volume_db = wind_db


## SOUND-3: a thump on this tick's mapped impact, if any and if the cooldown
## has run: the next pooled player round-robin at impact_db_of the
## intensity, played from its start.
func _fire_thump() -> void:
	if impact_intensity <= 0.0 or thump_players.is_empty() or not impact_ready(ticks, last_impact_tick):
		return
	thump_intensity = impact_intensity
	thump_db = impact_db_of(impact_intensity)
	last_impact_tick = ticks
	var player := thump_players[next_thump]
	next_thump = (next_thump + 1) % THUMP_PLAYERS
	# was-> player.volume_db = thump_db (CAT-AWARE-1: thump_db stays the mapped
	# base; in cat mode the written volume is trimmed and the burst plays
	# slower - the pitch is written in cat mode only, a realistic thump's
	# player is never touched beyond its volume and play()).
	player.volume_db = cat_thump_db_of(thump_db, cat_mode)
	if cat_mode:
		player.pitch_scale = cat_thump_pitch_of(cat_mode)
	player.play()
	impacts_fired += 1


func _make_player(player_name: String, stream: AudioStreamWAV) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = player_name
	player.stream = stream
	player.volume_db = MUTE_DB
	# CAT-AWARE-1: routed to the cat bus at creation, in cat mode only.
	if cat_mode:
		player.bus = CAT_BUS_NAME
	add_child(player)
	player.play()
	return player


## A pooled thump player: the burst loaded, muted, NOT playing until a thump.
func _make_thump_player(player_name: String, stream: AudioStreamWAV) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = player_name
	player.stream = stream
	player.volume_db = MUTE_DB
	if cat_mode:
		player.bus = CAT_BUS_NAME
	add_child(player)
	return player


## The mapped state as a dictionary, the tests' determinism pin (sixteen
## values; was-> twelve: CAT-AWARE-1 added the cat mode, the squeal's
## written pitch and volume under it - the same numbers as skid_pitch /
## skid_db, which ARE the written ones - and the thump's pitch; the twelve
## earlier values unchanged with FD_CAT off; was-> seven: SOUND-3 added the
## wind's written volume, the openness, the two trims and the impact
## intensity).
func state() -> Dictionary:
	return {
		"engine_pitch": engine_pitch, "engine_db": engine_db,
		"surface_pitch": surface_pitch, "surface_db": surface_db,
		"skid_intensity": skid_intensity, "skid_pitch": skid_pitch, "skid_db": skid_db,
		"wind_db": wind_db, "openness": openness, "wind_offset_db": wind_offset_db, "surface_offset_db": surface_offset_db,
		"impact_intensity": impact_intensity,
		"cat_mode": cat_mode, "skid_pitch_cat": skid_pitch, "skid_db_cat": skid_db, "thump_pitch_cat": cat_thump_pitch_of(cat_mode),
	}


## One line for the eye (was-> ending at the ticks: CAT-AWARE-1 added the
## cat mix's on / off at the tail).
func describe() -> String:
	return "sound: engine %.3f x / %.1f dB (%.0f rpm, throttle %.2f), surface %.3f x / %.1f dB (drag %.2f, grip %.2f / %.2f, %.1f m/s), skid %.3f x / %.1f dB (intensity %.3f), wind %.1f dB, openness %.3f (nearest shell %.1f m, trims %.2f / %+.2f dB), %d thumps (last %.3f at %.1f dB), %d ticks, cat mix %s" % [engine_pitch, engine_db, last_rpm, last_throttle, surface_pitch, surface_db, last_drag, last_grip_front, last_grip_rear, last_speed, skid_pitch, skid_db, skid_intensity, wind_db, openness, nearest_shell_m, wind_offset_db, surface_offset_db, impacts_fired, thump_intensity, thump_db, ticks, "on" if cat_mode else "off"]

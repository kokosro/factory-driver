extends SceneTree
## Headless refuel test: REFUEL AT STATION (scripts/refuel.gd; the driver's
## need on the Ring, "running low on fuel already" / "maybe get some gas
## from somewhere"). Run via tests/run_tests.sh, or:
##
##   godot --headless --path . --import
##   godot --headless --fixed-fps 60 --path . --script res://tests/refuel_test.gd
##
## THE KEY: refuel is U, plain (physical 85), and on no other action, the
## engine's built-ins walked too (the minimap test's check, on this key;
## the brief's H is the engine's own plain ui_filedialog_show_hidden, as
## the flagger and the minimap found before). THE STATIONS: the focus
## table's nine E2 records, every one can("sell_fuel"), all nine kept by
## Refuel.selling; the radius 30 m. THE CORE, pure, on synthetic records
## (a station at a real record's lat/lon, the car set off its projected
## position by hand): 10 m off it is near, 30 m off it is near
## (inclusive), 30.001 m off it is not, 4 km off it is not; two stations,
## the nearer one; the real nine at the certified spawn (2037.199,
## -1355.401): none within 30 m (E2.4 is the nearest, 311 m through the
## game's own projection; the brief's python list put E2.7 at ~430 m,
## which the projection the skeleton is tested against does not bear out) - the Ring is
## inert at the spawn. THE RING (eifel_ring.tscn): the Refuel node is
## wired (car, hud), its line is a child of the HUD named RefuelHint,
## hidden at the spawn after the settle, nothing filled (fill_count 0)
## and the tank only ever lower (the idle burn); the car put at E2.4's
## position through its own reset_to (the honest teleport: the same call
## R makes, origin.y 0, the car stood on the profile's height there) with
## the tank at 20 L and the engine off (the idle burn would otherwise
## move the tank under the bit-exact assertions): the line is up with the
## exact text; the key held ~30 ticks fills the tank to exactly
## FUEL_TANK_CAPACITY_L (the bits), one more tick and fuel_mass is exactly
## fuel_l x FUEL_DENSITY; released and held again at a full tank: still
## exactly capacity, no further fill counted; the wear, the battery's
## wear and charge and the odometer set to marks by hand before the fill
## stay at them (nothing restored but the fuel); moved 100 m off, the
## line is down and the key fills nothing. THE PAD (main.tscn): no Refuel
## node in the tree (by name and by class), no RefuelHint under its HUD
## after the settle, the key held there fills nothing (the tank at 20 L
## only ever lower), and the scene file's text names no refuel. THE
## DETERMINISM: a fresh car (scenes/car.tscn) under a bare Refuel node at
## E2.4 filled the same way holds the identical fuel_l bits and the
## identical fuel_mass after a tick. No network, no python; writes
## nothing under /tmp and nothing to the data dir (the store is off
## headless). Exits 0 on success, 1 on any failed check.

const MAIN_SCENE := "res://scenes/main.tscn"
const RING_SCENE := "res://scenes/eifel_ring.tscn"
const CAR_SCENE := "res://scenes/car.tscn"

## Physics frames to let the car settle after a load or a reset.
const SETTLE_FRAMES := 20

## Ticks the key is held for a fill, and ticks the engine-off car is
## watched for a tank that stays.
const HOLD_FRAMES := 30

## The certified spawn (scenes/eifel_ring.tscn's Car transform) and the
## station the Ring's checks use: E2.4, the nearest to the spawn (311 m;
## measured through the game's own projection, SkeletonLoader.wgs84_to_local,
## the one the skeleton and the E11 anchor are tested against).
const SPAWN_XZ := Vector2(2037.199, -1355.401)
const RING_STATION_ID := "E2.4"
const STATIONS_COUNT := 9

## The tank the fill starts from [L], and how far the car is moved off the
## station to lose the line [m].
const PART_TANK_L := 20.0
const AWAY_M := 100.0

## The marks set by hand on what a fill must not restore.
const WEAR_MARK := 0.25
const BATTERY_WEAR_MARK := 0.1
const BATTERY_CHARGE_MARK := 0.5
const ODOMETER_MARK_M := 1234.5

## How far a mark may drift over the fill's ticks by the car's own
## bookkeeping at rest (the key-on load on the battery, ~1e-5 over 30
## ticks; the tyres' ~1e-12): a fill restores nothing, so nothing moves
## toward new at all, and nothing moves this far in any direction.
const MARK_DRIFT := 1e-3

var _failures := 0


func _initialize() -> void:
	_run.call_deferred()


func _run() -> void:
	_check_key()
	_check_stations()
	_check_core()
	var ring := await _check_ring()
	await _check_pad()
	await _check_determinism(ring)
	_finish()


# =============================================================================
#  The key
# =============================================================================

## U, plain, and nothing else on plain U: every action's key events walked,
## the engine's built-in ui_ actions among them.
func _check_key() -> void:
	var events := InputMap.action_get_events(Refuel.ACTION) if InputMap.has_action(Refuel.ACTION) else []
	var on_key := events.size() == 1 and events[0] is InputEventKey and (events[0] as InputEventKey).physical_keycode == Refuel.KEY and (events[0] as InputEventKey).keycode == 0 and (events[0] as InputEventKey).get_modifiers_mask() == 0 and not (events[0] as InputEventKey).command_or_control_autoremap
	var others := PackedStringArray()
	for action in InputMap.get_actions():
		if action == Refuel.ACTION:
			continue
		for event in InputMap.action_get_events(action):
			if not event is InputEventKey:
				continue
			var key := event as InputEventKey
			if (key.physical_keycode == Refuel.KEY or key.keycode == Refuel.KEY) and key.get_modifiers_mask() == 0 and not key.command_or_control_autoremap:
				others.append(String(action))
	_check(Refuel.KEY == KEY_U and OS.get_keycode_string(Refuel.KEY) == "U", "the refuel key is U (physical %d, the engine names it %s)" % [Refuel.KEY, OS.get_keycode_string(Refuel.KEY)])
	_check(on_key and others.is_empty(), "refuel's one event is plain physical U (keycode 0, no modifier), and no other action - the engine's built-ins included - is on plain U (%s)" % (", ".join(others) if not others.is_empty() else "none"))
	_check(Refuel.HINT_TEXT == "FUEL STATION near — hold U to fill" and Refuel.HINT_TEXT.contains(OS.get_keycode_string(Refuel.KEY)), "the line names the key: \"%s\"" % Refuel.HINT_TEXT)


# =============================================================================
#  The stations
# =============================================================================

func _check_stations() -> void:
	var stations := Buildings.by_element("E2")
	var selling := 0
	for station: Buildings.Record in stations:
		if station.can("sell_fuel"):
			selling += 1
	_check(stations.size() == STATIONS_COUNT and selling == STATIONS_COUNT, "the focus table places %d E2 gas stations, %d of them can(sell_fuel)" % [stations.size(), selling])
	_check(Refuel.selling(stations).size() == STATIONS_COUNT and Refuel.PRIVILEGE == "sell_fuel", "Refuel.selling keeps all %d (the privilege %s)" % [Refuel.selling(stations).size(), Refuel.PRIVILEGE])
	_check(Refuel.RADIUS_M == 30.0, "the radius is %.1f m" % Refuel.RADIUS_M)
	var reference := Buildings.record(RING_STATION_ID)
	_check(reference != null and reference.element == "E2" and reference.can("sell_fuel"), "%s is an E2 that sells fuel, at (%.2f, %.2f) region metres" % [RING_STATION_ID, reference.position().x if reference != null else 0.0, reference.position().y if reference != null else 0.0])


# =============================================================================
#  The core, pure
# =============================================================================

## A synthetic station at exactly (0, 0) region metres: position() overridden,
## so the boundary is tested on exact float32 numbers (a real record's
## projected position is ~2 km from the origin, where a float32 metre has
## 0.0002 m steps and "exactly 30 m off" is not representable).
class OriginStation:
	extends Buildings.Record
	func position() -> Vector2:
		return Vector2.ZERO


## A synthetic record at a real record's lat/lon: its position() is the
## projection's, the car set off it by hand.
func _synthetic(id: String, like: Buildings.Record) -> Buildings.Record:
	var record := Buildings.Record.new()
	record.id = id
	record.element = "E2"
	record.lat = like.lat
	record.lon = like.lon
	record.privileges = PackedStringArray(["sell_fuel"])
	return record


func _check_core() -> void:
	var real := Buildings.by_element("E2")
	var reference := Buildings.record(RING_STATION_ID)
	if not _check(reference != null, "the core's reference station exists"):
		return
	var origin := OriginStation.new()
	origin.id = "O"
	origin.element = "E2"
	origin.privileges = PackedStringArray(["sell_fuel"])
	var one: Array[Buildings.Record] = [origin]
	var zero := Vector2.ZERO
	_check(origin.position() == zero and origin.can("sell_fuel"), "a synthetic station at exactly (0, 0) that sells fuel")
	_check(Refuel.nearest_within(zero + Vector2(10.0, 0.0), one, Refuel.RADIUS_M) == origin, "10 m off the station: near")
	_check(Refuel.nearest_within(zero + Vector2(30.0, 0.0), one, Refuel.RADIUS_M) == origin, "30 m off the station: near (inclusive)")
	_check(Refuel.nearest_within(zero + Vector2(30.001, 0.0), one, Refuel.RADIUS_M) == null, "30.001 m off the station: not near")
	_check(Refuel.nearest_within(zero + Vector2(4000.0, 0.0), one, Refuel.RADIUS_M) == null, "4 km off the station: not near")
	_check(Refuel.nearest_within(zero, [] as Array[Buildings.Record], Refuel.RADIUS_M) == null, "no station at all: not near")
	var station := _synthetic("S", reference)
	var at := station.position()
	var far := _synthetic("F", Buildings.record("E2.1"))
	var two: Array[Buildings.Record] = [far, station]
	_check(at != zero and Refuel.nearest_within(at + Vector2(0.0, 5.0), two, Refuel.RADIUS_M) == station and Refuel.nearest_within(far.position() + Vector2(0.0, 5.0), two, Refuel.RADIUS_M) == far, "two stations at real records' lat/lon (%s's and E2.1's): the nearer one each time" % RING_STATION_ID)
	var nearest_m := INF
	var nearest_id := ""
	for record: Buildings.Record in real:
		var d := SPAWN_XZ.distance_to(record.position())
		if d < nearest_m:
			nearest_m = d
			nearest_id = record.id
	_check(Refuel.nearest_within(SPAWN_XZ, real, Refuel.RADIUS_M) == null and nearest_id == RING_STATION_ID and nearest_m > 300.0, "the real nine at the certified spawn: none within %.0f m, the nearest %s at %.1f m - the Ring is inert at the spawn" % [Refuel.RADIUS_M, nearest_id, nearest_m])


# =============================================================================
#  The Ring
# =============================================================================

## Returns the fill's result {fuel_l, fuel_mass} for the determinism check.
func _check_ring() -> Dictionary:
	var result := {"fuel_l": -1.0, "fuel_mass": -1.0}
	var packed: PackedScene = load(RING_SCENE)
	if not _check(packed != null, "ring scene loads"):
		return result
	var scene := packed.instantiate()
	root.add_child(scene)
	await _step(SETTLE_FRAMES)
	var car := scene.get_node_or_null("Car") as ArcadeCar
	var hud := scene.get_node_or_null("HUD") as HUD
	var refuel := scene.get_node_or_null("Refuel") as Refuel
	if not _check(car != null and hud != null and refuel != null and refuel.car == car and refuel.hud == hud, "the Ring's Car, HUD and Refuel exist, the Refuel node wired to both"):
		return result
	var hint := hud.get_node_or_null(Refuel.HINT_NAME) as Label
	_check(hint != null and hint.get_parent() == hud and hint.text == Refuel.HINT_TEXT, "the line is a Label under the HUD named %s with the exact text" % Refuel.HINT_NAME)
	_check(refuel.stations.size() == STATIONS_COUNT, "the node holds the %d selling stations" % refuel.stations.size())
	var loaded := car.fuel_l
	_check(loaded <= ArcadeCar.FUEL_TANK_CAPACITY_L and ArcadeCar.FUEL_TANK_CAPACITY_L - loaded < 0.01, "headless the car loaded the full tank: %.6f L after the settle's idle burn (the tank %.1f L)" % [loaded, ArcadeCar.FUEL_TANK_CAPACITY_L])
	await _step(SETTLE_FRAMES)
	_check(not refuel.hint_visible() and hint != null and not hint.visible and refuel.near == null and refuel.fill_count == 0, "at the spawn after %d more ticks: the line hidden, no station near, nothing filled" % SETTLE_FRAMES)
	_check(car.fuel_l <= loaded and loaded - car.fuel_l < 0.01, "the tank at the spawn only ever lower: %.6f L after the idle burn (was %.3f)" % [car.fuel_l, loaded])
	Input.action_press(Refuel.ACTION)
	await _step(HOLD_FRAMES)
	Input.action_release(Refuel.ACTION)
	_check(refuel.fill_count == 0 and car.fuel_l < loaded, "the key held %d ticks at the spawn fills nothing (%.6f L)" % [HOLD_FRAMES, car.fuel_l])

	# The honest teleport: reset_to, R's own call, origin.y 0 (the car is
	# stood on the profile's height there), heading as the spawn's.
	var station := Buildings.record(RING_STATION_ID)
	var at := station.position()
	car.reset_to(Transform3D(car.global_basis, Vector3(at.x, 0.0, at.y)))
	_engine_off(car)
	car.fuel_l = PART_TANK_L
	await _step(SETTLE_FRAMES)
	var here := refuel.car_xz()
	_check(here.distance_to(at) <= Refuel.RADIUS_M and is_finite(car.global_position.y), "the car put at %s stands %.3f m from it after %d ticks (y %.2f)" % [RING_STATION_ID, here.distance_to(at), SETTLE_FRAMES, car.global_position.y])
	_check(car.fuel_l == PART_TANK_L and not car.engine_running, "the engine off, the tank stays at exactly %.1f L over the settle" % PART_TANK_L)
	_check(refuel.near == station and refuel.hint_visible() and hint.visible and hint.text == Refuel.HINT_TEXT, "the line is up with the exact text: \"%s\"" % refuel.hint_text())

	# The marks: what a fill must not restore.
	car.clutch_wear = WEAR_MARK
	car.front_brake_wear = WEAR_MARK
	car.rear_brake_wear = WEAR_MARK
	car.front_tyre_wear = WEAR_MARK
	car.rear_tyre_wear = WEAR_MARK
	car.engine_wear = WEAR_MARK
	car.battery_wear = BATTERY_WEAR_MARK
	car.battery_charge = BATTERY_CHARGE_MARK
	car.odometer_m = ODOMETER_MARK_M
	var marks := _marks(car)
	var fills_before := refuel.fill_count
	Input.action_press(Refuel.ACTION)
	await _step(HOLD_FRAMES)
	_check(car.fuel_l == ArcadeCar.FUEL_TANK_CAPACITY_L and refuel.fill_count == fills_before + 1, "the key held %d ticks: the tank is exactly FUEL_TANK_CAPACITY_L (%.6f L), filled on one tick (%d fill)" % [HOLD_FRAMES, car.fuel_l, refuel.fill_count - fills_before])
	Input.action_release(Refuel.ACTION)
	await _step(1)
	_check(car.fuel_mass == car.fuel_l * ArcadeCar.FUEL_DENSITY and car.fuel_mass == ArcadeCar.FUEL_TANK_CAPACITY_L * ArcadeCar.FUEL_DENSITY, "one tick later fuel_mass is exactly fuel_l x FUEL_DENSITY: %.6f kg" % car.fuel_mass)
	result.fuel_l = car.fuel_l
	result.fuel_mass = car.fuel_mass
	fills_before = refuel.fill_count
	Input.action_press(Refuel.ACTION)
	await _step(HOLD_FRAMES)
	Input.action_release(Refuel.ACTION)
	_check(car.fuel_l == ArcadeCar.FUEL_TANK_CAPACITY_L and refuel.fill_count == fills_before, "released and held again %d ticks at a full tank: still exactly capacity, nothing more filled" % HOLD_FRAMES)
	var after := _marks(car)
	var restored := PackedStringArray()
	var drift := 0.0
	for field: String in marks:
		var was: float = marks[field]
		var now: float = after[field]
		# The battery's charge only ever drains with the engine off (the
		# key-on load); everything else only ever grows (the car's own
		# bookkeeping at rest, ~1e-12 of tyre wear a tick on the terrain).
		# A fill restores nothing: nothing moves toward new.
		var toward_new := now > was if field == "battery_charge" else now < was
		if toward_new or absf(now - was) >= MARK_DRIFT:
			restored.append("%s %.12f -> %.12f" % [field, was, now])
		drift = maxf(drift, absf(now - was))
	_check(restored.is_empty(), "nothing but the fuel: the six wear marks, the battery's wear and charge and the odometer stand where they were set to within %s (the largest drift %s, the car's own ticking; nothing moved toward new: %s)" % [MARK_DRIFT, drift, ", ".join(restored) if not restored.is_empty() else "none"])

	# Away: the line down, the key dead.
	car.reset_to(Transform3D(car.global_basis, Vector3(at.x + AWAY_M, 0.0, at.y)))
	_engine_off(car)
	car.fuel_l = PART_TANK_L
	await _step(SETTLE_FRAMES)
	fills_before = refuel.fill_count
	Input.action_press(Refuel.ACTION)
	await _step(HOLD_FRAMES)
	Input.action_release(Refuel.ACTION)
	_check(refuel.car_xz().distance_to(at) > Refuel.RADIUS_M and refuel.near == null and not refuel.hint_visible() and not hint.visible, "moved %.0f m off the station (%.1f m from it): the line is down" % [AWAY_M, refuel.car_xz().distance_to(at)])
	_check(car.fuel_l == PART_TANK_L and refuel.fill_count == fills_before, "and the key held %d ticks there fills nothing (%.1f L)" % [HOLD_FRAMES, car.fuel_l])

	scene.queue_free()
	await _step(2)
	return result


## The engine off, honestly: engine_running false AND the crank at rest
## (car.gd keeps engine_running from the rpm every tick: at idle omega a
## false flag catches again the same tick); the starter is never pressed,
## so it stays off. The idle burn would otherwise move the tank under the
## bit-exact assertions.
func _engine_off(car: ArcadeCar) -> void:
	car.engine_running = false
	car.engine_omega = 0.0


## What a fill must leave alone, as one dictionary for an exact compare.
func _marks(car: ArcadeCar) -> Dictionary:
	return {
		"clutch_wear": car.clutch_wear,
		"front_brake_wear": car.front_brake_wear,
		"rear_brake_wear": car.rear_brake_wear,
		"front_tyre_wear": car.front_tyre_wear,
		"rear_tyre_wear": car.rear_tyre_wear,
		"engine_wear": car.engine_wear,
		"battery_wear": car.battery_wear,
		"battery_charge": car.battery_charge,
		"odometer_m": car.odometer_m,
	}


# =============================================================================
#  The pad: nothing
# =============================================================================

func _check_pad() -> void:
	var text := FileAccess.get_file_as_string(MAIN_SCENE)
	_check(text != "" and not text.to_lower().contains("refuel"), "the pad's scene file names no refuel")
	var packed: PackedScene = load(MAIN_SCENE)
	if not _check(packed != null, "main scene loads"):
		return
	var main := packed.instantiate()
	root.add_child(main)
	await _step(SETTLE_FRAMES)
	var car := main.get_node_or_null("Car") as ArcadeCar
	var hud := main.get_node_or_null("HUD") as HUD
	if not _check(car != null and hud != null, "the pad's Car and HUD exist"):
		return
	var refuel_nodes := 0
	var named := main.find_children("Refuel", "", true, false).size()
	for node: Node in main.find_children("*", "", true, false):
		if node is Refuel:
			refuel_nodes += 1
	_check(named == 0 and refuel_nodes == 0 and not main is Refuel, "the pad's tree holds no Refuel node, by name or by class")
	_check(hud.get_node_or_null(Refuel.HINT_NAME) == null, "no %s under the pad's HUD after %d ticks" % [Refuel.HINT_NAME, SETTLE_FRAMES])
	_engine_off(car)
	car.fuel_l = PART_TANK_L
	await _step(SETTLE_FRAMES)
	Input.action_press(Refuel.ACTION)
	await _step(HOLD_FRAMES)
	Input.action_release(Refuel.ACTION)
	_check(car.fuel_l == PART_TANK_L and hud.get_node_or_null(Refuel.HINT_NAME) == null, "the key held %d ticks on the pad fills nothing (%.1f L), no line appears" % [HOLD_FRAMES, car.fuel_l])
	main.queue_free()
	await _step(2)


# =============================================================================
#  Determinism
# =============================================================================

## A fresh car under a bare Refuel node (no HUD: the line hangs under the
## node) at E2.4, filled the same way: the same bits.
func _check_determinism(ring: Dictionary) -> void:
	var packed: PackedScene = load(CAR_SCENE)
	if not _check(packed != null, "car scene loads"):
		return
	var holder := Node3D.new()
	root.add_child(holder)
	var car := packed.instantiate() as ArcadeCar
	holder.add_child(car)
	var refuel := Refuel.new()
	refuel.car = car
	holder.add_child(refuel)
	var station := Buildings.record(RING_STATION_ID)
	var at := station.position()
	car.reset_to(Transform3D(Basis.IDENTITY, Vector3(at.x, 0.0, at.y)))
	_engine_off(car)
	car.fuel_l = PART_TANK_L
	await _step(SETTLE_FRAMES)
	_check(refuel.near == station and refuel.hint_visible() and refuel.hint_text() == Refuel.HINT_TEXT, "a fresh car at %s under a bare Refuel node: the station near, the line up" % RING_STATION_ID)
	Input.action_press(Refuel.ACTION)
	await _step(HOLD_FRAMES)
	Input.action_release(Refuel.ACTION)
	await _step(1)
	_check(car.fuel_l == ring.fuel_l and car.fuel_l == ArcadeCar.FUEL_TANK_CAPACITY_L, "the fresh car's fill: fuel_l %.6f, the Ring's %.6f - identical bits" % [car.fuel_l, ring.fuel_l])
	_check(car.fuel_mass == ring.fuel_mass and car.fuel_mass == car.fuel_l * ArcadeCar.FUEL_DENSITY, "and fuel_mass after a tick: %.6f kg, the Ring's %.6f - identical bits" % [car.fuel_mass, ring.fuel_mass])
	holder.queue_free()
	await _step(2)


# =============================================================================
#  Helpers
# =============================================================================

func _step(frames: int) -> void:
	for i in frames:
		await physics_frame


func _check(condition: bool, description: String) -> bool:
	if condition:
		print("  ok    ", description)
	else:
		_failures += 1
		printerr("  FAIL  ", description)
	return condition


func _finish() -> void:
	Input.action_release(Refuel.ACTION)
	if _failures == 0:
		print("REFUEL TEST PASSED")
	else:
		print("REFUEL TEST FAILED: %d check(s) failed" % _failures)
	quit(1 if _failures > 0 else 0)

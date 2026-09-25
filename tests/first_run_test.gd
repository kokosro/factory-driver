extends SceneTree
## Headless first-run test: 4B-6, docs/design/4b/first-run-flow.md steps 1-3
## and 6-8 (the pin, the test centre, the yard, the voucher, the rental, the
## first car) on the garage's menu patterns; world.json. Run via
## tests/run_tests.sh, or:
##
##   godot --headless --path . --import
##   env FD_TELEMETRY=0 godot --headless --fixed-fps 60 --path . --script res://tests/first_run_test.gd
##
## THE STORE IS PINNED OFF (the refuel test's idiom: FD_TELEMETRY=0 first
## thing, asserted off): nothing here reads or writes the data folder. The
## world record goes to a file of this test's own through
## WorldStore.path_override (the one injectable path every node reads:
## the map layer, the garage, the ledger), the cars file to another, both
## under /tmp/fd-4B6-first-<pid>/, removed at the end.
##
## WHAT IS CHECKED, in order: THE STORE (scripts/world_store.gd) on a file
## of its own - defaults on no file, a voucher added, listed unspent, spent
## once and not twice, a save writing back what it does not know, a field
## none of its own reported and read as its default, the rental written
## and cleared, the user:// path resolved through DataDir, active_path ""
## headless and the override when set; THE SEED - world.json in
## DataDir.SEEDED_FILES, copied beside cars.json from a source that has it,
## nothing new from one that has not. THE MAP OPENS FIRST - the pad scene
## loaded on a fresh (absent) world file: the WorldMap layer is up at
## _ready and a beat later, the tree paused, forced (Esc and Tab do nothing,
## the garage refuses to open under it), the voucher ledger on the licence
## manager. THE PIN - the continent lists the one region pin (the Ring's
## bbox, holding the school's and the dealership's lat/lon), Enter on it
## lists the region's test centres: exactly one, E8.1 Fahrschule Hecken,
## from the focus table; Enter on it shows the yard card (the measured
## estate decision, the dealership) with "Go to the yard" its last row;
## Right and Left zoom in and out. THE YARD - Enter on the last row writes
## spawn_region "eifel_ring" and test_centre "E8.1", closes the map, runs
## the tree and puts the car on the yard's start line (x 0, z 100, facing
## -Z, inside z 30..110), where it stays; then a second pad scene on the
## record present keeps its map hidden and its car at the pad's spawn, and
## a third with pending_yard set arrives in the yard. THE L0 SITTING AND
## THE VOUCHER - the sitting sat through the licence manager the way
## tests/licence_test.gd sits it (the book key, key 1, every element
## driven by the scripted pilot on the input actions, the manager's human
## run judging): PASSED, licence_changed fired ONCE with L0, the ledger
## wrote ONE voucher (kind car, class general, dealership E4.1, granted by
## L0, unspent) and no more; then a PRACTICE RUN on the complete record,
## driven whole and passed: licence_changed fired no more, the file holds
## the one voucher still; then the ledger alone on a bare manager: seven
## record_element calls announce L0 once and write one voucher,
## grant_if_due again writes none while it sits unspent, nor once it is
## spent (L0 or L1 announced after: was a second voucher -> none; 4B-6
## audit). THE RENTAL
## (scripts/rental_gate.gd) - started on the licensed car: the gate in
## front of the licence manager, a child of the car, the program pinned
## ECO with eco's driver, the record written; the three aid switches and
## the program key pressed through the car's own ticks flip NOTHING (the
## car's own key cycle is put back the same tick, counted), the hint up
## and down again; the clutch key delegated to the manager (L0: the pedal
## moves); the hour on the tick clock ending the rental by itself, the
## manager back on the car, the record cleared, the switches flipping
## again; the hour up while THE STUDY holds the gate aside keeps an ended
## gate answering as the manager (never a freed one handed back), and a
## car leaving the tree ends its rental and clears the record (4B-6
## audit). TAKING THE CAR (scripts/first_car.gd) on the store side - the
## voucher spent, fd_1001's entry in the test's cars.json read back field
## by field as a new car's (odometer 0, the FD-1001's own full tank, the
## dashboard, battery, wear and licence defaults, no problems), the
## Boxster's entry untouched, "active_car" fd_1001, a rental ended by it,
## a second take refused, nothing written where the store is off; the
## config itself: FD-1001 / fd_1001, valid, no trademark. THE DEALERSHIP
## ON THE RING - eifel_ring.tscn with an unspent voucher: the DRIVE page's
## world-map row, the two dealership rows greyed at the pit with the hint
## naming where to go, live once the car stands at E4.1 (reset_to, the
## refuel test's teleport); the loaner row starting the rental on the
## Ring's car (no manager to stand in front of; a stale "active" record
## in the file greys nothing), the take row spending the
## voucher, ending the rental and writing no entry (the store is off),
## the rows gone after, the CAR page naming the car owned; the world-map
## row instancing the layer beside the Ring's garage and Esc closing it.
## READABILITY - the window at the game's 1280 x 720, the DRIVE page with
## the dealership's rows (greyed on the pad, live on the Ring; 4B-6 audit:
## was the map alone), the map opened from the garage's row, its three
## zooms walked with Right: no control past the screen, every row inside
## the scroll area, PgDn reaching the end.
## Exits 0 on success, 1 on any failed check.

const MAIN_SCENE := "res://scenes/main.tscn"
const RING_SCENE := "res://scenes/eifel_ring.tscn"

## Physics frames to let a scene settle after a load.
const SETTLE_FRAMES := 20

## Give up on an element after this many physics frames (70 s).
const MAX_ELEMENT_FRAMES := 4200

## Frames the clutch key is held for the gate's check: 0.5 s, the pedal is
## on the floor in 0.2 (ArcadeCar.CLUTCH_PEDAL_SPEED).
const CLUTCH_HOLD_FRAMES := 30

## How far a laid-out rect may reach past the screen before it counts as
## off it [px] (the menu test's tolerance).
const OVERFLOW_TOLERANCE_PX := 1.0

## PgDn presses that reach the end of the longest zoom, with room.
const MAX_PAGE_DOWNS := 20

## Where this test writes: a folder of its own, one per process.
const TMP_DIR_PREFIX := "/tmp/fd-4B6-first-"

var _failures := 0
var _tmp_dir := ""
var _world_file := ""
var _store_file := ""
var _main: Node
var _car: ArcadeCar
var _pad: TestPad
var _hud: HUD
var _licence: LicenceManager
var _missions: MissionManager
var _garage: Garage
var _map: WorldMap
var _card: Label
var _banner: Label
var _hint: Label
var _levels: Array[int] = []
var _chosen: Array = []


func _initialize() -> void:
	# The refuel test's idiom: pinned before anything asks (the runner does
	# not set it; an inherited FD_TELEMETRY=1 would let the scenes below
	# write the data folder).
	OS.set_environment("FD_TELEMETRY", "0")
	_run.call_deferred()


func _run() -> void:
	_tmp_dir = TMP_DIR_PREFIX + str(OS.get_process_id())
	DirAccess.make_dir_recursive_absolute(_tmp_dir)
	_world_file = _tmp_dir.path_join("world.json")
	_store_file = _tmp_dir.path_join("cars.json")
	_check(not OdometerStore.enabled() and not TelemetryRecorder.should_record() and WorldStore.active_path() == "", "suite: the store is off headless (FD_TELEMETRY=0 pinned) and WorldStore names no file: nothing reads or writes the data folder")

	print("-- the world store")
	_check_store()
	print("-- the seed")
	_check_seed()

	WorldStore.path_override = _world_file
	print("-- a fresh world: the map opens first")
	if not await _check_map_opens_first():
		_finish()
		return
	print("-- the pin and the centre")
	await _check_pin()
	print("-- the yard")
	await _check_yard()
	print("-- a record present: the map stays hidden")
	await _check_record_present()
	print("-- the L0 sitting and the voucher")
	await _sit_l0_for_voucher()
	print("-- a practice run adds none")
	await _practice_run()
	print("-- the ledger alone")
	await _check_ledger_alone()
	print("-- the rental lock")
	await _check_rental()
	print("-- the rental lives with its car")
	await _check_rental_lifecycle()
	print("-- taking the car: the store side")
	await _check_take_store()
	print("-- the dealership on the Ring")
	await _check_dealership_on_ring()
	print("-- readability: nothing off the screen")
	await _check_readability()

	_car.clear_driver_input()
	_car.reset_to_spawn()
	_pad.reset_cones()
	WorldStore.path_override = ""
	_finish()


# =============================================================================
#  The store
# =============================================================================

func _check_store() -> void:
	var file := _tmp_dir.path_join("store_probe.json")
	var fresh := WorldStore.load_driver(file)
	_check(
		not FileAccess.file_exists(file) and fresh.spawn_region == "" and fresh.test_centre == "" and fresh.vouchers == [] and fresh.rental == {} and fresh.active_car == "" and (fresh.problems as Array).is_empty() and not WorldStore.has_record(file),
		"no file: every driver field its default (no region, no centre, no vouchers, no rental, no car), no problems, no record",
	)
	_check(WorldStore.PATH == "user://world.json" and WorldStore.VERSION == 1 and WorldStore.DRIVER_DEFAULTS.keys() == ["spawn_region", "test_centre", "vouchers", "rental", "active_car"], "the file is user://world.json, version 1, the driver object's five fields")
	var written := WorldStore.add_voucher({"kind": "car", "class": "general", "dealership": "E4.1", "granted_by": "L0", "spent": false}, file)
	var stored: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(file))
	_check(
		written == {"kind": "car", "class": "general", "dealership": "E4.1", "granted_by": "L0", "spent": false} and stored.version == 1 and stored.driver.vouchers.size() == 1 and WorldStore.vouchers(file).size() == 1 and WorldStore.unspent_vouchers(file).size() == 1 and not WorldStore.has_record(file),
		"add_voucher: the voucher as given, in the file under version 1, listed once and unspent; a voucher is no record (no pin yet)",
	)
	var spent := WorldStore.spend_voucher(file)
	var again := WorldStore.spend_voucher(file)
	_check(spent.spent == true and spent.dealership == "E4.1" and WorldStore.unspent_vouchers(file).is_empty() and WorldStore.vouchers(file).size() == 1 and WorldStore.vouchers(file)[0].spent == true and again.is_empty(), "spend_voucher: the one unspent is marked spent and returned, none unspent after, a second spend returns {} and changes nothing")
	_write(file, JSON.stringify({"version": 1, "future": {"x": 1}, "driver": {"spawn_region": "somewhere", "later_field": 7, "vouchers": []}}))
	WorldStore.set_spawn("eifel_ring", "E8.1", file)
	stored = JSON.parse_string(FileAccess.get_file_as_string(file))
	_check(stored.future.x == 1 and stored.driver.later_field == 7 and stored.driver.spawn_region == "eifel_ring" and stored.driver.test_centre == "E8.1" and WorldStore.has_record(file), "set_spawn: the region and the centre written, a field the store does not know (above and inside the driver) written back as it was; now a record")
	_write(file, JSON.stringify({"version": 1, "driver": {"spawn_region": 5, "test_centre": "E8.1", "vouchers": "none", "rental": {"active": "yes", "granted_at_s": 0, "expires_s": 3600}, "active_car": ["fd"]}}))
	var refused := WorldStore.load_driver(file)
	var problems: Array = refused.problems
	_check(
		refused.spawn_region == "" and refused.test_centre == "E8.1" and refused.vouchers == [] and refused.rental == {} and refused.active_car == "" and problems.size() == 4
		and problems[0].contains("spawn_region") and problems[1].contains("vouchers") and problems[2].contains("rental") and problems[3].contains("active_car") and not WorldStore.has_record(file),
		"a field that is none of its own (a number for a name, text for the list, text for a flag, a list for a name) reads as its default and is reported by name; the good field beside them still loads (%d problems)" % problems.size(),
	)
	_write(file, JSON.stringify({"version": 1, "driver": {"vouchers": [{"kind": "car", "class": "general", "dealership": "E4.1", "granted_by": "L0", "spent": "no"}]}}))
	refused = WorldStore.load_driver(file)
	_check(refused.vouchers == [] and (refused.problems as Array).size() == 1 and String(refused.problems[0]).contains("[0] spent"), "a voucher whose spent is no flag refuses the list, by index and field")
	var rental := WorldStore.set_rental(12.5, 3600.0, file)
	var active := WorldStore.rental_active(file)
	WorldStore.clear_rental(file)
	_check(rental == {"active": true, "granted_at_s": 12.5, "expires_s": 3600.0} and active and WorldStore.rental(file) == {} and not WorldStore.rental_active(file), "set_rental writes an active rental with its seconds, clear_rental empties it")
	var root_before := DataDir.root()
	DataDir.apply_root(_tmp_dir.path_join("root"))
	var probe := WorldStore.PATH
	WorldStore.set_spawn("eifel_ring", "E8.1", probe)
	var under_root := FileAccess.file_exists(_tmp_dir.path_join("root/world.json")) and WorldStore.has_record(probe)
	DataDir.apply_root(root_before)
	# was `under_root and resolve == PATH if root_before == "" else true`: the
	# ternary took the whole check, vacuous under a custom root (4B-6 audit).
	_check(under_root and DataDir.root() == root_before and (DataDir.resolve(WorldStore.PATH) == WorldStore.PATH or root_before != ""), "user://world.json goes through DataDir.resolve: under a custom root it is <root>/world.json; the run's root put back")
	WorldStore.path_override = file
	var overridden := WorldStore.active_path()
	WorldStore.path_override = ""
	_check(overridden == file and WorldStore.active_path() == "", "active_path: the override when a test sets one, \"\" headless without (the game's PATH only with the store on)")


func _check_seed() -> void:
	_check(DataDir.SEEDED_FILES == ["cars.json", "issues.json", "world.json"], "DataDir.SEEDED_FILES holds world.json beside cars.json and issues.json (was the two)")
	var src := _tmp_dir.path_join("seed_src")
	var dst := _tmp_dir.path_join("seed_dst")
	DirAccess.make_dir_recursive_absolute(src)
	_write(src.path_join("cars.json"), '{"version": 1, "cars": {}}')
	_write(src.path_join("world.json"), '{"version": 1, "driver": {"spawn_region": "eifel_ring"}}')
	var seeded := DataDir.seed_folder(dst, [src])
	var copied: PackedStringArray = seeded.copied
	copied.sort()
	_check(seeded.seeded and copied == PackedStringArray(["cars.json", "world.json"]) and FileAccess.get_file_as_string(dst.path_join("world.json")) == FileAccess.get_file_as_string(src.path_join("world.json")) and FileAccess.file_exists(src.path_join("world.json")), "seed: world.json copied beside cars.json, byte for byte, the source's left where it was")
	var src_without := _tmp_dir.path_join("seed_src_without")
	var dst_without := _tmp_dir.path_join("seed_dst_without")
	DirAccess.make_dir_recursive_absolute(src_without)
	_write(src_without.path_join("cars.json"), '{"version": 1, "cars": {}}')
	var seeded_without := DataDir.seed_folder(dst_without, [src_without])
	_check(seeded_without.seeded and seeded_without.copied == PackedStringArray(["cars.json"]) and not FileAccess.file_exists(dst_without.path_join("world.json")), "... a source without world.json copies nothing new (the menu test's pinned lists stand)")


# =============================================================================
#  The map opens first
# =============================================================================

func _check_map_opens_first() -> bool:
	_check(not FileAccess.file_exists(_world_file) and WorldStore.active_path() == _world_file, "the world file named for the run is this test's own and does not exist yet: a fresh world")
	var packed: PackedScene = load(MAIN_SCENE)
	if not _check(packed != null, "main scene loads"):
		return false
	_main = packed.instantiate()
	root.add_child(_main)
	_map = _main.get_node_or_null("WorldMap") as WorldMap
	var at_ready := _map != null and _map.is_open and _map.visible and paused and _map.forced
	await _step(SETTLE_FRAMES)
	_car = _main.get_node_or_null("Car") as ArcadeCar
	_pad = _main.get_node_or_null("TestPad") as TestPad
	_hud = _main.get_node_or_null("HUD") as HUD
	_licence = _main.get_node_or_null("LicenceManager") as LicenceManager
	_missions = _main.get_node_or_null("MissionManager") as MissionManager
	_garage = _main.get_node_or_null("Garage") as Garage
	_card = _main.get_node_or_null("HUD/LicenceCard") as Label
	_banner = _main.get_node_or_null("HUD/MissionBanner") as Label
	_hint = _main.get_node_or_null("HUD/GateHint") as Label
	if not _check(_car != null and _pad != null and _hud != null and _licence != null and _missions != null and _garage != null and _map != null and _card != null and _banner != null and _hint != null, "Car, TestPad, HUD, LicenceManager, MissionManager, Garage and WorldMap exist"):
		return false
	_check(at_ready and _map.is_open and _map.visible and paused and _map.forced, "a fresh world: the WorldMap layer is up at _ready and %d frames later, the tree paused, forced (a first run)" % SETTLE_FRAMES)
	_check(_map.layer == Garage.LAYER and _map.process_mode == Node.PROCESS_MODE_ALWAYS and _map.path == _world_file and _map.car == _car and _map.licence == _licence and _map.garage == _garage, "the layer draws at the garage's layer, processes through the pause, reads the run's file, wired to the car, the manager and the garage (main.tscn)")
	_check(_map.ledger != null and _map.ledger.path == _world_file and _licence.licence_changed.is_connected(_map.ledger._on_licence_changed), "the voucher ledger is made on the licence manager, writing the same file")
	_check(not _garage.is_open and not _garage.can_open() and not _garage.open(), "the garage is closed and refuses to open under the map")
	_licence.licence_changed.connect(func(level: int) -> void: _levels.append(level))
	_map.chosen.connect(func(region: String, centre: String) -> void: _chosen.append([region, centre]))
	var position_before := _car.global_position
	await _tap(&"abort_mission")
	var after_esc := _map.is_open and paused and not _garage.is_open
	await _tap(Garage.ACTION_OPEN)
	_check(after_esc and _map.is_open and paused and not _garage.is_open and _car.global_position == position_before, "Esc and Tab do nothing on a first run: the map stays up, the tree paused, the garage closed, the car where it was")
	return true


# =============================================================================
#  The pin and the centre
# =============================================================================

func _check_pin() -> void:
	var rows := _map.page_rows()
	var region: Dictionary = WorldMap.REGIONS[0]
	_check(_map.zoom == WorldMap.Zoom.CONTINENT and rows.size() == 1 and rows[0].kind == "pin" and rows[0].id == "eifel_ring" and rows[0].enabled and rows[0].label.contains("Nürburgring") and rows[0].hint.contains("1 test centre"), "the continent lists exactly one pin, the Ring's region, its hint counting one test centre")
	var school := Buildings.record("E8.1")
	var dealer := Buildings.record("E4.1")
	_check(
		WorldMap.REGIONS.size() == 1 and region.bbox == SkeletonLoader.BBOX and school != null and dealer != null
		and WorldMap.region_contains(region, school.lat, school.lon) and WorldMap.region_at(school.lat, school.lon).id == "eifel_ring"
		and WorldMap.region_contains(region, dealer.lat, dealer.lon) and WorldMap.region_at(0.0, 0.0).is_empty(),
		"the pin's bbox is SkeletonLoader.BBOX %s and holds the school (%.5f, %.5f) and the dealership; a pin outside every region falls in none" % [str(SkeletonLoader.BBOX), school.lat, school.lon],
	)
	await _tap(&"ui_accept")
	rows = _map.page_rows()
	var centres := WorldMap.centres_of(region)
	_check(
		_map.zoom == WorldMap.Zoom.REGION and rows.size() == 1 and rows[0].kind == "centre" and rows[0].id == "E8.1" and rows[0].label == "Fahrschule Hecken — test centre" and rows[0].enabled
		and centres.size() == 1 and centres[0].id == "E8.1" and centres[0].element == "E8" and centres[0].osm_id == 667524970 and rows[0].hint.contains("(4515, -2300)"),
		"Enter on the pin: the region's test centres from the focus table, exactly one, E8.1 Fahrschule Hecken (way 667524970), its hint naming the yard on the estate",
	)
	await _tap(&"ui_left")
	var back_out: bool = _map.zoom == WorldMap.Zoom.CONTINENT and _map.page_rows()[0].kind == "pin"
	await _tap(&"ui_right")
	_check(back_out and _map.zoom == WorldMap.Zoom.REGION and _map.page_rows()[0].id == "E8.1", "Left zooms out to the continent, Right back into the pin under the cursor")
	await _tap(&"ui_accept")
	rows = _map.page_rows()
	var text := _map.page_text()
	_check(
		_map.zoom == WorldMap.Zoom.CENTRE and rows.size() == 1 and rows[rows.size() - 1].kind == "go" and rows[rows.size() - 1].label == "Go to the yard" and rows[0].id == "E8.1"
		and text.contains("(4515, -2300)") and text.contains("B9") and text.contains("7.50 %") and text.contains("1.09 %") and text.contains("E4.1"),
		"Enter on the centre: the yard card, its last row \"Go to the yard\", the text carrying the measured decision (the estate patch (4515, -2300), the school a B9, 7.50 % vs 1.09 %) and the voucher's dealership E4.1",
	)
	var yard: Dictionary = WorldMap.YARDS["E8.1"]
	_check(yard.yard_xz == Vector2(4515.0, -2300.0) and yard.school_xz.distance_to(school.position()) < 0.01, "the yard's data: the patch centre (4515, -2300), the school marker at the record's own projected position (%.3f, %.3f)" % [school.position().x, school.position().y])
	await _tap(&"ui_left")
	var to_region := _map.zoom == WorldMap.Zoom.REGION
	await _tap(&"ui_right")
	_check(to_region and _map.zoom == WorldMap.Zoom.CENTRE and _map.page_rows()[0].kind == "go", "Left back to the centres, Right into the centre again")


# =============================================================================
#  The yard
# =============================================================================

func _check_yard() -> void:
	var before := _car.global_position
	_check(not WorldMap.in_yard(before), "before the choice the car stands at the pad's spawn (%.1f, %.1f), outside the yard" % [before.x, before.z])
	await _tap(&"ui_accept")
	var driver := WorldStore.load_driver(_world_file)
	_check(driver.spawn_region == "eifel_ring" and driver.test_centre == "E8.1" and WorldStore.has_record(_world_file) and _chosen == [["eifel_ring", "E8.1"]], "Enter on \"Go to the yard\": world.json holds spawn_region eifel_ring and test_centre E8.1 (a record now), chosen fired once")
	_check(not _map.is_open and not _map.visible and not paused and not _map.forced, "the map is down and the tree runs")
	var at := _car.global_position
	var forward := -_car.global_transform.basis.z
	_check(WorldMap.in_yard(at) and absf(at.x) < 0.01 and absf(at.z - TestPad.EMERGENCY_START_Z) < 0.01 and forward.z < -0.999 and absf(forward.x) < 0.001, "the car is in the yard: on the emergency lane's start (x %.2f, z %.1f; z 30..110, x within the lanes), facing -Z down the course" % [at.x, at.z])
	await _step(SETTLE_FRAMES)
	_check(WorldMap.in_yard(_car.global_position) and _car.forward_speed < 0.05 and _car.engine_running, "... and stays there at rest, the engine running (%.1f, %.1f)" % [_car.global_position.x, _car.global_position.z])
	# With the map down the keys are the garage's again: Esc with everything
	# idle opens the garage (its own rule), never the map; Tab closes it.
	await _tap(&"abort_mission")
	var esc_opens_garage := not _map.is_open and _garage.is_open and paused
	await _tap(Garage.ACTION_OPEN)
	var tab_closes := not _garage.is_open and not paused
	await _tap(Garage.ACTION_OPEN)
	var tab_opens := _garage.is_open and paused and not _map.is_open
	await _tap(Garage.ACTION_OPEN)
	_check(esc_opens_garage and tab_closes and tab_opens and not _garage.is_open and not paused and not _map.is_open, "with the map down the keys are the garage's again: Esc (everything idle) opens the garage, not the map; Tab closes and opens it; the map stays down")


func _check_record_present() -> void:
	var second: Node = load(MAIN_SCENE).instantiate()
	root.add_child(second)
	var second_map := second.get_node("WorldMap") as WorldMap
	var at_ready := not second_map.is_open and not second_map.visible and not paused
	await _step(5)
	var second_car := second.get_node("Car") as ArcadeCar
	_check(at_ready and not second_map.is_open and not paused and second_map.path == _world_file and not WorldMap.in_yard(second_car.global_position) and second_map.ledger != null, "a second pad scene on the record present: its map stays hidden at _ready and after, the tree runs, its car at the pad's spawn; the ledger still made")
	second.queue_free()
	await _step(2)
	WorldMap.pending_yard = true
	var third: Node = load(MAIN_SCENE).instantiate()
	root.add_child(third)
	var third_car := third.get_node("Car") as ArcadeCar
	var arrived := WorldMap.in_yard(third_car.global_position) and not WorldMap.pending_yard
	await _step(5)
	_check(arrived and WorldMap.in_yard(third_car.global_position) and not (third.get_node("WorldMap") as WorldMap).is_open, "pending_yard set (the choice made from another scene): a pad scene arrives with its car in the yard and the flag cleared")
	third.queue_free()
	await _step(2)


# =============================================================================
#  The L0 sitting and the voucher
# =============================================================================

## licence_test.gd's harness: the manager's sitting driven with pilots, one
## per element as the manager moves on, until the manager is out of
## RUNNING. Returns the verdicts by element name and the frames it took.
func _drive_sitting(pilot_for: Callable) -> Dictionary:
	var verdicts := {}
	var pilot: LicenceExams = null
	var pilot_index := -1
	var frames := 0
	var element_frames := 0
	var delta := 1.0 / Engine.physics_ticks_per_second
	while _licence.is_running() and frames < MAX_ELEMENT_FRAMES * 7:
		if _licence.element_index != pilot_index:
			if pilot != null:
				pilot.abort()
				await physics_frame
				frames += 1
				var previous: Dictionary = _licence.last_result
				verdicts[previous.name] = previous
			pilot_index = _licence.element_index
			element_frames = 0
			var element: Dictionary = _licence.elements[pilot_index]
			var scripted: Dictionary = pilot_for.call(element)
			pilot = LicenceExams.begin(scripted, _car, _pad, true, false)
		pilot.tick(delta)
		await physics_frame
		frames += 1
		element_frames += 1
		if element_frames > MAX_ELEMENT_FRAMES:
			break
		if not _licence.is_running():
			break
	if pilot != null:
		pilot.abort()
	if not _licence.last_result.is_empty():
		verdicts[_licence.last_result.name] = _licence.last_result
	return {"verdicts": verdicts, "frames": frames}


func _sit_l0_for_voucher() -> void:
	var granted := [0]
	_map.ledger.voucher_granted.connect(func(_voucher: Dictionary) -> void: granted[0] += 1)
	_check(_licence.level() == LicenceExams.LICENCE_NONE and WorldStore.vouchers(_world_file).is_empty() and _levels.is_empty(), "before the sitting: unlicensed, no voucher, nothing announced")
	await _tap(LicenceManager.ACTION_BOOK)
	_fresh_fuel(_car)
	await _tap(LicenceManager.ACTION_SIT_L0)
	_check(_licence.is_running() and _licence.exam == LicenceExams.EXAM_L0 and _licence.element_index == 0 and not _licence.practice and not _licence.run.scripted, "1 in the book starts the L0 sitting at the theory, a human run, no practice")
	var seen := await _drive_sitting(func(element: Dictionary) -> Dictionary: return element)
	var verdicts: Dictionary = seen.verdicts
	var all_passed := verdicts.size() == 7
	for name: String in verdicts:
		all_passed = all_passed and verdicts[name].passed
	_check(not _licence.is_running() and _licence.last_sitting_passed and all_passed and _licence.level() == LicenceExams.LICENCE_L0, "the sitting PASSED on every one of its seven elements (%d frames), L0 held" % seen.frames)
	_check(_levels == [LicenceExams.LICENCE_L0], "licence_changed fired ONCE, with L0 (%s)" % str(_levels))
	var vouchers := WorldStore.vouchers(_world_file)
	_check(
		vouchers.size() == 1 and vouchers[0] == {"kind": "car", "class": "general", "dealership": "E4.1", "granted_by": "L0", "spent": false}
		and WorldStore.unspent_vouchers(_world_file).size() == 1 and _map.ledger.granted == 1 and granted[0] == 1 and _map.ledger.levels_heard == [LicenceExams.LICENCE_L0] and _map.ledger.has_unspent_l0(),
		"the ledger wrote ONE voucher: kind car, class general, dealership E4.1, granted by L0, unspent - and announced it once",
	)
	_check(WorldStore.load_driver(_world_file).spawn_region == "eifel_ring" and WorldStore.load_driver(_world_file).test_centre == "E8.1", "the pin's record is still in the file beside it")
	await _tap(&"abort_mission")
	_check(_licence.state == LicenceManager.State.IDLE, "Esc closes the banner")


func _practice_run() -> void:
	await _tap(LicenceManager.ACTION_BOOK)
	_fresh_fuel(_car)
	await _tap(LicenceManager.ACTION_SIT_L0)
	_check(_licence.is_running() and _licence.practice and _licence.element_index == 0, "with the complete record 1 sits the exam again from the theory as a practice run")
	var seen := await _drive_sitting(func(element: Dictionary) -> Dictionary: return element)
	var verdicts: Dictionary = seen.verdicts
	var all_passed := verdicts.size() == 7
	for name: String in verdicts:
		all_passed = all_passed and verdicts[name].passed
	_check(not _licence.is_running() and _licence.last_sitting_passed and all_passed, "the practice run PASSED whole (%d frames)" % seen.frames)
	_check(_levels == [LicenceExams.LICENCE_L0] and _map.ledger.granted == 1 and _map.ledger.levels_heard == [LicenceExams.LICENCE_L0] and WorldStore.vouchers(_world_file).size() == 1 and WorldStore.unspent_vouchers(_world_file).size() == 1, "licence_changed fired no more (still once), the ledger wrote nothing more: the one voucher, still unspent (a practice run records nothing, and the level never moved)")
	await _tap(&"abort_mission")


## The ledger on a bare manager (no car, no pad): the record driven by
## record_element alone.
func _check_ledger_alone() -> void:
	var file := _tmp_dir.path_join("ledger_probe.json")
	var bare := LicenceManager.new()
	bare.name = "BareLicenceManager"
	root.add_child(bare)
	var ledger := VoucherLedger.new()
	ledger.path = file
	ledger.attach(bare)
	var announced: Array[int] = []
	bare.licence_changed.connect(func(level: int) -> void: announced.append(level))
	for element in LicenceExams.l0_sitting():
		bare.record_element(element.name)
	_check(bare.level() == LicenceExams.LICENCE_L0 and announced == [LicenceExams.LICENCE_L0] and ledger.granted == 1 and WorldStore.vouchers(file).size() == 1 and WorldStore.unspent_vouchers(file)[0].granted_by == "L0", "seven elements recorded on a bare manager: L0 announced once, one voucher written")
	bare.record_pass(LicenceExams.EXAM_L0)
	for element in LicenceExams.l0_sitting():
		bare.record_element(element.name)
	var second := ledger.grant_if_due(LicenceExams.LICENCE_L0)
	var third := ledger.grant_if_due(LicenceExams.LICENCE_L1)
	_check(announced == [LicenceExams.LICENCE_L0] and second.is_empty() and third.is_empty() and ledger.granted == 1 and WorldStore.vouchers(file).size() == 1, "the pass and the elements recorded again announce nothing; grant_if_due for L0 or L1 writes no second voucher while one sits unspent (belt and braces)")
	var none := ledger.grant_if_due(LicenceExams.LICENCE_NONE)
	WorldStore.spend_voucher(file)
	var after_spend := ledger.grant_if_due(LicenceExams.LICENCE_L0)
	var l1_after_spend := ledger.grant_if_due(LicenceExams.LICENCE_L1)
	# was: with the voucher spent a fresh L0 announcement granted a second
	# (the guard on UNSPENT vouchers) -> granted once, spent or not (4B-6
	# audit: L1 earned after the car was taken bought a second car).
	_check(none.is_empty() and after_spend.is_empty() and l1_after_spend.is_empty() and ledger.has_l0() and not ledger.has_unspent_l0() and WorldStore.vouchers(file).size() == 1 and WorldStore.unspent_vouchers(file).is_empty() and ledger.granted == 1, "... unlicensed grants none; with the voucher spent a fresh L0 or an L1 announcement grants NO second (granted once, spent or not; was: a second granted)")
	bare.licence_changed.emit(LicenceExams.LICENCE_L1)
	_check(ledger.levels_heard.back() == LicenceExams.LICENCE_L1 and ledger.granted == 1 and WorldStore.vouchers(file).size() == 1, "licence_changed(L1) heard after the voucher was spent writes none")
	ledger.detach()
	bare.record_element("SOMETHING")
	_check(not bare.licence_changed.is_connected(ledger._on_licence_changed) and ledger.granted == 1, "detach: the ledger hears nothing more (was granted 2 -> 1)")
	bare.queue_free()
	await _step(1)


# =============================================================================
#  The rental lock
# =============================================================================

func _check_rental() -> void:
	_fresh_fuel(_car)
	_car.reset_to_spawn()
	await _step(5)
	_car.gearbox_mode = ArcadeCar.GearboxMode.SPORT
	_car.set_driver_profile(ArcadeCar.DRIVER_PROFILES["test_driver"])
	_check(_car.licence_gate == _licence and _licence.level() == LicenceExams.LICENCE_L0, "licensed: the car's gate is the manager, L0 held")
	await _tap("tcs_toggle")
	var flipped_before := not _car.tcs_on
	await _tap("tcs_toggle")
	_check(flipped_before and _car.tcs_on, "before the rental the TCS key flips the switch (and back)")

	var gate := RentalGate.start(_car, _hud, _world_file)
	var eco_profile: Dictionary = ArcadeCar.DRIVER_PROFILES[ArcadeCar.MODE_DRIVERS[ArcadeCar.GearboxMode.ECO]]
	_check(gate != null and _car.licence_gate == gate and gate.previous_gate == _licence and gate.get_parent() == _car and gate.name == "RentalGate" and RentalGate.active_on(_car) == gate and RentalGate.start(_car, _hud, _world_file) == gate, "start: the rental gate in front of the licence manager, a child of the car; a second start hands the same gate back")
	_check(_car.gearbox_mode == ArcadeCar.GearboxMode.ECO and _car.driver_profile == eco_profile and _car.tcs_on and _car.abs_on and _car.sc_on, "the program pinned ECO with eco's driver seated, the aids on")
	var rental := WorldStore.rental(_world_file)
	_check(rental.active == true and rental.expires_s == RentalGate.HOUR_S and rental.granted_at_s == 0.0 and gate.expires_s == 3600.0, "the record: active, one hour (3 600 s) on the tick clock")
	await _step(2)
	var restored_before := gate.restored
	await _tap("tcs_toggle")
	await _tap("abs_toggle")
	await _tap("sc_toggle")
	var hint_seen := _hint.visible and _hint.text == RentalGate.HINT
	await _tap("gearbox_mode")
	_check(_car.tcs_on and _car.abs_on and _car.sc_on and gate.refused == 3, "T, G and K pressed through the car's own ticks flip nothing: the gate refused all three (%d)" % gate.refused)
	_check(_car.gearbox_mode == ArcadeCar.GearboxMode.ECO and _car.driver_profile == eco_profile and gate.restored > restored_before, "N pressed: the program is ECO after the tick with eco's driver - the car's own key cycle ran and the gate put it back the same tick (%d restorations)" % (gate.restored - restored_before))
	_check(hint_seen, "the hint by the aid lamps says '%s'" % RentalGate.HINT)
	await _step(int(RentalGate.HINT_TIME * Engine.physics_ticks_per_second) + 5)
	_check(not _hint.visible, "... and is down again %.1f s later" % RentalGate.HINT_TIME)
	_car.automatic = false
	Input.action_press("clutch_pedal")
	await _step(CLUTCH_HOLD_FRAMES)
	var pedal := _car.clutch_pedal
	Input.action_release("clutch_pedal")
	await _step(CLUTCH_HOLD_FRAMES)
	_car.automatic = true
	_check(pedal >= 0.99 and _car.clutch_pedal == 0.0 and gate.allows(&"clutch_pedal") and not gate.allows(&"tcs_toggle"), "the clutch key is the manager's to answer through the gate: licensed, the pedal moves (%.2f held); the gate itself allows clutch_pedal and refuses tcs_toggle" % pedal)
	_car.gearbox_mode = ArcadeCar.GearboxMode.SPORT
	_car.tcs_on = false
	await _step(1)
	_check(_car.gearbox_mode == ArcadeCar.GearboxMode.ECO and _car.tcs_on, "the program and an aid moved from code are put back on the next tick too")

	# The hour ends the rental by itself.
	gate.elapsed_s = RentalGate.HOUR_S - 1.5 / Engine.physics_ticks_per_second
	await _step(3)
	_check(not is_instance_valid(gate) or not gate.active(), "the hour up on the tick clock: the rental ended by itself")
	_check(_car.licence_gate == _licence and RentalGate.active_on(_car) == null and WorldStore.rental(_world_file) == {} and not WorldStore.rental_active(_world_file), "the manager is the car's gate again, no gate under the car, the record cleared")
	await _tap("tcs_toggle")
	await _tap("gearbox_mode")
	var flipped_after := not _car.tcs_on and _car.gearbox_mode != ArcadeCar.GearboxMode.ECO
	await _tap("tcs_toggle")
	_car.gearbox_mode = ArcadeCar.GearboxMode.SPORT
	_car.set_driver_profile(ArcadeCar.DRIVER_PROFILES["test_driver"])
	_check(flipped_after and _car.tcs_on, "after the rental the switches flip and the program moves again")


## The rental's lifetime (4B-6 audit): ended while THE STUDY holds the
## gate aside (study.gd _take_the_car / _hand_back_the_car: the car's gate
## saved, set null, put back) the gate is kept as an ended gate answering
## as the manager, never a freed object handed back (was: queue_free); a
## car leaving the tree ends its rental and clears the record (was: the
## record stayed "active" with no gate anywhere).
func _check_rental_lifecycle() -> void:
	var gate := RentalGate.start(_car, _hud, _world_file)
	await _step(1)
	var saved: Object = _car.licence_gate
	_car.licence_gate = null
	gate.elapsed_s = RentalGate.HOUR_S - 1.5 / Engine.physics_ticks_per_second
	await _step(3)
	_check(saved == gate and is_instance_valid(gate) and not gate.active() and gate.name == RentalGate.ENDED_NAME and RentalGate.active_on(_car) == null and not WorldStore.rental_active(_world_file), "the hour up while the study holds the gate aside: the rental ended, the record cleared, the gate kept (renamed %s), no active gate on the car" % RentalGate.ENDED_NAME)
	_car.licence_gate = saved
	_check(gate.allows(&"tcs_toggle") == _licence.allows(&"tcs_toggle") and gate.allows(&"gearbox_mode") == _licence.allows(&"gearbox_mode") and gate.allows(&"clutch_pedal"), "the gate the study hands back answers as the licence manager (the aids and the program key no longer refused)")
	await _tap("tcs_toggle")
	var flipped := not _car.tcs_on
	await _tap("tcs_toggle")
	_check(flipped and _car.tcs_on, "through the handed-back gate the TCS key flips the switch (and back)")
	_car.licence_gate = _licence
	gate.queue_free()
	await _step(1)

	var bare: ArcadeCar = (load("res://scenes/car.tscn") as PackedScene).instantiate()
	bare.position = Vector3(200.0, 2.0, 200.0)
	root.add_child(bare)
	await _step(2)
	var bare_gate := RentalGate.start(bare, null, _world_file)
	var on := WorldStore.rental_active(_world_file) and bare.licence_gate == bare_gate
	root.remove_child(bare)
	_check(on and not bare_gate.active() and bare.licence_gate == null and WorldStore.rental(_world_file) == {}, "a car leaving the tree (a scene change, the game closing) takes its rental with it: ended, its gate off the car, the record cleared")
	bare.free()
	await _step(1)


# =============================================================================
#  Taking the car
# =============================================================================

func _check_take_store() -> void:
	var text := FileAccess.get_file_as_string(FirstCar.CONFIG_PATH)
	var config: Variant = JSON.parse_string(text)
	var errors := CarConfigValidation.validate(config, "fd_1001.json")
	_check(config is Dictionary and errors.is_empty() and config.identity.name == "FD-1001" and config.identity.car_id == FirstCar.CAR_ID and config.config_version == 1 and FirstCar.car_name() == "FD-1001", "configs/cars/fd_1001.json: FD-1001 / fd_1001, config_version 1, valid (%d faults)" % errors.size())
	_check(not text.to_lower().contains("porsche") and not text.to_lower().contains("boxster") and not text.to_lower().contains("nissan"), "... unbranded: no trademark in the file")
	_check(FirstCar.tank_capacity_l() == float(config.fuel.tank_capacity_l) and FirstCar.tank_capacity_l() > 0.0, "its tank is the config's %.0f L" % FirstCar.tank_capacity_l())
	var refused := FirstCar.take("", _store_file, true, null)
	_check(not refused.taken and refused.reason == "no world record this run" and not FileAccess.file_exists(_store_file), "take with no world file: nothing taken, nothing written")

	var gate := RentalGate.start(_car, _hud, _world_file)
	await _step(1)
	OdometerStore.save_odometer("boxster_986", 1234.5, _store_file)
	var unspent_before := WorldStore.unspent_vouchers(_world_file).size()
	var result := FirstCar.take(_world_file, _store_file, true, _car)
	await _step(1)
	var driver := WorldStore.load_driver(_world_file)
	_check(unspent_before == 1 and result.taken and result.reason == "" and result.voucher.spent == true and result.voucher.dealership == "E4.1" and WorldStore.unspent_vouchers(_world_file).is_empty() and WorldStore.vouchers(_world_file).size() == 1 and WorldStore.vouchers(_world_file)[0].spent == true, "take: the one unspent voucher is spent (dealership E4.1), none unspent after, none added")
	_check(driver.active_car == FirstCar.CAR_ID and driver.spawn_region == "eifel_ring" and driver.test_centre == "E8.1", "world.json: active_car fd_1001, the pin's record beside it")
	_check((not is_instance_valid(gate) or not gate.active()) and _car.licence_gate == _licence and WorldStore.rental(_world_file) == {}, "a rental on the car ends with the car of one's own (the loaner is for a driver without one)")
	var entry := Garage.stored_entry(FirstCar.CAR_ID, _store_file)
	var fuel := OdometerStore.load_fuel(FirstCar.CAR_ID, FirstCar.tank_capacity_l(), _store_file)
	var licence := OdometerStore.load_licence(FirstCar.CAR_ID, _store_file)
	var dashboard := OdometerStore.load_driver(FirstCar.CAR_ID, _store_file)
	var battery := OdometerStore.load_battery(FirstCar.CAR_ID, _store_file)
	var wear := OdometerStore.load_wear(FirstCar.CAR_ID, _store_file)
	var clean: bool = (fuel.problem == "") and (licence.problems as Array).is_empty() and (dashboard.problems as Array).is_empty() and (battery.problems as Array).is_empty() and (wear.problems as Array).is_empty()
	var defaults_match: bool = entry.odometer_m == 0.0 and fuel.fuel_l == FirstCar.tank_capacity_l() and entry.fuel_l == FirstCar.tank_capacity_l()
	for field: String in OdometerStore.DRIVER_DEFAULTS:
		defaults_match = defaults_match and entry.driver[field] == OdometerStore.DRIVER_DEFAULTS[field]
	for field: String in OdometerStore.BATTERY_DEFAULTS:
		defaults_match = defaults_match and entry.battery[field] == OdometerStore.BATTERY_DEFAULTS[field]
	for field: String in OdometerStore.WEAR_DEFAULTS:
		defaults_match = defaults_match and entry.wear[field] == OdometerStore.WEAR_DEFAULTS[field]
	defaults_match = defaults_match and entry.licence.level == LicenceExams.LICENCE_NONE and entry.licence.passed == [] and entry.licence.elements == []
	_check(clean and defaults_match and not result.entry.is_empty(), "cars.json: fd_1001's entry read back through the store's own loaders field by field - odometer 0, the tank full at %.0f L, the six dashboard defaults, the two battery defaults, the six wear defaults, the licence none / no passes / no elements, no problems" % FirstCar.tank_capacity_l())
	var stored: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(_store_file))
	_check(stored.version == 1 and stored.cars.has("boxster_986") and stored.cars.boxster_986.odometer_m == 1234.5 and stored.cars.has(FirstCar.CAR_ID) and stored.cars.size() == 2, "the file: version 1, the Boxster's entry beside it untouched (1 234.5 m), two cars")
	var second := FirstCar.take(_world_file, _store_file, true, _car)
	_check(not second.taken and second.reason == "no unspent voucher" and WorldStore.load_driver(_world_file).active_car == FirstCar.CAR_ID and JSON.parse_string(FileAccess.get_file_as_string(_store_file)) == stored, "a second take is refused: no unspent voucher, the files unchanged")
	WorldStore.add_voucher(VoucherLedger.voucher_record(), _world_file)
	var off_file := _tmp_dir.path_join("cars_off.json")
	var off := FirstCar.take(_world_file, off_file, false, null)
	_check(off.taken and off.entry.is_empty() and not FileAccess.file_exists(off_file) and WorldStore.unspent_vouchers(_world_file).is_empty(), "with the store off (headless) a take spends the voucher and writes no entry (the licence manager's rule for its record)")


# =============================================================================
#  The dealership on the Ring
# =============================================================================

func _check_dealership_on_ring() -> void:
	WorldStore.set_active_car("", _world_file)
	WorldStore.add_voucher(VoucherLedger.voucher_record(), _world_file)
	var packed: PackedScene = load(RING_SCENE)
	if not _check(packed != null, "the Ring scene loads"):
		return
	var ring := packed.instantiate()
	root.add_child(ring)
	await _step(SETTLE_FRAMES)
	var ring_car := ring.get_node_or_null("Car") as ArcadeCar
	var ring_garage := ring.get_node_or_null("Garage") as Garage
	if not _check(ring_car != null and ring_garage != null and ring.get_node_or_null("WorldMap") == null and ring.get_node_or_null("LicenceManager") == null, "the Ring: a car, a garage, no WorldMap node of its own, no licence manager"):
		ring.queue_free()
		return
	var dealer := Garage.dealership_position()
	_check(Garage.DEALERSHIP_ID == "E4.1" and dealer.distance_to(Vector2(512.481, -6408.644)) < 0.01 and Garage.DEALERSHIP_RADIUS_M == 60.0, "the dealership is E4.1 at (512.481, -6408.644) in region metres, the rows live within 60 m")
	ring_garage.open()
	ring_garage.show_page(Garage.Page.DRIVE)
	var rows := ring_garage.page_rows()
	var by_kind := {}
	for row in rows:
		by_kind[row.kind] = row
	_check(
		by_kind.has("world_map") and by_kind.has("take_car") and by_kind.has("loaner") and not by_kind.take_car.enabled and not by_kind.loaner.enabled
		and by_kind.take_car.hint.contains("E4.1") and by_kind.take_car.hint.contains("Adenau") and by_kind.take_car.label == "Take the FD-1001 (voucher)" and by_kind.loaner.label == "Take the loaner (1 h, eco)"
		and rows[2].kind == "world_map" and rows[3].kind == "take_car" and rows[4].kind == "loaner" and rows[5].kind == "test" and ring_garage.page_text().contains("DEALERSHIP") and not ring_garage.at_dealership(),
		"at the pit with an unspent voucher: the world map row, then the dealership's two rows greyed, their hint saying where to go (E4.1, Adenau), the tests after",
	)
	_check(not ring_garage.activate_row(3) and not ring_garage.activate_row(4) and ring_garage.is_open and RentalGate.active_on(ring_car) == null, "the greyed rows do nothing")
	ring_garage.close()
	ring_car.reset_to(Transform3D(Basis(), Vector3(dealer.x, 0.0, dealer.y)))
	await _step(5)
	_check(ring_garage.at_dealership() and Vector2(ring_car.global_position.x, ring_car.global_position.z).distance_to(dealer) < 0.5, "the car put at the dealership (reset_to): at_dealership")
	# A record left "active" by a run that died (no gate anywhere) does not
	# grey the loaner row (was: it did, for good; 4B-6 audit).
	WorldStore.set_rental(0.0, RentalGate.HOUR_S, _world_file)
	ring_garage.open()
	ring_garage.show_page(Garage.Page.DRIVE)
	rows = ring_garage.page_rows()
	_check(rows[3].kind == "take_car" and rows[3].enabled and rows[4].kind == "loaner" and rows[4].enabled and ring_garage.page_text().contains("you are here") and WorldStore.rental_active(_world_file), "the rows are live at the dealership (the loaner's too, a stale rental record in the file notwithstanding)")
	await _check_drive_page_fits(ring_garage, "the Ring's DRIVE page at the dealership (rows live)")
	_check(ring_garage.activate_row(4) and not ring_garage.is_open and not paused, "the loaner row closes the door")
	await _step(2)
	var ring_gate := RentalGate.active_on(ring_car)
	_check(ring_gate != null and ring_car.licence_gate == ring_gate and ring_gate.previous_gate == null and ring_car.gearbox_mode == ArcadeCar.GearboxMode.ECO and WorldStore.rental_active(_world_file) and ring_gate.allows(&"clutch_pedal") and not ring_gate.allows(&"sc_toggle"), "the rental is on the Ring's car: the gate in front of no gate (no manager here; the clutch allowed, an aid refused), ECO pinned, the record active")
	ring_garage.open()
	ring_garage.show_page(Garage.Page.DRIVE)
	rows = ring_garage.page_rows()
	_check(rows[3].kind == "take_car" and rows[3].enabled and rows[4].kind == "loaner" and not rows[4].enabled and rows[4].hint.contains("already out"), "with the loaner out its row is greyed, the car's row live")
	_check(ring_garage.activate_row(3) and not ring_garage.is_open, "the take row closes the door")
	await _step(2)
	var result: Dictionary = ring_garage.last_dealership_result
	_check(result.taken and result.voucher.spent == true and result.entry.is_empty() and WorldStore.unspent_vouchers(_world_file).is_empty() and WorldStore.load_driver(_world_file).active_car == FirstCar.CAR_ID, "taken: the voucher spent, active_car fd_1001, no entry written (the store is off headless: cars.json in the data folder untouched)")
	_check(RentalGate.active_on(ring_car) == null and ring_car.licence_gate == null and WorldStore.rental(_world_file) == {}, "the loaner is returned with the car of one's own: no gate on the car, the record cleared")
	ring_garage.open()
	ring_garage.show_page(Garage.Page.DRIVE)
	rows = ring_garage.page_rows()
	var kinds := PackedStringArray()
	for row in rows:
		kinds.append(row.kind)
	_check(not kinds.has("take_car") and not kinds.has("loaner") and kinds[2] == "world_map" and kinds[3] == "test", "no voucher unspent: the dealership's rows are gone, the world map row stays")
	ring_garage.show_page(Garage.Page.CAR)
	_check(ring_garage.page_text().contains("OWNED  FD-1001 (fd_1001)"), "the CAR page names the car owned (the swap into the scene is deferred and says so)")
	ring_garage.show_page(Garage.Page.DRIVE)
	_check(ring_garage.activate_row(2) and not ring_garage.is_open, "the world map row closes the door")
	var ring_map := ring.get_node_or_null("WorldMap") as WorldMap
	_check(ring_map != null and ring_map.is_open and not ring_map.forced and paused and ring_map.car == ring_car and ring_map.garage == ring_garage and ring_garage.world_map(false) == ring_map, "... and opens the map, instanced beside the Ring's garage (no node in eifel_ring.tscn), not forced, the tree paused")
	await _tap(&"abort_mission")
	_check(not ring_map.is_open and not paused and not ring_garage.is_open, "Esc closes it (a record exists) and the tree runs; the garage did not open on the same press")
	ring.queue_free()
	await _step(2)
	_check(not is_instance_valid(ring) and is_instance_valid(_car) and _car.is_inside_tree() and not paused, "the Ring unloaded, the pad still here")


# =============================================================================
#  Readability
# =============================================================================

func _check_readability() -> void:
	var screen := Rect2(Vector2.ZERO, Vector2(
		float(ProjectSettings.get_setting("display/window/size/viewport_width")),
		float(ProjectSettings.get_setting("display/window/size/viewport_height")),
	))
	root.size = Vector2i(screen.size)
	await _step(2)
	_check(root.get_visible_rect() == screen and screen.size == Vector2(1280, 720), "the window is the game's own %d x %d" % [int(screen.size.x), int(screen.size.y)])
	# The DRIVE page with the dealership's rows greyed (an unspent voucher,
	# away from the dealership: the longer hint) - the new garage surface
	# at 1280 x 720 too (4B-6 audit: only the map's zooms were measured).
	WorldStore.add_voucher(VoucherLedger.voucher_record(), _world_file)
	_garage.open()
	_garage.show_page(Garage.Page.DRIVE)
	var greyed := _garage.page_rows()
	_check(greyed[3].kind == "take_car" and not greyed[3].enabled and greyed[4].kind == "loaner" and not greyed[4].enabled, "an unspent voucher on the pad: the dealership's two rows are there, greyed")
	await _check_drive_page_fits(_garage, "the pad's DRIVE page with the dealership's rows greyed")
	WorldStore.spend_voucher(_world_file)
	_garage.show_page(Garage.Page.DRIVE)
	var rows := _garage.page_rows()
	_check(rows[2].kind == "world_map" and _garage.activate_row(2) and not _garage.is_open and _map.is_open and not _map.forced and paused, "the garage's World map row opens the pad's own layer, not forced")
	var frame: Control = _map.get_node("Frame")
	var scroll: ScrollContainer = _map.get_node("Frame/Column/Scroll")
	var body: Control = _map.get_node("Frame/Column/Scroll/Body")
	var panel: Control = _map.get_node("Frame/Column/MapPanel")
	for zoom in WorldMap.ZOOM_TITLES.size():
		if zoom > 0:
			await _tap(&"ui_right")
		await _step(2)
		var title: String = WorldMap.ZOOM_TITLES[_map.zoom]
		var off := _off_screen(_map, screen)
		_check(_map.zoom == zoom and off.is_empty() and _inside(frame.get_global_rect(), screen) and _inside(panel.get_global_rect(), frame.get_global_rect()) and panel.size.y >= WorldMap.PANEL_HEIGHT, "%s: the frame %.0f x %.0f px at (%.0f, %.0f) inside the screen, the raster panel inside it, every control inside it or its scroll area%s" % [title, frame.size.x, frame.size.y, frame.global_position.x, frame.global_position.y, _listed(off)])
		var map_rows := _map.page_rows()
		var unreachable := PackedStringArray()
		for row in map_rows.size():
			if row > 0:
				await _tap(&"ui_down")
			var button: Control = _map.get_node("Frame/Column/Scroll/Body/Row%d" % row)
			if not (_map.cursor == row and _inside(button.get_global_rect(), scroll.get_global_rect())):
				unreachable.append("%s (%s)" % [map_rows[row].label, button.get_global_rect()])
		var downs := 0
		while downs < MAX_PAGE_DOWNS:
			var before := scroll.scroll_vertical
			await _tap(&"ui_page_down")
			downs += 1
			if scroll.scroll_vertical == before:
				break
		var last: Control = body.get_child(body.get_child_count() - 1)
		_check(unreachable.is_empty() and _inside(last.get_global_rect(), scroll.get_global_rect()) and map_rows.size() >= 1, "%s: Down lands on each of its %d row(s) inside the %.0f px scroll area (the page is %.0f px), PgDn reaches its end%s" % [title, map_rows.size(), scroll.size.y, body.size.y, ": " + ", ".join(unreachable) if not unreachable.is_empty() else ""])
		for _up in MAX_PAGE_DOWNS:
			if scroll.scroll_vertical == 0:
				break
			await _tap(&"ui_page_up")
	await _tap(&"abort_mission")
	_check(not _map.is_open and not paused and not _garage.is_open, "Esc closes the map opened from the garage; the garage did not open on the same press")


## `garage` open on DRIVE at the game's 1280 x 720: the frame and every
## control inside the screen or the scroll area, Down landing on each row
## inside the scroll area, PgDn reaching the end (the menu test's rule).
func _check_drive_page_fits(garage: Garage, title: String) -> void:
	var screen := Rect2(Vector2.ZERO, Vector2(
		float(ProjectSettings.get_setting("display/window/size/viewport_width")),
		float(ProjectSettings.get_setting("display/window/size/viewport_height")),
	))
	root.size = Vector2i(screen.size)
	await _step(2)
	var frame: Control = garage.get_node("Frame")
	var scroll: ScrollContainer = garage.get_node("Frame/Column/Scroll")
	var body: Control = garage.get_node("Frame/Column/Scroll/Body")
	var off := _off_screen(garage, screen)
	_check(garage.is_open and garage.page == Garage.Page.DRIVE and screen.size == Vector2(1280, 720) and off.is_empty() and _inside(frame.get_global_rect(), screen), "%s: the frame %.0f x %.0f px inside the 1280 x 720 screen, every control inside it or its scroll area%s" % [title, frame.size.x, frame.size.y, _listed(off)])
	var rows := garage.page_rows()
	var unreachable := PackedStringArray()
	for row in rows.size():
		if row > 0:
			await _tap(&"ui_down")
		var button: Control = garage.get_node("Frame/Column/Scroll/Body/Row%d" % row)
		if not (garage.cursor == row and _inside(button.get_global_rect(), scroll.get_global_rect())):
			unreachable.append("%s (%s)" % [rows[row].label, button.get_global_rect()])
	var downs := 0
	while downs < MAX_PAGE_DOWNS:
		var before := scroll.scroll_vertical
		await _tap(&"ui_page_down")
		downs += 1
		if scroll.scroll_vertical == before:
			break
	var last: Control = body.get_child(body.get_child_count() - 1)
	_check(unreachable.is_empty() and _inside(last.get_global_rect(), scroll.get_global_rect()) and rows.size() >= 5, "%s: Down lands on each of its %d rows inside the %.0f px scroll area (the page is %.0f px), PgDn reaches its end%s" % [title, rows.size(), scroll.size.y, body.size.y, ": " + ", ".join(unreachable) if not unreachable.is_empty() else ""])
	garage.show_page(Garage.Page.DRIVE)


## The visible Controls under `node` that reach past `bounds` by more than
## OVERFLOW_TOLERANCE_PX (the menu test's walk).
func _off_screen(node: Node, bounds: Rect2, path := "") -> PackedStringArray:
	var found := PackedStringArray()
	for child in node.get_children():
		var child_path := path + "/" + child.name
		var child_bounds := bounds
		if child is Control:
			var control := child as Control
			if not control.is_visible_in_tree():
				continue
			var rect := control.get_global_rect()
			var over := maxf(
				maxf(bounds.position.x - rect.position.x, rect.end.x - bounds.end.x),
				maxf(bounds.position.y - rect.position.y, rect.end.y - bounds.end.y),
			)
			if over > OVERFLOW_TOLERANCE_PX:
				found.append("%s by %.0f px (%s)" % [child_path, over, rect])
			if control is ScrollContainer:
				child_bounds = Rect2(rect.position.x, -1.0e9, rect.size.x, 2.0e9)
		found.append_array(_off_screen(child, child_bounds, child_path))
	return found


func _inside(rect: Rect2, bounds: Rect2) -> bool:
	return rect.position.x >= bounds.position.x - OVERFLOW_TOLERANCE_PX and rect.position.y >= bounds.position.y - OVERFLOW_TOLERANCE_PX \
		and rect.end.x <= bounds.end.x + OVERFLOW_TOLERANCE_PX and rect.end.y <= bounds.end.y + OVERFLOW_TOLERANCE_PX


func _listed(off: PackedStringArray) -> String:
	return "" if off.is_empty() else " - OFF: " + ", ".join(off)


# =============================================================================
#  Harness
# =============================================================================

func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


## The certified fresh car's tank: full, its mass with it (licence_test.gd's
## idiom: a reset keeps the fuel).
func _fresh_fuel(car: ArcadeCar) -> void:
	car.fuel_l = ArcadeCar.FUEL_TANK_CAPACITY_L
	car.fuel_mass = car.fuel_l * ArcadeCar.FUEL_DENSITY


func _tap(action: StringName) -> void:
	Input.action_press(action)
	await _step(2)
	Input.action_release(action)
	await _step(2)


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
	for action in LicenceExams.ACTIONS:
		Input.action_release(action)
	WorldStore.path_override = ""
	WorldMap.pending_yard = false
	if _tmp_dir != "" and DirAccess.dir_exists_absolute(_tmp_dir):
		_remove_tree(_tmp_dir)
	if _failures == 0:
		print("FIRST RUN TEST PASSED")
	else:
		print("FIRST RUN TEST FAILED: %d check(s) failed" % _failures)
	quit(1 if _failures > 0 else 0)


## Removes the test's own folder, files first, folders after, deepest
## first; hidden files included (the seed's marker is a dotfile).
func _remove_tree(dir: String) -> void:
	var listing := DirAccess.open(dir)
	if listing == null:
		return
	listing.include_hidden = true
	for file_name in listing.get_files():
		DirAccess.remove_absolute(dir.path_join(file_name))
	for dir_name in listing.get_directories():
		_remove_tree(dir.path_join(dir_name))
	DirAccess.remove_absolute(dir)

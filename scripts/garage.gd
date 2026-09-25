class_name Garage
extends CanvasLayer
## The garage: the game's menu, a pause overlay over the pad. Tab opens it
## when nothing is running (a mission, a sitting, a lesson); so does Esc,
## when nothing at all is up (no run, no banner, no book) - during a run Esc
## keeps its meaning, abort, and with a banner or the book up it closes
## that first; Tab or Esc close the garage again. Open, the tree is paused
## (SceneTree.paused: the car, the managers, the HUD and the recorder stand
## still; this layer alone keeps processing, PROCESS_MODE_ALWAYS), the
## driving keys reach nothing and everything under the dim is exactly as it
## was when the door closes again: the same ticks after the same ticks, to
## the bit, whether the garage was open in between or not
## (tests/menu_test.gd holds it there). No time scale, no delta of its own.
##
## Five pages, tabs across the top, the arrow keys and Enter or the mouse:
##   DRIVE      free driving on a map (MAPS: exactly the maps there are), the
##              world map (the first run's layer, scripts/world_map.gd,
##              opened again from here; 4B-6), the dealership's rows where
##              the driver holds an unspent voucher (the FD-1001 on the
##              voucher, the loaner: scripts/first_car.gd,
##              scripts/rental_gate.gd; greyed away from the dealership),
##              the five handling tests, the L0 sitting, the skid pad exam -
##              every one started through the mission manager's and the
##              licence manager's own start paths, nothing duplicated here,
##   THE STUDY  the lessons (scripts/study_lessons.gd), started through
##              scripts/study.gd; a coming-soon lesson is listed and greyed,
##   CAR        the car's condition as it stands: the odometer, the tank, the
##              battery, the wear of every component as a bar, the dashboard
##              - the same fields the store keeps per car (condition_text
##              reads a store-shaped entry: the live car's or a file's),
##   LICENCE    the licence held, what is passed, what the next level still
##              takes, and the licence book's own text (LicenceManager),
##   SETTINGS   the data folder (DataDir: where it is, choose another, back
##              to the default - a native folder dialog, opened only from
##              here), the HUD bar legend (HUD.bar_legend) and the keys.
## Built from Controls alone, in _build: no scene, no assets. Inert until
## opened: closed it costs a key check a tick.

signal opened
signal closed

## Tab opens and closes; Esc closes, and opens when everything is idle.
const ACTION_OPEN := &"garage"
const ACTION_CLOSE := &"abort_mission"

## Above the HUD (its layer is 1).
const LAYER := 10

enum Page { DRIVE, STUDY, CAR, LICENCE, SETTINGS }
const PAGE_TITLES: Array[String] = ["DRIVE", "THE STUDY", "CAR", "LICENCE", "SETTINGS"]

## The maps free driving can be had on: exactly the ones there are, the
## scene each is, and the row's hint (what is true of that map). Two: the
## pad main.tscn is, and the Ring - the Nordschleife's road alone, bare,
## built from the checked-in skeleton and drape (4B-4), no dressing yet;
## the car spawns at the pit area (ring-region-decisions.md §4). A map that
## is another scene is changed to (_free_drive).
## was one map, a second entry a scene _free_drive did not change to and
## said so -> the Ring row and the change (4B-4).
const MAPS: Array[Dictionary] = [
	{"id": "factory_test_pad", "title": "Factory test pad", "scene": "res://scenes/main.tscn", "hint": "The pad as it is; R puts the car back on the start line."},
	{"id": "eifel_ring", "title": "Nordschleife (bare road)", "scene": "res://scenes/eifel_ring.tscn", "hint": "The Ring's road alone, no dressing yet; the car starts at the pit area by T13; R puts it back at the last place all four wheels stood on the road (was: back at the pit, 2026-09-24)."},
]

## The first-run map's scene, instanced beside this layer where the scene
## has none of its own (the Ring; the pad carries one in main.tscn).
const WORLD_MAP_SCENE := "res://scenes/world_map.tscn"

## The general dealership the first-run voucher is honoured at (the Ring's
## E4 record, PUT IN STONE: VoucherLedger.DEALERSHIP) and how near the car
## must stand to it for the dealership's rows to be live [m]: the OSM
## position is the building's centre, the forecourt is around it.
const DEALERSHIP_ID := VoucherLedger.DEALERSHIP
const DEALERSHIP_RADIUS_M := 60.0

## The road data's attribution, shown on the SETTINGS page as OpenStreetMap
## requires (docs/design/4b/data-pipeline.md §8: the exact string).
const OSM_ATTRIBUTION := "© OpenStreetMap contributors — data licensed under ODbL 1.0, https://www.openstreetmap.org/copyright"

## The frame: size [px], corner radius [px], border width [px], the margins
## inside [px], and how far a row scrolls per key [px].
const FRAME_SIZE := Vector2(1120, 640)
const FRAME_CORNER_RADIUS := 18
const FRAME_BORDER_WIDTH := 4
const FRAME_MARGIN := 18
const SCROLL_STEP := 60.0

## The wear bars on the CAR page: width and height [px].
const WEAR_BAR_SIZE := Vector2(300, 12)

const COLOR_DIM := Color(0, 0, 0, 0.6)
const COLOR_FRAME := Color(0.12, 0.14, 0.2, 0.97)
const COLOR_BORDER := Color(1.0, 0.78, 0.2, 1)
const COLOR_TITLE := Color(1.0, 0.9, 0.35, 1)
const COLOR_TEXT := Color(0.94, 0.94, 0.9, 1)
const COLOR_DIM_TEXT := Color(0.94, 0.94, 0.9, 0.6)
const COLOR_TAB := Color(0.18, 0.21, 0.3, 1)
const COLOR_TAB_CURRENT := Color(1.0, 0.78, 0.2, 1)
const COLOR_ROW := Color(0.16, 0.19, 0.27, 1)
const COLOR_ROW_CURSOR := Color(0.32, 0.36, 0.5, 1)
const COLOR_ROW_DISABLED := Color(0.16, 0.19, 0.27, 0.5)
const COLOR_BAR_BACK := Color(0, 0, 0, 0.45)
const COLOR_WEAR := Color(1.0, 0.55, 0.2, 1)
const COLOR_FUEL := Color(0.85, 0.85, 0.8, 1)
const COLOR_BATTERY := Color(0.55, 0.8, 0.95, 1)

## The keys, as the SETTINGS page lists them (the README's Controls table).
const CONTROLS_TEXT := """Up / W  accelerate          Down / S  brake; a fresh press at a stop selects reverse
Left / A, Right / D  steer      Space  handbrake (hold mid-corner to slide)
Q / E  shift down / up (switches to manual; under neutral: reverse)      M  automatic / manual
N  sport / comfort / eco program (and its driver)      T  TCS      G  ABS      K  SC (licensed only)
Left Shift  clutch pedal (hold; manual, licensed only)      I  starter (tap to crank; hold to keep cranking)
R  reset the car: on the pad to the start line, on a world map to the last place all four wheels stood on the road (keeps the fuel, the heat, the wear; aborts a run or a lesson)
C  cycle the camera: cockpit, front, overhead, wheel, chase      B  look back (hold)      , / .  look left / right (hold)
X  X-ray view      1 - 5  start handling test 1 - 5      Esc  abort the run / close its result
L  licence book (1 sits the L0 exam, 2 the skid pad test while it is open; digits answer the theory)
Tab  garage (also Esc when nothing is running); in it: Left / Right  tabs, Up / Down  rows, Enter  go, PgUp / PgDn  scroll"""

@export var car: ArcadeCar
@export var hud: HUD
@export var missions: MissionManager
@export var licence: LicenceManager
@export var study: Study

var is_open := false
var page := Page.DRIVE

## The keyboard's row on the page, an index into the page's rows; -1 on a
## page without rows.
var cursor := -1

## The current page's rows (see page_rows) and their buttons.
var _rows: Array[Dictionary] = []
var _row_buttons: Array[Button] = []

## The current page's text blocks, joined for page_text().
var _texts: PackedStringArray = PackedStringArray()

## Whether everything was idle the tick before (see _physics_process): Esc
## opens the garage only on a tick that follows an idle one, so the Esc
## that closes a banner or the book never opens the garage as well.
var _idle_last_tick := false

## What the SETTINGS page last said about a folder chosen or refused.
var _folder_status := ""

## What the dealership's last row did (FirstCar.take's dictionary), for
## whoever asks (tests).
var last_dealership_result: Dictionary = {}

## The first-run map layer beside this one, found or made on demand.
var _world_map: WorldMap
var _folder_dialog: FileDialog

var _frame: PanelContainer
var _car_name: Label
var _tabs: Array[Button] = []
var _scroll: ScrollContainer
var _body: VBoxContainer
var _footer: Label
var _row_style: StyleBoxFlat
var _row_cursor_style: StyleBoxFlat


func _ready() -> void:
	layer = LAYER
	process_mode = Node.PROCESS_MODE_ALWAYS
	visible = false
	_build()


func _physics_process(_delta: float) -> void:
	if not is_open:
		var idle := _everything_idle()
		if Input.is_action_just_pressed(ACTION_OPEN):
			open()
		elif Input.is_action_just_pressed(ACTION_CLOSE) and idle and _idle_last_tick:
			open()
		_idle_last_tick = idle
		return
	if Input.is_action_just_pressed(ACTION_OPEN) or Input.is_action_just_pressed(ACTION_CLOSE):
		close()
		return
	if Input.is_action_just_pressed(&"ui_left"):
		show_page(posmod(page - 1, PAGE_TITLES.size()) as Page)
	elif Input.is_action_just_pressed(&"ui_right"):
		show_page(posmod(page + 1, PAGE_TITLES.size()) as Page)
	elif Input.is_action_just_pressed(&"ui_down"):
		_move_cursor(1)
	elif Input.is_action_just_pressed(&"ui_up"):
		_move_cursor(-1)
	elif Input.is_action_just_pressed(&"ui_page_down"):
		_scroll.scroll_vertical += int(SCROLL_STEP * 4.0)
	elif Input.is_action_just_pressed(&"ui_page_up"):
		_scroll.scroll_vertical -= int(SCROLL_STEP * 4.0)
	elif Input.is_action_just_pressed(&"ui_accept"):
		activate_row(cursor)


# =============================================================================
#  Open and close
# =============================================================================

## Whether the garage may open: nothing running, and the world map not up
## (was: nothing running alone -> the map layer pauses the tree as this one
## does, and Tab or Esc pressed under a forced first-run map must not open
## the garage over it and then unpause the world under the map; 4B-6).
func can_open() -> bool:
	if missions and missions.is_running():
		return false
	var map := world_map(false)
	if map and map.is_open:
		return false
	if licence and licence.is_running():
		return false
	if study and study.is_running():
		return false
	return true


## Nothing running, no banner up, no book open: what Esc opens the garage on.
func _everything_idle() -> bool:
	if not can_open():
		return false
	if missions and missions.state != MissionManager.State.IDLE:
		return false
	if licence and (licence.state != LicenceManager.State.IDLE or licence.book_open):
		return false
	if study and study.state != Study.State.IDLE:
		return false
	return true


## Opens the garage over the pad: banners down, the book closed, the tree
## paused. Returns false while something is running.
func open() -> bool:
	if is_open:
		return true
	if not can_open():
		return false
	if missions:
		missions.dismiss_banner()
	if licence:
		licence.dismiss_banner()
		licence.close_book()
	if study:
		study.dismiss_banner()
	is_open = true
	get_tree().paused = true
	visible = true
	show_page(page)
	opened.emit()
	return true


## Closes the garage and lets the pad run on from exactly where it stood.
func close() -> void:
	if not is_open:
		return
	is_open = false
	visible = false
	get_tree().paused = false
	_idle_last_tick = false
	closed.emit()


func toggle() -> void:
	if is_open:
		close()
	else:
		open()


# =============================================================================
#  Pages
# =============================================================================

## Shows `wanted`, built anew from what the car, the managers and the store
## say right now; the cursor on its first row.
func show_page(wanted: Page) -> void:
	page = wanted
	for index in _tabs.size():
		_tab_style(_tabs[index], index == page)
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	_rows.clear()
	_row_buttons.clear()
	_texts = PackedStringArray()
	match page:
		Page.DRIVE:
			_build_drive_page()
		Page.STUDY:
			_build_study_page()
		Page.CAR:
			_build_car_page()
		Page.LICENCE:
			_build_licence_page()
		Page.SETTINGS:
			_build_settings_page()
	cursor = 0 if not _rows.is_empty() else -1
	_scroll.scroll_vertical = 0
	_highlight_cursor()


## The current page's rows: {label, hint, kind, enabled}, in order. `kind`
## is what the row starts: "map", "world_map", "take_car", "loaner",
## "test", "l0", "skid_pad", "lesson", "choose_folder", "default_folder".
func page_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for row in _rows:
		rows.append({"label": row.label, "hint": row.hint, "kind": row.kind, "enabled": row.enabled, "id": row.get("id", "")})
	return rows


## Everything the current page says in its text blocks (the CAR, LICENCE
## and SETTINGS pages' readouts), joined with newlines.
func page_text() -> String:
	return "\n".join(_texts)


## Does what row `index` of the current page does (the keyboard's Enter, the
## mouse's click). False for no such row or one that is greyed.
func activate_row(index: int) -> bool:
	if index < 0 or index >= _rows.size() or not _rows[index].enabled:
		return false
	var action: Callable = _rows[index].action
	action.call()
	return true


func _move_cursor(step: int) -> void:
	if _rows.is_empty():
		_scroll.scroll_vertical += int(SCROLL_STEP * step)
		return
	cursor = clampi(cursor + step, 0, _rows.size() - 1)
	_highlight_cursor()
	if cursor < _row_buttons.size():
		_scroll.ensure_control_visible(_row_buttons[cursor])


func _highlight_cursor() -> void:
	for index in _row_buttons.size():
		var button := _row_buttons[index]
		var row := _rows[index]
		button.add_theme_stylebox_override("normal", _row_cursor_style if index == cursor else _row_style)
		button.add_theme_stylebox_override("disabled", _row_style)
		button.text = ("%s %s" % ["▶" if index == cursor else "  ", row.label]) + ("\n      %s" % row.hint if row.hint != "" else "")


# --- DRIVE -------------------------------------------------------------------------

func _build_drive_page() -> void:
	_add_heading("FREE DRIVE")
	for map in MAPS:
		_add_row("Free drive  —  %s" % map.title, map.hint, "map", _free_drive.bind(map), true, map.id)
	# was the two maps then the tests -> the world map row after the maps
	# (4B-6, first-run-flow.md §2: "After the first run the garage's DRIVE
	# page gets a row 'World map' that opens the same layer"), and the
	# dealership's rows after it where the driver holds an unspent voucher.
	_add_row("World map", "The pin, the region's test centres and the yard: the first run's map, opened again. Esc comes back here.", "world_map", _open_world_map, true, "world_map")
	var world_path := WorldStore.active_path()
	if world_path != "" and not WorldStore.unspent_vouchers(world_path).is_empty():
		var here := at_dealership()
		# was `active_on(car) != null or WorldStore.rental_active(...)` -> the
		# gate on this car alone: a record left "active" by a run that died
		# greyed the row for good (4B-6 audit; start writes it anew).
		var rental_on := RentalGate.active_on(car) != null
		var where := "Drive to the general dealership %s in Adenau on the Ring (x %.0f, z %.0f in region metres): the voucher is honoured there." % [DEALERSHIP_ID, dealership_position().x, dealership_position().y]
		_add_heading("DEALERSHIP  —  general dealership %s%s" % [DEALERSHIP_ID, "  (you are here)" if here else ""])
		_add_row("Take the %s (voucher)" % FirstCar.car_name(), "Your voucher: one general-class car. The %s's entry starts fresh in cars.json and the voucher is spent." % FirstCar.car_name() if here else where, "take_car", _take_first_car, here, FirstCar.CAR_ID)
		_add_row("Take the loaner (1 h, eco)", ("A liveried loaner for an hour on the tick clock: eco program only, TCS, ABS and SC stay on (the licence gate refuses the switches)." if not rental_on else "A loaner is already out.") if here else where, "loaner", _take_loaner, here and not rental_on, "loaner")
	_add_heading("HANDLING TESTS  (keys 1 - 5 on the pad; a PASSED counts towards L1)")
	var tests := HandlingTests.all_tests()
	var index_stored: Dictionary = missions.telemetry.index if missions and missions.telemetry else {}
	for index in tests.size():
		var test := tests[index]
		var hint := "%s  —  gold %.1f s" % [test.objective, test.gold_time_s]
		var best := TelemetryRecorder.best_line(index_stored, test)
		if best != "":
			hint += "  —  " + best
		_add_row("Test %d  %s" % [index + 1, test.title], hint, "test", _start_test.bind(index), true, test.name)
	_add_heading("LICENCE EXAMS")
	# was "all or nothing" -> each element kept once passed, the sitting
	# resumed: the user's verdict, 2026-09-22 14:56 + 15:02.
	_add_row("L0 licence sitting", "The theory (%d questions) and six elements: parallel park, bay park, hill start, three-point turn, reversing, emergency stop. Each element passed is kept; a sitting resumes at the first not yet passed." % LicenceExams.quiz_questions().size(), "l0", _start_l0, true, LicenceExams.EXAM_L0)
	_add_row("Skid pad exam", LicenceExams.skid_pad_test().objective, "skid_pad", _start_skid_pad, true, LicenceExams.EXAM_SKID_PAD)


## Free driving on `map`: the door opens; on the map this scene already is
## (the garage's parent is the scene's root, its scene_file_path the map's)
## that is all, another map's scene is changed to. The car there is a fresh
## instance at that scene's spawn: nothing of this car goes along (the
## store keeps the odometer, the fuel, the wear and the rest; where it was
## parked stays with queued item 3S).
## was a push_error, "changing scenes is not built yet" -> the change
## (4B-4, the Conductor's ruling: change_scene_to_file, the car
## re-instanced fresh).
func _free_drive(map: Dictionary) -> void:
	close()
	var scene_root := get_parent()
	if scene_root != null and scene_root.scene_file_path == map.scene:
		return
	get_tree().change_scene_to_file(map.scene)


## The world map layer beside this one: the scene's own (main.tscn carries
## one), else one instanced from WORLD_MAP_SCENE when `make` (the Ring's
## garage), null otherwise.
func world_map(make: bool) -> WorldMap:
	if _world_map != null and is_instance_valid(_world_map):
		return _world_map
	_world_map = null
	var scene_root := get_parent()
	if scene_root == null:
		return null
	for child in scene_root.get_children():
		if child is WorldMap:
			_world_map = child
			return _world_map
	if not make:
		return null
	var packed: PackedScene = load(WORLD_MAP_SCENE)
	if packed == null:
		return null
	var map := packed.instantiate() as WorldMap
	map.name = "WorldMap"
	map.car = car
	map.licence = licence
	map.garage = self
	scene_root.add_child(map)
	_world_map = map
	return map


## The "World map" row: the door closes and the map opens (it pauses the
## tree as this layer does; Esc there comes back to the world).
func _open_world_map() -> void:
	close()
	var map := world_map(true)
	if map:
		map.open(false)


## Where the dealership stands (region metres), from the focus table.
static func dealership_position() -> Vector2:
	var record := Buildings.record(DEALERSHIP_ID)
	return record.position() if record else Vector2.ZERO


## Whether the car stands at the dealership: on the Ring, within
## DEALERSHIP_RADIUS_M of its recorded position.
func at_dealership() -> bool:
	var scene_root := get_parent()
	if car == null or scene_root == null or scene_root.scene_file_path != MAPS[1].scene:
		return false
	var at := Vector2(car.global_position.x, car.global_position.z)
	return at.distance_to(dealership_position()) <= DEALERSHIP_RADIUS_M


## "Take the FD-1001 (voucher)": FirstCar.take - the voucher spent, the
## entry written where the store is on, the car recorded as the driver's;
## the door closes.
func _take_first_car() -> void:
	close()
	last_dealership_result = FirstCar.take(WorldStore.active_path(), OdometerStore.PATH, OdometerStore.enabled(), car)


## "Take the loaner": the rental gate on this car for an hour.
func _take_loaner() -> void:
	close()
	RentalGate.start(car, hud, WorldStore.active_path())


func _start_test(index: int) -> void:
	close()
	if missions:
		missions.start_mission(index)


func _start_l0() -> void:
	close()
	if licence:
		licence.start_l0_sitting()


func _start_skid_pad() -> void:
	close()
	if licence:
		licence.start_skid_pad_test()


# --- THE STUDY -------------------------------------------------------------------------

func _build_study_page() -> void:
	_add_text("Lessons: the scripted driver drives the real car in front of you with every input on show (bottom left). Optional, any lesson any time, as often as you like. Esc ends a lesson.", COLOR_DIM_TEXT)
	for group in StudyLessons.GROUPS:
		_add_heading(group)
		for entry in StudyLessons.catalogue():
			if entry.group != group:
				continue
			var soon: bool = entry.get("coming_soon", false)
			_add_row("%s%s" % [entry.title, "  (coming soon)" if soon else ""], entry.objective, "lesson", _start_lesson.bind(entry), not soon, entry.id)


func _start_lesson(entry: Dictionary) -> void:
	close()
	if study:
		study.start_lesson(entry)


# --- CAR -------------------------------------------------------------------------

func _build_car_page() -> void:
	var entry := car_entry(car, licence) if car else {}
	_add_heading("%s  —  %s" % [car_name(), ArcadeCar.CAR_ID])
	_add_text(condition_text(entry), COLOR_TEXT)
	_add_heading("FUEL AND BATTERY")
	_add_bar("Fuel", float(entry.get("fuel_l", 0.0)) / ArcadeCar.FUEL_TANK_CAPACITY_L, "%.1f of %.0f L" % [entry.get("fuel_l", 0.0), ArcadeCar.FUEL_TANK_CAPACITY_L], COLOR_FUEL)
	var battery: Dictionary = entry.get("battery", {})
	_add_bar("Battery charge", float(battery.get("charge", 0.0)), "%.0f %% of a new battery" % (float(battery.get("charge", 0.0)) * 100.0), COLOR_BATTERY)
	_add_bar("Battery health", 1.0 - float(battery.get("capacity_wear", 0.0)), "%.1f %% of its capacity lost for good" % (float(battery.get("capacity_wear", 0.0)) * 100.0), COLOR_BATTERY)
	_add_heading("WEAR  (each component's share of its life used; under 1 % is as new to the physics)")
	var wear: Dictionary = entry.get("wear", {})
	for field: String in OdometerStore.WEAR_DEFAULTS:
		var share := float(wear.get(field, 0.0))
		_add_bar(field.replace("_", " ").capitalize(), share, "%.3f %%" % (share * 100.0), COLOR_WEAR)
	var world_path := WorldStore.active_path()
	if world_path != "":
		var owned := String(WorldStore.load_driver(world_path).active_car)
		if owned != "":
			_add_text("OWNED  %s (%s): taken at the dealership on the voucher; its entry rides cars.json. It becomes the car in the scene when the car swap lands (deferred: scripts/first_car.gd)." % [FirstCar.car_name() if owned == FirstCar.CAR_ID else owned, owned], COLOR_TITLE)
	var kept := "kept in %s" % DataDir.root_on_disk().path_join(OdometerStore.PATH.trim_prefix("user://")) if OdometerStore.enabled() else "not kept in this run (no window: the store is off)"
	_add_text("The car's file: %s. Saved every %.0f s of driving and when the game closes." % [kept, ArcadeCar.ODOMETER_SAVE_INTERVAL], COLOR_DIM_TEXT)


## The car's name from its config's identity, the id if the file says none.
static func car_name() -> String:
	var config: Variant = JSON.parse_string(FileAccess.get_file_as_string(ArcadeCar.CONFIG_PATH))
	if config is Dictionary and (config as Dictionary).get("identity") is Dictionary:
		return String((config as Dictionary).identity.get("name", ArcadeCar.CAR_ID))
	return ArcadeCar.CAR_ID


## The live car as a store-shaped entry (the keys of a car's entry in
## OdometerStore: odometer_m, fuel_l, driver, battery, wear), and its
## licence from the manager where there is one.
static func car_entry(target_car: ArcadeCar, licence_manager: LicenceManager = null) -> Dictionary:
	var entry := {
		"odometer_m": target_car.odometer_m,
		"fuel_l": target_car.fuel_l,
		"driver": target_car.driver_settings(),
		"battery": target_car.battery_settings(),
		"wear": target_car.wear_settings(),
	}
	if licence_manager:
		entry["licence"] = licence_manager.licence.duplicate(true)
	return entry


## A car's entry as the store has it in the file at `path`, the same shape
## as car_entry, through the store's own loaders (a field that is none of
## its own reads as its default there).
static func stored_entry(car_id: String, path := OdometerStore.PATH) -> Dictionary:
	var driver := OdometerStore.load_driver(car_id, path)
	driver.erase("problems")
	var battery := OdometerStore.load_battery(car_id, path)
	battery.erase("problems")
	var wear := OdometerStore.load_wear(car_id, path)
	wear.erase("problems")
	var licence_record := OdometerStore.load_licence(car_id, path)
	licence_record.erase("problems")
	return {
		"odometer_m": OdometerStore.load_odometer(car_id, path),
		"fuel_l": OdometerStore.load_fuel(car_id, ArcadeCar.FUEL_TANK_CAPACITY_L, path).fuel_l,
		"driver": driver,
		"battery": battery,
		"wear": wear,
		"licence": licence_record,
	}


## The CAR page's readout of a store-shaped `entry`: the odometer, the tank,
## the battery, the wear and the dashboard, one line each.
static func condition_text(entry: Dictionary) -> String:
	var driver: Dictionary = entry.get("driver", OdometerStore.DRIVER_DEFAULTS)
	var battery: Dictionary = entry.get("battery", OdometerStore.BATTERY_DEFAULTS)
	var wear: Dictionary = entry.get("wear", OdometerStore.WEAR_DEFAULTS)
	var view := int(driver.get("camera_view", OdometerStore.CAMERA_VIEW_COCKPIT))
	var view_name: String = ChaseCamera.MODE_NAMES[view] if view >= 0 and view < ChaseCamera.MODE_NAMES.size() else str(view)
	var lines := PackedStringArray()
	lines.append("ODOMETER  %.1f km" % (float(entry.get("odometer_m", 0.0)) / 1000.0))
	lines.append("FUEL  %.1f L of %.0f  (%.0f %%)" % [entry.get("fuel_l", 0.0), ArcadeCar.FUEL_TANK_CAPACITY_L, float(entry.get("fuel_l", 0.0)) / ArcadeCar.FUEL_TANK_CAPACITY_L * 100.0])
	lines.append("BATTERY  charge %.0f %%, health %.1f %% (capacity lost %.1f %%)" % [float(battery.get("charge", 0.0)) * 100.0, (1.0 - float(battery.get("capacity_wear", 0.0))) * 100.0, float(battery.get("capacity_wear", 0.0)) * 100.0])
	lines.append("WEAR  clutch %.3f %%   brakes front %.3f %% rear %.3f %%   tyres front %.3f %% rear %.3f %%   engine %.3f %%" % [
		float(wear.get("clutch", 0.0)) * 100.0, float(wear.get("brakes_front", 0.0)) * 100.0, float(wear.get("brakes_rear", 0.0)) * 100.0,
		float(wear.get("tyres_front", 0.0)) * 100.0, float(wear.get("tyres_rear", 0.0)) * 100.0, float(wear.get("engine", 0.0)) * 100.0,
	])
	lines.append("DASHBOARD  TCS %s   ABS %s   SC %s   gearbox %s %s   camera %s" % [
		"on" if driver.get("tcs_on", true) else "OFF", "on" if driver.get("abs_on", true) else "OFF", "on" if driver.get("sc_on", true) else "OFF",
		"automatic" if driver.get("automatic", true) else "MANUAL", String(driver.get("gearbox_mode", "sport")).to_upper(), view_name,
	])
	if entry.has("licence"):
		var record: Dictionary = entry.licence
		lines.append("LICENCE  %s   passed: %s" % [LicenceExams.licence_title(int(record.get("level", LicenceExams.LICENCE_NONE))), ", ".join(PackedStringArray(record.get("passed", []))) if not (record.get("passed", []) as Array).is_empty() else "nothing yet"])
	return "\n".join(lines)


# --- LICENCE -------------------------------------------------------------------------

func _build_licence_page() -> void:
	_add_text(licence_text(), COLOR_TEXT)
	_add_heading("THE LICENCE BOOK")
	_add_text(licence.book_text() if licence else "", COLOR_TEXT)


## The rank panel: the licence held, the rank it is, every pass, the L0
## sitting's checklist (the theory and the six elements, each ticked or not
## from the record) and what the next level still takes - all from the
## licence manager's record and LicenceExams' data.
func licence_text() -> String:
	var level := licence.level() if licence else LicenceExams.LICENCE_NONE
	var passed: Array = licence.licence.get("passed", []) if licence else []
	var elements: Array = licence.licence.get("elements", []) if licence else []
	var lines := PackedStringArray()
	lines.append("LICENCE HELD:  %s" % LicenceExams.licence_title(level))
	var rank := "none: the first rank, TEST DRIVER, is an L1 holder"
	for entry in LicenceExams.RANKS:
		if entry.requires.get("licence", 99) <= level and entry.playable:
			rank = entry.title
	lines.append("RANK:  %s" % rank)
	lines.append("PASSED:  %s" % (", ".join(PackedStringArray(passed)) if not passed.is_empty() else "nothing yet"))
	lines.append("L0 ELEMENTS:  %s" % "   ".join(LicenceManager.checklist(elements)))
	var missing := PackedStringArray()
	if level < LicenceExams.LICENCE_L0:
		# was "all in one sitting" -> each element kept: the user's verdict,
		# 2026-09-22 14:56 + 15:02.
		lines.append("NEXT, L0 CITIZEN:  the L0 sitting (key 1 in the licence book, or DRIVE here): theory, parallel park, bay park, hill start, three-point turn, reversing, emergency stop - each element passed is kept, the sitting resumes at the first not yet passed.")
	elif level < LicenceExams.LICENCE_L1:
		for exam in LicenceExams.l1_requirements():
			if not passed.has(exam):
				missing.append(exam)
		lines.append("NEXT, L1 FACTORY ENTRY:  still to pass - %s" % ", ".join(missing))
	else:
		lines.append("NEXT:  RACE DRIVER - its certification set is not written yet (not yet playable).")
	return "\n".join(lines)


# --- SETTINGS -------------------------------------------------------------------------

func _build_settings_page() -> void:
	_add_heading("DATA LOCATION")
	_add_text(data_location_text(), COLOR_TEXT)
	_add_text("Road data:  " + OSM_ATTRIBUTION, COLOR_TEXT)
	_add_row("Choose a data folder…", "A native folder dialog. Takes effect at the next start: the first start in a new folder copies your data there; nothing is moved or deleted.", "choose_folder", _choose_folder, true)
	_add_row("Use the default folder", "Forgets the chosen folder (the FD_DATA_DIR variable, if set, still wins). Takes effect at the next start.", "default_folder", _use_default_folder, true)
	if _folder_status != "":
		_add_text(_folder_status, COLOR_TITLE)
	_add_heading("HUD BARS: WHAT EVERY BAR MEANS")
	_add_text(HUD.bar_legend(), COLOR_TEXT)
	_add_heading("CONTROLS")
	_add_text(CONTROLS_TEXT, COLOR_TEXT)


## Where the data is this run and where it came from, and what the next
## start will use.
func data_location_text() -> String:
	var lines := PackedStringArray()
	var root := DataDir.root()
	if root == "":
		lines.append("This run:  the default folder, %s" % OS.get_user_data_dir())
	else:
		lines.append("This run:  %s%s" % [root, "  (from the FD_DATA_DIR variable)" if OS.get_environment(DataDir.ENV_VAR).strip_edges() != "" else "  (chosen in these settings)"])
	var bootstrap := DataDir.read_bootstrap()
	lines.append("Chosen folder (the bootstrap file %s):  %s" % [DataDir.BOOTSTRAP_PATH, bootstrap if bootstrap != "" else "none, the default"])
	lines.append("In it: cars.json (the car's odometer, fuel, dashboard, battery, wear, licence) and telemetry/ (every drive, as JSON lines).")
	var seeded: Dictionary = get_node_or_null("/root/DataBootstrap").seeded if get_node_or_null("/root/DataBootstrap") else {}
	if seeded.get("seeded", false):
		lines.append("On this start the folder was new to the game and was seeded with a copy of %s (%d item(s)); the original is untouched." % [seeded.source, (seeded.copied as PackedStringArray).size()])
	return "\n".join(lines)


## Opens the native folder dialog, once; what it picks goes to
## _on_folder_chosen. Never opened by a test.
func _choose_folder() -> void:
	if _folder_dialog == null:
		_folder_dialog = FileDialog.new()
		_folder_dialog.name = "FolderDialog"
		_folder_dialog.file_mode = FileDialog.FILE_MODE_OPEN_DIR
		_folder_dialog.access = FileDialog.ACCESS_FILESYSTEM
		_folder_dialog.use_native_dialog = true
		_folder_dialog.title = "Factory Driver data folder"
		_folder_dialog.current_dir = DataDir.root_on_disk()
		_folder_dialog.dir_selected.connect(_on_folder_chosen)
		add_child(_folder_dialog)
	_folder_dialog.popup_centered(Vector2i(800, 600))


## Whether the folder dialog has ever been made (a test asserts it never is).
func folder_dialog_opened() -> bool:
	return _folder_dialog != null


func _on_folder_chosen(dir: String) -> void:
	var problem := DataDir.set_bootstrap(dir)
	if problem != "":
		_folder_status = "Not taken: %s" % problem
	else:
		_folder_status = "Chosen: %s. From the next start on the data lives there; the first start in it copies what is here now." % dir
	show_page(Page.SETTINGS)


func _use_default_folder() -> void:
	var problem := DataDir.set_bootstrap("")
	_folder_status = "Not taken: %s" % problem if problem != "" else "The default folder again from the next start on."
	show_page(Page.SETTINGS)


# =============================================================================
#  Building
# =============================================================================

## The frame, the header, the tabs, the scrolling body and the footer, once.
func _build() -> void:
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = COLOR_DIM
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	_frame = PanelContainer.new()
	_frame.name = "Frame"
	_frame.anchor_left = 0.5
	_frame.anchor_right = 0.5
	_frame.anchor_top = 0.5
	_frame.anchor_bottom = 0.5
	_frame.offset_left = -FRAME_SIZE.x * 0.5
	_frame.offset_right = FRAME_SIZE.x * 0.5
	_frame.offset_top = -FRAME_SIZE.y * 0.5
	_frame.offset_bottom = FRAME_SIZE.y * 0.5
	var frame_style := StyleBoxFlat.new()
	frame_style.bg_color = COLOR_FRAME
	frame_style.border_color = COLOR_BORDER
	frame_style.set_border_width_all(FRAME_BORDER_WIDTH)
	frame_style.set_corner_radius_all(FRAME_CORNER_RADIUS)
	frame_style.set_content_margin_all(FRAME_MARGIN)
	_frame.add_theme_stylebox_override("panel", frame_style)
	add_child(_frame)

	var column := VBoxContainer.new()
	column.name = "Column"
	column.add_theme_constant_override("separation", 8)
	_frame.add_child(column)

	var header := HBoxContainer.new()
	header.name = "Header"
	column.add_child(header)
	var title := Label.new()
	title.name = "Title"
	title.text = "GARAGE"
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", COLOR_TITLE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_car_name = Label.new()
	_car_name.name = "CarName"
	_car_name.text = car_name()
	_car_name.add_theme_font_size_override("font_size", 16)
	_car_name.add_theme_color_override("font_color", COLOR_DIM_TEXT)
	_car_name.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	header.add_child(_car_name)

	var tabs := HBoxContainer.new()
	tabs.name = "Tabs"
	tabs.add_theme_constant_override("separation", 6)
	column.add_child(tabs)
	for index in PAGE_TITLES.size():
		var tab := Button.new()
		tab.name = PAGE_TITLES[index].replace(" ", "")
		tab.text = PAGE_TITLES[index]
		tab.focus_mode = Control.FOCUS_NONE
		tab.add_theme_font_size_override("font_size", 18)
		tab.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tab.pressed.connect(show_page.bind(index as Page))
		tabs.add_child(tab)
		_tabs.append(tab)

	_scroll = ScrollContainer.new()
	_scroll.name = "Scroll"
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(_scroll)
	_body = VBoxContainer.new()
	_body.name = "Body"
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 6)
	_scroll.add_child(_body)

	_footer = Label.new()
	_footer.name = "Footer"
	_footer.text = "Left / Right  tabs      Up / Down  rows      Enter  go      PgUp / PgDn  scroll      Tab / Esc  close      (or the mouse)"
	_footer.add_theme_font_size_override("font_size", 14)
	_footer.add_theme_color_override("font_color", COLOR_DIM_TEXT)
	column.add_child(_footer)

	_row_style = StyleBoxFlat.new()
	_row_style.bg_color = COLOR_ROW
	_row_style.set_corner_radius_all(8)
	_row_style.set_content_margin_all(8)
	_row_cursor_style = _row_style.duplicate()
	_row_cursor_style.bg_color = COLOR_ROW_CURSOR


func _tab_style(tab: Button, current: bool) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = COLOR_TAB_CURRENT if current else COLOR_TAB
	style.set_corner_radius_all(10)
	style.set_content_margin_all(8)
	tab.add_theme_stylebox_override("normal", style)
	tab.add_theme_stylebox_override("hover", style)
	tab.add_theme_stylebox_override("pressed", style)
	tab.add_theme_color_override("font_color", Color.BLACK if current else COLOR_TEXT)
	tab.add_theme_color_override("font_hover_color", Color.BLACK if current else COLOR_TITLE)


func _add_heading(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", COLOR_TITLE)
	_body.add_child(label)
	_texts.append(text)


func _add_text(text: String, color: Color) -> void:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", color)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_child(label)
	_texts.append(text)


## A row: a button the mouse can press and the cursor can land on.
func _add_row(label: String, hint: String, kind: String, action: Callable, enabled: bool, id := "") -> void:
	var row := {"label": label, "hint": hint, "kind": kind, "action": action, "enabled": enabled, "id": id}
	var button := Button.new()
	button.name = "Row%d" % _rows.size()
	button.focus_mode = Control.FOCUS_NONE
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.disabled = not enabled
	button.add_theme_font_size_override("font_size", 16)
	button.add_theme_color_override("font_color", COLOR_TEXT)
	button.add_theme_color_override("font_disabled_color", COLOR_DIM_TEXT)
	button.add_theme_color_override("font_hover_color", COLOR_TITLE)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	# was: the hint on one line, the button as wide as its longest line and
	# the frame grown with it, past the screen's right edge (THE STUDY's
	# page 1621 px wide on a 1280 px screen) -> the text wraps to the
	# frame's width, the row grows down instead: the user's report,
	# 2026-09-22 16:15. tests/menu_test.gd holds every page inside the screen.
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var index := _rows.size()
	button.pressed.connect(activate_row.bind(index))
	_body.add_child(button)
	_rows.append(row)
	_row_buttons.append(button)


## A labelled bar, `fraction` 0..1 full (clamped, NaN empty), its reading
## beside it.
func _add_bar(label: String, fraction: float, reading: String, color: Color) -> void:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 12)
	var name_label := Label.new()
	name_label.text = label
	name_label.custom_minimum_size = Vector2(180, 0)
	name_label.add_theme_font_size_override("font_size", 15)
	name_label.add_theme_color_override("font_color", COLOR_TEXT)
	line.add_child(name_label)
	var back := ColorRect.new()
	back.custom_minimum_size = WEAR_BAR_SIZE
	back.color = COLOR_BAR_BACK
	line.add_child(back)
	var fill := ColorRect.new()
	fill.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	fill.color = color
	var share := 0.0 if is_nan(fraction) else clampf(fraction, 0.0, 1.0)
	fill.visible = share > 0.0
	fill.scale.x = share
	back.add_child(fill)
	var value := Label.new()
	value.text = reading
	value.add_theme_font_size_override("font_size", 14)
	value.add_theme_color_override("font_color", COLOR_DIM_TEXT)
	line.add_child(value)
	_body.add_child(line)
	_texts.append("%s: %s" % [label, reading])

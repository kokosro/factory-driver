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
## Seven pages, tabs across the top, the arrow keys and Enter or the mouse:
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
##              reads a store-shaped entry: the live car's or a file's); the
##              cars owned and selected; and the DEALERSHIP (TROC-1 slice
##              3; was ECON-3's price table and BUY rows): the exchange-terms
##              table's cars (scripts/dealership.gd,
##              configs/dealership.json), an OWNED line or a BARTER row
##              each, the row live where the driver holds what the desk's
##              terms accept (barter_car: the held obligations transferred
##              to the desk first, then the store's side as
##              CampaignStore.take_car writes it, every transfer reversed
##              where that fails). The credits BUY row is DORMANT behind
##              CREDITS_BUY_ENABLED (buy_car intact, unreached),
##   LICENCE    the licence held, what is passed, what the next level still
##              takes, and the licence book's own text (LicenceManager),
##   SETTINGS   the data folder (DataDir: where it is, choose another, back
##              to the default - a native folder dialog, opened only from
##              here), the sound settings (SOUND-5: SoundSettings, the cat
##              mix on / off and the master trim, two rows that write
##              user://sound_settings.json and take effect on the next
##              sound node - the next drive), the HUD bar legend
##              (HUD.bar_legend) and the keys.
##   MISSIONS   campaign rank, episodes, promotion credentials and entitlements.
##   JOBS       the job board (ECON-1): the credits held, and every paid job
##              in the runner's catalog - its kind, its pay, whether it has
##              been done - started through the mission runner like an
##              episode. A page of its own: the ladder pays nothing and the
##              board unlocks nothing, two loops that share a runner.
## Built from Controls alone, in _build: no scene, no assets. Inert until
## opened: closed it costs a key check a tick.

signal opened
signal closed

## Tab opens and closes; Esc closes, and opens when everything is idle.
const ACTION_OPEN := &"garage"
const ACTION_CLOSE := &"abort_mission"

## Above the HUD (its layer is 1).
const LAYER := 10

# was six pages -> seven: ECON-1 adds JOBS after MISSIONS.
enum Page { DRIVE, STUDY, CAR, LICENCE, SETTINGS, MISSIONS, JOBS }
const PAGE_TITLES: Array[String] = ["DRIVE", "THE STUDY", "CAR", "LICENCE", "SETTINGS", "MISSIONS", "JOBS"]

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

## THE DORMANCY FLAG (ruling 16036083, slice 3's point: the credits BUY row
## goes DORMANT behind a flag - dormant, NOT deleted; it overrules the
## design doc §5 item 3's proposed retire). false, the shipped state: the
## CAR page's dealership trades by barter (the BARTER rows, barter_car), its
## heading carries no credits balance, and buy_car/_buy_car stay intact and
## unreached from the page. true: the credits BUY row and the heading's
## balance render exactly as ECON-3 shipped them wherever a credits ledger
## is wired, the BARTER row only where none is.
## was: no flag - the BUY row was the CAR page's only buy path, keyed on
## the credits balance.
const CREDITS_BUY_ENABLED := false

## The origins a barter trade's transfers are written under in the
## obligations log: "dealership:<car_id>" for the trade,
## "dealership:<car_id>:reverse" for a transfer handed back.
const TRADE_PREFIX := "dealership:"
const TRADE_REVERSE_SUFFIX := ":reverse"

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

## SOUND-5: what the last sound-settings row did, shown under the rows.
var _sound_status := ""

## What the dealership's last row did (FirstCar.take's dictionary), for
## whoever asks (tests).
var last_dealership_result: Dictionary = {}

## What the CAR page's last BUY row did (buy_car's dictionary; {} before
## any), shown on the page and read by tests.
var last_purchase_result: Dictionary = {}

## What the CAR page's last BARTER row did (barter_car's dictionary; {}
## before any), shown on the page and read by tests.
var last_barter_result: Dictionary = {}

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
	var runner := MissionRunner.of(get_tree())
	if runner:
		runner.campaign.changed.connect(_campaign_changed)


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
	var runner := MissionRunner.of(get_tree())
	if runner and not runner.active.is_empty():
		return false
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
		Page.MISSIONS:
			_build_missions_page()
		Page.JOBS:
			_build_jobs_page()
	cursor = 0 if not _rows.is_empty() else -1
	_scroll.scroll_vertical = 0
	_highlight_cursor()


## The current page's rows: {label, hint, kind, enabled}, in order. `kind`
## is what the row starts: "map", "world_map", "take_car", "loaner",
## "test", "l0", "skid_pad", "lesson", "choose_folder", "default_folder",
## "mission", "reward", "job", "buy_car".
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
## re-instanced fresh) -> the Ring through the loading scene (LOADING-1,
## decisions.org C07BE6F1 "no freezing load": scripts/loading.gd builds
## it on worker threads behind a live progress bar and hands over; was
## the direct change, ~17 s of held window under the macOS loading
## bubble). The pad stays direct (its build is trivial), and with the
## setting application/use_async_build off every map is direct as before
## (the suite's menu test pins it off; LoadingScreen.routes decides).
func _free_drive(map: Dictionary) -> void:
	close()
	var scene_root := get_parent()
	if scene_root != null and scene_root.scene_file_path == map.scene:
		return
	if LoadingScreen.routes(map.scene):
		LoadingScreen.go(get_tree(), map.scene)
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
	var runner := MissionRunner.of(get_tree())
	# ECON-3: the ledger is read here as the JOBS page reads it (gated: the
	# defaults, nothing read), for the SELECTED line and the dealership.
	var wired := runner != null and CreditsLedger.active_path() != ""
	if wired:
		runner.credits.load_state()
	var purchases: Array = runner.credits.transactions() if wired else []
	# TROC-1 slice 3: the obligations ledger read the same way, its own
	# wiring (the two stores are gated independently), for the traded lines
	# and the BARTER rows.
	var bartering := runner != null and ObligationsLedger.active_path() != ""
	if bartering:
		runner.obligations.load_state()
	var records: Array = runner.obligations.records() if bartering else []
	if runner and runner.campaign.owns_car("fd_1073"):
		_add_text("OWNED  " + CampaignStore.REWARDS.test_driver + " (fd_1073): granted at promotion.", COLOR_TITLE)
		_add_row("TAKE — " + CampaignStore.REWARDS.test_driver, "Select your reward car. Live vehicle swapping is pending; driving still uses the Boxster.", "take_reward", _take_reward_car.bind("fd_1073"), world_path != "", "fd_1073")
	if runner and runner.campaign.owns_car("boxster_986"):
		_add_text("OWNED  " + CampaignStore.REWARDS.chief + " (boxster_986): granted at promotion; pad Boxster stand-in.", COLOR_TITLE)
		_add_row("TAKE — " + CampaignStore.REWARDS.chief, "Select your reward car. The pad Boxster stands in for the customised car; live vehicle swapping is pending.", "take_reward", _take_reward_car.bind("boxster_986"), world_path != "", "boxster_986")
	if runner and runner.campaign.owns_car("fd_2000"):
		_add_text("OWNED  " + CampaignStore.REWARDS.ace + " (fd_2000): granted at promotion; config-only FD-2000 stand-in.", COLOR_TITLE)
		_add_row("TAKE — " + CampaignStore.REWARDS.ace, "Select your reward car. FD-2000 is a config-only stand-in; live vehicle swapping is pending and driving still uses the Boxster.", "take_reward", _take_reward_car.bind("fd_2000"), world_path != "", "fd_2000")
	if world_path != "":
		var owned := String(WorldStore.load_driver(world_path).active_car)
		if owned == "fd_1073":
			_add_text("SELECTED  " + CampaignStore.REWARDS.test_driver, COLOR_TITLE)
		elif owned == "boxster_986" and runner and runner.campaign.owns_car(owned):
			_add_text("SELECTED  " + CampaignStore.REWARDS.chief, COLOR_TITLE)
		elif owned == "fd_2000" and runner and runner.campaign.owns_car(owned):
			_add_text("SELECTED  " + CampaignStore.REWARDS.ace, COLOR_TITLE)
		elif owned != "" and Dealership.purchased(purchases, owned):
			_add_text("SELECTED  %s (%s): bought at the dealership; its entry rides cars.json. It becomes the car in the scene when the car swap lands (deferred: scripts/first_car.gd)." % [Dealership.car_name(owned), owned], COLOR_TITLE)
		elif owned != "" and traded(records, owned):
			_add_text("SELECTED  %s (%s): traded at the dealership; its entry rides cars.json. It becomes the car in the scene when the car swap lands (deferred: scripts/first_car.gd)." % [Dealership.car_name(owned), owned], COLOR_TITLE)
		elif owned != "":
			_add_text("OWNED  %s (%s): taken at the dealership on the voucher; its entry rides cars.json. It becomes the car in the scene when the car swap lands (deferred: scripts/first_car.gd)." % [FirstCar.car_name() if owned == FirstCar.CAR_ID else owned, owned], COLOR_TITLE)
	_build_dealership(runner, wired, world_path, purchases, bartering, records)
	var kept := "kept in %s" % DataDir.root_on_disk().path_join(OdometerStore.PATH.trim_prefix("user://")) if OdometerStore.enabled() else "not kept in this run (no window: the store is off)"
	_add_text("The car's file: %s. Saved every %.0f s of driving and when the game closes." % [kept, ArcadeCar.ODOMETER_SAVE_INTERVAL], COLOR_DIM_TEXT)


## The dealership (TROC-1 slice 3; was ECON-3's price table): the
## exchange-terms table's cars in file order, an OWNED line for a car the
## driver holds (by promotion, by a purchase in the dormant credits log, or
## by trade), a BARTER row for one they do not, live where the driver holds
## the open obligations the desk's binding term asks for and a world record
## exists; a greyed row says what is held and how many more are needed. The
## terms are shown verbatim: they are the counterparty's words. Rows only
## where an obligations ledger is wired (`bartering`: the runner's, its
## store on): gated (headless, no override) a row could trade nothing and
## write nothing, so the terms are listed as text alone and the page says
## why. `wired` is the credits ledger's own wiring, independent of it: it
## feeds the OWNED-by-purchase scan (`purchases`) and the dormant BUY
## branch, reached only with CREDITS_BUY_ENABLED. The table's faults are
## listed as the JOBS page lists the ledger's.
## was: the heading "DEALERSHIP  —  CREDITS: %d", a BUY row per car keyed
## on the balance, its hint the basis and the price's shortfall, the prices
## as text where gated -> the heading without a balance (the retired
## credits surface, design doc §4), the BARTER row, its hint the desk's
## terms and what the driver holds (the basis is provenance, not a hint),
## the terms as text where gated.
func _build_dealership(runner: MissionRunner, wired: bool, world_path: String, purchases: Array, bartering: bool, records: Array) -> void:
	var table := Dealership.read()
	var balance: int = runner.credits.balance() if wired else 0
	_add_heading("DEALERSHIP  —  CREDITS: %d" % balance if CREDITS_BUY_ENABLED else "DEALERSHIP")
	_add_text("The garage's car shop trades by TROC: barter, not debit. Each car's desk names what it accepts, in its own words; where you hold it, the BARTER row hands it over - the open obligations owed to you, the oldest first, transferred to the desk - and the car is yours. Nothing is priced and nothing is summed. The credits BUY row is dormant (Garage.CREDITS_BUY_ENABLED). The promotion ladder's reward cars are among them (a trade takes one early; the ladder still grants it). The Ring's general dealership %s in Adenau honours the voucher from the DRIVE page; this shop is a page of the garage, no building to drive to. A traded car's entry starts fresh in cars.json and it is selected; live vehicle swapping is pending, driving still uses the Boxster." % DEALERSHIP_ID, COLOR_DIM_TEXT)
	if CREDITS_BUY_ENABLED and not wired:
		_add_text("No ledger this run (the store is off): the prices are listed, nothing can be bought.", COLOR_DIM_TEXT)
	if not bartering:
		_add_text("No obligations ledger this run (the store is off): the terms are listed, nothing can be traded.", COLOR_DIM_TEXT)
	if last_purchase_result.get("summary", "") != "":
		_add_text("Last purchase: " + last_purchase_result.summary, COLOR_TEXT)
	if last_barter_result.get("summary", "") != "":
		_add_text("Last trade: " + last_barter_result.summary, COLOR_TEXT)
	for problem: String in table.problems:
		_add_text("Dealership: " + problem, COLOR_DIM_TEXT)
	var holding: Array = runner.obligations.open_view("player") if bartering else []
	for entry: Dictionary in table.cars:
		var car_id: String = entry.car_id
		var price: int = entry.price_credits
		var label := Dealership.car_name(car_id)
		var term := binding_term(entry)
		var terms_text := terms_text_of(entry)
		var held := offerable(holding, Dealership.dealer_of(entry)).size()
		if runner and runner.campaign.owns_car(car_id):
			if CREDITS_BUY_ENABLED:
				_add_text("OWNED  %s (%s): granted at promotion; listed at %d credits, not for sale to its owner." % [label, car_id, price], COLOR_TITLE)
			else:
				_add_text("OWNED  %s (%s): granted at promotion; not for trade to its owner." % [label, car_id], COLOR_TITLE)
		elif Dealership.purchased(purchases, car_id):
			_add_text("OWNED  %s (%s): bought here for %d credits." % [label, car_id, price], COLOR_TITLE)
		elif _traded_to(records, Dealership.dealer_of(entry), car_id):
			_add_text("OWNED  %s (%s): traded here for %s." % [label, car_id, terms_text], COLOR_TITLE)
		elif CREDITS_BUY_ENABLED and wired:
			var hint: String = entry.basis
			if world_path == "":
				hint += "  No world record this run: nothing can be bought."
			elif balance >= price:
				hint += "  You hold %d credits." % balance
			else:
				hint += "  You hold %d credits: %d short." % [balance, price - balance]
			_add_row("BUY — %s — %d credits" % [label, price], hint, "buy_car", _buy_car.bind(car_id), world_path != "" and balance >= price, car_id)
		elif bartering:
			var needed := term_count(term)
			var satisfiable := not term.is_empty() and held >= needed
			var hint := "The dealer accepts: %s. " % terms_text
			if world_path == "":
				hint += "No world record this run: nothing can be traded."
			elif satisfiable:
				hint += "You hold %d open obligations." % held
			elif held == 0 or term.is_empty():
				hint += "You hold no obligations the desk accepts."
			else:
				hint += "You hold %d open obligations: %d more needed." % [held, needed - held]
			_add_row("BARTER — %s — for %s" % [label, terms_text], hint, "barter_car", _barter_car.bind(car_id), world_path != "" and satisfiable, car_id)
		else:
			if CREDITS_BUY_ENABLED:
				_add_text("%s (%s): %d credits." % [label, car_id, price], COLOR_TEXT)
			_add_text("%s (%s): the dealer accepts %s." % [label, car_id, terms_text], COLOR_TEXT)


## The term of `entry` (Dealership.read's kept entry) a barter settles: of
## the terms settled by "obligation", the one asking for the fewest (the
## first in file order among equals) - the terms are a menu, and the least
## the desk will take is what the row requires. {} where no term is settled
## by an obligation (a "voucher" term is slice 4's: validated by the
## reader, settled by nothing in this build). No value is compared: a count
## is how many records the desk asks for.
static func binding_term(entry: Dictionary) -> Dictionary:
	var binding := {}
	for term: Dictionary in Dealership.terms_of(entry):
		if term.settle != "obligation":
			continue
		if binding.is_empty() or term_count(term) < term_count(binding):
			binding = term
	return binding


## How many things `term` asks for: its count, 1 where it carries none (and
## for {}).
static func term_count(term: Dictionary) -> int:
	return int(term.get("count", 1))


## What the desk accepts for `entry`, in the desk's own words: the binding
## term's accepts; where no term binds, every term's joined by " or ".
static func terms_text_of(entry: Dictionary) -> String:
	var term := binding_term(entry)
	if not term.is_empty():
		return str(term.accepts)
	var words := PackedStringArray()
	for other: Dictionary in Dealership.terms_of(entry):
		words.append(str(other.accepts))
	return " or ".join(words)


## Of `holding` (the driver's open held obligations, the ledger's
## open_view("player")), the ones that can be handed to the desk
## `dealer_id`, in the log's order: every one the desk does not itself owe.
## The ledger refuses a transfer to a record's own debtor (the two sides
## are never one id), so what the desk owes the driver is not payment at
## that desk - settling it is a redemption, slice 4's vocabulary.
static func offerable(holding: Array, dealer_id: String) -> Array:
	return holding.filter(func(record: Dictionary) -> bool: return record.get("debtor") != dealer_id)


static func trade_origin(car_id: String) -> String:
	return TRADE_PREFIX + car_id


static func trade_reverse_origin(car_id: String) -> String:
	return TRADE_PREFIX + car_id + TRADE_REVERSE_SUFFIX


## Ownership by trade: whether the obligations log `records`
## (ObligationsLedger.records()) holds a committed barter of `car_id` - a
## record whose transfers carry {"to": the car's desk, "origin":
## "dealership:<car_id>"} AND whose CURRENT creditor is that desk. A
## reversed trade's record is back with "player" and does not count; the
## transfer stays in its history (the log is append-only). The desk's id is
## the table's (Dealership.read: a res:// read, nothing written); a car the
## table does not trade was never traded.
static func traded(records: Array, car_id: String) -> bool:
	return _traded_to(records, Dealership.dealer_of(Dealership.entry_of(Dealership.read(), car_id)), car_id)


## traded's scan, the desk's id given (the page holds the table already).
static func _traded_to(records: Array, dealer_id: String, car_id: String) -> bool:
	if dealer_id == "":
		return false
	for record: Variant in records:
		if not record is Dictionary or record.get("creditor") != dealer_id or not record.get("transfers") is Array:
			continue
		for transfer: Variant in record.transfers:
			if transfer is Dictionary and transfer.get("to") == dealer_id and transfer.get("origin") == trade_origin(car_id):
				return true
	return false


## The BARTER row: barter_car with the run's own paths (the store where it
## is on), the page built anew so the row becomes OWNED or the refusal
## shows.
func _barter_car(car_id: String) -> void:
	last_barter_result = barter_car(car_id, WorldStore.active_path(), OdometerStore.PATH, OdometerStore.enabled(), car)
	show_page(Page.CAR)


## Trades for `car_id` on the desk's exchange-terms (TROC-1 slice 3), in
## this order: the obligations FIRST - the first N open obligations the
## driver holds as creditor (offerable: the desk's own debts to the driver
## left out), in the log's order, each transferred to the car's desk (ObligationsLedger.transfer, origin "dealership:<car_id>"; N
## the binding term's count) - then the store's side exactly as buy_car
## writes it: the entry with a new car's defaults (FirstCar.default_entry,
## the tank its config's) where the store is kept (`store_kept`, the
## running game; an entry the file already holds is kept as it is),
## "active_car" in the world record at `world_path`, a rental on
## `target_car` ended. A transfer refused mid-trade refuses the WHOLE
## trade; so does the store's side failing AFTER the transfers: every
## committed transfer is reversed (transferred back to "player", origin
## "dealership:<car_id>:reverse") and the failure reported. A reversal that
## itself fails is said so: that obligation sits with the desk - the log is
## the ledger, append-only, nothing is erased. Refused before any write: no
## runner or obligations ledger this run, no world record, a car the table
## does not trade, a car already owned (by promotion, by a purchase in the
## credits log, or by trade), a config the validation refuses, an
## obligations file of a later build's, terms the driver's held obligations
## do not meet (the greyed row's guard, checked again here). Returns
##   {"bought": bool, "reason": "" or why not, "summary": one line for
##    the page, "traded": the transferred records as written, "reversed":
##    the handed-back records as written, "entry": the entry written or {}}
func barter_car(car_id: String, world_path: String, store_path := OdometerStore.PATH, store_kept := false, target_car: ArcadeCar = null) -> Dictionary:
	var result := {"bought": false, "reason": "", "summary": "", "traded": [], "reversed": [], "entry": {}}
	var label := Dealership.car_name(car_id)
	var runner := MissionRunner.of(get_tree())
	if runner == null or ObligationsLedger.active_path() == "":
		return _trade_refused(result, label, "no obligations ledger this run (the store is off)")
	if world_path == "":
		return _trade_refused(result, label, "no world record this run")
	var entry := Dealership.entry_of(Dealership.read(), car_id)
	if entry.is_empty():
		return _trade_refused(result, label, "the dealership does not sell %s" % car_id)
	var dealer_id := Dealership.dealer_of(entry)
	var ledger: ObligationsLedger = runner.obligations
	ledger.load_state()
	var purchases: Array = []
	if CreditsLedger.active_path() != "":
		runner.credits.load_state()
		purchases = runner.credits.transactions()
	if runner.campaign.owns_car(car_id) or Dealership.purchased(purchases, car_id) or _traded_to(ledger.records(), dealer_id, car_id):
		return _trade_refused(result, label, "already owned")
	var config: Variant = JSON.parse_string(FileAccess.get_file_as_string(Dealership.config_path(car_id)))
	if not config is Dictionary or not CarConfigValidation.validate(config, car_id).is_empty():
		return _trade_refused(result, label, "its config is refused by the validation")
	if ledger.newer_file:
		return _trade_refused(result, label, "the obligations file is a later build's")
	var term := binding_term(entry)
	var terms_text := terms_text_of(entry)
	if term.is_empty():
		return _trade_refused(result, label, "the dealer accepts %s, which nothing settles in this build" % terms_text)
	var needed := term_count(term)
	var held := offerable(ledger.open_view("player"), dealer_id)
	if held.size() < needed:
		return _trade_refused(result, label, "the dealer accepts %s: %d more needed (%d of %d held)" % [terms_text, needed - held.size(), held.size(), needed])
	for i: int in needed:
		var moved := ledger.transfer(held[i].id, "player", dealer_id, trade_origin(car_id))
		if moved.is_empty():
			return _trade_refused(result, label, "the ledger refused the transfer of %s" % held[i].id + _reverse_trade(result, ledger, dealer_id, car_id))
		result.traded.append(moved)
	var failure := ""
	if store_kept and not OdometerStore._cars(OdometerStore._read(store_path)).has(car_id):
		var fresh := FirstCar.default_entry()
		fresh.fuel_l = config.fuel.tank_capacity_l
		OdometerStore.save_car(car_id, fresh.odometer_m, fresh.fuel_l, store_path, fresh.driver, fresh.battery, fresh.wear)
		OdometerStore.save_licence(car_id, fresh.licence, store_path)
		if OdometerStore._cars(OdometerStore._read(store_path)).has(car_id):
			result.entry = fresh
		else:
			failure = "the car's entry could not be written to cars.json"
	if failure == "":
		WorldStore.set_active_car(car_id, world_path)
		if WorldStore.load_driver(world_path).active_car != car_id:
			failure = "the world record could not be written"
	if failure != "":
		return _trade_refused(result, label, failure + _reverse_trade(result, ledger, dealer_id, car_id))
	var rental := RentalGate.active_on(target_car)
	if rental:
		rental.end()
	elif WorldStore.rental_active(world_path):
		WorldStore.clear_rental(world_path)
	result.bought = true
	result.summary = "%s traded for %s." % [label, terms_text]
	return result


## Hands every transfer in `result.traded` back to "player" (origin
## "dealership:<car_id>:reverse"), the handed-back records appended to
## `result.reversed`, and returns the clause the refusal ends with: what
## was handed back, or - honestly - which obligation a failed reversal
## left with the desk. "" where nothing had been transferred.
static func _reverse_trade(result: Dictionary, ledger: ObligationsLedger, dealer_id: String, car_id: String) -> String:
	var stuck := PackedStringArray()
	for moved: Dictionary in result.traded:
		var back := ledger.transfer(moved.id, dealer_id, "player", trade_reverse_origin(car_id))
		if back.is_empty():
			stuck.append(str(moved.id))
		else:
			result.reversed.append(back)
	if not stuck.is_empty():
		return ", AND the reversal failed: %s sits with the dealer (the log is the ledger, nothing is erased)" % ", ".join(stuck)
	if result.traded.is_empty():
		return ""
	return ", the %d obligations handed back" % result.traded.size() if result.traded.size() != 1 else ", the obligation handed back"


static func _trade_refused(result: Dictionary, label: String, reason: String) -> Dictionary:
	result.reason = reason
	result.summary = "%s not traded: %s." % [label, reason]
	return result


## The BUY row: buy_car with the run's own paths (the store where it is
## on), the page built anew so the row becomes OWNED or the refusal shows.
func _buy_car(car_id: String) -> void:
	last_purchase_result = buy_car(car_id, WorldStore.active_path(), OdometerStore.PATH, OdometerStore.enabled(), car)
	show_page(Page.CAR)


## Buys `car_id` at the dealership's price (ECON-3), in this order: the
## ledger's spend FIRST (the debit committed, reason "car:<car_id>"), then
## the store's side exactly as CampaignStore.take_car's branch writes it -
## the entry with a new car's defaults (FirstCar.default_entry, the tank
## its config's) where the store is kept (`store_kept`, the running game;
## an entry the file already holds is kept as it is, take_car's rule),
## "active_car" in the world record at `world_path`, a rental on
## `target_car` ended - and where the store's side fails AFTER the spend
## the price is refunded (earn, reason "refund:car:<car_id>") and the
## failure reported. Refused before any write: no runner or ledger this
## run, no world record, a car the table does not sell, a car already
## owned (by promotion or by purchase), a config the validation refuses,
## a credits file of a later build's, a balance the price exceeds (the
## greyed row's guard, checked again here). TROC-1 slice 3: DORMANT - no
## row reaches it while CREDITS_BUY_ENABLED is false - and a car owned by
## trade (traded: the barter's committed transfer in the obligations log)
## is already owned here too, never re-bought on the dormant path. Returns
##   {"bought": bool, "reason": "" or why not, "summary": one line for
##    the page, "transaction": the spend as written or {}, "refund": the
##    refund as written or {}, "entry": the entry written or {}}
func buy_car(car_id: String, world_path: String, store_path := OdometerStore.PATH, store_kept := false, target_car: ArcadeCar = null) -> Dictionary:
	var result := {"bought": false, "reason": "", "summary": "", "transaction": {}, "refund": {}, "entry": {}}
	var label := Dealership.car_name(car_id)
	var runner := MissionRunner.of(get_tree())
	if runner == null or CreditsLedger.active_path() == "":
		return _purchase_refused(result, label, "no ledger this run (the store is off)")
	if world_path == "":
		return _purchase_refused(result, label, "no world record this run")
	var entry := Dealership.entry_of(Dealership.read(), car_id)
	if entry.is_empty():
		return _purchase_refused(result, label, "the dealership does not sell %s" % car_id)
	var ledger: CreditsLedger = runner.credits
	ledger.load_state()
	runner.obligations.load_state()
	if runner.campaign.owns_car(car_id) or Dealership.purchased(ledger.transactions(), car_id) or traded(runner.obligations.records(), car_id):
		return _purchase_refused(result, label, "already owned")
	var config: Variant = JSON.parse_string(FileAccess.get_file_as_string(Dealership.config_path(car_id)))
	if not config is Dictionary or not CarConfigValidation.validate(config, car_id).is_empty():
		return _purchase_refused(result, label, "its config is refused by the validation")
	var price: int = entry.price_credits
	if ledger.newer_file:
		return _purchase_refused(result, label, "the credits file is a later build's")
	if ledger.balance() < price:
		return _purchase_refused(result, label, "%d credits short (%d of %d)" % [price - ledger.balance(), ledger.balance(), price])
	var transaction := ledger.spend(price, Dealership.purchase_reason(car_id))
	if transaction.is_empty():
		return _purchase_refused(result, label, "the ledger refused the payment")
	result.transaction = transaction
	var failure := ""
	if store_kept and not OdometerStore._cars(OdometerStore._read(store_path)).has(car_id):
		var fresh := FirstCar.default_entry()
		fresh.fuel_l = config.fuel.tank_capacity_l
		OdometerStore.save_car(car_id, fresh.odometer_m, fresh.fuel_l, store_path, fresh.driver, fresh.battery, fresh.wear)
		OdometerStore.save_licence(car_id, fresh.licence, store_path)
		if OdometerStore._cars(OdometerStore._read(store_path)).has(car_id):
			result.entry = fresh
		else:
			failure = "the car's entry could not be written to cars.json"
	if failure == "":
		WorldStore.set_active_car(car_id, world_path)
		if WorldStore.load_driver(world_path).active_car != car_id:
			failure = "the world record could not be written"
	if failure != "":
		result.refund = ledger.earn(price, Dealership.refund_reason(car_id))
		return _purchase_refused(result, label, failure + (", the %d credits refunded" % price if not result.refund.is_empty() else ", AND the refund failed: the ledger holds the debit"))
	var rental := RentalGate.active_on(target_car)
	if rental:
		rental.end()
	elif WorldStore.rental_active(world_path):
		WorldStore.clear_rental(world_path)
	result.bought = true
	result.summary = "%s bought for %d credits." % [label, price]
	return result


static func _purchase_refused(result: Dictionary, label: String, reason: String) -> Dictionary:
	result.reason = reason
	result.summary = "%s not bought: %s." % [label, reason]
	return result


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
	# SOUND-5: the sound settings, two rows over the store (read once per
	# build; the rows are live where the store names a file - gated, headless
	# without an override, they are shown with the defaults and disabled).
	_add_heading("SOUND")
	var sound := SoundSettings.current()
	var live := SoundSettings.active_path() != ""
	_add_text(sound_settings_text(sound, live), COLOR_TEXT)
	_add_row(cat_mix_label(sound.cat_mix_chosen(), sound.cat_mix(), OS.get_environment(SoundNode.CAT_ENV_VAR)), "Enter flips what is heard and keeps it. The household's cat mix (CAT-AWARE-1): the squeal pitched down and 6 dB quieter, the thumps softened, a gentle low-pass on every sound. Takes effect on the next drive (the next sound node made). FD_CAT set to anything but 1 by the caller overrides it with the realistic mix; FD_SOUND=0 is silence whatever this says.", "cat_mix", _flip_cat_mix, live)
	_add_row(master_trim_label(sound.master_trim_db()), "Enter: %.1f dB quieter each press, down to %.0f dB, then round to %+.0f dB. One offset on every sound the game writes (the engine, the rumble, the squeal, the wind, the thumps); a muted channel stays muted. Takes effect on the next drive." % [SoundSettings.TRIM_STEP_DB, SoundSettings.TRIM_DB_MIN, SoundSettings.TRIM_DB_MAX], "master_trim", _step_master_trim, live)
	if _sound_status != "":
		_add_text(_sound_status, COLOR_TITLE)
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


## SOUND-5: the cat mix row's label, pure: the mix a sound node made now
## would play (SoundNode.cat_mode_effective of the FD_CAT `env`, whether a
## cat mix is `chosen` in the store and the chosen `on`), in words - and
## where the store does not decide it, why: not chosen yet (the
## environment's semantics as shipped), or chosen but overridden by a
## caller's FD_CAT.
static func cat_mix_label(chosen: bool, on: bool, env: String) -> String:
	var heard := SoundNode.cat_mode_effective(env, chosen, on)
	var text := "Cat mix: ON — the squeal down-pitched, thumps softened (the cat's hearing)" if heard else "Cat mix: OFF — the realistic mix"
	if not chosen:
		return text + " (not chosen here yet: as launched, FD_CAT %s)" % ("unset" if env == "" else env)
	if env != "" and env != "1":
		return text + " (the caller's FD_CAT=%s overrides the %s chosen here this run)" % [env, "ON" if on else "OFF"]
	return text


## SOUND-5: the master trim row's label, pure: the trim as the store keeps
## it (clamped, snapped), signed.
static func master_trim_label(db: float) -> String:
	return "Master trim: %+.1f dB — one offset on every sound" % SoundSettings.trim_of(db)


## SOUND-5: where the sound settings live this run and what is read, for
## the SETTINGS page; `live` whether the store names a file (the rows are
## live) - gated, the defaults are shown and nothing can be written.
static func sound_settings_text(sound: SoundSettings, live: bool) -> String:
	var lines := PackedStringArray()
	if live:
		lines.append("Kept in %s beside the rest of the data (no file until a row is pressed: until then the launch decides the mix, FD_CAT=1 the cat mix as run.sh sets it, and there is no trim)." % SoundSettings.PATH.trim_prefix("user://"))
	else:
		lines.append("The store is off this run (no window, nothing recorded): the defaults are shown and the rows cannot write.")
	for problem in sound.problems:
		lines.append("Read with a problem: %s" % problem)
	return "\n".join(lines)


## SOUND-5: the cat mix row - the mix a node would play now, flipped and
## written as the chosen one (the first press chooses: the opposite of what
## the environment gives), the page rebuilt with the new label and a status
## line.
func _flip_cat_mix() -> void:
	var sound := SoundSettings.current()
	var heard := SoundNode.cat_mode_effective(OS.get_environment(SoundNode.CAT_ENV_VAR), sound.cat_mix_chosen(), sound.cat_mix())
	var written := sound.set_cat_mix(not heard)
	if written.is_empty():
		_sound_status = "Not taken: %s" % _sound_refusal(sound)
	else:
		_sound_status = "Cat mix %s from the next drive on." % ("ON" if written.cat_mix else "OFF")
	show_page(Page.SETTINGS)


## SOUND-5: the master trim row - one step quieter (SoundSettings.trim_stepped:
## TRIM_STEP_DB down, round to TRIM_DB_MAX past TRIM_DB_MIN), written.
func _step_master_trim() -> void:
	var sound := SoundSettings.current()
	var written := sound.set_master_trim_db(SoundSettings.trim_stepped(sound.master_trim_db()))
	if written.is_empty():
		_sound_status = "Not taken: %s" % _sound_refusal(sound)
	else:
		_sound_status = "Master trim %+.1f dB from the next drive on." % written.master_trim_db
	show_page(Page.SETTINGS)


## Why a sound-settings write was refused, in words.
static func _sound_refusal(sound: SoundSettings) -> String:
	if SoundSettings.active_path() == "":
		return "the store is off this run."
	if sound.newer_file:
		return "%s is a later build's file; it is left alone." % SoundSettings.PATH
	return "%s could not be written." % SoundSettings.PATH


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


# --- MISSIONS --------------------------------------------------------------------

func _campaign_changed() -> void:
	if is_open and page in [Page.MISSIONS, Page.CAR, Page.JOBS]:
		show_page(page)

func _build_missions_page() -> void:
	var runner := MissionRunner.of(get_tree())
	if runner == null:
		_add_text("Campaign unavailable.", COLOR_DIM_TEXT)
		return
	runner.configure(car, hud)
	var record := runner.campaign.state
	_add_heading("CAMPAIGN RANK: " + (record.rank.replace("_", " ").to_upper() if record.rank != "" else "NOT ENROLLED — earn L1 FACTORY ENTRY"))
	var credentials := PackedStringArray()
	for rank: String in CampaignStore.RANKS:
		if record.credentials[rank + "_licence"]:
			credentials.append(rank.replace("_", " ").capitalize() + " licence")
	_add_text("Campaign credentials: " + (", ".join(credentials) if not credentials.is_empty() else "none yet"), COLOR_TEXT)
	_add_text("Ace is the final rank." if record.rank == "ace" else "Promotion tests: FD-12 → Test Driver, FD-22 → Chief, FD-33 → Ace. Unlimited retries.", COLOR_TEXT)
	_add_text(runner.result_text(), COLOR_TEXT)
	if runner.catalog.is_empty():
		_add_text("No playable campaign missions yet. The mission ladder is under construction.", COLOR_DIM_TEXT)
	for id: String in runner.catalog:
		var mission: Dictionary = runner.catalog[id]
		# Paid jobs have the JOBS page; the ladder's page lists the ladder.
		if mission.has("reward_credits"):
			continue
		var reason := runner.campaign.unlock_reason(mission)
		if reason == "" and not runner.environment_matches(mission.environment):
			reason = "Open the " + mission.environment + " from DRIVE first"
		var best: Dictionary = record.results.get(id, {})
		var hint: String = mission.briefing + ("\nLocked: " + reason if reason != "" else "\nEnter to start — " + mission.environment)
		if not best.is_empty():
			hint += "\nBest %.3f s — %s — %d attempts" % [best.best_time_s, best.medal, best.attempts]
		_add_row(id + " — " + mission.title, hint, "mission", _start_episode.bind(id), reason == "", id)
	_add_heading("REWARD ENTITLEMENTS")
	for rank: String in CampaignStore.REWARDS:
		if CampaignStore.REWARD_CARS.has(rank):
			var owned := runner.campaign.owns_car(CampaignStore.REWARD_CARS[rank])
			_add_row(("OWNED — TAKE — " if owned else "") + CampaignStore.REWARDS[rank], "Select your promotion reward. Live vehicle swapping is pending; driving still uses the Boxster." if owned else "Requires " + rank.replace("_", " "), "reward", _take_reward_car.bind(CampaignStore.REWARD_CARS[rank]), owned and WorldStore.active_path() != "", rank)
		else:
			_add_row(CampaignStore.REWARDS[rank], ("Earned" if record.rewards[rank] else "Requires " + rank.replace("_", " ")) + " — car configuration coming later", "reward", Callable(), false, rank)

## The job board, TROC (TROC-1 slice 2; was: the credits held, the payments
## received, then the rows with their pay): one row per posted job naming
## its poster and what the poster will owe, then the driver's open
## obligations. The obligations ledger is read here and nowhere at idle;
## gated (headless, no override) it reads nothing and nothing is owed.
func _build_jobs_page() -> void:
	var runner := MissionRunner.of(get_tree())
	if runner == null:
		_add_text("Job board unavailable.", COLOR_DIM_TEXT)
		return
	runner.configure(car, hud)
	var record := runner.campaign.state
	_add_heading("JOB BOARD")
	_add_text("The board trades by TROC: a job done leaves its poster owing you what they promised, every time it is done. No credits, no balances: each row names who posts the job, what they will owe you and the tip they offer; what is owed to you and by you is listed below. The promotion ladder leaves nobody owing.", COLOR_TEXT)
	var listed := 0
	for id: String in runner.catalog:
		var job: Dictionary = runner.catalog[id]
		if not job.has("reward_credits"):
			continue
		listed += 1
		var reason := runner.campaign.unlock_reason(job)
		if reason == "" and not runner.environment_matches(job.environment):
			reason = "Open the " + job.environment + " from DRIVE first"
		var best: Dictionary = record.results.get(id, {})
		var done: bool = best.get("medal", "") != ""
		var hint: String = job.briefing + ("\nLocked: " + reason if reason != "" else "\nEnter to start — " + job.environment)
		if not best.is_empty():
			hint += "\nBest %.3f s — %s — %d attempts" % [best.best_time_s, best.medal if done else "not yet delivered", best.attempts]
		if job.has("poster"):
			hint += "\nPosted by %s — on delivery they owe you: %s" % [job.poster, job.poster_owed]
			if job.has("poster_offers"):
				hint += " — tip: " + job.poster_offers
		_add_row("%s%s — %s  —  %s" % ["DONE — " if done else "", id, job.title, str(job.get("job_kind", "job"))], hint, "job", _start_episode.bind(id), reason == "", id)
	if listed == 0:
		_add_text("No jobs posted.", COLOR_DIM_TEXT)
	runner.obligations.load_state()
	var owed_to_me: Array = runner.obligations.open_view("player")
	var owed_by_me: Array = runner.obligations.open_view("", "player")
	for entry: Dictionary in owed_to_me:
		_add_text("Owed to you by %s: %s" % [entry.debtor, entry.owed], COLOR_TEXT)
	for entry: Dictionary in owed_by_me:
		_add_text("You owe %s: %s" % [entry.creditor, entry.owed], COLOR_TEXT)
	if owed_to_me.is_empty() and owed_by_me.is_empty():
		_add_text("Nothing owed to you or by you yet.", COLOR_DIM_TEXT)

func _take_reward_car(car_id: String) -> void:
	var runner := MissionRunner.of(get_tree())
	if runner and runner.campaign.take_car(car_id, WorldStore.active_path(), OdometerStore.PATH, OdometerStore.enabled(), car):
		show_page(Page.CAR)

func _start_episode(id: String) -> void:
	var runner := MissionRunner.of(get_tree())
	runner.configure(car, hud)
	close()
	runner.start(id)

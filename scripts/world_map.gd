class_name WorldMap
extends CanvasLayer
## The first-run map (docs/design/4b/first-run-flow.md §2-3, steps 1-3):
## where a new driver drops the pin, picks the region's test centre and is
## taken to its yard. A full-screen state built like a garage page: a
## CanvasLayer over everything (LAYER, the garage's), PROCESS_MODE_ALWAYS,
## the tree paused while it is open, rows the keyboard walks and a headless
## test drives (page_rows / activate_row, the garage's pattern), Enter to
## confirm, Left / Right between the three zooms, Esc closing it - except
## on a first run, where Esc does NOTHING: there is no world to go back to
## (open question 3 of the flow, resolved: the map is forced on a fresh
## record and "Go to the yard" is the only way out).
##
## THE ZOOMS: CONTINENT, a plain labelled raster of Europe with one pin per
## region built so far (REGIONS: the Ring, SkeletonLoader.BBOX; the
## rendering source is DEFERRED per the flow's §2, no tiles service in 4B);
## REGION, the pinned region's test centres from its focus table
## (Buildings.by_element("E8"): the Ring has one, E8.1 Fahrschule Hecken;
## a region with none says so rather than pretending); CENTRE, the chosen
## centre's yard card and its last row, "Go to the yard".
##
## THE YARD (the E8 rule, ring-region-decisions.md line 118: "its yard is
## the pad's licence course on the flattest DGM1 patch within 300 m
## (slope < 1.5 %); if none, the yard moves to the Nürburgring industrial
## estate (landuse=industrial by Meuspath) and the school building stays a
## B9"), MEASURED 4B-6 on the checked-in drape lattice (10 m step, 701 x
## 601 from (0, -6000)), 100 x 100 m patches probed 3 x 3 and the height
## spread taken over the patch's 141.4 m diagonal, the game's own
## projection (SkeletonLoader.wgs84_to_local) for every anchor:
##   - Fahrschule Hecken (E8.1, way 667524970) projects to x 948.421,
##     z -6156.388: 156 m beyond the lattice's northern edge (z -6000), so
##     the covered band within 300 m of it is its southern strip. The
##     flattest patch there measures 7.50 % (centre (980, -5910), 10.61 m
##     of spread; the orchestrator's coarser scan 8.195 % at (975, -5925),
##     11.59 m) - nothing near 1.5 %: NO qualifying patch.
##   - The estate anchor, Porsche Service Zentrum Meuspath (E3.1 / E1.8),
##     projects to x 4414.961, z -2550.796. Within 300 m the patch centred
##     (4515, -2300) measures 1.092 % (1.54 m of spread, heights
##     527.97..529.51 m, 270 m from the anchor; 5 m neighbours on a finer
##     grid down to 0.73 %): under 1.5 %, the ESTATE BRANCH HOLDS.
## DECISION (recorded here; ring-region-decisions.md and focus.json are
## frozen this iteration): the yard goes to the industrial estate, patch
## centre (4515, -2300), and the school building stays a B9 - the map's
## marker for the centre stands at the school's own projected position.
## WHAT THE CHOICE DOES: the pad's licence course IS the yard (the flow's
## §3: "element E8's yard = the pad's course geometry ... on flat ground;
## the pad scene stays as it is for tests and certs"), so "Go to the yard"
## writes spawn_region / test_centre into world.json (WorldStore) and puts
## the car at the yard's start line on the pad: the emergency lane's start
## (x 0, z TestPad.EMERGENCY_START_Z), facing -Z down the course. From the
## pad scene that is one reset_to; from another scene the pad is changed
## to and the car placed there on arrival (pending_yard).
##
## WHO OPENS IT: with NO world record this run (WorldStore.active_path
## names a file and it holds no spawn_region) the pad scene's _ready opens
## the map first, forced; with a record the game starts in the yard as
## ever and the garage's DRIVE row "World map" opens the same layer, Esc
## closing it. Headless with no file named (every existing test) the layer
## is inert: hidden, nothing read, nothing written. The voucher ledger
## (scripts/voucher_ledger.gd) is made here too, on the licence manager,
## where a file is named: L0 granted writes the voucher into the same
## record.
##
## Built from Controls alone, the garage's way (the same node names -
## Frame/Column/Scroll/Body/Row<n> - so the menu test's readability walk
## reads it as it reads a garage page); nothing here touches the car but
## the one reset_to of the yard spawn.

signal opened
signal closed
signal chosen(region: String, centre: String)

## The garage's layer: over the HUD, never both open at once.
const LAYER := Garage.LAYER

## Esc (or Tab) closes the map when it is not forced.
const ACTION_CLOSE := &"abort_mission"
const ACTION_GARAGE := &"garage"

## The pad scene the yard is on.
const PAD_SCENE := "res://scenes/main.tscn"

enum Zoom { CONTINENT, REGION, CENTRE }
const ZOOM_TITLES: Array[String] = ["CONTINENT", "REGION", "TEST CENTRE"]

## The regions built so far: the id world.json records, the title on the
## map, the WGS84 bbox [minlat, minlon, maxlat, maxlon] the pin covers, the
## focus table its test centres come from and the world scene. One today.
const REGIONS: Array[Dictionary] = [
	{"id": "eifel_ring", "title": "Eifel — the Nürburgring region", "bbox": SkeletonLoader.BBOX, "focus": Buildings.PATH, "scene": "res://scenes/eifel_ring.tscn"},
]

## The test-centre element and the general dealership's id (the voucher's,
## VoucherLedger.DEALERSHIP).
const CENTRE_ELEMENT := "E8"
const DEALERSHIP_ELEMENT := "E4"

## Each centre's yard, by focus id: where the yard stands in region metres
## (x east, z south; the measured decision in the header), where the school
## building stands (the map's marker), and the decision's text.
const YARDS := {
	"E8.1": {
		"yard_xz": Vector2(4515.0, -2300.0),
		"school_xz": Vector2(948.421, -6156.388),
		"decision": "The yard: the pad's licence course on the Nürburgring industrial estate by Meuspath, patch centre (4515, -2300) - the flattest 100 m patch within 300 m of the school measures 7.50 % (the E8 rule wants under 1.5 %), the estate's 1.09 %; the school building stays a B9 (measured 4B-6 on the drape lattice; ring-region-decisions.md line 118).",
	},
}

## Where the car stands after the choice: the yard's start line, the
## emergency lane's start, facing -Z down the course (the pad's way).
const YARD_SPAWN_X := 0.0

## The yard's extent on the pad, for whoever asks (tests): z from the
## licence course's near end to the hill start's foot, x the yard's lanes.
const YARD_Z_MIN := 30.0
const YARD_Z_MAX := 110.0
const YARD_X_HALF := 40.0

## The continent raster's window, lon / lat [deg]: Europe.
const CONTINENT_LON_MIN := -12.0
const CONTINENT_LON_MAX := 32.0
const CONTINENT_LAT_MIN := 34.0
const CONTINENT_LAT_MAX := 62.0

## The frame and the raster panel [px]; the garage's frame, the panel a
## band across its top.
const FRAME_SIZE := Garage.FRAME_SIZE
const PANEL_HEIGHT := 220.0
const SCROLL_STEP := Garage.SCROLL_STEP

const COLOR_SEA := Color(0.10, 0.16, 0.26, 1)
const COLOR_LAND := Color(0.20, 0.27, 0.24, 1)
const COLOR_GRID := Color(1, 1, 1, 0.08)
const COLOR_PIN := Color(1.0, 0.78, 0.2, 1)
const COLOR_CENTRE := Color(0.55, 0.85, 1.0, 1)
const COLOR_YARD := Color(0.35, 1.0, 0.45, 1)
const COLOR_DEALER := Color(1.0, 0.55, 0.2, 1)
const COLOR_MARKER_TEXT := Color(0.94, 0.94, 0.9, 1)

@export var car: ArcadeCar
@export var licence: LicenceManager
@export var garage: Garage

var is_open := false

## Whether this opening is a first run's: no record, Esc does nothing.
var forced := false

var zoom := Zoom.CONTINENT

## The pinned region (an index into REGIONS) and the chosen centre's id.
var region_index := 0
var centre_id := ""

## The keyboard's row, an index into the zoom's rows; -1 without rows.
var cursor := -1

## The world record's file this layer reads and writes: WorldStore's
## active path at _ready ("" headless: inert); a test may set it before
## _ready through WorldStore.path_override.
var path := ""

## The voucher ledger on the licence manager, where a file is named.
var ledger: VoucherLedger

## Set before a change to the pad scene: its map places the car in the
## yard on arrival and clears it.
static var pending_yard := false

var _rows: Array[Dictionary] = []
var _row_buttons: Array[Button] = []
var _texts: PackedStringArray = PackedStringArray()
var _opened_this_tick := false

var _frame: PanelContainer
var _zoom_label: Label
var _panel: MapPanel
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
	path = WorldStore.active_path()
	if path != "" and licence:
		ledger = VoucherLedger.new()
		ledger.path = path
		ledger.attach(licence)
	if pending_yard:
		pending_yard = false
		place_in_yard()
	elif path != "" and not WorldStore.has_record(path):
		open(true)


func _physics_process(_delta: float) -> void:
	if not is_open:
		return
	if _opened_this_tick:
		# The press that opened the map (the garage's Enter) is not the
		# map's: the garage ticks first, this layer after it, same tick.
		_opened_this_tick = false
		return
	if Input.is_action_just_pressed(ACTION_CLOSE) or Input.is_action_just_pressed(ACTION_GARAGE):
		if not forced:
			close()
		return
	if Input.is_action_just_pressed(&"ui_down"):
		_move_cursor(1)
	elif Input.is_action_just_pressed(&"ui_up"):
		_move_cursor(-1)
	elif Input.is_action_just_pressed(&"ui_right"):
		zoom_in()
	elif Input.is_action_just_pressed(&"ui_left"):
		zoom_out()
	elif Input.is_action_just_pressed(&"ui_page_down"):
		_scroll.scroll_vertical += int(SCROLL_STEP * 4.0)
	elif Input.is_action_just_pressed(&"ui_page_up"):
		_scroll.scroll_vertical -= int(SCROLL_STEP * 4.0)
	elif Input.is_action_just_pressed(&"ui_accept"):
		activate_row(cursor)


# =============================================================================
#  Open and close
# =============================================================================

## Opens the map over the scene, the tree paused, at the continent; the
## garage closed first if it was up. `as_forced`: a first run, no Esc.
func open(as_forced := false) -> bool:
	if is_open:
		forced = forced or as_forced
		return true
	if garage and garage.is_open:
		garage.close()
	is_open = true
	forced = as_forced
	_opened_this_tick = true
	get_tree().paused = true
	visible = true
	show_zoom(Zoom.CONTINENT)
	opened.emit()
	return true


## Closes the map and lets the scene run on.
func close() -> void:
	if not is_open:
		return
	is_open = false
	forced = false
	visible = false
	get_tree().paused = false
	closed.emit()


# =============================================================================
#  Zooms
# =============================================================================

## Shows `wanted`, built anew: the raster's window and markers, the rows
## and the texts; the cursor on the first row.
func show_zoom(wanted: Zoom) -> void:
	zoom = wanted
	_zoom_label.text = "%s  (%d / %d)" % [ZOOM_TITLES[zoom], zoom + 1, ZOOM_TITLES.size()]
	for child in _body.get_children():
		_body.remove_child(child)
		child.queue_free()
	_rows.clear()
	_row_buttons.clear()
	_texts = PackedStringArray()
	match zoom:
		Zoom.CONTINENT:
			_build_continent()
		Zoom.REGION:
			_build_region()
		Zoom.CENTRE:
			_build_centre()
	cursor = 0 if not _rows.is_empty() else -1
	_scroll.scroll_vertical = 0
	_highlight_cursor()
	_panel.queue_redraw()


## Right: into the cursor's pin or centre; nothing past the centre.
func zoom_in() -> void:
	match zoom:
		Zoom.CONTINENT:
			if cursor >= 0 and cursor < _rows.size() and _rows[cursor].kind == "pin":
				activate_row(cursor)
		Zoom.REGION:
			if cursor >= 0 and cursor < _rows.size() and _rows[cursor].kind == "centre":
				activate_row(cursor)


## Left: out one zoom; nothing before the continent.
func zoom_out() -> void:
	match zoom:
		Zoom.CENTRE:
			show_zoom(Zoom.REGION)
		Zoom.REGION:
			show_zoom(Zoom.CONTINENT)


## The current zoom's rows: {label, hint, kind, enabled, id}, in order.
## `kind`: "pin" (a region), "centre" (a test centre), "go" (the yard).
func page_rows() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for row in _rows:
		rows.append({"label": row.label, "hint": row.hint, "kind": row.kind, "enabled": row.enabled, "id": row.get("id", "")})
	return rows


## Everything the zoom says in its text blocks, joined with newlines.
func page_text() -> String:
	return "\n".join(_texts)


## Does what row `index` does. False for no such row or a greyed one.
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


# --- CONTINENT -------------------------------------------------------------------------

func _build_continent() -> void:
	_panel.set_window(Rect2(CONTINENT_LON_MIN, -CONTINENT_LAT_MAX, CONTINENT_LON_MAX - CONTINENT_LON_MIN, CONTINENT_LAT_MAX - CONTINENT_LAT_MIN), "EUROPE", true)
	for index in REGIONS.size():
		var region: Dictionary = REGIONS[index]
		var centre := region_centre(region)
		_panel.add_marker(Vector2(centre.y, -centre.x), region.title, COLOR_PIN, true)
	_add_heading("DROP THE PIN  —  the region your first run starts in")
	for index in REGIONS.size():
		var region: Dictionary = REGIONS[index]
		var bbox: Array = region.bbox
		var centres := centres_of(region)
		_add_row("Pin:  %s" % region.title, "lat %.2f .. %.2f, lon %.2f .. %.2f  —  %d test centre%s" % [bbox[0], bbox[2], bbox[1], bbox[3], centres.size(), "" if centres.size() == 1 else "s"], "pin", _choose_region.bind(index), true, region.id)
	_add_text("A plain raster: the regions built so far are the pins; the rest of Europe is outline only (the rendering source is deferred, no tiles service in 4B). Enter or Right picks the pin; Left comes back.", Garage.COLOR_DIM_TEXT)


func _choose_region(index: int) -> void:
	region_index = clampi(index, 0, REGIONS.size() - 1)
	show_zoom(Zoom.REGION)


# --- REGION -------------------------------------------------------------------------

func _build_region() -> void:
	var region: Dictionary = REGIONS[region_index]
	var corners := region_corners_xz(region)
	_panel.set_window(Rect2(corners.position, corners.size), region.title, false)
	var centres := centres_of(region)
	for record: Buildings.Record in centres:
		_panel.add_marker(record.position(), "%s (%s)" % [record.osm_name, record.id], COLOR_CENTRE, true)
		if YARDS.has(record.id):
			_panel.add_marker(YARDS[record.id].yard_xz, "the yard", COLOR_YARD, false)
	for record: Buildings.Record in dealerships_of(region):
		_panel.add_marker(record.position(), "general dealership (%s)" % record.id, COLOR_DEALER, false)
	_add_heading("%s  —  TEST CENTRES" % region.title.to_upper())
	if centres.is_empty():
		_add_text("no test centre here yet — nearest: none built", Garage.COLOR_TEXT)
	for record: Buildings.Record in centres:
		var yard: Dictionary = YARDS.get(record.id, {})
		var hint := "%s %d, %s; the yard %s" % [record.osm_type, record.osm_id, _place_of(record), "on the industrial estate at (%.0f, %.0f)" % [yard.yard_xz.x, yard.yard_xz.y] if not yard.is_empty() else "not placed"]
		_add_row("%s — test centre" % record.osm_name, hint, "centre", _choose_centre.bind(record.id), true, record.id)
	_add_text("From the region's focus table (%s). Enter or Right picks the centre; Left back to the continent." % region.focus, Garage.COLOR_DIM_TEXT)


func _choose_centre(id: String) -> void:
	centre_id = id
	show_zoom(Zoom.CENTRE)


# --- CENTRE -------------------------------------------------------------------------

func _build_centre() -> void:
	var region: Dictionary = REGIONS[region_index]
	var record := Buildings.record(centre_id)
	var yard: Dictionary = YARDS.get(centre_id, {})
	var name := record.osm_name if record else centre_id
	if not yard.is_empty():
		var school: Vector2 = yard.school_xz
		var yard_xz: Vector2 = yard.yard_xz
		var low := Vector2(minf(school.x, yard_xz.x) - 300.0, minf(school.y, yard_xz.y) - 300.0)
		var high := Vector2(maxf(school.x, yard_xz.x) + 300.0, maxf(school.y, yard_xz.y) + 300.0)
		_panel.set_window(Rect2(low, high - low), name, false)
		_panel.add_marker(school, "%s (school building, B9)" % name, COLOR_CENTRE, true)
		_panel.add_marker(yard_xz, "the yard (the pad's licence course)", COLOR_YARD, true)
	elif record:
		var at := record.position()
		_panel.set_window(Rect2(at - Vector2(500.0, 500.0), Vector2(1000.0, 1000.0)), name, false)
		_panel.add_marker(at, name, COLOR_CENTRE, true)
	_add_heading("%s  —  THE YARD" % name.to_upper())
	_add_row("Go to the yard", "The car is put on the yard's start line, facing the course. THE STUDY is in the garage from there (Tab); the L0 sitting starts from the licence book (L, then 1) or the garage's DRIVE row.", "go", _go_to_yard, true, centre_id)
	if not yard.is_empty():
		_add_text(yard.decision, Garage.COLOR_TEXT)
	var dealers := dealerships_of(region)
	if not dealers.is_empty():
		var dealer: Buildings.Record = dealers[0]
		_add_text("Passing the L0 sitting grants a voucher for one general-class car, honoured at the region's general dealership %s (%s): the garage's DRIVE page shows the row when you stand there." % [dealer.id, _place_of(dealer)], Garage.COLOR_TEXT)
	_add_text("Left goes back to the region's centres.", Garage.COLOR_DIM_TEXT)


## The choice: the record written (where a file is named), the map closed,
## the car in the yard - on the pad now, or the pad changed to.
func _go_to_yard() -> void:
	var region: Dictionary = REGIONS[region_index]
	if path != "":
		WorldStore.set_spawn(region.id, centre_id, path)
	chosen.emit(region.id, centre_id)
	close()
	var scene_root := get_parent()
	if car and scene_root != null and scene_root.scene_file_path == PAD_SCENE:
		place_in_yard()
		return
	pending_yard = true
	get_tree().change_scene_to_file(PAD_SCENE)


## The yard's start line on the pad: x 0, z EMERGENCY_START_Z, facing -Z.
static func yard_spawn() -> Transform3D:
	return Transform3D(Basis(), Vector3(YARD_SPAWN_X, 0.0, TestPad.EMERGENCY_START_Z))


## Whether `at` (x, z) is inside the yard's extent on the pad.
static func in_yard(at: Vector3) -> bool:
	return at.z >= YARD_Z_MIN and at.z <= YARD_Z_MAX and absf(at.x) <= YARD_X_HALF


## Puts the car on the yard's start line (reset_to: at rest, the engine
## running, the fuel and the wear kept).
func place_in_yard() -> void:
	if car:
		car.reset_to(yard_spawn())


# =============================================================================
#  The data
# =============================================================================

## Whether `region`'s bbox holds (lat, lon).
static func region_contains(region: Dictionary, lat: float, lon: float) -> bool:
	var bbox: Array = region.bbox
	return lat >= bbox[0] and lat <= bbox[2] and lon >= bbox[1] and lon <= bbox[3]


## The region the pin at (lat, lon) falls in, {} for none.
static func region_at(lat: float, lon: float) -> Dictionary:
	for region in REGIONS:
		if region_contains(region, lat, lon):
			return region
	return {}


## The bbox's centre (lat, lon).
static func region_centre(region: Dictionary) -> Vector2:
	var bbox: Array = region.bbox
	return Vector2((bbox[0] + bbox[2]) * 0.5, (bbox[1] + bbox[3]) * 0.5)


## The bbox's corners in region metres: (x_min, z_min) and the size, the
## four projected corners' extent.
static func region_corners_xz(region: Dictionary) -> Rect2:
	var bbox: Array = region.bbox
	var points := [
		SkeletonLoader.wgs84_to_local(bbox[0], bbox[1]), SkeletonLoader.wgs84_to_local(bbox[0], bbox[3]),
		SkeletonLoader.wgs84_to_local(bbox[2], bbox[1]), SkeletonLoader.wgs84_to_local(bbox[2], bbox[3]),
	]
	var low: Vector2 = points[0]
	var high: Vector2 = points[0]
	for point: Vector2 in points:
		low = Vector2(minf(low.x, point.x), minf(low.y, point.y))
		high = Vector2(maxf(high.x, point.x), maxf(high.y, point.y))
	return Rect2(low, high - low)


## The region's test centres (its E8 records), from its focus table. The
## Ring's table is the one Buildings reads; another region's would come
## with its file.
static func centres_of(region: Dictionary) -> Array[Buildings.Record]:
	if region.focus != Buildings.PATH:
		return []
	return Buildings.by_element(CENTRE_ELEMENT)


## The region's general dealerships (its E4 records).
static func dealerships_of(region: Dictionary) -> Array[Buildings.Record]:
	if region.focus != Buildings.PATH:
		return []
	return Buildings.by_element(DEALERSHIP_ELEMENT)


## Where a record stands, for a hint: its region metres.
static func _place_of(record: Buildings.Record) -> String:
	var at := record.position()
	return "at (%.0f, %.0f) in region metres" % [at.x, at.y]


# =============================================================================
#  Building
# =============================================================================

func _build() -> void:
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.color = Garage.COLOR_DIM
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
	frame_style.bg_color = Garage.COLOR_FRAME
	frame_style.border_color = Garage.COLOR_BORDER
	frame_style.set_border_width_all(Garage.FRAME_BORDER_WIDTH)
	frame_style.set_corner_radius_all(Garage.FRAME_CORNER_RADIUS)
	frame_style.set_content_margin_all(Garage.FRAME_MARGIN)
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
	title.text = "WORLD MAP"
	title.add_theme_font_size_override("font_size", 30)
	title.add_theme_color_override("font_color", Garage.COLOR_TITLE)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title)
	_zoom_label = Label.new()
	_zoom_label.name = "ZoomLabel"
	_zoom_label.add_theme_font_size_override("font_size", 16)
	_zoom_label.add_theme_color_override("font_color", Garage.COLOR_DIM_TEXT)
	_zoom_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	header.add_child(_zoom_label)

	_panel = MapPanel.new()
	_panel.name = "MapPanel"
	_panel.custom_minimum_size = Vector2(0, PANEL_HEIGHT)
	_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_panel.clip_contents = true
	column.add_child(_panel)

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
	_footer.text = "Up / Down  rows      Enter  go      Right / Left  zoom in / out      PgUp / PgDn  scroll      Esc  close (not on a first run: there is no world yet)"
	_footer.add_theme_font_size_override("font_size", 14)
	_footer.add_theme_color_override("font_color", Garage.COLOR_DIM_TEXT)
	column.add_child(_footer)

	_row_style = StyleBoxFlat.new()
	_row_style.bg_color = Garage.COLOR_ROW
	_row_style.set_corner_radius_all(8)
	_row_style.set_content_margin_all(8)
	_row_cursor_style = _row_style.duplicate()
	_row_cursor_style.bg_color = Garage.COLOR_ROW_CURSOR


func _add_heading(text: String) -> void:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 15)
	label.add_theme_color_override("font_color", Garage.COLOR_TITLE)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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


## A row: the garage's _add_row, the same button, the same name.
func _add_row(label: String, hint: String, kind: String, action: Callable, enabled: bool, id := "") -> void:
	var row := {"label": label, "hint": hint, "kind": kind, "action": action, "enabled": enabled, "id": id}
	var button := Button.new()
	button.name = "Row%d" % _rows.size()
	button.focus_mode = Control.FOCUS_NONE
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.disabled = not enabled
	button.add_theme_font_size_override("font_size", 16)
	button.add_theme_color_override("font_color", Garage.COLOR_TEXT)
	button.add_theme_color_override("font_disabled_color", Garage.COLOR_DIM_TEXT)
	button.add_theme_color_override("font_hover_color", Garage.COLOR_TITLE)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var index := _rows.size()
	button.pressed.connect(activate_row.bind(index))
	_body.add_child(button)
	_rows.append(row)
	_row_buttons.append(button)


# =============================================================================
#  The raster panel
# =============================================================================

## The plain raster: a window in map units (the continent's lon / -lat, a
## region's x / z metres; y down on the screen is south either way) fitted
## into the panel, a graticule, a land tint for the continent, and the
## markers - a dot, a bigger one for a pin, its label beside it, both kept
## inside the panel. Drawn, never a Control of its own per marker: the
## panel's rect is what the readability check measures.
class MapPanel:
	extends Control

	var window := Rect2(0, 0, 1, 1)
	var title := ""
	var land := false
	var markers: Array[Dictionary] = []

	func set_window(rect: Rect2, name: String, with_land: bool) -> void:
		window = rect
		title = name
		land = with_land
		markers.clear()
		queue_redraw()

	func add_marker(at: Vector2, label: String, color: Color, big: bool) -> void:
		markers.append({"at": at, "label": label, "color": color, "big": big})
		queue_redraw()

	## A map point on the panel: the window fitted whole, centred.
	func to_px(at: Vector2) -> Vector2:
		var scale_px := minf(size.x / maxf(window.size.x, 1e-9), size.y / maxf(window.size.y, 1e-9))
		var offset := (size - window.size * scale_px) * 0.5
		var px := offset + (at - window.position) * scale_px
		return Vector2(clampf(px.x, 6.0, size.x - 6.0), clampf(px.y, 6.0, size.y - 6.0))

	func _draw() -> void:
		draw_rect(Rect2(Vector2.ZERO, size), WorldMap.COLOR_SEA)
		if land:
			# The continent's plain tint: a band of land across the middle
			# (no coastline data in 4B: outline only, said so on the page).
			var scale_px := minf(size.x / window.size.x, size.y / window.size.y)
			var offset := (size - window.size * scale_px) * 0.5
			var low := offset + (Vector2(-10.0, -60.0) - window.position) * scale_px
			var high := offset + (Vector2(30.0, -36.0) - window.position) * scale_px
			draw_rect(Rect2(low, high - low), WorldMap.COLOR_LAND)
		for i in range(1, 8):
			var x := size.x * i / 8.0
			var y := size.y * i / 8.0
			draw_line(Vector2(x, 0), Vector2(x, size.y), WorldMap.COLOR_GRID)
			draw_line(Vector2(0, y), Vector2(size.x, y), WorldMap.COLOR_GRID)
		var font := ThemeDB.fallback_font
		draw_string(font, Vector2(8.0, 18.0), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Garage.COLOR_TITLE)
		for marker: Dictionary in markers:
			var px := to_px(marker.at)
			var radius: float = 7.0 if marker.big else 4.0
			draw_circle(px, radius + 2.0, Color(0, 0, 0, 0.6))
			draw_circle(px, radius, marker.color)
			var text_size := font.get_string_size(marker.label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13)
			var text_at := Vector2(px.x + radius + 6.0, px.y + 5.0)
			if text_at.x + text_size.x > size.x - 4.0:
				text_at.x = maxf(4.0, px.x - radius - 6.0 - text_size.x)
			draw_string(font, text_at, marker.label, HORIZONTAL_ALIGNMENT_LEFT, -1, 13, WorldMap.COLOR_MARKER_TEXT)

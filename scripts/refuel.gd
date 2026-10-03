class_name Refuel
extends Node
## REFUEL AT STATION: the one place in the game a tank is filled. The
## driver's need on the Ring ("running low on fuel already", "maybe get
## some gas from somewhere"): the Boxster burns what it carries
## (scripts/car.gd, the tank and the burn), a reset keeps the level
## (reset_to: "R is a reset, not a refuel"), and until now nothing in the
## game put fuel back - a gas station was "world content to come". This
## node is that content, at its smallest honest size: on the Ring scene
## (scenes/eifel_ring.tscn), when the car stands within RADIUS_M of one of
## the region's placed E2 gas stations, one HUD line offers the fill
## (HINT_TEXT), and while the key (ACTION) is held the tank is filled to
## its capacity - `car.fuel_l = ArcadeCar.FUEL_TANK_CAPACITY_L`, through
## the car's own public setter, which clamps to the tank; the fuel's mass
## follows on the car's next tick (car.gd's _physics_process refreshes
## fuel_mass from fuel_l every tick, and total_mass() rides it). That is
## the whole state change. Nothing else is restored: the wear, the battery,
## the odometer, the heat all stay where they are (a fill is a fill, as a
## reset is a reset); no menu, no animation, no trickle - one deterministic
## fill to the bit, the same number every time. Away from every station: no
## line, no key, nothing.
##
## FUEL FOR OBLIGATIONS (TROC-1 slice 4; was PAID FUEL, ECON-3, now the
## DORMANT credits path below): the station trades fuel for an obligation.
## The rulings (decisions.org 85BE93B5, 2026-09-30, "THE ECONOMY IS TROC -
## FULL RULING": "fuel stations trade fuel for delivery obligations
## (matching the Cat Matrix rule: 10% social stations free, others
## barter)"; 16036083, 2026-10-01: the build order approved as proposed,
## this is docs/design/troc-redesign.md §5 item 4 - "refuel.gd's
## wired-ledger seam becomes a wired-trade seam: with an obligations ledger
## on, holding U at a station creates ... an obligation named by the
## station's terms; the grace seam (free fill where nothing is wired)
## survives. The 10% social rule stays parked."). THE TRADE: the fill tick
## computes the litres the tank is short BEFORE the write, rounded UP to
## the whole litre (fill_litres: ceil, deterministic - the old price's
## rounding rule kept on the litres themselves), and opens ONE record in
## the obligations ledger FIRST (ObligationsLedger.create: creditor the
## station's own id - near.id, "E2.4" - debtor PLAYER, owed the station's
## words owed_text "fuel <n> L", kind FUEL_KIND "fuel-voucher", origin
## FUEL_ORIGIN "refuel", status open) - trade before fuel, the purchase
## order kept: a create the ledger refuses (the store gated, the file a
## later build's, a write that failed) is NO fuel, the tank untouched, the
## tick counted refused. All or nothing, as before. NO credit moves: the
## obligation IS the debt - the driver owes the station the fuel's worth,
## redeemable against any of the station's needs, in whatever the station
## later accepts (the ruling's "whatever Y later accepts"). Nothing is
## priced and nothing is summed: a 44 L fill and a 1 L fill are two
## records, each named, never added. One fill is one record: the tank is
## full after the first tick, so holding the key leaves one obligation,
## not thirty. THE WIRED-TRADE SEAM: the station trades only where an
## obligations ledger is wired - the mission runner's
## (MissionRunner.of(get_tree()).obligations) with its store on
## (ObligationsLedger.active_path() != ""); without a runner (a bare test
## node) or with the store gated (headless, no override) the fill happens
## free exactly as before and the line is exactly HINT_TEXT - THE GRACE
## SEAM survives, the unpaid refuel stays until the station-only rule
## lands with the cat ecology. The line with a ledger wired names the
## station and what the fill will leave owed (troc_line: "... (barter —
## you will owe E2.4: fuel 44 L)", or "... (barter — the tank is full)").
## owed_count counts the fills that left a record and last_obligation is
## the last record as written. NOT in this slice (honestly): redeeming a
## held delivery obligation at the pump (the design's "create-or-redeem")
## - every fill creates; nothing redeems an obligation anywhere yet.
##
## THE DORMANT CREDITS PATH (ECON-3's paid fuel; was: "no money changes
## hands (no economy yet)"), kept behind CREDITS_FUEL_ENABLED exactly as
## the dealership's BUY row is (Garage.CREDITS_BUY_ENABLED, the slice-3
## ruling: dormant, NOT deleted). false, the shipped state: wired_ledger()
## is null whatever the credits store's wiring, the price and the balance
## reach no line and no spend is written. true: the paragraph below is the
## behaviour again wherever a credits ledger is wired and no obligations
## ledger is (the trade wins where both are: TROC is the economy). The
## station charged LITRE_PRICE_CREDITS a litre, AUTHORED - no source fuel
## price exists; 2 cr/L makes a full 64 L Boxster fill 128 credits, about
## one good courier job (the board pays 95-150), so fuel is a routine but
## real draw on the job income. The fill tick computes the litres the tank
## is short BEFORE the write and the cost as those litres times the price,
## rounded UP to the whole credit (fill_cost: ceil, deterministic, no float
## dust in the balance), and pays the credits ledger FIRST (spend, reason
## "fuel") - payment before fuel, the purchase order: a spend the ledger
## refuses (the balance cannot cover it) is NO fuel, the tank untouched,
## the line says the shortfall. All or nothing: no partial fill for what
## the balance can cover (a documented follow-up). THE GRACE SEAM: the
## station pays only where a ledger is wired - the mission runner's
## (MissionRunner.of(get_tree()).credits) with its store on
## (CreditsLedger.active_path() != ""); without a runner (a bare test
## node) or with the store gated (headless, no override) the fill happens
## free exactly as before and the line is exactly HINT_TEXT. The unpaid
## refuel stays until the station-only rule lands with the cat ecology.
## fill_count counts every tick that filled, traded, paid or free;
## paid_credits sums what this node paid (the dormant path: 0 shipped) and
## refused_count the ticks a fill was refused (a trade or a spend).
##
## THE STATIONS are the region's typed buildings (scripts/buildings.gd,
## data/regions/eifel_ring/focus.json): Buildings.by_element("E2") read
## once at _ready, kept to the records that can("sell_fuel") - the
## vocabulary's privilege, held by every E2 (element-library.md §5); a
## record without it would sell nothing here. Positions are region metres
## (Record.position(): SkeletonLoader's projection, x east, z south) and
## the car's are its global x/z: the distance is planar. The nearest
## station within RADIUS_M counts, none else (nearest_within, the pure
## core; the test drives it with synthetic records). Nothing of a station
## is surfaced: not its OSM name, not its brand tags - the region table
## carries those as provenance only (the stone table drops brands
## in-game), and the line names no station.
##
## THE HUD LINE is made here in code and put on the HUD as a child (the
## minimap's idiom, scripts/gps_minimap.gd _label: the HUD is a
## CanvasLayer, add_child works; scenes/hud.tscn and scripts/hud.gd are
## untouched), styled as hud.tscn's GateHint (amber, black outline 6 px,
## 18 px), just above it at the bottom right, hidden unless a station is
## near. With an obligations ledger wired the line names the station and
## what the fill will leave owed (troc_line: "... (barter — you will owe
## E2.4: fuel 44 L)"; the litres move with the idle burn until the key is
## pressed, and the record is written from the tank as the fill tick finds
## it). With the dormant credits path on and wired the line carried the
## price and the balance (hint_line: "... (2 cr/L — you hold N cr)", or
## the shortfall "... (2 cr/L — need ~X cr, you hold N cr)" when the
## balance cannot cover the tank's gap), the credits ledger read from disk
## once on ARRIVAL at a station (the tick `near` turns from null to a
## record) and in memory after. The obligations ledger is not read at idle
## at all: create reads the file first, so the record joins the log as it
## stands on disk. On the pad (scenes/main.tscn) this node does not exist:
## the pad has no station and no scene edit puts one there.
##
## THE KEY: U (physical 85), plain, "fill Up". The brief named H; walking
## the whole InputMap headless (the minimap's and the flagger's own
## conflict check, the engine's built-ins included) H is NOT free: Godot
## 4.7's ui_filedialog_show_hidden is a plain H (keycode 72, no modifier),
## and the garage does open a FileDialog (the folder picker) - the same
## finding that sent the flagger to V and the minimap to P
## (scripts/issue_flagger.gd, scripts/gps_minimap.gd). The free plain
## letters were J, O, U, Y, Z (measured 2026-09-25); U is the one with a
## word in it. project.godot gains exactly one action, refuel, on this
## one key; the test holds it there and holds every other action off it.
##
## This node READS the car's position and WRITES its fuel_l, and with an
## obligations ledger wired the ledger (create; the dormant path's spend
## with the flag on), nothing else; it presses no input and moves nothing.

## The key: U, plain. See the header for the conflict check.
const ACTION := &"refuel"
const KEY := KEY_U

## How near the car must stand to a station's recorded position [m]: the
## OSM position is the station's point (a node) or the centre of its
## footprint (a way; the widest bounds here reach ~35 m diagonally, E2.9),
## and the car's origin must keep clear of the building shell - so the
## gameplay radius is measured from the POINT, not surveyed over the
## forecourt: 30 m of "you are at the station" is what the record can
## honestly carry. Inclusive: at exactly RADIUS_M the station is near.
const RADIUS_M := 30.0

## The privilege a station sells fuel by (ElementCatalogue.PRIVILEGES).
const PRIVILEGE := "sell_fuel"

## The line, exactly this: the tool names its key. No station name in it.
## Without a ledger wired this is the whole line.
const HINT_TEXT := "FUEL STATION near — hold U to fill"

## TROC-1 slice 4: the trade's words. The debtor of every fill (the
## ledger's opaque id for the driver, the runner's and the garage's one),
## the kind of the record (ObligationsLedger.KINDS), its origin, and what
## the station is owed, in its words: the whole litres (fill_litres).
const PLAYER := "player"
const FUEL_KIND := "fuel-voucher"
const FUEL_ORIGIN := "refuel"
const OWED_TEXT := "fuel %d L"

## What the line adds with an obligations ledger wired: the station and
## what the fill will leave owed, or that there is nothing to fill.
const HINT_TROC_SUFFIX := " (barter — you will owe %s: %s)"
const HINT_FULL_SUFFIX := " (barter — the tank is full)"

## THE DORMANCY FLAG (TROC-1 slice 4, the slice-3 shape:
## Garage.CREDITS_BUY_ENABLED). false, the shipped state: the credits path
## below is unreached - wired_ledger() null, no price on any line, no
## spend. true: ECON-3's paid fuel again wherever a credits ledger is
## wired and no obligations ledger is. A const, not a setting: the
## economy is TROC by ruling; the path is kept, not offered.
const CREDITS_FUEL_ENABLED := false

## The price of a litre [credits], AUTHORED (see the header), the dormant
## credits path's. A fill cost ceil(litres short x this), whole credits.
const LITRE_PRICE_CREDITS := 2

## The ledger reason a fill was written under (the dormant credits path).
const FUEL_REASON := "fuel"

## What the line added with a credits ledger wired (the dormant path): the
## price and the balance, or the shortfall (the cost of the tank's gap
## now, the balance).
const HINT_PRICE_SUFFIX := " (%d cr/L — you hold %d cr)"
const HINT_SHORT_SUFFIX := " (%d cr/L — need ~%d cr, you hold %d cr)"

## The line's node on the HUD and its style: hud.tscn's GateHint, stacked
## above it (GateHint: offset -760..-370 x, -200..-174 y from the bottom
## right).
const HINT_NAME := "RefuelHint"
const HINT_COLOR := Color(1, 0.7, 0.15, 1)
const HINT_OUTLINE_COLOR := Color(0, 0, 0, 1)
const HINT_OUTLINE_PX := 6
const HINT_FONT_PX := 18
const HINT_OFFSET_LEFT := -760.0
const HINT_OFFSET_TOP := -232.0
const HINT_OFFSET_RIGHT := -370.0
const HINT_OFFSET_BOTTOM := -206.0

## The car whose tank is filled, and the HUD the line goes on. Wired by the
## scene (NodePath exports, the Garage's idiom).
@export var car: ArcadeCar
@export var hud: HUD

## The stations that sell fuel, read once at _ready (Buildings reads the
## file once; this keeps the filtered list).
var stations: Array[Buildings.Record] = []

## The station the car stands within RADIUS_M of this tick, null away from
## all of them. What the line shows and the key acts on.
var near: Buildings.Record = null

## How many ticks filled the tank: the test's proof that nothing filled it
## at the spawn and something did at the station. Traded, paid or free.
var fill_count := 0

## How many fills left an obligation in the ledger (TROC-1 slice 4), and
## the last record as written ({} before the first).
var owed_count := 0
var last_obligation: Dictionary = {}

## What this node paid the credits ledger [credits], summed (the dormant
## path: 0 shipped), and how many ticks a fill was refused (the trade's
## create refused, or on the dormant path the balance could not cover it:
## no fuel either way).
var paid_credits := 0
var refused_count := 0

var _hint: Label


func _ready() -> void:
	stations = selling(Buildings.by_element(Buildings.STATION_ELEMENT))
	_hint = _make_hint()
	# The HUD is a CanvasLayer: a Label under it draws. Without a HUD (a
	# bare node in a test) the label hangs under this node, drawn nowhere,
	# freed with it.
	(hud if hud != null else self).add_child(_hint)


func _physics_process(_delta: float) -> void:
	if car == null:
		return
	var was := near
	near = nearest_within(car_xz(), stations, RADIUS_M)
	_hint.visible = near != null
	if near == null:
		return
	var trade := wired_obligations()
	# The dormant credits path: null unless CREDITS_FUEL_ENABLED; and the
	# trade wins where both are wired (TROC is the economy).
	var ledger := wired_ledger() if trade == null else null
	if ledger != null and was == null:
		# Arrival: the file as it stands on disk, once.
		ledger.load_state()
	var cost := fill_cost(car.fuel_l)
	var line := troc_line(near.id, car.fuel_l) if trade != null else hint_line(cost, ledger.balance() if ledger != null else 0, ledger != null)
	if _hint.text != line:
		_hint.text = line
	if Input.is_action_pressed(ACTION) and car.fuel_l < ArcadeCar.FUEL_TANK_CAPACITY_L:
		if trade != null:
			# Trade before fuel: the obligation is opened first, from the
			# tank as this tick finds it; a refused create is no fuel, the
			# tank untouched (all or nothing).
			var record := trade.create(near.id, PLAYER, owed_text(car.fuel_l), FUEL_KIND, FUEL_ORIGIN)
			if record.is_empty():
				refused_count += 1
				return
			owed_count += 1
			last_obligation = record
		elif ledger != null:
			# The dormant path: payment before fuel, a refused spend is no
			# fuel, the tank untouched (all or nothing).
			if ledger.spend(cost, FUEL_REASON).is_empty():
				refused_count += 1
				return
			paid_credits += cost
		# The whole state change: the car's own setter clamps to the tank,
		# the mass follows on the car's next tick.
		car.fuel_l = ArcadeCar.FUEL_TANK_CAPACITY_L
		fill_count += 1


## The obligations ledger a fill trades against (TROC-1 slice 4): the
## mission runner's, where there is a runner and its store is on
## (ObligationsLedger.active_path() != ""); null otherwise - the fill is
## free then unless the dormant credits path is on and wired (the grace
## seam, see the header).
func wired_obligations() -> ObligationsLedger:
	var runner := MissionRunner.of(get_tree()) if is_inside_tree() else null
	if runner == null or ObligationsLedger.active_path() == "":
		return null
	return runner.obligations


## The credits ledger a fill paid (the DORMANT path): null while
## CREDITS_FUEL_ENABLED is false, whatever the credits store's wiring; with
## the flag on, the mission runner's where there is a runner and its store
## is on (CreditsLedger.active_path() != ""), null otherwise.
func wired_ledger() -> CreditsLedger:
	if not CREDITS_FUEL_ENABLED:
		return null
	var runner := MissionRunner.of(get_tree()) if is_inside_tree() else null
	if runner == null or CreditsLedger.active_path() == "":
		return null
	return runner.credits


## The litres a fill from `fuel_l` puts in, as the station counts them:
## the gap to the tank's capacity rounded up to the whole litre; 0 for a
## full (or over-full) tank. Pure, deterministic: no float dust in a
## record's words.
static func fill_litres(fuel_l: float) -> int:
	return int(ceil(maxf(ArcadeCar.FUEL_TANK_CAPACITY_L - fuel_l, 0.0)))


## What a fill from `fuel_l` leaves owed, in the station's words: OWED_TEXT
## of fill_litres ("fuel 44 L"). Pure.
static func owed_text(fuel_l: float) -> String:
	return OWED_TEXT % fill_litres(fuel_l)


## The line with an obligations ledger wired, at `station_id` with the
## tank at `fuel_l`: HINT_TEXT with the station and what the fill will
## leave owed, or with HINT_FULL_SUFFIX when there is nothing to fill. Pure.
static func troc_line(station_id: String, fuel_l: float) -> String:
	if fill_litres(fuel_l) == 0:
		return HINT_TEXT + HINT_FULL_SUFFIX
	return HINT_TEXT + HINT_TROC_SUFFIX % [station_id, owed_text(fuel_l)]


## What a fill from `fuel_l` cost [credits] on the dormant credits path:
## the litres to the tank's capacity times LITRE_PRICE_CREDITS, rounded up
## to the whole credit; 0 for a full (or over-full) tank. Pure.
static func fill_cost(fuel_l: float) -> int:
	var litres := maxf(ArcadeCar.FUEL_TANK_CAPACITY_L - fuel_l, 0.0)
	return int(ceil(litres * LITRE_PRICE_CREDITS))


## The dormant credits path's line for a fill that costs `cost` against
## `balance`: HINT_TEXT alone without a ledger (`wired` false), else with
## the price and the balance, or the shortfall when the balance cannot
## cover the cost. Pure.
static func hint_line(cost: int, balance: int, wired: bool) -> String:
	if not wired:
		return HINT_TEXT
	if balance >= cost:
		return HINT_TEXT + HINT_PRICE_SUFFIX % [LITRE_PRICE_CREDITS, balance]
	return HINT_TEXT + HINT_SHORT_SUFFIX % [LITRE_PRICE_CREDITS, cost, balance]


## Whether the line is up: a station is near.
func hint_visible() -> bool:
	return _hint != null and _hint.visible


## The line's text as it stands.
func hint_text() -> String:
	return _hint.text if _hint != null else ""


## The car's place in region metres (x east, z south): its global x and z.
func car_xz() -> Vector2:
	return Vector2(car.global_position.x, car.global_position.z)


## The records among `records` that sell fuel (can(PRIVILEGE)), in order.
static func selling(records: Array[Buildings.Record]) -> Array[Buildings.Record]:
	var found: Array[Buildings.Record] = []
	for record: Buildings.Record in records:
		if record.can(PRIVILEGE):
			found.append(record)
	return found


## The station of `stations` nearest to `car_pos` (region metres, x/z) and
## within `radius_m` of it, inclusive; null when none is. Pure: the
## records' positions and one distance each.
static func nearest_within(car_pos: Vector2, stations: Array[Buildings.Record], radius_m: float) -> Buildings.Record:
	var best: Buildings.Record = null
	var best_m := radius_m
	for station: Buildings.Record in stations:
		var distance_m := car_pos.distance_to(station.position())
		if distance_m <= best_m:
			best = station
			best_m = distance_m
	return best


func _make_hint() -> Label:
	var label := Label.new()
	label.name = HINT_NAME
	label.text = HINT_TEXT
	label.visible = false
	label.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	label.offset_left = HINT_OFFSET_LEFT
	label.offset_top = HINT_OFFSET_TOP
	label.offset_right = HINT_OFFSET_RIGHT
	label.offset_bottom = HINT_OFFSET_BOTTOM
	label.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	label.add_theme_color_override("font_color", HINT_COLOR)
	label.add_theme_color_override("font_outline_color", HINT_OUTLINE_COLOR)
	label.add_theme_constant_override("outline_size", HINT_OUTLINE_PX)
	label.add_theme_font_size_override("font_size", HINT_FONT_PX)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

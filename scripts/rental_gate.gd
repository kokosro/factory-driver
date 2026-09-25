class_name RentalGate
extends Node
## The rental lock (docs/design/4b/first-run-flow.md §5, the driver's rule
## verbatim: "with the rented car ... only eco mode available, can't turn
## tcs, sc or abs off"). A gate on the car's licence_gate hook - the same
## hook the licence manager refuses the aid switches through
## (LicenceManager.allows, ArcadeCar._gate_allows) - with a second reason:
## while a rental is on, the three aid switches and the gearbox program key
## are refused (REFUSED), and every other action is the previous gate's to
## answer (the clutch pedal key: the licence is held, the manager allows
## it). Nothing in car.gd changes: the car asks its gate, this is the gate.
##
## THE ECO PIN: car.gd reads the program key BEFORE it asks any gate
## (_physics_process, `if Input.is_action_just_pressed("gearbox_mode")` runs
## the cycle unconditionally), so refusing "gearbox_mode" alone would not
## hold the program. This node is therefore a child of the car and TICKS
## right after it (a parent's _physics_process runs before its children's):
## every tick it puts the program back on ECO with eco's own driver seated
## (set_driver_profile, the key's own idiom), and the three aids back on,
## whatever the tick before did - measured in tests/first_run_test.gd:
## the key pressed, the mode is ECO after the tick, the aids are on. The
## restorations are counted (restored) so a test can see the pin bite.
##
## THE HOUR: on the tick clock (deterministic, pausable: the tree paused
## by the garage or the map stands this node still with the car), ends
## the rental by itself (end): the previous gate is put back, the record
## in world.json is cleared, the node frees itself. Taking a car of one's
## own ends it too (FirstCar.take): the rule is "if you don't own a car".
## So does the car leaving the tree (a scene change, the game closing:
## _exit_tree) - the rental lives with the car it is on (was: the record
## stayed "active" with no gate anywhere and the garage's loaner row read
## "already out" for good; 4B-6 audit). Ended while its seat is empty -
## THE STUDY holds the gate aside for a lesson and puts it back after -
## the node is not freed but stays an ended gate that answers as the
## previous one (renamed ENDED_NAME), so the gate the lesson hands back is
## never a freed object (was: queue_free under the study's saved gate).
## What happens to the car at the hour beyond the lock coming off is
## DEFERRED (first-run-flow.md §7).

## The name an ended gate still under its car goes by (see the header).
const ENDED_NAME := "RentalGateEnded"

## The actions refused while a rental is on.
const REFUSED: Array[StringName] = [&"tcs_toggle", &"abs_toggle", &"sc_toggle", &"gearbox_mode"]

## What a refused key says by the aid lamps (HUD.set_gate_hint), and for
## how long [s].
const HINT := "RENTAL — eco, aids on"
const HINT_TIME := 1.5

## The rental's length [s of the tick clock]: one hour.
const HOUR_S := 3600.0

## The car this gate is on and the gate it stands in front of (the licence
## manager on the pad, null on the Ring); the HUD for the hint where there
## is one.
var car: ArcadeCar
var previous_gate: Object = null
var hud: HUD

## The file the rental record is kept in (WorldStore.active_path at the
## start; "" writes nothing).
var world_path := ""

## Seconds of the tick clock the rental has run, and its length.
var elapsed_s := 0.0
var expires_s := HOUR_S

## How many times a tick found the program or an aid moved and put it back.
var restored := 0

## How many refusals this gate has answered.
var refused := 0

var _hint_left := 0.0
var _ended := false
var _leaving := false


## Starts a rental on `target_car`: this gate in front of its current one,
## the program pinned to eco, the aids on, the record written where
## `path` names a file. The node is added under the car, named
## "RentalGate". Returns the gate. A car already under one keeps that one.
static func start(target_car: ArcadeCar, target_hud: HUD = null, path := "", length_s := HOUR_S) -> RentalGate:
	var existing := active_on(target_car)
	if existing:
		return existing
	var gate := RentalGate.new()
	gate.name = "RentalGate"
	gate.car = target_car
	gate.hud = target_hud
	gate.world_path = path
	gate.expires_s = length_s
	gate.previous_gate = target_car.licence_gate
	target_car.licence_gate = gate
	gate._pin()
	target_car.add_child(gate)
	if path != "":
		WorldStore.set_rental(0.0, length_s, path)
	return gate


## The rental gate on `target_car`, null for none (an ended one is none).
static func active_on(target_car: ArcadeCar) -> RentalGate:
	if target_car == null:
		return null
	var gate := target_car.get_node_or_null("RentalGate") as RentalGate
	return gate if gate != null and gate.active() else null


## The gate's answer: no to REFUSED while on (the hint up), else the
## previous gate's, yes without one.
func allows(action: StringName) -> bool:
	if not _ended and action in REFUSED:
		refused += 1
		_hint_left = HINT_TIME
		if hud:
			hud.set_gate_hint(HINT)
		return false
	if previous_gate == null:
		return true
	return previous_gate.allows(action)


## Ends the rental: the previous gate back on the car, the record cleared,
## the node freed - or, with the gate held aside (the study's lesson), kept
## as an ended gate answering as the previous one. Idempotent.
func end() -> void:
	if _ended:
		return
	_ended = true
	var seated := is_instance_valid(car) and car.licence_gate == self
	if seated:
		car.licence_gate = previous_gate
	if world_path != "":
		WorldStore.clear_rental(world_path)
	if is_instance_valid(hud) and _hint_left > 0.0:
		hud.set_gate_hint("")
	if seated or _leaving or not is_instance_valid(car) or not car.is_inside_tree():
		queue_free()
	else:
		name = ENDED_NAME


## The car leaving the tree takes the rental with it (the header).
func _exit_tree() -> void:
	_leaving = true
	end()


## Whether the rental is still on.
func active() -> bool:
	return not _ended


func _physics_process(delta: float) -> void:
	if _ended:
		return
	if _hint_left > 0.0:
		_hint_left -= delta
		if _hint_left <= 0.0 and hud:
			hud.set_gate_hint("")
	_pin()
	elapsed_s += delta
	if elapsed_s >= expires_s:
		end()


# The pin itself: the program on ECO with eco's driver, the aids on.
func _pin() -> void:
	if not is_instance_valid(car):
		return
	if car.gearbox_mode != ArcadeCar.GearboxMode.ECO:
		car.gearbox_mode = ArcadeCar.GearboxMode.ECO
		car.set_driver_profile(ArcadeCar.DRIVER_PROFILES[ArcadeCar.MODE_DRIVERS[ArcadeCar.GearboxMode.ECO]])
		restored += 1
	if not car.tcs_on:
		car.tcs_on = true
		restored += 1
	if not car.abs_on:
		car.abs_on = true
		restored += 1
	if not car.sc_on:
		car.sc_on = true
		restored += 1

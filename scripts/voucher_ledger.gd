class_name VoucherLedger
extends RefCounted
## The voucher's trigger (docs/design/4b/first-run-flow.md §4): passing the
## L0 sitting grants the driver a voucher for one car from the region's
## general dealership. This ledger only LISTENS: attach(manager) connects
## the licence manager's licence_changed(level), and on a level of L0 or
## better it writes one voucher into world.json (WorldStore.add_voucher):
##   {"kind": "car", "class": "general", "dealership": "E4.1",
##    "granted_by": "L0", "spent": false}
## record_pass and record_element are not touched; the licence semantics
## are FROZEN (tests/licence_test.gd) and this class asks them for nothing.
##
## GRANTED ONCE: (1) the manager emits licence_changed only when the level
## MOVES (licence_manager.gd _record_changed), and a practice run on a
## complete record records nothing (record_element is skipped on
## practice), so L0 is announced exactly once per record; (2) the ledger
## itself never adds a second L0 voucher once one is in the file, spent
## or not, whatever announced the level (was: none while one sat UNSPENT
## -> once spent, the next licence_changed at L0 or better - L1 earned
## later, a second car's own L0 - granted a second car; 4B-6 audit).
##
## THE DEALERSHIP is the Ring's E4 record, PUT IN STONE
## (ring-region-decisions.md line 117: Autohaus Rausch, way 831174023,
## unbranded in-game; data/regions/eifel_ring/focus.json id E4.1): this
## region's first-run dealership. A second region names its own when it
## comes; the id is the voucher's, not the ledger's.
##
## No autoload, no node: the first-run map layer (scripts/world_map.gd)
## makes one in the running game and a test makes its own, each handing the
## file it should write (path; a test's own, never the data folder).

## Fired when a voucher was written, with the voucher as written.
signal voucher_granted(voucher: Dictionary)

## The region's general dealership (focus.json id) and what grants the
## voucher, as written into every voucher of this ledger's.
const DEALERSHIP := "E4.1"
const GRANTED_BY := "L0"

## The file the vouchers go into: WorldStore.PATH unless told otherwise.
var path := WorldStore.PATH

## How many vouchers this ledger has written.
var granted := 0

## The levels announced to this ledger, in order (a test reads them).
var levels_heard: Array[int] = []

var _manager: LicenceManager


## The voucher L0 grants, as a fresh record.
static func voucher_record() -> Dictionary:
	return WorldStore.voucher({"kind": "car", "class": "general", "dealership": DEALERSHIP, "granted_by": GRANTED_BY, "spent": false})


## Listens to `manager`'s licence_changed; a manager listened to before is
## let go. Null detaches.
func attach(manager: LicenceManager) -> void:
	detach()
	_manager = manager
	if _manager:
		_manager.licence_changed.connect(_on_licence_changed)


func detach() -> void:
	if _manager and _manager.licence_changed.is_connected(_on_licence_changed):
		_manager.licence_changed.disconnect(_on_licence_changed)
	_manager = null


## Whether an L0 voucher of this dealership sits in the file unspent.
func has_unspent_l0() -> bool:
	for entry: Dictionary in WorldStore.unspent_vouchers(path):
		if entry.granted_by == GRANTED_BY and entry.dealership == DEALERSHIP:
			return true
	return false


## Whether an L0 voucher of this dealership is in the file at all, spent
## or not: the one the driver was granted.
func has_l0() -> bool:
	for entry: Dictionary in WorldStore.vouchers(path):
		if entry.granted_by == GRANTED_BY and entry.dealership == DEALERSHIP:
			return true
	return false


## Grants the voucher for `level` where it is due: L0 or better and none
## of this ledger's in the file yet, spent or not (was: none unspent).
## Returns the voucher written, {} when nothing was.
func grant_if_due(level: int) -> Dictionary:
	if level < LicenceExams.LICENCE_L0 or has_l0():
		return {}
	var written := WorldStore.add_voucher(voucher_record(), path)
	granted += 1
	voucher_granted.emit(written)
	return written


func _on_licence_changed(level: int) -> void:
	levels_heard.append(level)
	grant_if_due(level)

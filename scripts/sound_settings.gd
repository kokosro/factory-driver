class_name SoundSettings
extends RefCounted
## SOUND-5 (2026-10-03): the garage's sound settings, the store. The
## household's cat mix (CAT-AWARE-1) was an environment variable alone -
## FD_CAT=1, which run.sh exports where the caller has not set it - and
## the driver asked for it as a SETTING: chosen in the garage, kept with
## the rest of the data, with a master trim beside it (plan task A675B305).
## One small JSON file beside cars.json, world.json, campaign.json,
## credits.json and obligations.json, user://sound_settings.json:
##   {"version": 1, "cat_mix": false, "master_trim_db": -3.0}
## At most those three fields, the MINIMAL schema: `cat_mix` whether the
## sound nodes play the cat-aware mix (the squeal down-pitched and trimmed,
## the thumps softened, the low-pass bus) - PRESENT ONLY ONCE CHOSEN in the
## garage (below) - and `master_trim_db` one offset [dB] on every sound a
## node writes, clamped to TRIM_DB_MIN..TRIM_DB_MAX and snapped to
## TRIM_SNAP on every load and every set, 0 where there is none. A field
## the store does not know is reported and left out, never written back
## (was-> the WorldStore's ride-along: this file carries two settings and
## nothing else).
##
## THE PRECEDENCE (the ruled shape, amended by the Conductor 2026-10-03 on
## the absent-file corner; scripts/sound.gd cat_mode_effective holds the
## pure function, SoundNode._ready applies it once per node):
##   1. FD_SOUND "0" wins over everything: no node, no bus, no sound - the
##      SoundWatcher's switch exactly as it was (scripts/sound_watch.gd).
##      This file NEVER turns sound on or off; it shapes the mix of a sound
##      the environment already allows.
##   2. NO CAT MIX CHOSEN (no file, a file without cat_mix, a file that
##      cannot be trusted): TODAY'S environment semantics EXACTLY, the
##      CAT-AWARE-1 shipped default - FD_CAT "1" the cat mix, unset or "0"
##      or anything else the realistic mix, byte for byte as it landed (the
##      file comes into being only when the driver touches a sound row in
##      the garage, so every run before that - and every direct godot
##      launch - behaves as the game ships today). was-> the brief's
##      cat_mix default true with no file: amended, NOT that.
##   3. FD_CAT present and anything but "1" ("0", say - necessarily set by
##      the caller: run.sh fills only an unset or empty FD_CAT with "1"):
##      the caller's override, the realistic mix, this file's cat_mix
##      ignored.
##   4. FD_CAT unset or "1" (run.sh's default: "the household's default is
##      cat-aware") with a cat mix CHOSEN: THIS FILE decides - cat_mix true
##      is the cat mix, false the realistic one. So the setting exists to
##      let the driver turn the household's cat mix OFF (or on, launched
##      without run.sh) from the garage, persistently.
##   master_trim_db applies ALWAYS (the environment never overrides it;
##   rule 1 still comes first - silence trumps a trim); absent it is 0.
## Read once per sound node, in _ready (the FD_CAT convention): a change in
## the garage takes effect on the next sound node made - the next drive,
## the next scene - not on the one already playing.
##
## THE TEMPLATE IS ObligationsLedger (scripts/obligations_ledger.gd),
## itself CreditsLedger's, the machinery copied honestly: the atomic
## tmp+rename commit, the version refusal (newer_file), the tolerant reader
## that reports and invents nothing, the path_override test seam, the
## OdometerStore.enabled() gating, reads that never rewrite, a write that
## fails publishes nothing, the file read first so a set lands on the file
## as it stands on disk.
##
## TOLERANT READER: a missing file is the defaults (no cat mix chosen, no
## trim); malformed JSON, a file that is no object, and a version that is
## no whole number from 0 to VERSION read as the defaults, reported in
## `problems`; a cat_mix that is no bool is reported and reads as not
## chosen, a master_trim_db that is no finite number is reported and reads
## as 0, the other field kept; a trim outside the range is reported and
## clamped. Version 0, or none, reads as version 1 and is stamped 1 by the
## first write (VERSION is 1 from birth: there is no migration). A version
## ABOVE ours is a later build's file: read as the defaults AND never
## written over (every set refuses), so an older build cannot destroy a
## newer one's settings. Reads never rewrite. `problems` is the READER's
## channel only: a refused set returns {} and publishes nothing there.
##
## WRITES ARE ATOMIC: the whole file goes to <file>.tmp and is renamed over
## the file. A write that fails publishes nothing: the file and the state
## stay as they were.
##
## NO WALL CLOCK, no randomness.
##
## WHO READS IT IN A RUN (active_path): PATH behind the same switch as
## every other store (OdometerStore.enabled: on with a window, off
## headless); the headless suite reads and writes NOTHING unless a test
## points path_override at a file of its own - and then it reads and
## writes THAT file, gated or not (the ledgers' seam: tests/sound_test.gd
## pins the file-present corners and the trim through it, tests/menu_test.gd
## flips the garage's rows through it). Gated without an override, every
## set returns {} and keeps nothing, in memory or on disk, and every load is
## the defaults - no cat mix chosen, so the environment's semantics as
## shipped, and no test needs a seam to see the realistic mix - and the
## driver's folder is never touched by a test.
##
## THE SEED: sound_settings.json is in DataDir.SEEDED_FILES from birth (the
## TROC-1 slice 1 gap not repeated): a data folder chosen in the garage
## carries the cat mix and the trim with it.
##
## NO SIGNALS, no autoload, no node: the sound node loads one in _ready,
## the garage's SETTINGS page one per build, a test makes its own.

const PATH := "user://sound_settings.json"
const VERSION := 1

## The master trim's range [dB] and its grid: clamped and snapped on every
## load and every set. -24 is a whisper of the mix, +6 a little over it.
const TRIM_DB_MIN := -24.0
const TRIM_DB_MAX := 6.0
const TRIM_SNAP := 0.001

## The garage's step [dB] on the trim row (Garage: one press is this much
## quieter; past TRIM_DB_MIN it wraps to TRIM_DB_MAX).
const TRIM_STEP_DB := 0.5

## The trim where there is none [dB].
const DEFAULT_TRIM_DB := 0.0

## The fields a file may carry; anything else is reported and left out.
const FIELDS: Array[String] = ["version", "cat_mix", "master_trim_db"]

## A test's file, read and written instead of PATH; "" for none (the game).
static var path_override := ""

## What the last load or commit holds: {version, cat_mix, master_trim_db};
## cat_mix is null until chosen (never written to the file as null: the
## field is left out).
var state := defaults()

## One text per thing the last load found wrong; empty for a clean or an
## absent file.
var problems: Array[String] = []

## Whether the file last loaded is a later build's: never written over.
var newer_file := false


## No cat mix chosen (null), no trim.
static func defaults() -> Dictionary:
	return {"version": VERSION, "cat_mix": null, "master_trim_db": DEFAULT_TRIM_DB}


static func active_path() -> String:
	if path_override != "":
		return path_override
	return PATH if OdometerStore.enabled() else ""


static func whole(value: Variant) -> bool:
	return (value is int or value is float) and is_finite(value) and value == floor(value)


## `db` as the store keeps a trim: clamped to TRIM_DB_MIN..TRIM_DB_MAX and
## snapped to TRIM_SNAP; a value that is no finite number is the default.
static func trim_of(db: Variant) -> float:
	if not (db is int or db is float) or not is_finite(db):
		return DEFAULT_TRIM_DB
	return snappedf(clampf(float(db), TRIM_DB_MIN, TRIM_DB_MAX), TRIM_SNAP)


## The trim one garage press down from `db`: TRIM_STEP_DB quieter, snapped;
## at or under TRIM_DB_MIN it wraps to TRIM_DB_MAX (the one row walks the
## whole range). Pure.
static func trim_stepped(db: float) -> float:
	var from := trim_of(db)
	if from <= TRIM_DB_MIN:
		return TRIM_DB_MAX
	return trim_of(maxf(from - TRIM_STEP_DB, TRIM_DB_MIN))


## A settings store loaded from active_path(): what the sound node and the
## garage read.
static func current() -> SoundSettings:
	var settings := SoundSettings.new()
	settings.load_state()
	return settings


## Whether a cat mix has been chosen (the file carries a bool cat_mix); not
## chosen, the environment's semantics as shipped decide (see the header).
func cat_mix_chosen() -> bool:
	return state.cat_mix is bool


## The chosen cat mix; false where none is chosen (ask cat_mix_chosen first:
## SoundNode.cat_mode_effective takes both).
func cat_mix() -> bool:
	return state.cat_mix == true


func master_trim_db() -> float:
	return state.master_trim_db


## Reads the file active_path() names into `state`; the defaults where
## there is none, where the store is gated, or where the file cannot be
## trusted. Never writes.
func load_state() -> void:
	state = defaults()
	problems = []
	newer_file = false
	var path := active_path()
	if path == "":
		return
	var disk := DataDir.resolve(path)
	if not FileAccess.file_exists(disk):
		return
	var parser := JSON.new()
	if parser.parse(FileAccess.get_file_as_string(disk)) != OK:
		problems.append("%s: not JSON, the defaults are used" % path)
		return
	var data: Variant = parser.data
	if not data is Dictionary:
		problems.append("%s: not an object, the defaults are used" % path)
		return
	var version: Variant = data.get("version", 0)
	if not whole(version) or version < 0:
		problems.append("%s: version is no whole number of zero or more (%s), the defaults are used" % [path, str(version)])
		return
	if version > VERSION:
		newer_file = true
		problems.append("%s: version %d is a later build's (this one reads %d), the defaults are used and the file is left alone" % [path, int(version), VERSION])
		return
	var kept := defaults()
	if data.has("cat_mix"):
		if data.cat_mix is bool:
			kept.cat_mix = data.cat_mix
		else:
			problems.append("%s: cat_mix is no bool (%s), none is chosen" % [path, str(data.cat_mix)])
	if data.has("master_trim_db"):
		var trim: Variant = data.master_trim_db
		if not (trim is int or trim is float) or not is_finite(trim):
			problems.append("%s: master_trim_db is no finite number (%s), %.1f is used" % [path, str(trim), DEFAULT_TRIM_DB])
		else:
			kept.master_trim_db = trim_of(trim)
			if float(trim) < TRIM_DB_MIN or float(trim) > TRIM_DB_MAX:
				problems.append("%s: master_trim_db %s is outside %.0f..%.0f dB, %.1f is used" % [path, str(trim), TRIM_DB_MIN, TRIM_DB_MAX, kept.master_trim_db])
	for field: String in data:
		if not field in FIELDS:
			problems.append("%s: %s is none of the store's, it is left out" % [path, field])
	state = kept


## Writes `on` as the cat mix: from here on chosen, the file deciding under
## FD_CAT unset or "1". Returns the settings as written; {} when nothing
## was: the store is gated, the file is a later build's, or the write
## failed. The file is read first, so the other setting lands as it stands
## on disk.
func set_cat_mix(on: bool) -> Dictionary:
	var next := _next()
	if next.is_empty():
		return {}
	next.cat_mix = on
	return next.duplicate(true) if _commit(next) else {}


## Writes `db` as the master trim, clamped and snapped (trim_of); a cat mix
## not chosen stays not chosen (the field left out of the file). Returns
## the settings as written; {} when nothing was (set_cat_mix's refusals, or
## a `db` that is no finite number).
func set_master_trim_db(db: float) -> Dictionary:
	if not is_finite(db):
		return {}
	var next := _next()
	if next.is_empty():
		return {}
	next.master_trim_db = trim_of(db)
	return next.duplicate(true) if _commit(next) else {}


## The file read first, then a copy of the state to change; {} when the
## store is gated or the file is a later build's.
func _next() -> Dictionary:
	if active_path() == "":
		return {}
	load_state()
	if newer_file:
		return {}
	return state.duplicate(true)


func _commit(next: Dictionary) -> bool:
	var path := active_path()
	if path == "":
		return false
	var disk := DataDir.resolve(path)
	if DirAccess.make_dir_recursive_absolute(disk.get_base_dir()) != OK:
		return false
	var file := FileAccess.open(disk + ".tmp", FileAccess.WRITE)
	if file == null:
		return false
	# A cat mix not chosen is no field at all on disk (never "cat_mix": null).
	var written := next.duplicate(true)
	if not written.cat_mix is bool:
		written.erase("cat_mix")
	file.store_string(JSON.stringify(written, "  "))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK or DirAccess.rename_absolute(disk + ".tmp", disk) != OK:
		return false
	state = next
	return true

class_name DataDir
extends RefCounted
## Where the game's data lives: the per-car store (OdometerStore, cars.json),
## the issue store (IssueStore, issues.json), the telemetry (TelemetryRecorder,
## telemetry/) and whatever saves come later. Every one of them names its
## files under user:// as it always did; this class says where user:// really
## is for this run, and resolve() turns a user:// path into the path on disk
## that is read or written. Nothing else touches a path.
##
## The root is read once at startup (read_root, from the DataBootstrap
## autoload), from two places, the first that says anything winning:
##   1. the environment variable FD_DATA_DIR (ENV_VAR): an absolute folder,
##   2. the bootstrap file user://data_dir.txt (BOOTSTRAP_PATH) in the DEFAULT
##      location, holding one line, an absolute folder: what the garage's
##      SETTINGS page writes when a folder is chosen there.
## Neither set, or what is set is no absolute folder (reported, never used):
## user:// itself, which with use_custom_user_dir in project.godot is
## <the OS's data dir>/factory-driver (on macOS
## ~/Library/Application Support/factory-driver). A custom root is used AS
## the data folder: cars.json, issues.json and telemetry/ go straight into it.
##
## THE FIRST RUN IN A FOLDER COPIES (seed): a root without the MARKER_FILE in
## it is new to the game, and is seeded once with a COPY of the data found in
## the previous location - the default user:// folder for a custom root, or
## the pre-4A Godot default (OLD_DEFAULT_SUBDIR under the OS's data dir, where
## the game kept everything before it had a folder of its own) - the first of
## the two that holds any. Files only ever go in beside what is there: a file
## the new folder already has is left alone, and nothing is ever moved or
## deleted from the old one. The marker then says where it came from, and the
## folder is never seeded again. Behind the store's own switch
## (OdometerStore.enabled): the headless suite seeds nothing and writes
## nothing; its own checks run seed() on folders of their own.
##
## Every path in here is a String; a root is kept as an absolute path with no
## trailing separator.

## The environment variable naming the data folder [absolute path].
const ENV_VAR := "FD_DATA_DIR"

## The bootstrap file in the default location: one line, the data folder
## [absolute path]. Written by set_bootstrap, read by read_root.
const BOOTSTRAP_PATH := "user://data_dir.txt"

## The file a seeded root carries; its text says where the seed came from.
const MARKER_FILE := ".factory-driver-data"

## What a seed copies: these files and these folders (whole), relative to
## the root, whichever of them the source has.
# was: cars.json alone -> the issue store rides along (issues.json,
# IssueStore.PATH): a fresh data folder seeded without it lost every issue
# the driver had flagged in the old one (2026-09-24).
const SEEDED_FILES: Array[String] = ["cars.json", "issues.json"]
const SEEDED_DIRS: Array[String] = ["telemetry"]

## Where the game kept its data before it had a folder of its own: Godot's
## default user:// for a project named "Factory Driver", under the OS's data
## dir (OS.get_data_dir()).
const OLD_DEFAULT_SUBDIR := "Godot/app_userdata/Factory Driver"

## The custom root in use, "" for user:// itself. Set by read_root at
## startup (or apply_root by a test), read by resolve.
static var _root := ""

## Whether read_root has been through; resolve() before it is user://.
static var _root_read := false


# =============================================================================
#  Resolution
# =============================================================================

## Where the data folder is, from what the environment variable says
## (`env_value`) and what the bootstrap file says (`bootstrap_text`, the
## file's text or "" for no file), pure:
##   {"root": the absolute folder, or "" for user:// itself,
##    "source": "env", "bootstrap" or "default",
##    "problem": what was wrong with the one that spoke first, "" if nothing}
## The environment variable wins when it says anything; the bootstrap file
## next; both empty is the default. Whichever spoke first and is no absolute
## folder path is the problem - and the default is used, never a guess at
## what was meant.
static func resolve_root(env_value: String, bootstrap_text: String) -> Dictionary:
	var candidates := [["env", env_value], ["bootstrap", bootstrap_text]]
	for candidate: Array in candidates:
		var source: String = candidate[0]
		var text: String = String(candidate[1]).strip_edges()
		if text == "":
			continue
		var problem := root_problem(text)
		if problem != "":
			return {"root": "", "source": "default", "problem": "%s data folder %s: %s, the default folder is used" % [source, text, problem]}
		return {"root": text.rstrip("/"), "source": source, "problem": ""}
	return {"root": "", "source": "default", "problem": ""}


## What keeps `text` from being a data folder: it has to be an absolute path
## (a relative one would land somewhere different from every working
## directory) and not a Godot res:// or user:// path (the first is read-only
## in an export, the second is what this class is resolving).
static func root_problem(text: String) -> String:
	if text.begins_with("res://") or text.begins_with("user://"):
		return "is a Godot path, not a folder on disk"
	if not text.is_absolute_path():
		return "is not an absolute path"
	return ""


## Reads the root for this run: the environment variable, then the bootstrap
## file at `bootstrap_path` (BOOTSTRAP_PATH: in the default user://, never
## resolved through the root it names). Reports a problem (push_error) and
## keeps what resolve_root settled on. Once at startup; calling it again
## reads again.
static func read_root(bootstrap_path := BOOTSTRAP_PATH) -> Dictionary:
	var resolved := resolve_root(OS.get_environment(ENV_VAR), read_bootstrap(bootstrap_path))
	if resolved.problem != "":
		push_error("DataDir: %s" % resolved.problem)
	apply_root(resolved.root)
	return resolved


## Makes `root` the folder resolve() maps user:// to: "" for user:// itself.
## read_root's last step; a test may set a folder of its own and put "" back.
static func apply_root(root: String) -> void:
	_root = root.rstrip("/") if root != "" else ""
	_root_read = true


## The custom root in use, "" for user:// itself.
static func root() -> String:
	return _root


## The folder the data is in, as a path on disk (for the SETTINGS page and
## the CAR page's footer): the custom root, or where user:// is.
static func root_on_disk() -> String:
	return _root if _root != "" else OS.get_user_data_dir()


## `path` as it is read or written: a user:// path under a custom root goes
## under that root instead ("user://telemetry/index.json" ->
## "<root>/telemetry/index.json"); anything else - an absolute path a test
## hands in, a res:// path, user:// with no custom root - is itself.
static func resolve(path: String) -> String:
	if _root == "" or not path.begins_with("user://"):
		return path
	return _root.path_join(path.trim_prefix("user://"))


# =============================================================================
#  The bootstrap file
# =============================================================================

## What the bootstrap file at `path` says, stripped; "" for no file.
static func read_bootstrap(path := BOOTSTRAP_PATH) -> String:
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path).strip_edges()


## Writes `dir` into the bootstrap file at `path` - the folder the NEXT start
## resolves to (this run keeps the root it read) - or removes the file for
## "" (back to the default). Returns "" or what went wrong. A `dir` that is
## no data folder (root_problem) is refused and nothing is written.
static func set_bootstrap(dir: String, path := BOOTSTRAP_PATH) -> String:
	var wanted := dir.strip_edges()
	if wanted == "":
		if FileAccess.file_exists(path):
			var removed := DirAccess.remove_absolute(path)
			if removed != OK:
				return "could not remove %s (error %d)" % [path, removed]
		return ""
	var problem := root_problem(wanted)
	if problem != "":
		return "%s %s" % [wanted, problem]
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return "could not write %s (error %d)" % [path, FileAccess.get_open_error()]
	file.store_line(wanted.rstrip("/"))
	file.close()
	return ""


# =============================================================================
#  Seeding a new folder (the one-time copy)
# =============================================================================

## Seeds `root_dir` (an absolute folder, made if it is not there) once: with
## no MARKER_FILE in it, the SEEDED_FILES and SEEDED_DIRS of the first of
## `sources` (absolute folders; one that is not there, or is `root_dir`
## itself, or holds none of them, is passed over) are COPIED in, file by
## file, never over a file that is already there, and the marker is written
## saying where from. Nothing in a source is touched. Returns
##   {"seeded": whether anything was copied, "source": the folder it came
##    from or "", "copied": the relative paths copied, "reason": why nothing
##    was, "" otherwise}
## A root that already carries the marker is left exactly as it is.
static func seed_folder(root_dir: String, sources: Array[String]) -> Dictionary:
	var marker := root_dir.path_join(MARKER_FILE)
	if FileAccess.file_exists(marker):
		return {"seeded": false, "source": "", "copied": PackedStringArray(), "reason": "already seeded"}
	var made := DirAccess.make_dir_recursive_absolute(root_dir)
	if made != OK:
		return {"seeded": false, "source": "", "copied": PackedStringArray(), "reason": "could not make %s (error %d)" % [root_dir, made]}
	var copied := PackedStringArray()
	var source_used := ""
	for source in sources:
		if source == "" or source.rstrip("/") == root_dir.rstrip("/") or not DirAccess.dir_exists_absolute(source):
			continue
		if not _holds_data(source):
			continue
		source_used = source
		for file_name in SEEDED_FILES:
			if FileAccess.file_exists(source.path_join(file_name)):
				_copy_file(source.path_join(file_name), root_dir.path_join(file_name), file_name, copied)
		for dir_name in SEEDED_DIRS:
			if DirAccess.dir_exists_absolute(source.path_join(dir_name)):
				_copy_dir(source.path_join(dir_name), root_dir.path_join(dir_name), dir_name, copied)
		break
	var note := FileAccess.open(marker, FileAccess.WRITE)
	if note != null:
		if source_used == "":
			note.store_line("Factory Driver data folder. Fresh: nothing to copy from an earlier location.")
		else:
			note.store_line("Factory Driver data folder. Seeded with a copy of %s (%d item(s)); the original was left as it was." % [source_used, copied.size()])
		note.close()
	if source_used == "":
		return {"seeded": false, "source": "", "copied": copied, "reason": "nothing to copy"}
	return {"seeded": true, "source": source_used, "copied": copied, "reason": ""}


## Whether `dir` holds anything a seed would copy.
static func _holds_data(dir: String) -> bool:
	for file_name in SEEDED_FILES:
		if FileAccess.file_exists(dir.path_join(file_name)):
			return true
	for dir_name in SEEDED_DIRS:
		if DirAccess.dir_exists_absolute(dir.path_join(dir_name)):
			return true
	return false


## Copies one file, unless the destination is already there; notes `relative`
## in `copied` when it did.
static func _copy_file(from: String, to: String, relative: String, copied: PackedStringArray) -> void:
	if FileAccess.file_exists(to):
		return
	if DirAccess.copy_absolute(from, to) == OK:
		copied.append(relative)


## Copies a folder's files and sub-folders, _copy_file's way, file by file.
static func _copy_dir(from: String, to: String, relative: String, copied: PackedStringArray) -> void:
	if DirAccess.make_dir_recursive_absolute(to) != OK:
		return
	for file_name in DirAccess.get_files_at(from):
		_copy_file(from.path_join(file_name), to.path_join(file_name), relative.path_join(file_name), copied)
	for dir_name in DirAccess.get_directories_at(from):
		_copy_dir(from.path_join(dir_name), to.path_join(dir_name), relative.path_join(dir_name), copied)


## The game's own seed at startup: the root in use, from the default user://
## folder (when the root is a custom one) or the pre-4A Godot default. The
## DataBootstrap autoload calls it, behind the store's switch.
static func seed_on_startup() -> Dictionary:
	var sources: Array[String] = []
	if _root != "":
		sources.append(OS.get_user_data_dir())
	sources.append(OS.get_data_dir().path_join(OLD_DEFAULT_SUBDIR))
	return seed_folder(root_on_disk(), sources)

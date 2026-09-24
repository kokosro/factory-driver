#!/usr/bin/env bash
# The driver state between machines: pack the data folder's driver state
# (telemetry/, issues.json, cars.json - nothing else), upload it encrypted
# through ird, and merge it into another machine's data folder. The test
# sessions happen on one machine, the analysis on another.
#
#   tools/sync_driverstate.sh push          pack, upload encrypted, print the CID
#   tools/sync_driverstate.sh pull <cid>    download, decrypt, MERGE into the data folder
#
# THE PASSWORD: FD_SYNC_PASSWORD in the environment, nothing else. The script
# never stores, generates or prints it; ird is always called with --no-input
# (never prompt; fail instead) and gets the password on its --password flag,
# so a run with FD_SYNC_PASSWORD unset stops here before ird is called. The
# same password on both machines. LOSING THE PASSWORD LOSES THE BUNDLE: ird's
# own warning, lost passwords/keys are unrecoverable. (The flag is visible to
# the process list for as long as ird runs; keep the machine your own.)
#
# THE DATA FOLDER is resolved exactly as the game resolves it
# (scripts/data_dir.gd): FD_DATA_DIR when it says anything, else the
# bootstrap file data_dir.txt in the DEFAULT user:// folder (never under a
# custom root), else the default folder itself. A value that is no absolute
# folder (a relative path, a res:// or user:// path) is reported and the
# default is used - never a guess, and never the next candidate.
#
# THE BUNDLE is one folder, fd-driverstate-<host>-<YYYYmmdd-HHMMSS>/, holding
#   telemetry/     the whole tree, index.json included
#   cars.json      the per-car store
#   issues.json    the issue store, when one exists (none until an issue is filed)
# packed in a temporary folder that is removed afterwards, uploaded with
# `ird ipfs add <folder> --encrypt --name <the folder's name>`.
#
# A PULL NEVER CLOBBERS:
#   telemetry/     file by file: a path already here is kept (the local file
#                  wins), a path not here is copied in; nothing is deleted.
#                  The bundle's index.json is not a session file: see below.
#   issues.json    unioned by record id: the local record wins on a
#                  collision, the bundle's new records are appended after the
#                  local ones, next_issue_id the highest counter of the two
#                  files and the highest id present plus one. No local file:
#                  the bundle's records are written (a merge into nothing).
#   index.json     rebuilt from the session files on disk after the merge:
#                  sessions every <NNNN>_*.jsonl id present, next_session_id
#                  the highest of both indexes' and the highest id on disk
#                  plus one; last_test and best the LOCAL ones (the bundle's
#                  are printed for the driver to decide) - adopted from the
#                  bundle only when there is no local index at all.
#   cars.json      the local one stays (the odometer is per-machine state);
#                  the bundle's odometer per car is printed; none here either,
#                  the bundle's is NOT written (copy it by hand if wanted).
# Every decision is printed. Exit 2 on usage, 1 on any failure, with a message.
#
# Needs bash, python3 (3.9, the stock macOS one, is enough), ird, cp, find.
# The suite does not run this; `bash -n` and a sandboxed FD_DATA_DIR are the
# checks. Never point it at somebody else's data folder.
set -uo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

usage() {
	cat >&2 <<'EOF'
usage: tools/sync_driverstate.sh push
       tools/sync_driverstate.sh pull <cid>
FD_SYNC_PASSWORD must be set (never stored; losing it loses the bundle).
FD_DATA_DIR names the data folder, else the game's own resolution is used.
EOF
	exit 2
}

fail() {
	echo "sync_driverstate: $*" >&2
	exit 1
}

warn() {
	echo "sync_driverstate: warning: $*" >&2
}

# Leading and trailing whitespace off (String.strip_edges).
trim() {
	local text="$1"
	text="${text#"${text%%[![:space:]]*}"}"
	text="${text%"${text##*[![:space:]]}"}"
	printf '%s' "$text"
}

# Every trailing slash off (String.rstrip("/")).
strip_slashes() {
	local text="$1"
	while [ "${text%/}" != "$text" ]; do
		text="${text%/}"
	done
	printf '%s' "$text"
}

# What keeps a candidate from being a data folder (DataDir.root_problem);
# prints nothing for a good one.
root_problem() {
	case "$1" in
		res://*|user://*) echo "is a Godot path, not a folder on disk" ;;
		/*) ;;
		*) echo "is not an absolute path" ;;
	esac
}

# The default user:// folder: project.godot's custom_user_dir_name under the
# OS's data dir (use_custom_user_dir).
default_user_dir() {
	local name
	name="$(sed -n 's/^config\/custom_user_dir_name="\(.*\)"$/\1/p' "$ROOT/project.godot" | head -n 1)"
	[ -n "$name" ] || name="factory-driver"
	case "$(uname -s)" in
		Darwin) printf '%s' "$HOME/Library/Application Support/$name" ;;
		*) printf '%s' "${XDG_DATA_HOME:-$HOME/.local/share}/$name" ;;
	esac
}

# The data folder for this run, DataDir.resolve_root's way: sets DATA_DIR
# and DATA_SOURCE (env, bootstrap or default).
resolve_data_dir() {
	local default_dir bootstrap bootstrap_text="" source candidate problem
	default_dir="$(default_user_dir)"
	bootstrap="$default_dir/data_dir.txt"
	if [ -f "$bootstrap" ]; then
		bootstrap_text="$(cat "$bootstrap")"
	fi
	for source in env bootstrap; do
		case "$source" in
			env) candidate="$(trim "${FD_DATA_DIR:-}")" ;;
			bootstrap) candidate="$(trim "$bootstrap_text")" ;;
		esac
		[ -n "$candidate" ] || continue
		problem="$(root_problem "$candidate")"
		if [ -n "$problem" ]; then
			echo "sync_driverstate: $source data folder $candidate: $problem, the default folder is used" >&2
			DATA_DIR="$default_dir"
			DATA_SOURCE="default"
			return
		fi
		candidate="$(strip_slashes "$candidate")"
		if [ -z "$candidate" ]; then
			DATA_DIR="$default_dir"
			DATA_SOURCE="default"
			return
		fi
		DATA_DIR="$candidate"
		DATA_SOURCE="$source"
		return
	done
	DATA_DIR="$default_dir"
	DATA_SOURCE="default"
}

need_password() {
	if [ -z "${FD_SYNC_PASSWORD:-}" ]; then
		fail "set FD_SYNC_PASSWORD (the password is never stored; losing it loses the bundle)"
	fi
}

need_tools() {
	local tool
	for tool in ird python3 cp find; do
		command -v "$tool" >/dev/null 2>&1 || fail "$tool is not on the PATH"
	done
}

# The temporary folder, removed on exit whatever happens.
TMP=""
cleanup() {
	if [ -n "$TMP" ] && [ -d "$TMP" ]; then
		rm -rf "$TMP"
	fi
}
trap cleanup EXIT

count_files() {
	find "$1" -type f | wc -l | tr -d ' '
}

# =============================================================================
#  push
# =============================================================================

push() {
	need_password
	need_tools
	resolve_data_dir
	echo "data folder: $DATA_DIR ($DATA_SOURCE)"
	[ -d "$DATA_DIR" ] || fail "$DATA_DIR is not there: is this the data folder? (FD_DATA_DIR, or the game's SETTINGS page)"
	[ -f "$DATA_DIR/.factory-driver-data" ] || warn "$DATA_DIR carries no .factory-driver-data marker: is this the data folder?"
	[ -d "$DATA_DIR/telemetry" ] || fail "no telemetry/ in $DATA_DIR: not a data folder the game has driven in"
	[ -f "$DATA_DIR/cars.json" ] || fail "no cars.json in $DATA_DIR: not a data folder the game has driven in"
	local label bundle
	label="fd-driverstate-$(hostname -s)-$(date +%Y%m%d-%H%M%S)"
	TMP="$(mktemp -d)" || fail "mktemp failed"
	bundle="$TMP/$label"
	mkdir -p "$bundle" || fail "could not make $bundle"
	cp -R "$DATA_DIR/telemetry" "$bundle/telemetry" || fail "could not copy telemetry/"
	echo "packed  telemetry/ ($(count_files "$bundle/telemetry") files)"
	cp "$DATA_DIR/cars.json" "$bundle/cars.json" || fail "could not copy cars.json"
	echo "packed  cars.json"
	if [ -f "$DATA_DIR/issues.json" ]; then
		cp "$DATA_DIR/issues.json" "$bundle/issues.json" || fail "could not copy issues.json"
		echo "packed  issues.json"
	else
		echo "absent  issues.json (no issue filed on this machine yet: nothing to pack)"
	fi
	echo "bundle: $label ($(count_files "$bundle") files); uploading encrypted"
	local output cid url status
	output="$TMP/ird-add.out"
	# The password goes on the flag and nowhere else: not echoed, not logged.
	# --no-input keeps every prompt from hanging; --yes answers ird's one
	# upload confirmation (the storage bills the driver's own prepaid credits),
	# so the script can run unattended.
	ird ipfs add "$bundle" --encrypt --name "$label" --yes --no-input --password "$FD_SYNC_PASSWORD" >"$output" 2>&1
	status="$?"
	cat "$output"
	if [ "$status" -ne 0 ]; then
		fail "ird ipfs add failed (exit $status, its output is above)"
	fi
	# Any CIDv1 base32 (bafy… folder, bafkrei… raw blob - an encrypted pin is
	# one opaque blob, its CID bafkrei…) or the old base58 Qm….
	cid="$(grep -oE '(baf[a-z2-7]{20,}|Qm[1-9A-HJ-NP-Za-km-z]{44})' "$output" | head -n 1)"
	url="$(grep -oE 'https?://[^[:space:]]+' "$output" | head -n 1)"
	if [ -z "$cid" ]; then
		warn "no CID found in ird's output above: read it there"
		return
	fi
	echo "cid:     $cid"
	[ -z "$url" ] || echo "gateway: $url"
	echo "label:   $label"
	echo "pull it on the other machine with: FD_SYNC_PASSWORD=... tools/sync_driverstate.sh pull $cid"
}

# =============================================================================
#  pull
# =============================================================================

# Where the bundle landed under $1: the folder holding cars.json or
# telemetry/ (ird unpacks an encrypted folder into its original folder, whose
# name is the pin's; the download may sit one level down).
find_bundle() {
	local out="$1" found
	found="$(find "$out" -maxdepth 3 -name cars.json -type f 2>/dev/null | head -n 1)"
	if [ -z "$found" ]; then
		found="$(find "$out" -maxdepth 3 -name telemetry -type d 2>/dev/null | head -n 1)"
	fi
	[ -n "$found" ] || return 1
	dirname "$found"
}

pull() {
	local cid="$1"
	need_password
	need_tools
	resolve_data_dir
	echo "data folder: $DATA_DIR ($DATA_SOURCE)"
	[ -d "$DATA_DIR" ] || fail "$DATA_DIR is not there: start the game once there, or set FD_DATA_DIR to the data folder"
	[ -f "$DATA_DIR/.factory-driver-data" ] || warn "$DATA_DIR carries no .factory-driver-data marker: is this the data folder?"
	TMP="$(mktemp -d)" || fail "mktemp failed"
	local out="$TMP/out"
	echo "downloading $cid (decrypting)"
	if ! ird ipfs get "$cid" --decrypt --yes --no-input --password "$FD_SYNC_PASSWORD" -o "$out"; then
		fail "ird ipfs get failed (its output is above): the CID, the password, or the network"
	fi
	if [ -f "$out" ]; then
		fail "$cid came down as a single file, not an unpacked folder: is it a bundle this script pushed?"
	fi
	local bundle
	bundle="$(find_bundle "$out")" || fail "no cars.json and no telemetry/ in what came down: is $cid a bundle this script pushed? contents: $(find "$out" -maxdepth 3 | tr '\n' ' ')"
	echo "bundle: $bundle ($(count_files "$bundle") files)"

	# telemetry/: file by file, the local file wins, nothing deleted.
	local merged=0 kept=0 file rel
	if [ -d "$bundle/telemetry" ]; then
		mkdir -p "$DATA_DIR/telemetry" || fail "could not make $DATA_DIR/telemetry"
		while IFS= read -r -d '' file; do
			rel="${file#"$bundle/telemetry/"}"
			[ "$rel" != "index.json" ] || continue
			if [ -e "$DATA_DIR/telemetry/$rel" ]; then
				kept=$((kept + 1))
			else
				mkdir -p "$(dirname "$DATA_DIR/telemetry/$rel")" || fail "could not make a folder for telemetry/$rel"
				cp "$file" "$DATA_DIR/telemetry/$rel" || fail "could not copy telemetry/$rel"
				echo "merged  telemetry/$rel"
				merged=$((merged + 1))
			fi
		done < <(find "$bundle/telemetry" -type f -print0)
		echo "telemetry/: merged $merged, kept local $kept (a file already here always wins; nothing deleted)"
	else
		echo "telemetry/: none in the bundle, the local tree stands"
	fi

	# issues.json: the union by id, the local record winning.
	python3 - "$DATA_DIR/issues.json" "$bundle/issues.json" <<'PY' || fail "issues.json merge failed"
import json, os, re, sys
local_path, bundled_path = sys.argv[1], sys.argv[2]
ID = re.compile(r"^issue-(\d+)$")

def load(path):
	if not os.path.isfile(path):
		return None
	with open(path) as f:
		data = json.load(f)
	if not isinstance(data, dict) or not isinstance(data.get("issues"), list):
		sys.exit("%s: not an issue store ({\"version\", \"next_issue_id\", \"issues\": [...]})" % path)
	return data

local = load(local_path)
bundled = load(bundled_path)
if bundled is None:
	print("issues.json: none in the bundle, the local file stands (%s)" % ("%d record(s)" % len(local["issues"]) if local else "none here either"))
	sys.exit(0)
if local is None:
	print("issues.json: no local file, the bundle's is taken whole (a merge into nothing, not a clobber)")

local_issues = list(local["issues"]) if local else []
seen = set(r.get("id") for r in local_issues if isinstance(r, dict))
added = []
collided = 0
for record in bundled["issues"]:
	rid = record.get("id") if isinstance(record, dict) else None
	if rid in seen:
		collided += 1
		continue
	added.append(record)
	if rid is not None:
		seen.add(rid)
issues = local_issues + added
highest = 0
for record in issues:
	m = ID.match(str(record.get("id", ""))) if isinstance(record, dict) else None
	if m:
		highest = max(highest, int(m.group(1)))
def counter(data):
	try:
		return int(data.get("next_issue_id", 1)) if data else 1
	except (TypeError, ValueError):
		return 1
next_id = max(counter(local), counter(bundled), highest + 1)
version = (local or bundled).get("version", 1)
out = {"version": version, "next_issue_id": next_id, "issues": issues}
with open(local_path, "w") as f:
	json.dump(out, f, indent=2)
	f.write("\n")
print("issues.json: local %d, bundled %d, same id %d (local wins), appended %d -> %d record(s), next_issue_id %d (was local %s, bundled %d)"
	% (len(local_issues), len(bundled["issues"]), collided, len(added), len(issues), next_id, counter(local) if local else "none", counter(bundled)))
for record in added:
	print("  appended %s: %s" % (record.get("id"), str(record.get("description", ""))[:60]))
PY

	# index.json: rebuilt from what is on disk now.
	python3 - "$DATA_DIR/telemetry" "$bundle/telemetry/index.json" <<'PY' || fail "index.json rebuild failed"
import json, os, sys
telemetry_dir, bundled_path = sys.argv[1], sys.argv[2]
local_path = os.path.join(telemetry_dir, "index.json")

def load(path):
	if not os.path.isfile(path):
		return None
	with open(path) as f:
		data = json.load(f)
	return data if isinstance(data, dict) else None

def counter(data):
	try:
		return int(data.get("next_session_id", 1)) if data else 1
	except (TypeError, ValueError):
		return 1

local = load(local_path)
bundled = load(bundled_path)
ids = set()
if os.path.isdir(telemetry_dir):
	for day in sorted(os.listdir(telemetry_dir)):
		day_dir = os.path.join(telemetry_dir, day)
		if not os.path.isdir(day_dir):
			continue
		for name in os.listdir(day_dir):
			# <NNNN>_<HHMMSS>_<context>.jsonl: the digits before the first underscore.
			if not name.endswith(".jsonl") or "_" not in name:
				continue
			prefix = name.split("_", 1)[0]
			if prefix.isdigit():
				ids.add(int(prefix))
sessions = sorted(ids)
next_id = max(counter(local), counter(bundled), (sessions[-1] + 1) if sessions else 1)
source = local if local is not None else bundled
out = {"next_session_id": next_id, "sessions": sessions}
if source is not None and "last_test" in source:
	out["last_test"] = source["last_test"]
if source is not None and "best" in source:
	out["best"] = source["best"]
os.makedirs(telemetry_dir, exist_ok=True)
with open(local_path, "w") as f:
	json.dump(out, f, indent=2)
	f.write("\n")
print("index.json: rebuilt from disk, %d session(s) present%s, next_session_id %d (local %s, bundled %s, disk max+1 %d); last_test and best %s"
	% (len(sessions), (" (%d..%d)" % (sessions[0], sessions[-1])) if sessions else "", next_id,
	   counter(local) if local else "none", counter(bundled) if bundled else "none", (sessions[-1] + 1) if sessions else 1,
	   "kept local" if local is not None else ("adopted from the bundle (no local index)" if bundled is not None else "none on either side")))
if bundled is not None and local is not None:
	print("  the bundle's, for you to decide (not applied): last_test %s" % json.dumps(bundled.get("last_test")))
	for title, entry in sorted((bundled.get("best") or {}).items()):
		print("  the bundle's best %s: %s" % (title, json.dumps(entry, sort_keys=True)))
PY

	# cars.json: the local one stays; the bundle's odometers for the record.
	# The Conductor's ruling, 2026-09-24: with no local cars.json at all the
	# bundle's is NOT written - the odometer is per-machine state and the
	# game seeds this machine's own at its first drive; the driver copies it
	# by hand if wanted.
	python3 - "$DATA_DIR/cars.json" "$bundle/cars.json" <<'PY' || fail "cars.json report failed"
import json, os, sys
local_path, bundled_path = sys.argv[1], sys.argv[2]

def cars(path):
	if not os.path.isfile(path):
		return None
	with open(path) as f:
		data = json.load(f)
	return data.get("cars", {}) if isinstance(data, dict) else {}

local = cars(local_path)
bundled = cars(bundled_path)
if bundled is None:
	print("cars.json: none in the bundle, the local file stands")
	sys.exit(0)
if local is not None and open(local_path, "rb").read() == open(bundled_path, "rb").read():
	print("cars.json: local and bundled are the same bytes")
else:
	print("cars.json: kept local (the odometer is per-machine state; the bundle's is not applied)" if local is not None else "cars.json: no local file, and the bundle's is NOT written (copy it by hand if this machine should start from it)")
for car_id, entry in sorted(bundled.items()):
	mine = (local or {}).get(car_id, {}) if local else {}
	print("  the bundle's %s: odometer_m %s (local %s)" % (car_id, entry.get("odometer_m") if isinstance(entry, dict) else "?", mine.get("odometer_m", "none") if isinstance(mine, dict) else "?"))
PY
	echo "pull done: nothing overwritten, nothing deleted"
}

# =============================================================================
#  main
# =============================================================================

[ "$#" -ge 1 ] || usage
case "$1" in
	push)
		[ "$#" -eq 1 ] || usage
		push
		;;
	pull)
		[ "$#" -eq 2 ] || usage
		[ -n "$2" ] || usage
		pull "$2"
		;;
	*)
		usage
		;;
esac

#!/usr/bin/env bash
# Push-only checks with prepaid storage replaced by a local recorder. Every
# data write and captured bundle lives in our temporary folder, never user://.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SANDBOX="$(mktemp -d)"
trap 'rm -rf "$SANDBOX"' EXIT
export TMPDIR="$SANDBOX"
export FD_DATA_DIR="$SANDBOX/data" FD_SYNC_PASSWORD=x
export SYNC_TEST_CAPTURE="$SANDBOX/capture"
mkdir -p "$SANDBOX/bin" "$FD_DATA_DIR/telemetry/2026-09-28" "$SYNC_TEST_CAPTURE"
touch "$FD_DATA_DIR/.factory-driver-data"
printf 'a\n' > "$FD_DATA_DIR/telemetry/2026-09-28/a.jsonl"
printf 'b\n' > "$FD_DATA_DIR/telemetry/2026-09-28/b.jsonl"
printf '{}\n' > "$FD_DATA_DIR/telemetry/index.json"
printf '{"cars":{}}\n' > "$FD_DATA_DIR/cars.json"
printf '{"issues":[]}\n' > "$FD_DATA_DIR/issues.json"
cat > "$SANDBOX/bin/ird" <<'IRD'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$1 $2" >> "$SYNC_TEST_CAPTURE/calls"
if [ "$1 $2" != 'ipfs add' ]; then
	echo 'FAIL: push-only test called ird outside ipfs add' >&2
	exit 99
fi
rm -rf "$SYNC_TEST_CAPTURE/bundle"
cp -R "$3" "$SYNC_TEST_CAPTURE/bundle"
if [ -f "$SYNC_TEST_CAPTURE/fail" ]; then
	echo 'deliberate upload failure' >&2
	exit 17
fi
echo 'added ... bafkFAKECIDTEST1234567890abcdef'
IRD
chmod +x "$SANDBOX/bin/ird"
export PATH="$SANDBOX/bin:$PATH"
run_push() {
	bash "$ROOT/tools/sync_driverstate.sh" push > "$SANDBOX/output" 2>&1
}
contains() {
	grep -F "$1" "$SANDBOX/output" >/dev/null || { cat "$SANDBOX/output"; exit 1; }
}
calls() {
	[ "$(wc -l < "$SYNC_TEST_CAPTURE/calls" | tr -d ' ')" = "$1" ]
}
# Check the captured upload's exact telemetry paths and bytes, not just the
# reported counts; also prove the manifest never travels with the bundle.
check_bundle() {
	python3 - "$@" <<'PY'
import os, sys
from pathlib import Path
root = Path(os.environ['FD_DATA_DIR'])
bundle = Path(os.environ['SYNC_TEST_CAPTURE']) / 'bundle'
expected = {'2026-09-28/' + name + '.jsonl' for name in sys.argv[1:]}
actual = {p.relative_to(bundle / 'telemetry').as_posix()
          for p in (bundle / 'telemetry').rglob('*') if p.is_file()}
assert actual == expected, (actual, expected)
assert not list(bundle.rglob('.sync-pushed.json'))
for rel in actual:
    assert (bundle / 'telemetry' / rel).read_bytes() == (root / 'telemetry' / rel).read_bytes()
for name in ('cars.json', 'issues.json'):
    assert (bundle / name).read_bytes() == (root / name).read_bytes()
PY
}
check_manifest() {
	python3 - <<'PY'
import datetime, hashlib, json, os
from pathlib import Path
root = Path(os.environ['FD_DATA_DIR'])
m = json.loads((root / '.sync-pushed.json').read_text())
assert m['version'] == 1
assert datetime.datetime.fromisoformat(m['pushed_at']).tzinfo is not None
assert m['telemetry'] == {p.relative_to(root / 'telemetry').as_posix():
    hashlib.sha256(p.read_bytes()).hexdigest() for p in (root / 'telemetry').rglob('*.jsonl')}
for name in ('cars.json', 'issues.json'):
    assert m[name] == hashlib.sha256((root / name).read_bytes()).hexdigest()
assert not (root / 'telemetry' / '.sync-pushed.json').exists()
PY
}
warning='no usable push manifest: packing the full tree (a first push or a repair)'
run_push
contains "$warning"
contains 'telemetry/: packed 2 new/changed, skipped 0 already-pushed'
calls 1
check_bundle a b
check_manifest
echo 'ok: first push, exact bundle, root manifest and hashes'
cp "$FD_DATA_DIR/.sync-pushed.json" "$SANDBOX/old-manifest"
# Pull rebuilds this index; changing it must not buy another upload.
printf '{"sessions":[]}\n' > "$FD_DATA_DIR/telemetry/index.json"
run_push
contains 'nothing new to push (2 files already synced on '
contains '); no upload'
calls 1
cmp "$SANDBOX/old-manifest" "$FD_DATA_DIR/.sync-pushed.json"
echo 'ok: unchanged push exits 0, no ird call or manifest write; index ignored'
printf 'changed a\n' >> "$FD_DATA_DIR/telemetry/2026-09-28/a.jsonl"
printf 'c\n' > "$FD_DATA_DIR/telemetry/2026-09-28/c.jsonl"
run_push
contains 'telemetry/: packed 2 new/changed, skipped 1 already-pushed'
calls 2
check_bundle a c
check_manifest
echo 'ok: changed a and new c packed; unchanged b skipped'
printf 'not json\n' > "$FD_DATA_DIR/.sync-pushed.json"
run_push
contains "$warning"
contains 'telemetry/: packed 3 new/changed, skipped 0 already-pushed'
calls 3
check_bundle a b c
check_manifest
rm "$FD_DATA_DIR/.sync-pushed.json"
run_push
contains "$warning"
calls 4
check_bundle a b c
check_manifest
echo 'ok: corrupt and missing manifest each warn and repack full tree'
# JSON that parses can still be unusable; repair it just as visibly.
for invalid in '[]' '{"version":2}' '{"version":1}'; do
	printf '%s\n' "$invalid" > "$FD_DATA_DIR/.sync-pushed.json"
	run_push
	contains "$warning"
	check_bundle a b c
	check_manifest
done
calls 7
echo 'ok: non-object, wrong version and incomplete manifest repaired'
cp "$FD_DATA_DIR/.sync-pushed.json" "$SANDBOX/old-manifest"
printf 'retry a\n' >> "$FD_DATA_DIR/telemetry/2026-09-28/a.jsonl"
touch "$SYNC_TEST_CAPTURE/fail"
set +e
run_push
status=$?
set -e
[ "$status" -eq 1 ]
calls 8
check_bundle a
cmp "$SANDBOX/old-manifest" "$FD_DATA_DIR/.sync-pushed.json"
rm "$SYNC_TEST_CAPTURE/fail"
run_push
calls 9
check_bundle a
check_manifest
echo 'ok: upload failure exits 1, preserves manifest; next push retries a'
printf '{"cars":{"test":{}}}\n' > "$FD_DATA_DIR/cars.json"
run_push
calls 10
contains 'telemetry/: packed 0 new/changed, skipped 3 already-pushed'
check_bundle
check_manifest
printf '{"issues":[{"id":"test"}]}\n' > "$FD_DATA_DIR/issues.json"
run_push
calls 11
check_bundle
check_manifest
echo 'ok: cars-only and issues-only changes each upload fresh stores'
bash -n "$ROOT/tools/sync_driverstate.sh"
bash -n "$ROOT/tests/test_sync_driverstate.sh"
echo 'ok: bash -n for both scripts'

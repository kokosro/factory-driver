# Tests

`tests/run_tests.sh` is the gate: a headless import, then the config, element catalogue,
skeleton, world profile, ring drive, smoke, handling, camera, mission, battery, thermal,
tyre/brake thermal, steering-feel, wear, licence, menu, issue flag and airborne tests, the
driving ones on the tick clock (`--fixed-fps 60`), a few minutes (the ring drive test builds
the Ring's road twice and drives 2 km on it twice).
`tests/run_tests.sh --parallel` runs the eighteen tests side by side after the import and
prints the same lines in the same order. What each test checks is in the main
`README.md`.

## Gating a commit, not a working tree

An independent verifier should gate a copy of the committed tree, not the working tree
it happens to stand in:

```
dir="$(mktemp -d)"
git archive HEAD | tar -x -C "$dir"
cd "$dir"
tests/run_tests.sh
```

`git archive` writes out exactly what the commit holds: no uncommitted edit, no
untracked file and no stale `.godot/` cache can pass (or fail) the gate on the
commit's behalf, and nothing the run does - the import writes `.godot/` - touches
anybody's working tree, so it is safe while somebody else is editing or gating there.
The copy has no `.godot/` yet, so its first import is a full one and prints more than a
warm one does; the `== step` markers, the `  ok` lines and the verdicts are the same as
anywhere else. Several copies can be gated at once: the only things the suite writes
outside the project are the smoke test's `/tmp/fd-3R-smoke-<pid>/`, the battery
test's `/tmp/fd-3T-battery-<pid>/`, the wear test's `/tmp/fd-3L-wear-<pid>/`, the
licence test's `/tmp/fd-3K-licence-<pid>/`, the menu test's `/tmp/fd-4A-menu-<pid>/` and
the issue flag test's `/tmp/fd-3IF-issue-<pid>/`, one per process each, removed when the
test finishes (the ring drive test writes nothing:
it reads the checked-in skeleton and drape and builds in memory). No test opens a window or a
native dialog: the garage's folder picker is a GUI path the menu test never takes.

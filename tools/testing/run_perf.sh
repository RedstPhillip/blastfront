#!/bin/bash
# Usage: run_perf.sh <cpu|render> <result_file> [project_copy]
# Runs perfsuite.gd and writes its "R <metric> <value>" lines to <result_file> (full log: <result_file>.log).
#   cpu     headless, --fixed-fps 60: the engine never sleeps, so wall time per frame = CPU cost of one
#           60 Hz frame (physics tick + process + draw callbacks). Rendering is a dummy.
#   render  real rendering in a hidden 1px window, SubViewport at 1920x1080. For honest GPU/frame numbers use
#           BF_UNCAPPED=1 BF_OPAQUE=1 OVERRIDE=opaque.cfg (transparent windows stay vsynced at 60 fps).
#           Needs the screen on: a locked/off display stalls windowed runs.
# BF_SHORT=1 shortens the long phases; BF_PROF=1 collects per-function timings (use profile.sh).
# The project copy defaults to the mirror (not synced here: run sync_mirror.sh or import.sh first).
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
PROJ="${3:-$MIRROR}"
mkdir -p "$(dirname "$2")"
RESULT="$(native_path "$2")"
cleanup() { rm -f "$PROJ/override.cfg"; }
trap cleanup EXIT
cd "$PROJ"
SUITE="$(native_path "$TESTING_DIR/perfsuite.gd")"
if [ "$1" = "cpu" ]; then
	cp "$TESTING_DIR/overrides/headless.cfg" override.cfg
	timeout "${TIMEOUT:-900}" "$GODOT" --headless --path . --audio-driver Dummy --fixed-fps 60 -s "$SUITE" -- mode=cpu seed="${SEED:-7}" > "$RESULT.log" 2>&1
else
	cp "$TESTING_DIR/overrides/${OVERRIDE:-hidden.cfg}" override.cfg
	timeout "${TIMEOUT:-600}" "$GODOT" --path . --audio-driver Dummy -s "$SUITE" -- mode=render seed="${SEED:-7}" > "$RESULT.log" 2>&1
fi
grep "^R " "$RESULT.log" > "$RESULT"
grep -E "SCRIPT ERROR|Parse Error" "$RESULT.log" | sort | uniq -c | sort -rn | head -8

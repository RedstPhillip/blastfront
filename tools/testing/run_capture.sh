#!/bin/bash
# Usage: run_capture.sh <scenario> [out_dir]
# Runs a capture.gd scenario with real rendering but invisibly: a 1x1 borderless, transparent, unfocused
# window parked in the bottom-right screen corner (an off-screen window gets throttled by Windows), audio on
# the Dummy driver. The game renders into a 1280x720 (BF_FULLHD: 1920x1080) SubViewport that is saved as
# PNG on every "shot" action. Default out_dir: $WORK_DIR/captures/<scenario>.
# PROJ_OVERRIDE=<project copy> runs against another copy (e.g. $WORK_DIR/mirror_base) without syncing.
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
PROJ="${PROJ_OVERRIDE:-$MIRROR}"
[ -z "$BF_NOSYNC" ] && [ -z "$PROJ_OVERRIDE" ] && sync_project_to "$MIRROR"
OUT="${2:-$WORK_DIR/captures/$1}"
mkdir -p "$OUT"
cleanup() { rm -f "$PROJ/override.cfg"; }
trap cleanup EXIT
cp "$TESTING_DIR/overrides/${OVERRIDE:-hidden.cfg}" "$PROJ/override.cfg"
cd "$PROJ"
export BF_ONSCREEN=1
timeout "${TIMEOUT:-120}" "$GODOT" --path . --audio-driver Dummy --fixed-fps 60 ${EXTRA} \
	-s "$(native_path "$TESTING_DIR/capture.gd")" -- flags="${FLAGS:-none}" seed="${SEED:-1}" scenario="$1" \
	out="$(native_path "$OUT")" 2>&1 | filter_noise

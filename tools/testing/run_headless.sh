#!/bin/bash
# Usage: run_headless.sh <scenario>
# Runs a capture.gd scenario headless (no window, no audio, --fixed-fps 60 so it runs as fast as the CPU
# allows) in the mirror and prints the output with engine shutdown noise removed. Screenshots are skipped.
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
[ -z "$BF_NOSYNC" ] && sync_project_to "$MIRROR"
cleanup() { rm -f "$MIRROR/override.cfg"; }
trap cleanup EXIT
cp "$TESTING_DIR/overrides/headless.cfg" "$MIRROR/override.cfg"
cd "$MIRROR"
timeout "${TIMEOUT:-120}" "$GODOT" --headless --path . --audio-driver Dummy --fixed-fps 60 \
	-s "$(native_path "$TESTING_DIR/capture.gd")" -- flags="${FLAGS:-none}" seed="${SEED:-1}" scenario="${1:-sandbox}" \
	out="$(native_path "$WORK_DIR/headless")" 2>&1 | filter_noise | grep -v "CAPTURED"

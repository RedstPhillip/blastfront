#!/bin/bash
# Usage: run_probe.sh <probe.gd> <headless|render> [script args...]
# Runs one of the SceneTree probe scripts in this folder (bootprobe, depprobe, scriptprobe, gpuablate) in the
# mirror. headless: no window, dummy rendering. render: hidden opaque 1px window, uncapped (for GPU numbers).
#   run_probe.sh bootprobe.gd headless
#   run_probe.sh depprobe.gd headless target=res://scenes/game.tscn
#   run_probe.sh gpuablate.gd render world=mars          (BF_DRAW_ABLATE=1 or BF_HUD_ABLATE=1 for other sets)
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
PROBE="$(native_path "$TESTING_DIR/$1")"
MODE="$2"
shift 2
PROJ="${PROJ_OVERRIDE:-$MIRROR}"
cleanup() { rm -f "$PROJ/override.cfg"; }
trap cleanup EXIT
cd "$PROJ"
if [ "$MODE" = "render" ]; then
	cp "$TESTING_DIR/overrides/opaque.cfg" override.cfg
	timeout "${TIMEOUT:-600}" "$GODOT" --path . --audio-driver Dummy -s "$PROBE" -- "$@" 2>&1 | filter_noise
else
	cp "$TESTING_DIR/overrides/headless.cfg" override.cfg
	timeout "${TIMEOUT:-600}" "$GODOT" --headless --path . --audio-driver Dummy -s "$PROBE" -- "$@" 2>&1 | filter_noise
fi

#!/bin/bash
# Usage: run_probe.sh <probe.gd> <headless|sim|render> [script args...]
# Runs one of the SceneTree probe scripts in this folder in the mirror. headless: no window, dummy rendering.
# sim: headless with --fixed-fps 60, so gameplay probes (nav_probe, edge_probe, stuck_probe, swim_probe)
# simulate as fast as the CPU allows. render: hidden opaque 1px window, uncapped (for GPU numbers).
#   run_probe.sh bootprobe.gd headless
#   run_probe.sh depprobe.gd headless target=res://scenes/game.tscn
#   run_probe.sh gpuablate.gd render world=mars          (BF_DRAW_ABLATE=1 or BF_HUD_ABLATE=1 for other sets)
#   run_probe.sh edge_probe.gd sim world=rimefall
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
	FPS_ARGS=""
	[ "$MODE" = "sim" ] && FPS_ARGS="--fixed-fps 60"
	cp "$TESTING_DIR/overrides/headless.cfg" override.cfg
	timeout "${TIMEOUT:-600}" "$GODOT" --headless --path . --audio-driver Dummy $FPS_ARGS -s "$PROBE" -- "$@" 2>&1 | filter_noise
fi

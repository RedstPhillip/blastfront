#!/bin/bash
# Usage: release_boot.sh [project_copy] [runs]
# Exports a Windows release build of a project copy (default: the mirror) to $WORK_DIR/export_<copy name>
# and times process start -> first frames of the main menu -> quit, headless. Exported builds ignore
# `-s` scripts, so this wall-clock time is the honest player-facing start-up number. Also prints the .pck
# size (download size). Needs the 4.6.1 export templates installed.
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
PROJ="${1:-$MIRROR}"
RUNS="${2:-3}"
OUT="$WORK_DIR/export_$(basename "$PROJ")"
mkdir -p "$OUT"
(cd "$PROJ" && timeout 900 "$GODOT" --headless --path . --export-release "Windows Desktop" "$(native_path "$OUT/blastfront.exe")" > "$OUT/export.log" 2>&1)
cp "$TESTING_DIR/overrides/headless.cfg" "$OUT/override.cfg"
ls -l "$OUT/blastfront.pck" | awk '{printf "pck_bytes %s\n", $5}'
cd "$OUT"
for run in $(seq 1 "$RUNS"); do
	start=$(date +%s%N)
	timeout 120 ./blastfront.exe --headless --audio-driver Dummy --quit-after 2 > /dev/null 2>&1
	end=$(date +%s%N)
	echo "boot_and_quit_ms $(( (end - start) / 1000000 ))"
done

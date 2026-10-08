#!/bin/bash
# Usage: regress.sh [scenario ...]
# Compiles every script once (parse_all.gd), then runs the regression scenarios headless and reports OK/FAIL
# per step. FAIL lists the distinct script or engine errors (a GDScript runtime error is what freezes the game
# in the editor, i.e. "a crash").
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
[ -z "$BF_NOSYNC" ] && sync_project_to "$MIRROR"
export BF_NOSYNC=1
if [ $# -eq 0 ]; then
	parsed=$(bash "$TESTING_DIR/run_probe.sh" parse_all.gd headless 2>&1)
	if echo "$parsed" | grep -q "^PARSE OK"; then
		echo "OK   parse_all ($(echo "$parsed" | grep -o "PARSE OK [0-9]*" | cut -d' ' -f3) scripts)"
	else
		echo "FAIL parse_all"
		echo "$parsed" | grep -E "SCRIPT ERROR|Parse Error|PARSE FAILED|Failed to load" | sort | uniq -c | head -8
	fi
fi
DEFAULT="combat flow online_ui ui_quests victory gamepad explosive lo_interact loadout_inter loadout2 world_switch mars_play locker_esc"
for scenario in ${@:-$DEFAULT}; do
	output=$(TIMEOUT=240 bash "$TESTING_DIR/run_headless.sh" "$scenario" 2>&1)
	errors=$(echo "$output" | grep -E "SCRIPT ERROR|Parse Error|^ERROR|CrashHandler|Program crashed" | sort | uniq -c | head -5)
	if [ -z "$errors" ]; then
		echo "OK   $scenario"
	else
		echo "FAIL $scenario"
		echo "$errors"
	fi
done

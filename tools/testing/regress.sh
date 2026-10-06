#!/bin/bash
# Usage: regress.sh [scenario ...]
# Runs the regression scenarios headless and reports OK/FAIL per scenario. FAIL lists the distinct script or
# engine errors (a GDScript runtime error is what freezes the game in the editor, i.e. "a crash").
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
[ -z "$BF_NOSYNC" ] && sync_project_to "$MIRROR"
export BF_NOSYNC=1
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

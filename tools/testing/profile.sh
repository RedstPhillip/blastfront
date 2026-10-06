#!/bin/bash
# Usage: profile.sh [result_file]
# Function-level CPU profile: copies the mirror to $WORK_DIR/mirror_prof, wraps every engine callback (and
# the hot classes listed in instrument.py) in timers, and runs the short CPU perf suite with BF_PROF=1.
# Prints the top functions per phase as "P <phase> <script:function> <ms per frame> <calls per frame>".
# Times are inclusive and the wrappers add overhead: compare functions against each other, not with the
# uninstrumented frame times.
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
PROF="$WORK_DIR/mirror_prof"
RESULT="${1:-$WORK_DIR/results/profile}"
mkdir -p "$(dirname "$RESULT")"
if command -v robocopy >/dev/null 2>&1; then
	MSYS_NO_PATHCONV=1 robocopy "$(cygpath -w "$MIRROR")" "$(cygpath -w "$PROF")" /MIR /NFL /NDL /NJH /NJS /NP >/dev/null
else
	rsync -a --delete "$MIRROR/" "$PROF/"
fi
python "$TESTING_DIR/instrument.py" "$PROF"
BF_PROF=1 BF_SHORT=1 bash "$TESTING_DIR/run_perf.sh" cpu "$RESULT" "$PROF"
grep "^P " "$RESULT.log"

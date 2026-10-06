#!/bin/bash
# Usage: make_baseline.sh [name]
# Freezes the current mirror (sources + import cache) as $WORK_DIR/mirror_<name> (default: mirror_base), so
# "before" can be re-measured later on the same machine, interleaved with "after" runs. Run import.sh first.
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
TARGET="$WORK_DIR/mirror_${1:-base}"
if command -v robocopy >/dev/null 2>&1; then
	MSYS_NO_PATHCONV=1 robocopy "$(cygpath -w "$MIRROR")" "$(cygpath -w "$TARGET")" /MIR /NFL /NDL /NJH /NJS /NP >/dev/null
else
	rsync -a --delete "$MIRROR/" "$TARGET/"
fi
echo "baseline: $TARGET"

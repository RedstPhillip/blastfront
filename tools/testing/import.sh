#!/bin/bash
# Syncs the mirror and runs the editor's import headless. Needed on first use and whenever new assets or
# new class_name scripts arrive (a stale class cache turns every test into a flood of parse errors).
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
sync_project_to "$MIRROR"
cp "$TESTING_DIR/overrides/headless.cfg" "$MIRROR/override.cfg"
(cd "$MIRROR" && timeout 900 "$GODOT" --headless --path . --import > "$WORK_DIR/import.log" 2>&1)
# A fresh mirror imports resources in no particular order, so the first pass can complain about fonts and the
# theme referencing files that were not imported yet; a second pass settles it (and is quick).
if grep -qE "SCRIPT ERROR|Parse Error" "$WORK_DIR/import.log"; then
	(cd "$MIRROR" && timeout 900 "$GODOT" --headless --path . --import > "$WORK_DIR/import.log" 2>&1)
fi
rm -f "$MIRROR/override.cfg"
grep -E "SCRIPT ERROR|Parse Error" "$WORK_DIR/import.log" | sort -u | head -20
echo "import done (log: $WORK_DIR/import.log)"

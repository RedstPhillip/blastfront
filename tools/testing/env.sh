#!/bin/bash
# Shared settings for the test scripts (source it; every value can be overridden from the environment).
#
#   GODOT        Godot 4.6.1 editor binary. On Windows use the *_console.exe so output reaches the pipe.
#                Default: the copy next to the project folder on the main dev machine, else `godot` on PATH.
#   PROJECT_DIR  The repository (default: two levels above this folder).
#   WORK_DIR     Scratch space for the test mirror, baselines, captures and results. Must be OUTSIDE the
#                repository and outside any synced folder (Google Drive): it holds full project copies.
#   MIRROR       The project copy every test runs in (default: $WORK_DIR/mirror).

TESTING_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="${PROJECT_DIR:-$(cd "$TESTING_DIR/../.." && pwd)}"
WORK_DIR="${WORK_DIR:-${TMPDIR:-${TEMP:-/tmp}}/blastfront_testwork}"
MIRROR="${MIRROR:-$WORK_DIR/mirror}"

if [ -z "$GODOT" ]; then
	for candidate in \
		"$PROJECT_DIR/../../Godot_v4.6.1-stable_win64.exe/Godot_v4.6.1-stable_win64_console.exe" \
		"$PROJECT_DIR/../Godot_v4.6.1-stable_win64_console.exe"; do
		if [ -f "$candidate" ]; then
			GODOT="$candidate"
			break
		fi
	done
	GODOT="${GODOT:-godot}"
fi

mkdir -p "$WORK_DIR"

# Godot on Windows wants C:/... paths, not Git Bash's /c/...; elsewhere paths pass through unchanged.
native_path() {
	if command -v cygpath >/dev/null 2>&1; then
		cygpath -m "$1"
	else
		echo "$1"
	fi
}

# Copies the repository into a project folder (default: the mirror). The copy keeps its own .godot import
# cache, so only changed files reimport; .git and override.cfg are never copied.
sync_project_to() {
	local target="${1:-$MIRROR}"
	mkdir -p "$target"
	if command -v robocopy >/dev/null 2>&1; then
		MSYS_NO_PATHCONV=1 robocopy "$(cygpath -w "$PROJECT_DIR")" "$(cygpath -w "$target")" /MIR /XD .git .godot /XF override.cfg \
			/NFL /NDL /NJH /NJS /NP /R:1 /W:1 >/dev/null
		[ $? -ge 8 ] && echo "robocopy failed" >&2
	else
		rsync -a --delete --exclude .git --exclude .godot --exclude override.cfg "$PROJECT_DIR/" "$target/"
	fi
	return 0
}

# Strips the engine's shutdown noise so real errors stand out.
filter_noise() {
	grep -v "^\s*$" | grep -vE "leaked|RID allocations|~CompressedTexture2D|~Utilities|object.cpp|ObjectDB instances|Unreferenced static string|PagedAllocator|resources still in use|RenderingServer::get_singleton"
}

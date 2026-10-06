#!/bin/bash
# Mirrors the repository into $MIRROR (see env.sh). Tests never run in the real project folder: that would
# touch the developer's .godot cache and editor state. Skipped when BF_NOSYNC is set.
source "$(dirname "${BASH_SOURCE[0]}")/env.sh"
[ -n "$BF_NOSYNC" ] && exit 0
sync_project_to "$MIRROR"

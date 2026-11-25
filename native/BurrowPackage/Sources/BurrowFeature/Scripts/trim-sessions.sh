#!/bin/bash
src="$1"; label="$2"
dest="$HOME/.Trash/Burrow $label sessions $(date '+%Y-%m-%d %H.%M.%S')"
mkdir -p "$dest"
cd "$src" || exit 1
n=0
while IFS= read -r -d '' f; do mkdir -p "$dest/$(dirname "$f")"; mv "$f" "$dest/$f" && n=$((n+1)); done < <(find . -type f -name '*.jsonl' -not -path '*/memory/*' -mtime +30 -print0)
echo "$n"

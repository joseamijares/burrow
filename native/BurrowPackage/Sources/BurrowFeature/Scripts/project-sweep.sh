#!/bin/bash
D="$HOME/Library/Application Support/Burrow"
date +%s > "$D/sweep-pending"
printf '{"t":%s,"kind":"project-sweep","freed":0,"how":"reminder"}\n' "$(date +%s)" >> "$D/history.jsonl"
osascript -e 'display notification "Your monthly project sweep is ready. Open Burrow to review build folders and old worktrees." with title "Burrow"'

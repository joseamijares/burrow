#!/bin/bash
bid="$1"; name="$2"; L="$HOME/Library"
[ ${#bid} -ge 8 ] || bid="__none__"
nm="$name"; [ ${#nm} -ge 4 ] || nm="__none__"
for d in "Application Support" Caches Preferences "Preferences/ByHost" Logs "Saved Application State" HTTPStorages WebKit Containers "Group Containers" "Application Scripts" LaunchAgents Cookies; do
  [ -d "$L/$d" ] || continue
  find "$L/$d" -mindepth 1 -maxdepth 1 \( -iname "*$bid*" -o -iname "$nm" \) 2>/dev/null
done | sort -u | while IFS= read -r p; do printf '%s\t%s\n' "$(du -sk "$p" 2>/dev/null | cut -f1)" "$p"; done
true

#!/bin/bash
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
D="$HOME/Library/Application Support/Burrow"
W="$HOME/.config/mole/whitelist"; B="$D/whitelist.weekly.bak"
had=0; [ -f "$W" ] && { cp "$W" "$B"; had=1; }
restore() { if [ "$had" = 1 ]; then cp "$B" "$W"; else rm -f "$W"; fi; rm -f "$B"; }
trap restore EXIT
mkdir -p "$(dirname "$W")"
# A whitelist file switches off Mole's built-in one, so with none, start from those defaults
# (DEFAULT_WHITELIST_PATTERNS in Mole's lib/core/base.sh; Mole 1.74's copy as a fallback).
if [ "$had" = 0 ]; then
  base="$(dirname "$(readlink -f "$(command -v mo)")")/../libexec/lib/core/base.sh"
  defaults=$(awk '/DEFAULT_WHITELIST_PATTERNS=\(/{p=1;next} p&&/^\)/{exit} p' "$base" 2>/dev/null | sed -n 's/^ *"\(.*\)"$/\1/p' | sed "s|\$HOME|$HOME|; s|\$FINDER_METADATA_SENTINEL|FINDER_METADATA|")
  if [ -z "$defaults" ]; then
    defaults=$(printf '%s\n' "$HOME/Library/Caches/ms-playwright*" "$HOME/Library/Caches/camoufox*" "$HOME/Library/Caches/Cypress*" \
      "$HOME/.gradle/caches/*" "$HOME/.gradle/daemon/*" "$HOME/.ollama/models/*" "$HOME/Library/Caches/com.nssurge.surge-mac/*" \
      "$HOME/Library/Application Support/com.nssurge.surge-mac/*" "$HOME/Library/Caches/org.R-project.R/R/renv/*" \
      "$HOME/Library/Caches/JetBrains*" "$HOME/Library/Caches/com.jetbrains.toolbox*" "$HOME/Library/Caches/tealdeer/tldr-pages" \
      "$HOME/Library/Application Support/JetBrains*" "$HOME/Library/Caches/com.apple.finder" "$HOME/Library/Mobile Documents*" FINDER_METADATA)
  fi
  printf '%s\n' "$defaults" > "$W"
fi
# Never empty the Trash unattended: it is Burrow's undo for files it moved there.
# Never clean inside cloud folders: deleting there deletes on every device.
printf '%s\n' "$HOME/.Trash" "$HOME/.Trash/*" "$HOME/Library/CloudStorage" "$HOME/Library/CloudStorage/*" "$HOME/Library/Mobile Documents*" >> "$W"
b=$(df -k / | awk 'NR==2{print $4}')
mo clean </dev/null > "$D/last-scheduled-clean.log" 2>&1
code=$?
a=$(df -k / | awk 'NR==2{print $4}')
f=$(( (a-b)*1024 )); [ "$f" -lt 0 ] && f=0
printf '{"t":%s,"kind":"weekly-clean","freed":%s,"code":%s,"how":"scheduled"}\n' "$(date +%s)" "$f" "$code" >> "$D/history.jsonl"
gb=$(awk -v f="$f" 'BEGIN{printf "%.1f", f/1073741824}')
osascript -e "display notification \"Weekly clean finished. Freed $gb GB.\" with title \"Burrow\""

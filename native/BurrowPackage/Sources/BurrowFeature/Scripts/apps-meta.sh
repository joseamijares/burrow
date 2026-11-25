#!/bin/bash
D="$HOME/Library/Application Support/Burrow/icons"; mkdir -p "$D"
while IFS= read -r p; do
  [ -d "$p" ] || continue
  kb=$(du -sk "$p" 2>/dev/null | cut -f1)
  pl="$p/Contents/Info.plist"
  id=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$pl" 2>/dev/null)
  out="$D/${id:-$(basename "$p" .app)}.png"
  if [ ! -s "$out" ]; then
    ic=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$pl" 2>/dev/null)
    if [ -n "$ic" ]; then case "$ic" in *.icns) ;; *) ic="$ic.icns";; esac
      [ -f "$p/Contents/Resources/$ic" ] && sips -s format png -Z 64 "$p/Contents/Resources/$ic" --out "$out" >/dev/null 2>&1
    fi
  fi
  [ -s "$out" ] || out=""
  printf '%s\t%s\t%s\n' "$p" "${kb:-0}" "$out"
done
true

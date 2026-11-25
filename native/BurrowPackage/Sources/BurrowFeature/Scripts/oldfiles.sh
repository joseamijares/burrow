#!/bin/bash
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
for d in "$HOME/Downloads" "$HOME/Desktop" "$HOME/Documents"; do
  [ -d "$d" ] || continue
  { find "$d" -maxdepth 4 \( -name node_modules -o -name .git -o -name '*.app' -o -name '*.photoslibrary' \) -prune -o -type f \( -iname '*.dmg' -o -iname '*.pkg' -o -iname '*.mpkg' -o -iname '*.xip' -o -iname '*.iso' \) -print0 2>/dev/null | xargs -0 -I{} printf 'I\t%s\n' {}
    find "$d" -maxdepth 5 \( -name node_modules -o -name .git -o -name '*.app' -o -name '*.photoslibrary' -o -name '*.fcpbundle' \) -prune -o -type f -size +300M -print0 2>/dev/null | xargs -0 -I{} printf 'L\t%s\n' {}
  } | while IFS=$'\t' read -r k f; do
    sz=$(stat -f %z "$f" 2>/dev/null) || continue
    lu=$(mdls -name kMDItemLastUsedDate -raw "$f" 2>/dev/null)
    t=0; case "$lu" in 20*) t=$(date -j -f '%Y-%m-%d %H:%M:%S %z' "$lu" +%s 2>/dev/null || echo 0);; esac
    if [ "$t" = 0 ]; then t=$(stat -f %m "$f"); fi
    printf '%s\t%s\t%s\t%s\t%s\n' "$k" "$sz" "$t" "$t" "$f"
  done
done
true

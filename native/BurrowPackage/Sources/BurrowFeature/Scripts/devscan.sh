#!/bin/bash
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
roots=("$HOME/Documents" "$HOME/Projects" "$HOME/GitHub" "$HOME/dev" "$HOME/code" "$HOME/Developer")
if [ -f "$HOME/.config/mole/purge_paths" ]; then
  while IFS= read -r l; do case "$l" in ''|'#'*) ;; *) roots+=("${l/#\~/$HOME}");; esac; done < "$HOME/.config/mole/purge_paths"
fi
repos=$(for r in "${roots[@]}"; do [ -d "$r" ] && find "$r" -maxdepth 5 \( -name node_modules -o -name Library -o -name .Trash -o -name worktrees \) -prune -o -name .git -type d -print 2>/dev/null; done | sort -u)
while IFS= read -r g; do
  [ -n "$g" ] || continue
  repo="${g%/.git}"
  merged=$(git -C "$repo" branch --merged 2>/dev/null | sed 's/^[*+ ]*//')
  git -C "$repo" worktree list --porcelain 2>/dev/null | awk -v repo="$repo" '/^worktree /{p=substr($0,10)} /^branch /{b=substr($0,8)} /^detached/{b="(detached)"} /^$/{ if (p!="" && p!=repo) print p "\t" b; p=""; b=""} END{ if (p!="" && p!=repo) print p "\t" b}' | while IFS=$'\t' read -r wt br; do
    br="${br#refs/heads/}"
    if [ ! -d "$wt" ]; then printf 'W\t%s\t%s\t%s\t0\t0\t0\t0\t0\n' "$repo" "$wt" "$br"; continue; fi
    ts=$(git -C "$wt" log -1 --format=%ct 2>/dev/null || echo 0)
    mt=$(stat -f %m "$wt" 2>/dev/null || echo 0)
    dirty=$(git -C "$wt" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
    m=0; printf '%s\n' "$merged" | grep -Fxq -- "$br" && m=1
    kb=$(du -sk "$wt" 2>/dev/null | cut -f1)
    printf 'W\t%s\t%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$repo" "$wt" "$br" "${ts:-0}" "$mt" "$dirty" "$m" "${kb:-0}"
  done
done <<< "$repos"
for r in "${roots[@]}"; do
  [ -d "$r" ] || continue
  find "$r" -maxdepth 6 \( -name .git -o -name Library -o -name .Trash \) -prune -o -type d \( -name node_modules -o -name .next -o -name dist -o -name target -o -name .build -o -name build -o -name .turbo -o -name .parcel-cache \) -prune -print 2>/dev/null
done | sort -u | while IFS= read -r a; do
  parent=$(dirname "$a"); name=$(basename "$a")
  if git -C "$parent" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git -C "$parent" ls-files --error-unmatch -- "$name" >/dev/null 2>&1 && continue
    git -C "$parent" check-ignore -q -- "$name" 2>/dev/null || continue
  else
    case "$name" in node_modules|.next|.turbo|.parcel-cache) ;; *) continue ;; esac
  fi
  mt=$(stat -f %m "$a" 2>/dev/null || echo 0); pm=$(stat -f %m "$parent" 2>/dev/null || echo 0)
  kb=$(du -sk "$a" 2>/dev/null | cut -f1)
  [ "${kb:-0}" -gt 51200 ] && printf 'A\t%s\t%s\t%s\t%s\n' "$a" "$mt" "$pm" "$kb"
done
dd="$HOME/Library/Developer/Xcode/DerivedData"
[ -d "$dd" ] && printf 'X\t%s\t%s\n' "$dd" "$(du -sk "$dd" 2>/dev/null | cut -f1)"
for d in .claude .codex .cursor .gemini .ollama .windsurf .continue .aider .copilot; do
  [ -d "$HOME/$d" ] && printf 'G\t%s\t%s\n' "$d" "$(du -sk "$HOME/$d" 2>/dev/null | cut -f1)"
done
for pair in ".claude:$HOME/.claude/projects" ".codex:$HOME/.codex/sessions"; do
  name="${pair%%:*}"; dir="${pair#*:}"
  [ -d "$dir" ] || continue
  out=$(find "$dir" -type f -name '*.jsonl' -not -path '*/memory/*' -mtime +30 -print0 2>/dev/null | xargs -0 stat -f %z 2>/dev/null | awk '{n++; s+=$1} END{printf "%d\t%d", n, s}')
  printf 'O\t%s\t%s\t%s\n' "$name" "$dir" "$out"
done
loaded=$(launchctl list 2>/dev/null)
for f in "$HOME/Library/LaunchAgents"/*.plist; do
  [ -f "$f" ] || continue
  label=$(plutil -extract Label raw "$f" 2>/dev/null)
  prog=$(plutil -extract Program raw "$f" 2>/dev/null || plutil -extract ProgramArguments.0 raw "$f" 2>/dev/null)
  ex=0; [ -e "$prog" ] && ex=1
  pid=$(printf '%s\n' "$loaded" | awk -v l="$label" '$3==l{print $1}')
  printf 'L\t%s\t%s\t%s\t%s\t%s\n' "$f" "$label" "$prog" "$ex" "${pid:--}"
done
true

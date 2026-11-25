#!/bin/bash
export PATH="/opt/homebrew/bin:/usr/local/bin:$HOME/.cargo/bin:$HOME/.local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
export HOMEBREW_NO_AUTO_UPDATE=1
row() { printf '%s\t%s\t%s\t%s\t%s\t%s\t%s\n' "$1" "$2" "$3" "${4:-0}" "${5:-0}" "${6:-0}" "$7"; }
if command -v brew >/dev/null 2>&1; then
  C=$(brew --cellar); K=$(brew --caskroom)
  svc=$(brew services list 2>/dev/null | awk 'NR>1 && $2=="started"{print $1}')
  for f in $(brew leaves --installed-on-request 2>/dev/null); do
    n=${f##*/}; v=$(ls "$C/$n" 2>/dev/null | tail -1)
    s=0; printf '%s\n' "$svc" | grep -qx "$n" && s=1
    row brew "$f" "$v" "$(sed -n 's/.*"time": *\([0-9]*\).*/\1/p' "$C/$n/$v/INSTALL_RECEIPT.json" 2>/dev/null | head -1)" "$(du -sk "$C/$n" 2>/dev/null | cut -f1)" "$s"
  done
  for c in $(brew list --cask 2>/dev/null); do
    v=$(ls "$K/$c" 2>/dev/null | grep -v '^\.' | tail -1)
    ts=$(ls "$K/$c/.metadata/$v" 2>/dev/null | tail -1)
    row cask "$c" "$v" "$(date -j -f '%Y%m%d%H%M%S' "${ts%%.*}" +%s 2>/dev/null)" "$(du -skL "$K/$c" 2>/dev/null | cut -f1)" 0
  done
fi
for R in "$HOME/.local/lib/node_modules" "$HOME"/.nvm/versions/node/*/lib/node_modules /opt/homebrew/lib/node_modules /usr/local/lib/node_modules; do
  [ -d "$R" ] || continue; P=$(cd "$R/../.." && pwd)
  for p in "$R"/* "$R"/@*/*; do
    [ -f "$p/package.json" ] || continue; n=${p#"$R"/}; case "$n" in npm|corepack) continue;; esac
    v=$(sed -n 's/^ *"version": *"\([^"]*\)".*/\1/p' "$p/package.json" | head -1)
    row npm "$n" "$v" "$(stat -f %B "$p")" "$(du -sk "$p" 2>/dev/null | cut -f1)" 0 "$P"
  done
done
def=$(cat "$HOME/.nvm/alias/default" 2>/dev/null)
for N in "$HOME"/.nvm/versions/node/*; do
  [ -d "$N" ] || continue; v=${N##*/}; d=0; case "$v" in "$def"|"v$def"|"$def".*|"v$def".*) d=1;; esac
  row node "$v" "$v" "$(stat -f %B "$N")" "$(du -sk "$N" 2>/dev/null | cut -f1)" "$d" "$N"
done
if command -v pipx >/dev/null 2>&1; then V=$(pipx environment --value PIPX_LOCAL_VENVS 2>/dev/null)
  pipx list --short 2>/dev/null | while read -r n v; do row pipx "$n" "$v" "$(stat -f %B "$V/$n" 2>/dev/null)" "$(du -sk "$V/$n" 2>/dev/null | cut -f1)" 0; done; fi
if command -v uv >/dev/null 2>&1; then U=$(uv tool dir 2>/dev/null)
  uv tool list 2>/dev/null | grep -v '^-' | while read -r n v; do [ -n "$n" ] && row uv "$n" "${v#v}" "$(stat -f %B "$U/$n" 2>/dev/null)" "$(du -sk "$U/$n" 2>/dev/null | cut -f1)" 0; done; fi
if command -v cargo >/dev/null 2>&1; then
  cargo install --list 2>/dev/null | grep -v '^ ' | while read -r n v; do v=${v%:}; b=$(cargo install --list 2>/dev/null | awk -v n="$n" '$1==n{f=1;next} f&&/^ /{print $1; exit}'); row cargo "$n" "${v#v}" "$(stat -f %B "$HOME/.cargo/bin/$b" 2>/dev/null)" "$(du -sk "$HOME/.cargo/bin/$b" 2>/dev/null | cut -f1)" 0; done; fi
true

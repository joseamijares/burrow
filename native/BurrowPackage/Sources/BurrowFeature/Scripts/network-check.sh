#!/bin/bash
D="$HOME/Library/Application Support/Burrow"
out=$(/bin/bash "$D/scripts/netcheck.sh")
gw=$(printf '%s\n' "$out" | awk -F'\t' '$1=="gw"{print $3}')
net=$(printf '%s\n' "$out" | awk -F'\t' '$1=="net"{print $3}')
dns=$(printf '%s\n' "$out" | awk -F'\t' '$1=="dns"{print $2}')
printf '{"t":%s,"kind":"network-check","freed":0,"how":"scheduled","note":"router %s ms, internet %s ms, DNS %s ms"}\n' "$(date +%s)" "${gw:-–}" "${net:-–}" "${dns:-–}" >> "$D/history.jsonl"

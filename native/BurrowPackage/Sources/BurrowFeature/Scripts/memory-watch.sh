#!/bin/bash
D="$HOME/Library/Application Support/Burrow"
level=$(sysctl -n kern.memorystatus_vm_pressure_level 2>/dev/null || echo 1)
swap=$(sysctl -n vm.swapusage 2>/dev/null | awk '{for(i=1;i<=NF;i++){if($i=="total")t=$(i+2); if($i=="used")u=$(i+2)}} END{gsub("M","",t); gsub("M","",u); if (t>0) printf "%d", u*100/t; else print 0}')
used="pressure ${level}, swap ${swap}"
c=$(cat "$D/memwatch.count" 2>/dev/null || echo 0)
if [ "$level" -ge 4 ] || { [ "$level" -ge 2 ] && [ "${swap:-0}" -ge 85 ]; }; then c=$((c+1)); else c=0; fi
echo "$c" > "$D/memwatch.count"
if [ "$c" -eq 2 ]; then
  top=$(ps -axo rss=,comm= | sort -nr | head -1 | awk '{rss=$1; $1=""; sub(/^ /,""); n=split($0,a,"/"); app=$0; if (match($0,/[^\/]+\.app\//)) app=substr($0,RSTART,RLENGTH-5); else app=a[n]; printf "%s (%.1f GB)", app, rss/1048576}')
  osascript -e "display notification \"Memory is under pressure and swap is ${swap}% full. Biggest user: ${top}.\" with title \"Burrow\""
  printf '{"t":%s,"kind":"memory-alert","freed":0,"how":"scheduled","note":"%s"}\n' "$(date +%s)" "$used" >> "$D/history.jsonl"
fi

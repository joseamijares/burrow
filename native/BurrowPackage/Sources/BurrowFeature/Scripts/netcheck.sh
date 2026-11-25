#!/bin/bash
export PATH="/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin"
gw=$(route -n get default 2>/dev/null | awk '/gateway:/{print $2}')
p() { ping -c 3 -t 4 -q "$1" 2>/dev/null | awk -F'/' '/round-trip|rtt/{print $5}'; }
printf 'gw\t%s\t%s\n' "$gw" "$( [ -n "$gw" ] && p "$gw")"
printf 'net\t1.1.1.1\t%s\n' "$(p 1.1.1.1)"
s=$(perl -MTime::HiRes=time -e 'printf "%.4f", time')
dscacheutil -q host -a name "check-$RANDOM.apple.com" >/dev/null 2>&1
e=$(perl -MTime::HiRes=time -e 'printf "%.4f", time')
printf 'dns\t%s\n' "$(perl -e "printf '%.0f', ($e-$s)*1000")"

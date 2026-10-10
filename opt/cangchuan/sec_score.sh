#!/bin/sh
SC=0
S="$(cat /etc/ssh/sshd_config /etc/ssh/sshd_config.d/*.conf 2>/dev/null)"
printf '%s\n' "$S" | grep -qiE '^[[:space:]]*PasswordAuthentication[[:space:]]+no' && SC=$((SC+1))
printf '%s\n' "$S" | grep -qiE '^[[:space:]]*PermitRootLogin[[:space:]]+(no|prohibit-password)' && SC=$((SC+1))
if command -v ss >/dev/null 2>&1; then
  ss -lntp 2>/dev/null | grep -qE ':22[[:space:]].*sshd' || SC=$((SC+1))
elif command -v netstat >/dev/null 2>&1; then
  netstat -lntp 2>/dev/null | grep -qE ':22[[:space:]].*sshd' || SC=$((SC+1))
else
  SC=$((SC+1))
fi
if command -v nft >/dev/null 2>&1; then
  nft list ruleset 2>/dev/null | grep -q 'dport' && SC=$((SC+1))
elif command -v iptables >/dev/null 2>&1; then
  iptables -S 2>/dev/null | grep -qve '^-P' && SC=$((SC+1))
fi
pgrep -f fail2ban >/dev/null 2>&1 && SC=$((SC+1))
[ "$(df -P / 2>/dev/null | awk 'NR==2{gsub("%","",$5); print $5+0}')" -lt 90 ] && SC=$((SC+1))
echo $((SC*100/6))

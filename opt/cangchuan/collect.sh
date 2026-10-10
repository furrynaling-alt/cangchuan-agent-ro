#!/bin/bash
. /etc/cangchuan.conf
HS=$(hostname 2>/dev/null || cat /etc/hostname 2>/dev/null || echo unknown)
OS=$( (. /etc/os-release 2>/dev/null; echo "${PRETTY_NAME:-Linux}") )
CORES=$(nproc 2>/dev/null || echo 1)
# 静态检查建议：不要用未加引号的命令替换直接赋值数组（SC2207）
read -ra LA <<< "$(cat /proc/loadavg 2>/dev/null || echo '0 0 0')"
MEM=$(free -m 2>/dev/null | awk 'NR==2{print $2" "$3" "$7}')
MT=$(echo $MEM | cut -d' ' -f1); MU=$(echo $MEM | cut -d' ' -f2); MA=$(echo $MEM | cut -d' ' -f3)
DISK=$(df / 2>/dev/null | awk 'NR==2{gsub("%","",$5); print $5}')
UP=$(uptime -p 2>/dev/null | sed 's/^up //' || echo "-")
IP=$(curl -s --max-time 5 https://api.ipify.org 2>/dev/null)
[ -z "$IP" ] && IP=$(curl -s --max-time 5 https://ifconfig.me/ip 2>/dev/null)
[ -z "$IP" ] && IP=$(curl -s --max-time 5 https://ipinfo.io/ip 2>/dev/null)
[ -z "$IP" ] && IP=$(curl -s --max-time 5 https://myip.ipip.net 2>/dev/null | grep -oE '[0-9]{1,3}(\.[0-9]{1,3}){3}' | head -1)
[ -z "$IP" ] && IP=$(curl -s --max-time 5 http://members.3322.org/dyndns/getip 2>/dev/null | tr -d ' \n')
[ -z "$IP" ] && IP=$(ip -4 route get 1.1.1.1 2>/dev/null | awk '{for(i=1;i<=NF;i++) if($i=="src") print $(i+1)}' | head -1)
[ -z "$IP" ] && IP="-"
GEO=$(curl -s --max-time 6 "http://ip-api.com/json/?fields=city,country" 2>/dev/null)
CC=$(echo "$GEO" | grep -o '"city":"[^"]*"' | cut -d'"' -f4)
CO=$(echo "$GEO" | grep -o '"country":"[^"]*"' | cut -d'"' -f4)
if [ -n "$CC" ] || [ -n "$CO" ]; then REGION="${CO}·${CC}"; else REGION="-"; fi
REGION=$(echo "$REGION" | tr -d '"\\{}' | cut -c1-40)
HS=$(echo "$HS" | tr -d '"\\' | cut -c1-60)
OS=$(echo "$OS" | tr -d '"\\' | cut -c1-60)

# ── 网络流量：读 /proc/net/dev 两个采样点算实时速率 ──
RX1=0; TX1=0
while read -r ifc rest; do
  case "$ifc" in lo:|Inter-|face|Receive|Transmit) continue;; esac
  set -- $rest
  RX1=$((RX1 + ${1:-0})); TX1=$((TX1 + ${2:-0}))
done < <(awk 'NR>2{print $1, $2, $10}' /proc/net/dev)
RX1=${RX1%%.*}; TX1=${TX1%%.*}
NOW=$(date +%s)
UP_BPS=0; DN_BPS=0
if [ -f /opt/cangchuan/net.prev ]; then
  read PRX PTX PT < /opt/cangchuan/net.prev 2>/dev/null
  DT=$((NOW - ${PT:-$NOW}))
  [ "$DT" -gt 0 ] && {
    DN_BPS=$(( (RX1 - ${PRX:-$RX1}) / DT ))
    UP_BPS=$(( (TX1 - ${PTX:-$TX1}) / DT ))
    [ "$DN_BPS" -lt 0 ] && DN_BPS=0
    [ "$UP_BPS" -lt 0 ] && UP_BPS=0
  }
fi
printf '%s %s %s\n' "$RX1" "$TX1" "$NOW" > /opt/cangchuan/net.prev 2>/dev/null
echo "$RX1 $TX1 $UP_BPS $DN_BPS" > /tmp/cc_net 2>/dev/null

# ── 磁盘 GB + 安全分 ──
# 所有真实块设备一起统计；且「设备必须还插着」才算（拔了 U 盘，残留挂载点不计数）
DFK=$(for dev in $(df -PkT 2>/dev/null | awk 'NR>1 && $1 ~ /^\/dev\//{print $1}'); do
	base=$(basename "$dev")
	case "$base" in
		nvme*p[0-9]*|mmcblk*p[0-9]*) disk=${base%p*} ;;
		*) disk=$(echo "$base" | sed 's/[0-9]*$//') ;;
	esac
	[ -e "/sys/block/$disk" ] || continue
	df -PkT "$dev" 2>/dev/null | awk 'NR==2{print $3, $4}'
done | awk '{t+=$1; u+=$2} END{ if(t=="")t=0; if(u=="")u=0; print t, u }')
[ -z "$DFK" ] && DFK=$(df -Pk / 2>/dev/null | awk 'NR==2{print $2" "$3}')
DK_T=$(echo "$DFK" | awk '{printf "%.1f", $1/1048576}')
DK_U=$(echo "$DFK" | awk '{printf "%.1f", $2/1048576}')
SEC=$(/opt/cangchuan/sec_score.sh 2>/dev/null || echo 0)

cat <<EOJ
{"code":"$CODE","host":"$HS","os":"$OS","cores":${CORES:-1},
 "load1":${LA[0]:-0},"load5":${LA[1]:-0},"load15":${LA[2]:-0},
 "mem_total":${MT:-0},"mem_used":${MU:-0},"mem_avail":${MA:-0},
 "disk_used":${DISK:-0},"uptime":"$UP","ip":"$IP","region":"$REGION",
 "net_rx_bytes":${RX1:-0},"net_tx_bytes":${TX1:-0},
 "net_dn_bps":${DN_BPS:-0},"net_up_bps":${UP_BPS:-0},
 "disk_total_gb":${DK_T:-0},"disk_used_gb":${DK_U:-0},"sec_score":${SEC:-0}}
EOJ

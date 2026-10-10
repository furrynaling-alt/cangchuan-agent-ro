#!/bin/bash
# 棂海苍川 节点上报 · 只读定制版（cangchuan-agent-ro）
#
#   ★这个版本是给「只许它报，不许别人动它」的机器用的：
#     只做一件事：每 15 秒采集一次、上报一次。
#     不轮询指令、不接受任何命令、不被"待机/正常/归家"任何模式控制。
#     就算面板想指挥它，也没有通道 —— 它从不问"有没有指令"。
#
#   用法（一般不用手动跑，装成服务就自己跑）：
#     push-ro.sh          常驻，每 15 秒一次
#     push-ro.sh --once   只跑一轮
set -u
. /etc/cangchuan.conf
INTERVAL="${RO_INTERVAL:-30}"     # 默认 30 秒；想更快/更慢在 /etc/cangchuan.conf 里加一行 RO_INTERVAL=秒数

round() {
  J=$(/opt/cangchuan/collect.sh 2>/dev/null)
  [ -z "$J" ] && return 1
  printf '%s' "$J" > /opt/cangchuan/self.json
  printf '%s' "$J" > /tmp/cc_self_ro.json
  python3 - <<'EOPY' 2>/dev/null || cp /tmp/cc_self_ro.json /tmp/cc_send_ro.json
import json, hashlib
KEYS = ("uid","name","ip","region","cores","mem_total")
try:
    d = json.load(open("/tmp/cc_self_ro.json"))
except Exception:
    raise SystemExit(0)
try:
    s = json.load(open("/opt/cangchuan/chain.json"))
    ch = s.get("chain") or []
    if ch:
        ch = sorted(ch, key=lambda y: (not y.get("online"), y.get("name") or ""))
        canon = json.dumps([{k: x.get(k) for k in KEYS} for x in ch],
                           ensure_ascii=False, sort_keys=True, separators=(",", ":"))
        d["vote"] = hashlib.sha384(canon.encode()).hexdigest()
except Exception:
    pass
json.dump(d, open("/tmp/cc_send_ro.json", "w"), ensure_ascii=False)
EOPY
  curl -s --max-time 12 -X POST "$HUB/api/agent/push" \
    -H "Content-Type: application/json" -H "X-Push-Token: $CODE" \
    --data-binary @/tmp/cc_send_ro.json -o /dev/null 2>/dev/null
  return 0
  # ★到此为止：不碰 /api/agent/poll，不执行任何指令
}

if [ "${1:-}" = "--once" ]; then
  round
  exit 0
fi

echo "[$(date '+%F %T')] 只读探针启动：固定每 ${INTERVAL} 秒上报一次（不接受指令、不受模式控制）"
while true; do
  round >/dev/null 2>&1
  sleep "$INTERVAL"
done

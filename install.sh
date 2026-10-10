#!/bin/bash
# ============================================================
#  棂海苍川 · 节点上报【只读定制版】一键安装
#
#  一条命令：
#     curl -fsSL https://raw.githubusercontent.com/furrynaling-alt/cangchuan-agent-ro/main/install.sh \
#       | sudo bash -s 你的节点码
#
#  ★这个版本只做一件事：每 15 秒采集一次、上报一次。
#    不轮询指令、不接受任何命令、不被任何模式控制（没有"待机/正常/归家"）。
#    面板想指挥它也没有通道 —— 它从不问"有没有指令"。
#
#  装完这台机器自动出现在面板上：
#     名字 = 本机 hostname（想改就改 hostname，或装完在面板上改名）
#     地区 = 面板按公网 IP 自动判
# ============================================================
set -e
[ "$(id -u)" = "0" ] || { echo "要用 root 跑"; exit 1; }

CODE="${1:-}"
HUB="${2:-https://panel.naling.net}"
# 防呆：把占位符当真的贴进来会报 "syntax error near unexpected token newline"
case "$CODE" in
  *"<"*|*">"*|*"节点码"*|abc123xyz|xxx|xxxcode|YOUR_CODE)
    echo "❌ 这不是节点码，看着还是占位符：$CODE"
    echo "   节点码是面板上生成的一串（一台机器一个），整串贴进来、不要带尖括号 <>"
    echo "   形如：EXAMPLECODE1234567890ABCD（面板给你的那一串，整段贴进来）"
    exit 1;;
esac
[ -z "$CODE" ] && { echo "用法：... | sudo bash -s 你的节点码   （去面板生成，不要带 <>）"; exit 1; }
RAW="https://raw.githubusercontent.com/furrynaling-alt/cangchuan-agent-ro/main"
[ -z "$CODE" ] && { echo "用法：... | sudo bash -s 你的节点码"; exit 1; }

HERE="$(cd "$(dirname "$0")" 2>/dev/null && pwd || echo /tmp)"
if [ -f "$HERE/opt/cangchuan/collect.sh" ]; then
  SRC="$HERE"
else
  SRC="$(mktemp -d)"; mkdir -p "$SRC/opt/cangchuan" "$SRC/systemd"
  echo "== 从仓库下载组件 =="
  for f in opt/cangchuan/collect.sh opt/cangchuan/push-ro.sh opt/cangchuan/sec_score.sh \
           systemd/cangchuan-agent-ro.service; do
    curl -fsSL "$RAW/$f" -o "$SRC/$f" || { echo "  ！下载失败：$f"; exit 1; }
    echo "  ✓ $f"
  done
fi

# ── 0/5 先验节点码：不在面板白名单里，直接不装（别人拿随便一串装不上）──
echo "== 0/5 验节点码 =="
CHK=$(curl -s --max-time 15 -X POST -H "X-Push-Token: $CODE" -d '{}' "$HUB/api/node/check" 2>/dev/null)
if echo "$CHK" | grep -qE '"ok"[[:space:]]*:[[:space:]]*true'; then
  echo "  节点码有效 ✓"
else
  echo "  ❌ 这个节点码面板不认：$CHK"
  echo "     —— 节点码要先去面板生成（相当于这台机器的登录密码），不在白名单里的码一律拒收"
  exit 1
fi

echo "== 1/5 依赖检查 =="
need=""
for c in curl python3; do command -v $c >/dev/null 2>&1 || need="$need $c"; done
if [ -n "$need" ]; then
  echo "  缺依赖：$need ，尝试安装…"
  if command -v apt-get >/dev/null 2>&1; then apt-get update -qq && apt-get install -y -qq $need
  elif command -v apk >/dev/null 2>&1; then apk add --no-cache $need
  elif command -v dnf >/dev/null 2>&1; then dnf install -y $need
  elif command -v yum >/dev/null 2>&1; then yum install -y $need
  else echo "  请自己装：$need"; exit 1; fi
fi
echo "  curl / python3 OK"

echo "== 2/5 部署到 /opt/cangchuan =="
mkdir -p /opt/cangchuan
for f in collect.sh push-ro.sh sec_score.sh; do
  install -m 755 "$SRC/opt/cangchuan/$f" "/opt/cangchuan/$f"
done
echo "  3 个脚本已就位（push-ro.sh = 只上报，不接指令）"

echo "== 3/5 写配置 /etc/cangchuan.conf =="
umask 077
printf 'HUB=%s\nCODE=%s\nMODE=ro\n' "$HUB" "$CODE" > /etc/cangchuan.conf
chmod 600 /etc/cangchuan.conf
echo "  面板：$HUB"

echo "== 4/5 装服务（固定 15 秒上报，不接受任何指令）=="
install -m 644 "$SRC/systemd/cangchuan-agent-ro.service" /etc/systemd/system/cangchuan-agent-ro.service
systemctl daemon-reload
systemctl disable --now cangchuan-agent.service cangchuan-agent.timer 2>/dev/null >/dev/null || true
systemctl enable --now cangchuan-agent-ro.service
echo "  只读服务已开"

echo "== 5/5 立刻上报一次，验证 =="
/opt/cangchuan/push-ro.sh --once >/dev/null 2>&1 || true
sleep 2
if [ -f /opt/cangchuan/self.json ]; then
  python3 - <<'PY' 2>/dev/null || head -c 300 /opt/cangchuan/self.json
import json
d = json.load(open('/opt/cangchuan/self.json'))
print('    名字(hostname):', d.get('host'))
print('    系统          :', d.get('os'))
print('    IP            :', d.get('ip'))
print('    核数/内存     :', d.get('cores'), '核 /', d.get('mem_total'), 'MB')
print('    磁盘          :', str(d.get('disk_used')) + '%')
PY
else
  echo "  ！没生成 self.json —— 手动跑一次看报错： /opt/cangchuan/push-ro.sh --once"
fi

echo
echo "============================================"
echo " 装好了（只读版）。这台以【$(hostname)】出现在面板：$HUB"
echo " 它只会：每 15 秒上报一次数据 —— 收不到、也不会执行任何指令"
echo " 改名字：hostnamectl set-hostname 新名字（或面板上改）"
echo " 排查：systemctl status cangchuan-agent-ro"
echo "       /opt/cangchuan/push-ro.sh --once   # 手动跑一次"
echo "============================================"

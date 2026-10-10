# 棂海苍川 · 节点上报【只读定制版】

**只做一件事：每 15 秒采集一次、上报一次。**
不轮询指令、不接受任何命令、不被任何模式控制（没有"待机/正常/归家"）。
面板想指挥它也没有通道 —— **它从不问"有没有指令"**。

## 一条命令安装

```bash
curl -fsSL https://raw.githubusercontent.com/furrynaling-alt/cangchuan-agent-ro/main/install.sh | sudo bash -s <节点码>
```
- **节点码**在面板上生成，一台机器一个
- 想换面板地址：`... | sudo bash -s <节点码> https://panel.naling.net`

## 装完长什么样

```
名字 = 本机 hostname（想改：hostnamectl set-hostname 新名字，或面板上改名）
地区 = 面板按公网 IP 自动判
数据 = 每 15 秒一次：负载 / 内存 / 磁盘 / 流量 / 运行时长 / 安全分
```

## 和完整版的区别（一句话）

| | 只读定制版（本仓库） | 完整版 |
|---|---|---|
| 上报数据 | ✅ 固定 15 秒 | ✅ 按面板给的节奏（5s/30s/待机） |
| 收指令执行 | ❌ **完全没有这个通道** | ✅ 会轮询 `/api/agent/poll` |
| 适用 | 不想让任何人远程动它的机器 | 自己的机器，需要远程执行 |

**只读版的安全边界是"结构性的"**：它代码里只有一条 `curl … /api/agent/push`（上行），
从来没有 `/api/agent/poll`（下行）—— 不是"权限设了不给"，是**压根没有那条路**。

## 包里有什么

```
install.sh                             一键装（下载组件 → 写配置 → 装服务 → 验一次）
opt/cangchuan/collect.sh               采集 21 项
opt/cangchuan/push-ro.sh               只上报（固定 15 秒）；代码里没有 poll/exec
opt/cangchuan/sec_score.sh             安全分
systemd/cangchuan-agent-ro.service     常驻服务（Restart=always，MemoryMax=28M）
```

## 端口 / 权限

- **不开任何监听端口**，全是主动外连 443 → 面板
- 凭据只在 `/etc/cangchuan.conf`（600，仅 root 可读）

## 卸载

```bash
systemctl disable --now cangchuan-agent-ro
rm -f /etc/systemd/system/cangchuan-agent-ro.service /etc/cangchuan.conf
rm -rf /opt/cangchuan
```

## 排查

```bash
systemctl status cangchuan-agent-ro
journalctl -u cangchuan-agent-ro -n 30
/opt/cangchuan/push-ro.sh --once     # 手动跑一次
cat /opt/cangchuan/self.json         # 采到的原始数据
```

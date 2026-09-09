#!/usr/bin/env bash
# 从正在运行的 NAS 采集内核状态快照，供 localmodconfig 生成最小配置。
#
# 用法：
#   scripts/snapshot-nas.sh [ssh主机名，默认 nas]
#
# 产物（提交入库）：
#   docs/nas/lsmod.txt   当前已加载模块列表
#   docs/nas/config.gz   当前运行内核的 .config（来自 /proc/config.gz）
#
# 注意：localmodconfig 只能看到「已加载」的模块，看不到「以后会用到但此刻没加载」
# 的模块（wireguard/overlay/vxlan/nfsd 等）。因此快照前先预热，把依赖的服务和
# 模块唤醒；预热失败也没关系，scripts/keep-list.conf 会兜底强制保留。

set -euo pipefail

HOST="${1:-nas}"
REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${REPO_ROOT}/docs/nas"
SSH=(ssh -o ConnectTimeout=8 -o BatchMode=yes "$HOST")

mkdir -p "${OUT}"

echo "==> 预热 ${HOST} 上的服务与模块（用 root 连接即可，非 root 则尝试免密 sudo）"
"${SSH[@]}" '
  if [ "$(id -u)" -eq 0 ]; then SUDO=; elif sudo -n true 2>/dev/null; then SUDO="sudo -n"; else
    echo "preheat: skipped (需要 root 或免密 sudo)" >&2; exit 0
  fi
  # 本机实际启用的服务（注意：TS-564 上没有 docker）
  $SUDO systemctl start nfs-server samba-smbd syncthing 2>/dev/null || true
  # 架构需要、但只在按需时才加载的模块。刻意不加载 br_netfilter：
  # 它会改变桥上流量的 netfilter 行为，可能影响正在运行的路由 VM。
  for m in wireguard overlay vxlan ipvlan macvlan 8021q zram vfio_pci tun vhost_net vhost_vsock; do
    $SUDO modprobe "$m" 2>/dev/null || true
  done
  echo "preheat: ok"
'

echo "==> 采集 lsmod"
"${SSH[@]}" lsmod > "${OUT}/lsmod.txt"
echo "    $(wc -l < "${OUT}/lsmod.txt") 行"

echo "==> 采集 /proc/config.gz"
if ! "${SSH[@]}" 'test -r /proc/config.gz'; then
  echo "错误：目标内核未启用 CONFIG_IKCONFIG_PROC，无法导出 .config" >&2
  exit 1
fi
"${SSH[@]}" 'zcat /proc/config.gz' | gzip -9 > "${OUT}/config.gz"
echo "    $(zcat "${OUT}/config.gz" | wc -l) 行"

echo "==> 内核版本：$("${SSH[@]}" uname -r)"
echo "完成。接着运行：nix build .#genConfig 然后覆盖 generated/ 下的配置。"

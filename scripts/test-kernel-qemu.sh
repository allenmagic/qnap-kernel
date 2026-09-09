#!/usr/bin/env bash
# 用 QEMU + router-image release 的 rootfs 实测本仓库构建的内核（交互式）。
#
# 用法:
#   scripts/test-kernel-qemu.sh [alpine|gentoo] [--kernel PATH] [--tag TAG]
#
#   --kernel PATH   指定内核 bzImage（默认 nix build .#packages.x86_64-linux.kernel）
#   --tag TAG       release tag（默认自动探测最新 router-vm-*）
#
# 说明:
#   - 本内核是**宿主**内核，VIRTIO_BLK 等是模块；而 router rootfs 无 initramfs、
#     无 /lib/modules，用 virtio 挂盘会 "Unable to mount root"。故改用内核里
#     built-in 的 AHCI 挂盘（q35 自带控制器，磁盘 = /dev/sda）。
#   - qemu 的 readonly=on 与 if=ide 组合会报 "Block node is read-only"，
#     所以用可写临时副本，退出后删除，不污染缓存镜像。
#   - 串口直连当前终端，登录 root/root；退出 qemu：Ctrl-A 然后 X。
#   - 不挂网卡（本内核无内置 NIC 驱动）——openrc 的 network 相关服务会失败，
#     属预期，不影响登录。
#   - gentoo 镜像的 /etc/fstab 写的是 /dev/vda，AHCI 下会多一条挂载失败日志，
#     不影响启动到 login。
#
# 依赖: curl sha256sum python3 qemu-system-x86_64
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REPO_SLUG="allenmagic/router-image"
ASSETS_DIR="${REPO_ROOT}/build/test-assets"
TAG=""
KERNEL=""
DISTRO="alpine"

log() { printf '[test] %s\n' "$*" >&2; }
die() { printf '[test] 错误: %s\n' "$*" >&2; exit 1; }

while [ $# -gt 0 ]; do
    case "$1" in
        -h|--help) sed -n '2,/^set -/p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
        --kernel) KERNEL="${2:?}"; shift 2 ;;
        --tag)    TAG="${2:?}"; shift 2 ;;
        alpine|gentoo) DISTRO="$1"; shift ;;
        *) die "未知参数: $1" ;;
    esac
done

command -v qemu-system-x86_64 >/dev/null || die "未找到 qemu-system-x86_64"
mkdir -p "$ASSETS_DIR"

# ---------- 内核 ----------
if [ -z "$KERNEL" ]; then
    log "构建内核（已缓存则秒回）..."
    KERNEL="$(nix build --extra-experimental-features 'nix-command flakes' \
        --no-link --print-out-paths "${REPO_ROOT}#packages.x86_64-linux.kernel" | tail -1)/bzImage"
fi
[ -f "$KERNEL" ] || die "内核不存在: $KERNEL"
log "内核: $KERNEL（版本 $(basename "$(dirname "$KERNEL")" | sed 's/.*-linux-//')）"

# ---------- 镜像 ----------
if [ -z "$TAG" ]; then
    log "探测最新 release ..."
    TAG="$(python3 - "https://api.github.com/repos/${REPO_SLUG}/releases?per_page=50" <<'PY'
import json, sys, urllib.request
req = urllib.request.Request(sys.argv[1], headers={"User-Agent": "qnap-kernel-test"})
with urllib.request.urlopen(req, timeout=30) as r:
    for rel in json.load(r):
        if rel.get("tag_name", "").startswith("router-vm-"):
            print(rel["tag_name"]); break
PY
)" || die "探测失败，请用 --tag 指定"
fi
BASE="https://github.com/${REPO_SLUG}/releases/download/${TAG}"
log "release: ${TAG}"

SUMS="${ASSETS_DIR}/SHA256SUMS.${TAG}"
[ -f "$SUMS" ] || curl -sSLf -o "$SUMS" "$BASE/SHA256SUMS"
IMG="${ASSETS_DIR}/${DISTRO}-rootfs.qcow2"
want="$(awk -v n="${DISTRO}-rootfs.qcow2" '$2==n {print $1}' "$SUMS")"
[ -n "$want" ] || die "SHA256SUMS 里没有 ${DISTRO}-rootfs.qcow2"
if [ ! -f "$IMG" ] || [ "$(sha256sum "$IMG" | awk '{print $1}')" != "$want" ]; then
    log "下载 ${DISTRO}-rootfs.qcow2 ..."
    rm -f "$IMG"
    curl -sSLf --retry 5 --retry-all-errors -o "$IMG" "$BASE/${DISTRO}-rootfs.qcow2"
    [ "$(sha256sum "$IMG" | awk '{print $1}')" = "$want" ] || die "sha256 校验失败（下载被截断？）"
fi
log "镜像: $IMG"

# ---------- 启动 ----------
SCRATCH="$(mktemp --suffix=.qcow2)"
trap 'rm -f "$SCRATCH"' EXIT
cp "$IMG" "$SCRATCH"

log "启动 ${DISTRO}：登录 root/root，退出 Ctrl-A 然后 X"
exec qemu-system-x86_64 -machine q35 -m 512 -smp 2 -no-reboot \
    -kernel "$KERNEL" \
    -append "console=ttyS0 root=/dev/sda rootfstype=ext4 ro" \
    -drive "file=$SCRATCH,if=ide,format=qcow2" \
    -nographic

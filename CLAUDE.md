# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

This is a NixOS kernel customization project for the QNAP TS-564 NAS (Intel Celeron N5095) running a complex multi-layer architecture:

**Architecture:**
```
QNAP TS-564 (NixOS Host)
├─ NAS 功能 (存储、NFS、SMB)
├─ cloud-hypervisor VM (Router VM)
│  └─ Alpine/Gentoo + 自定义内核 (路由器功能)
└─ Nix Container
   └─ VPN + VRRP 浮动网关
```

**Key Features:**
- Linux LTS kernel (6.18.x) - 长期稳定支持
- **配置来源是 NAS 实机**：`.config` 由 `make localmodconfig` 从 NAS 当前运行状态裁剪而来（详见 `docs/localmodconfig-guide.md`）
- Highly optimized with Tremont-specific compiler flags
- Integration with the external qnap8528 hardware control module
- Full KVM virtualization support (cloud-hypervisor)
- Advanced networking (routing, NAT, VPN, VRRP)
- Container support (Nix containers with network namespace isolation)
- GitHub Actions CI/CD for automated kernel builds with binary caching

## Build Commands

### Local Development

重新采集 NAS 快照并生成最小配置（配置有变更时必做）：
```bash
scripts/snapshot-nas.sh                 # 从 NAS 抓 lsmod + /proc/config.gz 到 docs/nas/
nix build .#genConfig --print-out-paths # 沙盒内跑 localmodconfig + keep-list + 自校验
cp /nix/store/...-nas-localmodconfig-<版本>/config generated/nas-<版本>.config
```

Build the custom kernel:
```bash
nix build .#packages.x86_64-linux.kernel --print-out-paths --verbose

# Check kernel version
nix eval .#packages.x86_64-linux.kernel.version
```

用 QEMU + router-image release 的 rootfs 实测内核（串口直连，登录 root/root）：
```bash
scripts/test-kernel-qemu.sh alpine     # 或 gentoo
```
注意：本内核是宿主内核，`VIRTIO_BLK` 等是模块，所以用 built-in 的 AHCI 挂盘
（`root=/dev/sda`）。覆盖内核启动/SATA-AHCI/ext4/到 login；不覆盖 KVM/vhost/网络。

Build and test the entire NixOS module configuration:
```bash
nix build .#nixosModules.default
```

Evaluate the flake to check for syntax errors:
```bash
nix flake check
```

Update flake inputs (nixpkgs and qnap8528):
```bash
nix flake update
```

### CI/CD

`.github/workflows/build-kernel.yml`（push/PR/`workflow_dispatch`）依次执行：
校验 keep-list（`nix build .#genConfig`）→ `nix flake check --no-build` →
编译内核（`out`/`dev`/`modules`）→ 编译 `packages.qnap8528-module`，
并由 cachix-action 的 post-build hook 自动推送到 **`qnap-kernel`** 缓存。

- 需要仓库 secret `CACHIX_AUTH_TOKEN`（fork 的 PR 没有，只读不推）
- 缓存名在三处必须一致：`flake.nix` 的 `nixConfig`、workflow 的 `name`、消费端 substituter
- 消费端（NAS）引用方式与命中前提见 `README.md` 的 CI/CD 一节

## Architecture

### Kernel Customization Strategy

配置**不是手工维护的选项列表**，而是从 NAS 实机状态裁剪出来的 `.config`：

1. **配置来源**：`generated/nas-<版本>.config` —— 由 `scripts/snapshot-nas.sh`
   采集 NAS 的 `/proc/config.gz` + `lsmod`，再经 `nix build .#genConfig`
   跑 `make localmodconfig` 并叠加 `scripts/keep-list.conf` 得到。
   完整流程见 `docs/localmodconfig-guide.md`。

2. **构建方式**：`flake.nix` 用 `pkgs.linuxKernel.manualConfig` 直接喂这份原始
   `.config`（**不是** `structuredExtraConfig` / `autoModules` 通道）。
   源码骨架（版本、`src`、`kernelPatches`、`modDirVersion`）取自
   `linuxKernel.kernels.linux_default`。

3. **编译器优化层**（`stdenv` override）：
   - `-march=tremont` / `-mtune=tremont`：针对 N5095 Tremont 微架构
   - `-O2`：稳定性优先于激进优化
   - `-pipe`、`-fno-semantic-interposition`

4. **keep-list**（`scripts/keep-list.conf`）：localmodconfig 只能看到「已加载」的模块，
   必须用它把快照时未加载但必需的选项（wireguard/overlay/nfsd/KVM/...）拉回来。
   生成器会逐项自校验，写错符号名或 bool/tristate 类型会直接构建失败。

> ⚠️ 升级 nixpkgs 后必须重新执行 3.1/3.2 的采集与生成，否则新内核新增的必选项会缺失。

### Key Dependencies

The kernel configuration has a **critical dependency chain** for the qnap8528 module:
- `I2C_I801`: Intel SMBus controller driver (required for MCU communication)
- `PINCTRL_JASPERLAKE`: GPIO pinctrl for Jasper Lake platform
- These must be `yes` (built-in), not `module`, to satisfy qnap8528 symbol dependencies

### Module Integration Flow

```
flake.nix
  ├─> customKernel (linuxKernel.manualConfig, configfile = generated/nas-<版本>.config)
  ├─> kernelPackages = linuxPackagesFor customKernel
  └─> nixosModules.default
       └─> modules/kernel-custom.nix（kernelPackages 由 flake 作为参数传入）
            ├─> boot.kernelPackages = kernelPackages
            └─> boot.extraModulePackages
                 └─> qnap8528 (from external flake, compiled against custom kernel)
```

The qnap8528 module is:
- Fetched from external flake input `github:allenmagic/qnap8528`
- Cross-compiled against the custom kernel via `.override { kernel = config.boot.kernelPackages.kernel; }`
- Forced to load early via `boot.kernelModules`
- Configured with `skip_hw_check=1` parameter

### Initrd Optimization

`boot.initrd.availableKernelModules` is forced to minimal set:
- `xhci_pci`: USB boot support
- `ahci`: SATA boot support
- `sdhci_pci`: eMMC boot support

This eliminates probe delays for unused hardware during boot.

⚠️ TS-564 has **no NVMe hardware**（lspci 无 NVMe 控制器，根分区在 `/dev/sda2` SATA），
所以 `BLK_DEV_NVME=n` 且列表里不能出现 `nvme`（模块不存在会拖累 initrd 构建）。
若将来加装 M.2，需同时把 `m BLK_DEV_NVME` 加回 `scripts/keep-list.conf` 并重新生成配置。

## Hardware-Specific Configuration

### TS-564 Critical Drivers (all built-in)

- **Storage**: AHCI (`SATA_AHCI`), MMC/eMMC (`MMC_SDHCI`, `MMC_BLOCK`)
- **Network**: Intel i225/i226 2.5GbE (`IGC`)
- **Graphics**: Intel UHD for QuickSync transcoding (`DRM_I915`)
- **Audio**: Intel HDA + SOF (Sound Open Firmware) stack for HDMI audio
- **Monitoring**: `SENSORS_CORETEMP` (CPU temp), `SENSORS_IT87` (board sensor chip)

### Power Management

- `INTEL_IDLE`: Deep C-state support for idle power savings
- `X86_INTEL_PSTATE`: Modern Intel P-state frequency scaling
- `NO_HZ_IDLE`: Tickless idle for reduced power consumption
- `CPU_FREQ_GOV_POWERSAVE`: Default to powersave governor

## Development Workflow

When modifying the kernel configuration:

1. **Add new features**: Edit `structuredExtraConfig` in `modules/kernel-custom.nix`
2. **Test locally**: Run `nix build .#packages.x86_64-linux.kernel`
3. **Verify size impact**: Check output size with `du -sh result/`
4. **Test on hardware**: Deploy to TS-564 and verify boot + functionality
5. **Update qnap8528 dependency**: If kernel symbols change, may need to update external module

### Critical: Preserve Essential Features When Pruning

**⚠️ When optimizing/pruning the kernel, ALWAYS preserve these features:**

- **USB Support** (`USB_SUPPORT`, `USB_XHCI_HCD`, `HID`):
  - Required for USB peripherals (keyboards, mice, storage devices)
  - USB 3.0 ports on TS-564
  - Essential for hardware management and recovery

- **HDMI/Display** (`DRM_I915`):
  - Intel UHD Graphics driver
  - Required for HDMI output
  - Critical for hardware transcoding (QuickSync) in Jellyfin/Plex
  - Powers media server functionality

- **Audio Stack** (complete chain):
  - `SOUND`, `SND`, `SND_SOC` (base sound subsystem)
  - `SND_HDA_INTEL` (Intel HDA codec)
  - `SND_SOC_SOF_*` (Sound Open Firmware stack)
  - `SND_SOC_INTEL_SOUNDWIRE_LINK_BASELINE`
  - Required for HDMI audio output
  - Used for media playback and streaming

- **Virtualization Support** (⚠️ CRITICAL - Router VM 依赖):
  - `KVM`, `KVM_INTEL` (Intel VT-x support)
  - `VHOST_NET`, `VHOST_VSOCK` (cloud-hypervisor 高性能网络)
  - `VIRTIO_*` (complete virtio driver stack)
  - Required for cloud-hypervisor Router VM

- **Advanced Networking** (⚠️ CRITICAL - Router + VPN 功能):
  - `TUN`, `VETH`, `BRIDGE`, `MACVLAN`, `IPVLAN` (virtual networking)
  - `WIREGUARD` (VPN support)
  - `IP_ADVANCED_ROUTER`, `IP_MULTIPLE_TABLES` (policy routing)
  - `NF_NAT`, `NETFILTER` (NAT and firewall)
  - `IP_MULTICAST`, `IP_MROUTE` (VRRP multicast support)
  - Required for Router VM and VPN gateway container

- **Container Support** (⚠️ CRITICAL - Nix Container):
  - `NAMESPACES`, `NET_NS`, `USER_NS`, `PID_NS` (isolation)
  - `CGROUPS`, `MEMCG`, `BLK_CGROUP` (resource control)
  - `OVERLAY_FS` (container storage)
  - Required for VPN + VRRP gateway container

These features must be covered by `scripts/keep-list.conf`（否则 localmodconfig 会按快照
状态把它们裁掉）。改动 keep-list 后跑 `nix build .#genConfig`，自校验会报出未生效项。

## Reference: Active Kernel Modules

`docs/nas/lsmod.txt` 是最近一次从生产 TS-564 采集的已加载模块列表（`scripts/snapshot-nas.sh`
的产物），`docs/lsmod-reference.txt` 是更早的一份人工参考，两者都只作对照：

- 列表里的模块，其对应配置项应保留在 `generated/*.config` 中
- 增加新硬件支持时，先看它是否出现在这份列表里
- 系统升级或硬件变化后重新采集

重新采集（同时会刷新配置基线）：
```bash
scripts/snapshot-nas.sh
```

## Multi-Layer Architecture Specifics

### cloud-hypervisor VM (Router)
The Router VM runs on cloud-hypervisor with Alpine/Gentoo and a custom kernel. Host kernel requirements:
- vhost-net for high-performance networking
- virtio drivers for all device types
- TAP/TUN for VM networking
- Optional: VFIO for network card passthrough

### Nix Container (VPN Gateway)
The VPN gateway container provides:
- WireGuard or OpenVPN termination
- VRRP (keepalived) for floating IP
- Network namespace isolation

**Network topology**: Physical NIC → Bridge → Router VM + VPN Container

## Important Notes

- **Cachix setup**: 缓存名 `qnap-kernel` 已落地在三处（`flake.nix` nixConfig、workflow `name`、NAS substituter）；仍需把 Cachix 面板的 Public key 填进 `flake.nix` 的 `extra-trusted-public-keys` 占位符，并配 `CACHIX_AUTH_TOKEN` secret
- **Symbol dependencies**: When adding kernel features, check if qnap8528 module needs corresponding changes
- **Build time**: Full kernel build takes ~20-40 minutes on GitHub Actions runners
- **Testing**: Always test kernel boots on actual hardware before deploying to production NAS
- **Config regeneration**: 升级 nixpkgs / 换内核版本后，必须重跑 `scripts/snapshot-nas.sh` + `nix build .#genConfig`，并把新配置提交为 `generated/nas-<新版本>.config`
- **Module reference**: Keep `docs/nas/lsmod.txt` updated to reflect actual hardware usage
- **Virtualization**: Ensure KVM and vhost modules are loaded before starting VMs
- **Networking**: IP forwarding must be enabled in sysctl for routing functionality

## Reference Documentation

See `docs/` directory for detailed guides:
- `kernel-version-guide.md` - Kernel version selection (LTS vs latest)
- `multi-layer-architecture.md` - Complete architecture and networking setup
- `advanced-optimizations.md` - Compiler flags, performance tuning options
- `localmodconfig-guide.md` - **配置生成流程（必读）**：快照 → localmodconfig → keep-list → manualConfig
- `config-analysis.md` - Analysis of current hardware and loaded modules
- `commands-reference.md` - All commonly used commands
- `SUMMARY.md` - 历史草稿，部分内容（如 kernel-optimized-final.nix）已废弃，以本文件与 localmodconfig-guide.md 为准

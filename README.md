# qnap-kernel

为 QNAP TS-564 NAS 定制的 Linux 6.18.50 LTS 内核，使用 Nix flakes 构建。

## 硬件目标

- **设备**: QNAP TS-564 NAS
- **CPU**: Intel Celeron N5095 (Tremont 微架构)
- **架构**: x86_64

## 特性

- **LTS 内核**: Linux 6.18.50 (长期支持版本)
- **内核标识**: `uname -r` 显示 `6.18.50-QNAP-TS-564`（`CONFIG_LOCALVERSION`，见 `flake.nix` 的 `localVersion`；`modDirVersion` 必须同步）
- **配置来自实机**: `.config` 由 `make localmodconfig` 从 NAS 当前运行状态裁剪生成，模块数 7107 → 280
- **CPU 优化**: 针对 Tremont 的编译器优化 (`-march=tremont -mtune=tremont`)
- **虚拟化**: 完整的 KVM/QEMU 支持，包含 VirtIO 驱动
- **存储**: SATA (AHCI)、MMC/eMMC、软 RAID/LVM 支持（TS-564 无 NVMe，已按需关闭）
- **网络**: Intel i225/i226 2.5GbE (IGC 驱动)
- **电源管理**: Intel P-state、tickless idle、CPU 频率调节
- **可重现构建**: 使用 Nix flakes 声明式配置

## 快速开始

### 前置要求

- 启用 flakes 的 Nix
- 20+ GB 可用磁盘空间
- 推荐多核 CPU（构建使用 `-j20`）

### 生成配置并构建内核

```bash
# 1. 从 NAS 采集当前运行状态（lsmod + /proc/config.gz）
scripts/snapshot-nas.sh

# 2. 沙盒内跑 localmodconfig + keep-list，生成最小 .config
nix build .#genConfig --print-out-paths

# 3. 落盘（文件名必须与 flake 的内核版本一致）
cp /nix/store/...-nas-localmodconfig-<版本>/config generated/nas-<版本>.config

# 4. 构建内核
nix build .#packages.x86_64-linux.kernel --print-out-paths

# 检查内核版本
nix eval .#packages.x86_64-linux.kernel.version

# 验证 flake 语法
nix flake check
```

配置生成流程与 keep-list 写法见 [`docs/localmodconfig-guide.md`](docs/localmodconfig-guide.md)。

### 实测内核（QEMU）

拿 router-image 最新 release 的 `rootfs.qcow2` 当测试根文件系统，用本仓库内核启动，
串口直连终端，登录 `root/root`：

```bash
scripts/test-kernel-qemu.sh alpine     # 或 gentoo
```

我们的内核是**宿主**内核（`VIRTIO_BLK` 等是模块），所以用内核里 built-in 的
AHCI 挂盘（`root=/dev/sda`）。覆盖：内核启动、SATA/AHCI、ext4、用户态到 login；
不覆盖 KVM/vhost/网络（宿主侧能力，需内核当宿主时才能测）。

### 更新依赖

```bash
# 更新 nixpkgs 和 qnap8528 输入
nix flake update
```

## 项目结构

```
.
├── flake.nix                      # 主 flake：manualConfig 内核 + genConfig 生成器
├── flake.lock                     # 锁定的依赖版本
├── modules/
│   └── kernel-custom.nix          # NixOS 模块（boot.kernelPackages / qnap8528 / initrd）
├── scripts/
│   ├── snapshot-nas.sh            # 从 NAS 采集 lsmod + /proc/config.gz
│   ├── keep-list.conf             # 强制保留/关闭的配置项清单
│   └── test-kernel-qemu.sh        # 用 QEMU + router 镜像实测内核
├── generated/
│   └── nas-6.18.50.config         # 裁剪后的最终 .config（构建输入，必须提交）
├── docs/
│   ├── nas/{lsmod.txt,config.gz}  # 最近一次采集的原始快照
│   ├── localmodconfig-guide.md    # 配置生成流程（必读）
│   └── *.md / *.txt               # 架构、优化、硬件参考
└── .github/workflows/
    └── build-kernel.yml           # CI/CD 流水线
```

## 架构设计

配置策略是**「实机快照 + 离线裁剪」**，而不是手工维护选项列表：

1. **采集**: `scripts/snapshot-nas.sh` 从 NAS 抓 `lsmod` 与 `/proc/config.gz`
2. **裁剪**: `nix build .#genConfig` 在沙盒内跑 `make localmodconfig`，
   把 7107 个模块砍到 280 个，再叠加 `scripts/keep-list.conf` 拉回
   快照时未加载但必需的选项（wireguard/overlay/nfsd/KVM/...），最后逐项自校验
3. **构建**: `flake.nix` 用 `pkgs.linuxKernel.manualConfig` 直接喂
   `generated/nas-6.18.50.config`，源码骨架取自 `linux_default`，
   编译器优化为 `-march=tremont -mtune=tremont -O2 -pipe`

> ⚠️ nixpkgs 的 `autoModules = true` **不是** localmodconfig（它只是把每个可模块化
> 的选项一律设为 `m`）。本项目因此绕开 `structuredExtraConfig` 通道，直接喂原始 `.config`。

关键配置亮点：

- **VirtIO 支持**: 完整的 virtio 栈用于 QEMU/KVM 虚拟化
- **存储驱动**: AHCI、SCSI、MMC 内置（NVMe 无硬件，关闭）
- **文件系统**: EXT4、BTRFS、overlay、tmpfs
- **网络功能**: 高级路由、NAT、网桥、VPN (WireGuard)
- **容器支持**: 完整的命名空间和 cgroup 支持

## CI/CD

`.github/workflows/build-kernel.yml` 在 push / PR / `workflow_dispatch` 时：

1. 校验 keep-list 对当前内核源码仍全部生效（`nix build .#genConfig`）
2. `nix flake check --no-build`
3. 编译内核（`out` + `dev` + `modules` 三个输出）
4. 编译 qnap8528 外部模块（对本内核交叉编译）
5. 通过 cachix-action 的 post-build hook 自动推送到 **`qnap-kernel`** 缓存

### 首次配置

1. 在 <https://app.cachix.org> 创建缓存 `qnap-kernel`（或改成本仓库三处一致的其它名字）。
2. 仓库 **Settings → Secrets and variables → Actions** 添加 `CACHIX_AUTH_TOKEN`（Cachix 的 write token）。
3. 把 Cachix 面板上的 **Public key** 填到两处占位：
   - 本仓库 `flake.nix` 的 `nixConfig.extra-trusted-public-keys`
   - 消费端（NAS）`nix.settings.trusted-public-keys`

### 消费端（NAS）如何引用

```nix
# qnap-nixos-nas/modules/system/nix-settings.nix
nix.settings = {
  substituters = [
    "https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store"
    "https://cache.nixos.org"
    "https://qnap-kernel.cachix.org"
  ];
  trusted-public-keys = [
    "cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY="
    "qnap-kernel.cachix.org-1:<上面复制的公钥>"
  ];
};
```

```nix
# qnap-nixos-nas/flake.nix：加 input（不要 follows nixpkgs，
# 否则本地求值出的 derivation 与 CI 不一致，缓存命不中）
qnap-kernel.url = "github:allenmagic/qnap-kernel";
```

然后在宿主机配置里 import `qnap-kernel.nixosModules.kernel`（只换内核 + 注入本仓库
构建的 qnap8528；宿主已有 `hardware.qnap8528.enable`，用 `nixosModules.default`
会重复挂 qnap8528）。之后 NAS 上 `nix flake update qnap-kernel && nixos-rebuild boot`
即可直接从缓存拉取。

> 缓存命中的前提：NAS 求值出的 derivation 与 CI 完全一致 —— 同 flake rev、同
> `nixpkgs`（本仓库自带的 lock，**不要** follows 宿主的 nixpkgs）、`boot.kernelPatches`
> 为空、`boot.kernel.randstructSeed` 为默认值。

### qnap8528 也从缓存替换

`nixosModules.kernel` 在包集合上 extend 出 `qnap8528`（用**本仓库**的 qnap8528
input，`kernel = self.kernel`），使其与 CI 的 `packages.qnap8528-module` 是同一个
derivation。效果（NAS 上实测 `nixos-rebuild dry-build`）：

- qnap8528 从「will be built」变成「will be fetched」——直接拉 `.ko`，不再本地编译
- 因此 `kernel.dev`（622MB store / 593MB 下载）**不再是构建输入**，NAS 下载量从
  432MB 降到 28.8MB

⚠️ 副作用：宿主 `qnap-nixos-nas` 的 qnap8528 input rev 不再影响实际编出的 `.ko`
（以本仓库 `flake.lock` 为准）。升级 qnap8528 请改本仓库的 input。

## 与 qnap8528 集成

此内核设计用于配合 [qnap8528 硬件控制模块](https://github.com/allenmagic/qnap8528) 使用，该模块提供：

- IT8528 MCU 通信 (I2C)
- GPIO 控制（LED、按钮）
- 硬件监控（温度、风扇）

内核确保 `I2C_I801` 和 `PINCTRL_JASPERLAKE` 内置编译，以满足 qnap8528 的符号依赖。

## 多层架构支持

此内核支持复杂的 NAS 架构：

```
QNAP TS-564 (NixOS 宿主机)
├─ NAS 功能（存储、NFS、SMB）
├─ cloud-hypervisor 虚拟机（路由器 VM）
│  └─ Alpine/Gentoo + 自定义内核
└─ Nix 容器
   └─ VPN + VRRP 浮动网关
```

必需功能：
- **KVM/VirtIO**: 用于 cloud-hypervisor 路由器 VM
- **高级网络**: 用于路由、NAT、策略路由
- **容器支持**: 用于隔离的 VPN 网关

## 开发状态

### ✅ 已完成

- [x] Nix flake 设置与 LTS 内核选择
- [x] Tremont CPU 优化
- [x] **localmodconfig 实机配置生成**（快照脚本 + genConfig 生成器 + keep-list 自校验）
- [x] VirtIO 驱动配置
- [x] 存储和文件系统支持
- [x] GitHub 仓库设置
- [x] CI/CD 工作流框架

### 🔧 进行中

- [ ] QEMU 启动测试（virtio 驱动验证）
- [ ] Cachix 二进制缓存配置
- [ ] 硬件部署到 TS-564

### 📋 计划中

- [ ] 内核编译 + 上机启动验证（当前仅验证到「能求值/能实例化」）
- [ ] 性能基准测试
- [ ] 文档改进

## 已知问题

1. **Cachix 工作流失败**: GitHub Actions 工作流需要 `CACHIX_AUTH_TOKEN` secret 和有效的缓存名。
2. **QEMU 测试**: VirtIO 块设备检测需要验证。

## 贡献

这是个人 NAS 内核配置项目。如有问题或建议，请提交 GitHub issue。

## 许可证

本项目配置按原样提供仅供参考。Linux 内核本身使用 GPL-2.0 许可证。

## 参考资料

- [Linux Kernel](https://kernel.org/)
- [NixOS](https://nixos.org/)
- [QNAP TS-564](https://www.qnap.com/zh-cn/product/ts-564)
- [Intel Tremont 微架构](https://en.wikichip.org/wiki/intel/microarchitectures/tremont)

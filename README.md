# qnas-kernel

为 QNAP TS-564 NAS 定制的 Linux 6.18.50 LTS 内核，使用 Nix flakes 构建。

## 硬件目标

- **设备**: QNAP TS-564 NAS
- **CPU**: Intel Celeron N5095 (Tremont 微架构)
- **架构**: x86_64

## 特性

- **LTS 内核**: Linux 6.18.50 (长期支持版本)
- **CPU 优化**: 针对 Tremont 的编译器优化 (`-march=tremont -mtune=tremont`)
- **虚拟化**: 完整的 KVM/QEMU 支持，包含 VirtIO 驱动
- **存储**: SATA (AHCI)、NVMe、MMC/eMMC 支持
- **网络**: Intel i225/i226 2.5GbE (IGC 驱动)
- **电源管理**: Intel P-state、tickless idle、CPU 频率调节
- **可重现构建**: 使用 Nix flakes 声明式配置

## 快速开始

### 前置要求

- 启用 flakes 的 Nix
- 20+ GB 可用磁盘空间
- 推荐多核 CPU（构建使用 `-j20`）

### 构建内核

```bash
# 构建自定义内核
nix build .#packages.x86_64-linux.kernel --print-out-paths

# 检查内核版本
nix eval .#packages.x86_64-linux.kernel.version

# 构建 NixOS 模块
nix build .#nixosModules.default

# 验证 flake 语法
nix flake check
```

### 更新依赖

```bash
# 更新 nixpkgs 和 qnap8528 输入
nix flake update
```

## 项目结构

```
.
├── flake.nix                      # 主 Nix flake 配置
├── flake.lock                     # 锁定的依赖版本
├── modules/
│   ├── kernel-custom.nix          # 基础内核配置
│   ├── kernel-optimized-final.nix # 生产环境内核配置
│   └── kernel-package.nix         # 内核包构建器
├── docs/
│   ├── CLAUDE.md                  # AI 助手指令
│   ├── kernel-version-guide.md    # 版本选择说明
│   ├── multi-layer-architecture.md # 多层架构文档
│   ├── localmodconfig-guide.md    # 最小化配置指南
│   └── *.txt                      # 硬件参考数据
└── .github/workflows/
    └── build-kernel.yml           # CI/CD 流水线
```

## 架构设计

内核使用**四层配置策略**：

1. **内核版本**: `linuxKernel.kernels.linux_default` (6.18.50 LTS)
2. **编译器优化**: Tremont 专用 stdenv，使用 `-march=tremont -mtune=tremont -O2`
3. **特性裁剪**: 禁用未使用的子系统（无线、蓝牙）
4. **精细配置**: 通过 `structuredExtraConfig` 进行 CPU 优化和静态驱动编译

关键配置亮点：

- **VirtIO 支持**: 完整的 virtio 栈用于 QEMU/KVM 虚拟化
- **存储驱动**: AHCI、NVMe、SCSI、MMC 内置
- **文件系统**: EXT4、BTRFS、overlay、tmpfs
- **网络功能**: 高级路由、NAT、网桥、VPN (WireGuard)
- **容器支持**: 完整的命名空间和 cgroup 支持

## CI/CD

GitHub Actions 在推送到 `main` 分支时自动构建内核。工作流特性：

- 运行在 `ubuntu-latest` runner 上
- 使用 Cachix 进行二进制缓存（需要 `CACHIX_AUTH_TOKEN` secret）
- 可通过 `workflow_dispatch` 手动触发

⚠️ **注意**: `.github/workflows/build-kernel.yml` 中的 Cachix 缓存名 `your-qnap-cache` 需要替换为你的实际缓存名。

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
- [x] VirtIO 驱动配置
- [x] 存储和文件系统支持
- [x] GitHub 仓库设置
- [x] CI/CD 工作流框架

### 🔧 进行中

- [ ] QEMU 启动测试（virtio 驱动验证）
- [ ] Cachix 二进制缓存配置
- [ ] 硬件部署到 TS-564

### 📋 计划中

- [ ] `localmodconfig` 优化以最小化内核大小
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

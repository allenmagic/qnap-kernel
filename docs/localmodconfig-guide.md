# 从 NAS 实机状态生成最小内核配置（localmodconfig）

本文档描述本项目**实际采用**的配置生成流程：内核 `.config` 由 NAS 当前运行状态
经 `make localmodconfig` 裁剪而来，而不是手工维护 `structuredExtraConfig`。

## 1. 原理与边界

`make localmodconfig` 做的是**减法**：读取一份已有的 `.config`，对照 `lsmod`
把「编译成了模块、但当前没加载」的选项改成 `n`，其余保持不动。

因此有两条硬性前提：

1. **必须先有一份基线 `.config`**——本项目用 NAS 的 `/proc/config.gz`。
   空树直接跑 `make localmodconfig` 没有裁剪基线。
2. **它只能看到「已加载」的模块**——快照时刻没加载、但以后会用到的功能
   （`wireguard`、`overlay`、`vxlan`、`nfsd`、`br_netfilter` 等）会被误删。
   所以必须在生成后叠加 `scripts/keep-list.conf` 兜底。

> ⚠️ 常见误解：nixpkgs 的 `autoModules = true` **不是** localmodconfig。
> 它只是把 Kconfig 里每个「可编译为模块」的提问一律回答 `m`
> （见 `pkgs/os-specific/linux/kernel/generate-config.pl`），完全不读 `lsmod`，
> 效果与最小化相反。本项目因此不走 `structuredExtraConfig` 通道，而是直接
> 用 `pkgs.linuxKernel.manualConfig` 喂原始 `.config`。

## 2. 流水线

```
NAS（运行中）                 开发机 / CI                      内核构建
────────────────────────────────────────────────────────────────────────────
lsmod ─────┐
/proc/config.gz ─┴─► docs/nas/{lsmod.txt,config.gz}
                          │  nix build .#genConfig
                          │  （沙盒内 make localmodconfig + keep-list + 自校验）
                          ▼
                    generated/nas-<版本>.config  ──►  linuxKernel.manualConfig
                    （提交入库）                      （flake.nix，原样喂入）
```

三个产物各自的作用：

| 路径 | 说明 | 何时更新 |
|---|---|---|
| `docs/nas/lsmod.txt` | 快照时刻的已加载模块 | 每次重新采集 |
| `docs/nas/config.gz` | 快照时刻运行内核的 `.config` | 每次重新采集 |
| `generated/nas-<版本>.config` | 裁剪后的最终配置，**构建用的就是它** | 每次采集或升级内核后 |

## 3. 操作步骤

### 3.1 采集 NAS 快照

```bash
scripts/snapshot-nas.sh [ssh主机名，默认 nas]
```

脚本会先启动本机实际启用的服务并 `modprobe` 一批「按需才加载」的模块来「预热」
（用 root 连接即可；非 root 则尝试免密 sudo，都不可用只告警不影响），
然后抓取 `lsmod` 与 `/proc/config.gz`。注意 TS-564 上**没有 docker**，
脚本刻意不加载 `br_netfilter`（会改变桥上流量的 netfilter 行为，可能影响在跑的路由 VM）。

> 预热只是锦上添花：即使完全跳过，`scripts/keep-list.conf` 也会把必需的选项拉回来。

### 3.2 生成最小配置

```bash
nix build .#genConfig            # 产物在 store 里，路径由命令输出
# 或指定输出到仓库
nix build .#genConfig --print-out-paths
```

生成器在沙盒内执行：

1. `gunzip docs/nas/config.gz > .config`，`make olddefconfig`
   （把 NAS 的 6.18.x 配置升级到当前 flake 的内核版本）
2. `make LSMOD=docs/nas/lsmod.txt localmodconfig`
3. 逐行应用 `scripts/keep-list.conf`
4. `make olddefconfig` 修正依赖
5. **自校验**：逐项核对 keep-list 是否真的生效，任何一项没生效就让构建失败
   （防止写错符号名或 bool/tristate 类型被 Kconfig 静默丢弃）

### 3.3 落盘并提交

```bash
cp /nix/store/...-nas-localmodconfig-<版本>/config generated/nas-<版本>.config
git add generated/ && git commit
```

`flake.nix` 里的 `nasConfig` 会按 `generated/nas-${内核版本}.config` 自动找文件，
所以**升级内核版本后必须重新生成并改文件名**，否则求值直接报文件不存在。

## 4. keep-list 写法

`scripts/keep-list.conf` 每行 `<y|m|n> 选项名`（选项名不带 `CONFIG_` 前缀）：

```
y KVM          # 强制内置（bool 选项只能用 y）
m WIREGUARD    # 强制保留为模块（仅 tristate 有效）
n NO_HZ_FULL   # 强制关闭（处理 choice 冲突）
```

注意两点：

- **bool 选项不能用 `m`**，否则 `scripts/config` 写入 `=m` 后会被 Kconfig 判为非法并丢弃。
- **tristate 的实际取值受依赖上限约束**：若某依赖是 `m`，该选项最多也只能是 `m`。
  例如 `IGC` 依赖 `PTP_1588_CLOCK_OPTIONAL=m`，所以只能写 `m IGC`；
  `MMC_BLOCK` 依赖 `RPMB=m`，同理。

核对某个符号的真实名字与类型：

```bash
# 解包内核源码里的 Kconfig
tar -xJf /nix/store/*linux-<版本>.tar.xz --wildcards --no-anchored '*/Kconfig*' -C /tmp/ksrc
# 查定义（注意 menuconfig 也算）
grep -rn '^\(menu\)\?config <选项名>$' /tmp/ksrc
```

写完 keep-list 后直接 `nix build .#genConfig`，自校验会告诉你哪一项没生效。

## 5. 本项目当前效果（2026-09-09 快照）

| 指标 | NAS 原始（NixOS 6.18.44） | 生成结果（6.18.50） |
|---|---|---|
| `=m` 模块数 | 7107 | **280** |
| `=y` 内置数 | 2652 | 2114 |
| 配置文件行数 | 13291 | 8418 |
| 实际加载模块 | 232（预热后） | — |

`=y` 数量没有同步下降，是因为 `localmodconfig` 只裁剪 `=m`，内置项原样保留。

## 6. 注意事项

1. **每次 `nix flake update` 后必须重跑 `gen-config`**：新内核可能引入新选项，
   旧 `.config` 里没有的项会取默认值，可能关掉 NixOS 需要的东西。
2. **`boot.initrd.availableKernelModules` 与内置/模块的对应关系要留意**：
   根分区在 SATA（`/dev/sda2`），所以 `MMC_BLOCK=m` 不影响引导；若将来改用 eMMC
   引导，需要把 `mmc_block` 加进 initrd 模块列表。
3. **`.config` 是构建输入，必须提交**：不提交则 flake 求值失败（Nix 沙盒看不到未跟踪文件）。
4. **首次构建务必验证**：`nix build .#packages.x86_64-linux.kernel` 只证明能编译。
   先用 `scripts/test-kernel-qemu.sh alpine` 在 QEMU 里跑一遍（拿 router-image 的 rootfs
   当测试根文件系统，串口直连、登录 root/root），再上真机；换内核前保留上一代
   system generation 以便 `--rollback`。

## 7. 针对本架构的功能补齐清单

NAS 的快照是「静态瞬间」，很多能力在采集时并未加载，因此 keep-list 里专门补齐了
下面这些。它们对应 NAS + cloud-hypervisor 路由 VM + yunshu 容器 + 物理 USB/HDMI/音频
的实际需求：

| 领域 | 关键配置 | 取值 | 说明 |
|---|---|---|---|
| 虚拟化 | `KVM`/`KVM_INTEL` | `y` | cloud-hypervisor 依赖 |
| | `VHOST_NET`/`VHOST_VSOCK`/`VSOCKETS` | `m` | 半虚拟化网络/ vsock |
| | `VIRTIO_*` | `m` | 完整 virtio 栈 |
| | `VFIO`/`VFIO_PCI`/`VFIO_GROUP` | `m`/`m`/`y` | 预留 PCI 直通（`--device vfio`）；当前路由 VM 用 tap+桥，未启用 |
| 容器 | `NAMESPACES`/`NET_NS`/`USER_NS`/`CGROUPS`/`OVERLAY_FS` | `y`/`y`/`y`/`y`/`m` | yunshu 容器 |
| eBPF | `BPF`/`BPF_SYSCALL`/`CGROUP_BPF`/`BPF_JIT` | `y` | 内核里这几个是 **bool，无法设成 m** |
| | `NET_CLS_BPF`/`NET_ACT_BPF` | `m` | tc-bpf 按你的要求用模块 |
| | `DEBUG_INFO_BTF`/`DEBUG_INFO_BTF_MODULES` | `y` | CO-RE 工具链必需；**生成器必须装 `pahole`**，否则会被判为不可用 |
| USB | `USB_HID`/`HID_GENERIC`/`USB_HIDDEV`/`USB_STORAGE`/`USB_UAS`/`USB_ACM` | `m` | 键鼠/U盘/hidraw/CDC-ACM |
| UPS | `USB_HID`+`HIDRAW`+`POWER_SUPPLY`+`USB_ACM`+`USB_SERIAL` | 见左 | 覆盖 NUT 的 `usbhid-ups`（libusb/hidraw）与串口 UPS |
| 音频 | `SND_HDA_INTEL`/`SND_HDA_CODEC_HDMI` | `y`/`m` | HDMI 音频 |
| | `SND_SOC_SOF_ICELAKE`/`SOUNDWIRE_INTEL`/`SND_SOC_SOF_HDA_COMMON` | `m` | Jasper Lake 走 ICL 平台驱动（NAS 实机加载的就是 `snd_sof_pci_intel_icl`） |
| 显示 | `DRM_I915`/`DRM`/`FB`/`FRAMEBUFFER_CONSOLE` | `y` | HDMI 输出 + QuickSync 转码 |
| 网络 | `BRIDGE`/`VETH`/`TUN`/`VLAN_8021Q`/`BRIDGE_VLAN_FILTERING` | `y` | 桥接/VLAN |
| | `BRIDGE_NETFILTER` | `m` | 桥接流量过防火墙（NAS 上 docker 处于 inactive，原被裁） |
| | `NF_TABLES`/`NFT_NAT`/`NFT_MASQ`/`NFT_REDIR`/`NETFILTER_XT_TARGET_{MASQUERADE,REDIRECT}` | `y`/`m` | 浮动网关 NAT/REDIRECT |
| | `WIREGUARD`/`MACVLAN`/`IPVLAN`/`VXLAN` | `m` | VPN 与容器网络 |
| 存储 | `SATA_AHCI`/`BLK_DEV_SD`/`MD`/`BLK_DEV_DM`/`MMC_*` | 见左 | 盘位 + RAID/LVM + eMMC |
| | `BLK_DEV_NVME` | `n` | **TS-564 无 NVMe 硬件**（lspci 无控制器、无 `/dev/nvme*`），同时已从 initrd 列表移除 `nvme` |
| 电源 | `ACPI`/`PM_SLEEP`/`X86_INTEL_PSTATE`/`INTEL_IDLE`/`INTEL_HFI_THERMAL` | `y` | 变频/深 C-state |
| | `INTEL_RAPL`/`INTEL_POWERCLAMP`/`X86_PKG_TEMP_THERMAL`/`INTEL_SOC_DTS_THERMAL`/`INT340X_THERMAL`/`ACPI_FAN`/`ACPI_THERMAL` | `m` | 功耗/温度/风扇 |
| 看门狗 | `WATCHDOG_CORE`/`WDAT_WDT`/`INTEL_OC_WATCHDOG` | `m` | NAS 实机在用（`/dev/watchdog0,1`、`wdat_wdt`、`intel_oc_wdt`） |
| 硬件监控 | `I2C_I801`/`PINCTRL_JASPERLAKE`/`GPIOLIB`/`HWMON`/`SENSORS_IT87` | 见左 | qnap8528 的符号依赖 |

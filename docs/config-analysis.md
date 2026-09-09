# 内核配置分析报告

基于 TS-564 实际硬件信息和已加载模块的分析

生成日期: 2026-09-09

## 硬件清单总结

### CPU & 平台
- Intel Celeron N5095 (Jasper Lake, Tremont 架构)
- 4 核心，支持 Intel P-State 和 C-State 节能

### 存储控制器
1. **Intel AHCI SATA** (00:17.0) - 板载控制器
   - 驱动: `ahci`
   - 状态: ✅ 已配置 (`SATA_AHCI = yes`)

2. **ASMedia ASM1164 SATA** (01:00.0) - PCIe 扩展卡
   - 驱动: `ahci`
   - 状态: ✅ AHCI 驱动通用支持

3. **Intel eMMC Controller** (00:1a.0)
   - 驱动: `sdhci-pci`
   - 状态: ✅ 已配置 (`MMC = yes`, `MMC_SDHCI = yes`)

### 网络控制器
- **双 Intel I226-V 2.5GbE** (02:00.0, 03:00.0)
  - 驱动: `igc`
  - 状态: ✅ 已配置 (`IGC = yes`)

### 显卡与音频
1. **Intel UHD Graphics** (Jasper Lake)
   - 驱动: `i915`
   - 状态: ✅ 已配置 (`DRM_I915 = yes`)

2. **Intel HD Audio** (00:1f.3)
   - 驱动: `sof-audio-pci-intel-icl` (Sound Open Firmware)
   - 状态: ✅ 已配置 (完整 SOF 音频栈)

### USB 控制器
- **Intel USB 3.1 xHCI** (00:14.0)
  - 驱动: `xhci_hcd`
  - 状态: ✅ 已配置 (`USB_XHCI_HCD = yes`)

### 系统管理与传感器
1. **Intel Management Engine** (00:16.0)
   - 驱动: `mei_me`
   - 状态: ⚠️ 需要添加

2. **Intel SMBus** (00:1f.4)
   - 驱动: `i801_smbus` / `i2c_i801`
   - 状态: ✅ 已配置 (`I2C_I801 = yes`)

3. **Intel SPI Controller** (00:1f.5)
   - 驱动: `intel-spi` / `spi_intel_pci`
   - 状态: ⚠️ 需要添加

4. **IT87xx 硬件监控芯片** (ISA)
   - 驱动: `qnap8528` (提供风扇、温度监控)
   - 状态: ✅ 已配置 (`SENSORS_IT87 = yes`)

## 当前已加载模块分析

### 核心功能模块 (必须保留)

#### 1. QNAP 专有驱动
```
qnap8528 (90112 bytes)
```
- 用途: MCU 控制、风扇控制、温度监控、LED 控制
- 状态: ✅ 已通过外部模块集成

#### 2. 网络功能
```
nft_masq, nft_nat, nft_chain_nat, nf_nat - NAT 功能
nft_ct - 连接跟踪
nft_fib_* - 路由查询
xt_nat - iptables NAT 兼容
```
- 用途: Docker/VM 网络、防火墙、NAT
- 状态: ✅ 已配置 (`NETFILTER = true`)

#### 3. 虚拟网络
```
veth - 虚拟以太网对 (Docker 容器网络)
af_packet - 原始包接口
```
- 用途: 容器和虚拟机网络
- 状态: ⚠️ 需要确认虚拟化配置

#### 4. 文件系统和存储
```
nfsd - NFS 服务器
auth_rpcgss, nfs_acl, lockd, grace - NFS 相关组件
vfat, fat, nls_cp437, nls_iso8859_1 - FAT 文件系统
```
- 用途: NAS 文件共享服务
- 状态: ⚠️ NFSD 需要添加

#### 5. 音频栈 (完整的 SOF 链)
```
snd_sof_pci_intel_icl - SOF PCI 驱动
snd_sof_intel_hda_* - Intel HDA SOF 支持
soundwire_* - SoundWire 总线支持
snd_hda_codec_hdmi - HDMI 音频编解码器
```
- 状态: ✅ 已正确配置

#### 6. 显卡驱动
```
i915 (4853760 bytes) - Intel 核显驱动
drm_display_helper, ttm, drm_buddy - DRM 辅助模块
```
- 状态: ✅ 已配置

#### 7. 电源和温度管理
```
processor_thermal_device_* - CPU 温度管理
intel_rapl_msr - 能耗监控
coretemp - 核心温度传感器
intel_cstate, intel_powerclamp - 节能状态控制
```
- 状态: ⚠️ 需要添加热管理支持

#### 8. SPI Flash 和固件
```
mtd - Memory Technology Device 核心
spi_nor - SPI NOR flash 驱动
spi_intel_pci - Intel SPI 控制器
ofpart, cmdlinepart - MTD 分区解析
```
- 用途: BIOS/固件访问、可能的备份恢复功能
- 状态: ⚠️ 需要添加

#### 9. 加密加速
```
ghash_clmulni_intel - AES-GCM 硬件加速
aesni_intel - AES-NI 指令集支持
crc32c_cryptoapi - CRC32C 加速
```
- 用途: 加密存储、VPN、TLS 加速
- 状态: ⚠️ 需要添加

#### 10. Intel MEI (Management Engine)
```
mei_pxp - Protected Xe Path (DRM 内容保护)
mei_hdcp - HDCP 内容保护
```
- 用途: Intel ME 通信、DRM 内容播放
- 状态: ⚠️ 需要添加

## 配置建议

### 必须添加的配置项

#### 1. NFS 服务器支持
```nix
NFSD = module;  # 或 yes，取决于是否需要动态加载
NFS_V3 = yes;
NFS_V4 = yes;
NFS_V4_1 = yes;
NFS_V4_2 = yes;
NFSD_V3 = yes;
NFSD_V4 = yes;
```

#### 2. 虚拟化支持 (KVM)
```nix
KVM = yes;
KVM_INTEL = yes;
VHOST_NET = yes;
VHOST_VSOCK = yes;
VIRTIO = yes;
VIRTIO_PCI = yes;
VIRTIO_NET = yes;
VIRTIO_BLK = yes;
VIRTIO_BALLOON = yes;
VIRTIO_FS = yes;
```

#### 3. Intel MEI 支持
```nix
INTEL_MEI = yes;
INTEL_MEI_ME = yes;
INTEL_MEI_HDCP = module;  # HDCP 内容保护
INTEL_MEI_PXP = module;   # DRM 保护
```

#### 4. SPI Flash 和 MTD 支持
```nix
MTD = yes;
MTD_BLKDEVS = yes;
MTD_BLOCK = yes;
SPI = yes;
SPI_MASTER = yes;
SPI_INTEL_PCI = yes;
SPI_NOR = yes;
MTD_SPI_NOR = yes;
```

#### 5. 加密硬件加速
```nix
CRYPTO_AES_NI_INTEL = yes;
CRYPTO_GHASH_CLMUL_NI_INTEL = yes;
CRYPTO_CRC32C_INTEL = yes;
CRYPTO_SHA256_SSSE3 = yes;
CRYPTO_SHA512_SSSE3 = yes;
```

#### 6. 热管理和电源监控
```nix
INTEL_RAPL = yes;
INTEL_RAPL_MSR = yes;
X86_PKG_TEMP_THERMAL = yes;
INTEL_POWERCLAMP = yes;
INTEL_SOC_DTS_THERMAL = yes;
```

#### 7. 虚拟网络增强
```nix
VETH = yes;           # 虚拟以太网对 (Docker)
MACVLAN = yes;        # MACVLAN 支持
IPVLAN = yes;         # IPVLAN 支持
VXLAN = yes;          # VXLAN 隧道
```

### 可选但推荐的配置

#### 1. 容器和命名空间支持
```nix
NAMESPACES = yes;
UTS_NS = yes;
IPC_NS = yes;
USER_NS = yes;
PID_NS = yes;
NET_NS = yes;
CGROUPS = yes;
CGROUP_DEVICE = yes;
CGROUP_CPUACCT = yes;
CGROUP_FREEZER = yes;
CGROUP_SCHED = yes;
```

#### 2. OverlayFS (Docker 镜像存储)
```nix
OVERLAY_FS = yes;
OVERLAY_FS_REDIRECT_DIR = yes;
```

#### 3. 额外文件系统支持
```nix
XFS_FS = yes;          # 高性能文件系统
EXFAT_FS = yes;        # exFAT 支持（USB 设备）
NTFS3_FS = yes;        # NTFS 读写支持
FUSE_FS = yes;         # FUSE 用户态文件系统
```

#### 4. 额外存储特性
```nix
DM_RAID = yes;         # 软 RAID 支持
DM_SNAPSHOT = yes;     # LVM 快照
DM_THIN_PROVISIONING = yes;  # 精简配置
MD = yes;              # 软 RAID 核心
MD_RAID0 = yes;
MD_RAID1 = yes;
MD_RAID10 = yes;
MD_RAID456 = yes;
```

## 当前配置验证

### ✅ 已正确配置的功能
- USB 3.0/3.1 支持 (`USB_XHCI_HCD = yes`)
- Intel 核显和 HDMI (`DRM_I915 = yes`)
- 完整音频栈 (SOF + HDA)
- 双 2.5GbE 网卡 (`IGC = yes`)
- SATA AHCI 控制器
- eMMC 存储
- I2C/SMBus 总线 (`I2C_I801 = yes`)
- GPIO 控制 (`PINCTRL_JASPERLAKE = yes`)
- 基础 Netfilter 防火墙
- TUN/BRIDGE 虚拟网络
- Btrfs, Ext4, FAT 文件系统
- Intel 节能特性 (P-State, C-State, NO_HZ_IDLE)
- 核心温度传感器 (`SENSORS_CORETEMP`, `SENSORS_IT87`)

### ⚠️ 需要补充的功能
1. **NFS 服务器** - 重要 NAS 功能
2. **KVM 虚拟化** - 运行虚拟机
3. **Intel MEI** - 系统管理和 DRM 支持
4. **MTD/SPI-NOR** - 固件访问
5. **加密加速** - 性能优化
6. **热管理** - 完整的温度控制
7. **容器支持** - Docker/LXC 完整功能

## 下一步行动

1. **立即添加**: NFS、KVM、MEI、加密加速
2. **测试验证**: 在虚拟机中测试配置变更
3. **性能对比**: 记录添加功能前后的内核大小和启动时间
4. **功能测试**: 
   - NFS 挂载测试
   - KVM 虚拟机创建
   - Docker 容器运行
   - 加密存储性能

## 参考资料

- 模块列表: `docs/lsmod-reference.txt`
- 硬件信息: `docs/hardware-info.txt`
- 传感器信息: `docs/sensors-output.txt`
- 当前配置: `modules/kernel-custom.nix`

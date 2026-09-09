# TS-564 多层架构配置指南

## 架构总览

```
┌─────────────────────────────────────────────────────────────┐
│ QNAP TS-564 (NixOS Host)                                   │
│ ├─ NAS 功能 (存储、NFS、SMB)                               │
│ ├─ cloud-hypervisor VM (Router VM)                         │
│ │  └─ Alpine/Gentoo + 自定义内核 (路由器功能)              │
│ └─ Nix Container                                            │
│    └─ VPN + VRRP 浮动网关                                   │
└─────────────────────────────────────────────────────────────┘
```

## 关键需求分析

### 1. **NAS 主机内核需求**
- ✅ 存储性能（SATA AHCI、BTRFS/EXT4）
- ✅ NFS/SMB 服务器
- ✅ KVM 虚拟化（运行 cloud-hypervisor）
- ✅ 容器支持（Nix container）
- ✅ 网络性能（双 2.5GbE）
- ✅ VRRP 支持（VRRP 协议、虚拟 IP）
- ✅ VPN 支持（WireGuard/OpenVPN）
- ✅ 网络桥接、VLAN、路由转发

### 2. **虚拟化特殊需求**
- **cloud-hypervisor** 需要：
  - vhost-net（高性能虚拟网络）
  - vhost-vsock（VM 与 Host 通信）
  - virtio 驱动全家桶
  - TAP/TUN 设备
  - VFIO（如果需要设备直通）
  
### 3. **网络功能需求**
- **路由器 VM**：
  - 网络设备直通或桥接
  - 高性能数据包转发
  - NAT/防火墙（netfilter）
  
- **VPN 网关容器**：
  - WireGuard 或 OpenVPN
  - VRRP (keepalived)
  - 虚拟 IP 浮动
  - 网络命名空间隔离

## 针对性优化配置

### 关键配置项（必须启用）

```nix
structuredExtraConfig = with pkgs.lib.kernel; {
  
  # ==========================================
  # KVM 虚拟化核心（cloud-hypervisor 必需）
  # ==========================================
  KVM = yes;
  KVM_INTEL = yes;
  VHOST = yes;
  VHOST_NET = yes;           # 高性能虚拟网络（cloud-hypervisor 推荐）
  VHOST_VSOCK = yes;         # VM-Host 通信
  VHOST_SCSI = yes;          # 虚拟 SCSI（可选）
  
  # VirtIO 驱动全家桶
  VIRTIO = yes;
  VIRTIO_PCI = yes;
  VIRTIO_MMIO = yes;
  VIRTIO_NET = yes;          # 虚拟网卡
  VIRTIO_BLK = yes;          # 虚拟磁盘
  VIRTIO_BALLOON = yes;      # 内存气球
  VIRTIO_CONSOLE = yes;      # 虚拟串口
  VIRTIO_FS = yes;           # 共享文件系统（virtiofs）
  VIRTIO_VSOCKETS = yes;     # vsock 通信
  
  # VFIO（设备直通 - 如果需要网卡直通到 Router VM）
  VFIO = yes;
  VFIO_PCI = yes;
  VFIO_IOMMU_TYPE1 = yes;
  IOMMU_SUPPORT = yes;
  INTEL_IOMMU = yes;
  INTEL_IOMMU_DEFAULT_ON = yes;  # ⚠️ 仅在需要设备直通时启用
  
  # ==========================================
  # 网络虚拟化（关键）
  # ==========================================
  
  # 基础虚拟网络
  TUN = yes;                 # TAP/TUN 设备（VM 网络、VPN）
  VETH = yes;                # 虚拟以太网对（容器）
  BRIDGE = yes;              # 网络桥接
  BRIDGE_VLAN_FILTERING = yes;  # VLAN 过滤
  
  # 高级虚拟网络
  MACVLAN = yes;             # MAC VLAN
  MACVTAP = yes;             # MAC VTAP（直接给 VM）
  IPVLAN = yes;              # IP VLAN
  VXLAN = yes;               # VXLAN 隧道
  
  # 网络命名空间（容器隔离必需）
  NET_NS = yes;
  NETNS_CORE = yes;
  
  # ==========================================
  # VPN 支持
  # ==========================================
  
  # WireGuard（推荐）
  WIREGUARD = yes;           # 内核原生 WireGuard
  
  # OpenVPN 支持
  TUN = yes;                 # 已在上面启用
  CRYPTO_AES_NI_INTEL = yes; # 硬件 AES 加速
  CRYPTO_CHACHA20POLY1305 = yes;  # WireGuard 加密
  
  # IPsec VPN（如果需要）
  XFRM = yes;
  XFRM_USER = yes;
  INET_ESP = yes;
  INET_IPCOMP = yes;
  
  # ==========================================
  # VRRP 支持（浮动网关）
  # ==========================================
  
  # VRRP 需要组播支持
  IP_MULTICAST = yes;
  IP_MROUTE = yes;
  IP_PIMSM_V1 = yes;
  IP_PIMSM_V2 = yes;
  
  # ==========================================
  # 路由和防火墙
  # ==========================================
  
  # IP 转发（路由器必需）
  IP_ADVANCED_ROUTER = yes;
  IP_MULTIPLE_TABLES = yes;  # 策略路由
  IP_ROUTE_MULTIPATH = yes;  # 多路径路由
  
  # Netfilter（防火墙核心）
  NETFILTER = yes;
  NETFILTER_ADVANCED = yes;
  NF_CONNTRACK = yes;        # 连接跟踪
  NF_NAT = yes;              # NAT
  
  # nftables（现代防火墙）
  NF_TABLES = yes;
  NF_TABLES_IPV4 = yes;
  NF_TABLES_IPV6 = yes;
  NF_TABLES_INET = yes;
  NF_TABLES_BRIDGE = yes;
  NFT_NAT = yes;
  NFT_MASQ = yes;
  NFT_REDIR = yes;
  NFT_CT = yes;
  
  # iptables 兼容层
  IP_NF_IPTABLES = yes;
  IP_NF_FILTER = yes;
  IP_NF_NAT = yes;
  IP_NF_MANGLE = yes;
  IP_NF_TARGET_MASQUERADE = yes;
  
  # ==========================================
  # 容器支持（Nix container）
  # ==========================================
  
  # 命名空间完整支持
  NAMESPACES = yes;
  UTS_NS = yes;
  IPC_NS = yes;
  USER_NS = yes;
  PID_NS = yes;
  NET_NS = yes;
  
  # cgroups v2
  CGROUPS = yes;
  CGROUP_DEVICE = yes;
  CGROUP_CPUACCT = yes;
  CGROUP_FREEZER = yes;
  CGROUP_SCHED = yes;
  CGROUP_PIDS = yes;
  MEMCG = yes;
  BLK_CGROUP = yes;
  CGROUP_BPF = yes;
  
  # OverlayFS（容器存储）
  OVERLAY_FS = yes;
  OVERLAY_FS_REDIRECT_DIR = yes;
  
  # ==========================================
  # 网络性能优化
  # ==========================================
  
  # TCP BBR（高吞吐量）
  TCP_CONG_BBR = yes;
  DEFAULT_BBR = yes;
  NET_SCH_FQ = yes;          # BBR 需要 FQ 调度器
  
  # 网络队列优化
  NET_SCH_FQ_CODEL = yes;    # 队列管理
  NET_SCH_HTB = yes;         # 分层令牌桶（QoS）
  NET_SCH_PRIO = yes;        # 优先级队列
  
  # 多队列网络
  NET_RX_BUSY_POLL = yes;    # 低延迟轮询
  
  # 大型接收卸载
  INET_LRO = yes;
  
  # ==========================================
  # 存储和文件系统（NAS 核心）
  # ==========================================
  
  # 存储驱动
  SATA_AHCI = yes;
  ATA = yes;
  BLK_DEV_SD = yes;
  MMC = yes;
  MMC_SDHCI = yes;
  
  # 文件系统
  BTRFS_FS = yes;
  EXT4_FS = yes;
  XFS_FS = yes;
  VFAT_FS = yes;
  EXFAT_FS = yes;
  NTFS3_FS = yes;
  FUSE_FS = yes;
  
  # NFS 服务器
  NFSD = yes;
  NFSD_V3 = yes;
  NFSD_V4 = yes;
  NFS_V4_1 = yes;
  NFS_V4_2 = yes;
  
  # CIFS/SMB
  CIFS = module;
  CIFS_SMB_DIRECT = yes;
  
  # 软 RAID 和 LVM
  MD = yes;
  MD_RAID0 = yes;
  MD_RAID1 = yes;
  MD_RAID10 = yes;
  MD_RAID456 = yes;
  BLK_DEV_DM = yes;
  DM_SNAPSHOT = yes;
  DM_THIN_PROVISIONING = yes;
  
  # ==========================================
  # 性能优化
  # ==========================================
  
  # 定时器：100Hz（服务器省电）
  HZ_100 = yes;
  HZ = freeform "100";
  
  # 抢占模型：无抢占（服务器吞吐量）
  PREEMPT_NONE = yes;
  
  # I/O 调度器：BFQ
  IOSCHED_BFQ = yes;
  BFQ_GROUP_IOSCHED = yes;
  
  # CPU 优化
  MCORE2 = no;
  MATOM = yes;
  NUMA = no;                 # 单路 CPU
  
  # 压缩：ZSTD
  KERNEL_ZSTD = yes;
  
  # ==========================================
  # 硬件支持（必须保留）
  # ==========================================
  
  # USB
  USB_SUPPORT = yes;
  USB_XHCI_HCD = yes;
  HID = yes;
  
  # 显卡（QuickSync 转码）
  DRM_I915 = yes;
  
  # 音频
  SOUND = yes;
  SND = yes;
  SND_HDA_INTEL = yes;
  SND_SOC_SOF_INTEL_HDA_GENERIC = yes;
  
  # 网卡
  IGC = yes;
  
  # 传感器
  SENSORS_CORETEMP = yes;
  SENSORS_IT87 = yes;
  
  # 电源管理
  INTEL_IDLE = yes;
  X86_INTEL_PSTATE = yes;
  NO_HZ_IDLE = yes;
  
  # I2C/GPIO（qnap8528 依赖）
  I2C = yes;
  I2C_I801 = yes;
  PINCTRL_JASPERLAKE = yes;
  
  # ==========================================
  # 高级网络功能（Router VM 可能需要）
  # ==========================================
  
  # 流量控制和 QoS
  NET_SCHED = yes;
  NET_CLS = yes;
  NET_CLS_U32 = yes;
  NET_CLS_FW = yes;
  NET_ACT_POLICE = yes;
  NET_ACT_GACT = yes;
  
  # 连接跟踪辅助模块
  NF_CONNTRACK_FTP = yes;
  NF_CONNTRACK_H323 = yes;
  NF_CONNTRACK_SIP = yes;
  NF_CONNTRACK_PPTP = yes;
  
  # PPPoE（如果 Router VM 需要拨号）
  PPPOE = module;
  PPP = module;
  PPP_ASYNC = module;
  
  # VLAN 支持
  VLAN_8021Q = yes;
  VLAN_8021Q_GVRP = yes;
  
  # ==========================================
  # 安全和加密
  # ==========================================
  
  # 硬件加密加速
  CRYPTO_AES_NI_INTEL = yes;
  CRYPTO_GHASH_CLMUL_NI_INTEL = yes;
  CRYPTO_CRC32C_INTEL = yes;
  CRYPTO_SHA256_SSSE3 = yes;
  
  # 保留安全特性
  RETPOLINE = yes;
  PAGE_TABLE_ISOLATION = yes;
  STACKPROTECTOR_STRONG = yes;
  
  # 禁用调试
  DEBUG_KERNEL = no;
  DEBUG_INFO = no;
};
```

## 编译器优化（针对多层架构）

```nix
stdenv = pkgs.withCFlags [
  "-march=tremont"
  "-mtune=tremont"
  "-O2"                      # O2 更稳定（虚拟化环境）
  "-pipe"
  "-fno-semantic-interposition"
] pkgs.stdenv;
```

**为什么选择 O2 而非 O3？**
- 虚拟化环境对稳定性要求更高
- O2 已经提供了大部分性能优化
- 避免过度优化导致的边界情况 bug

## NixOS 系统配置建议

### 1. 启用 IP 转发

```nix
# /etc/nixos/configuration.nix
boot.kernel.sysctl = {
  "net.ipv4.ip_forward" = 1;
  "net.ipv6.conf.all.forwarding" = 1;
  
  # 网络性能优化
  "net.core.netdev_max_backlog" = 5000;
  "net.core.rmem_max" = 134217728;
  "net.core.wmem_max" = 134217728;
  "net.ipv4.tcp_rmem" = "4096 87380 67108864";
  "net.ipv4.tcp_wmem" = "4096 65536 67108864";
  
  # BBR
  "net.ipv4.tcp_congestion_control" = "bbr";
  "net.core.default_qdisc" = "fq";
  
  # VRRP 组播
  "net.ipv4.conf.all.arp_ignore" = 1;
  "net.ipv4.conf.all.arp_announce" = 2;
};
```

### 2. cloud-hypervisor 配置

```nix
# 确保加载必要的模块
boot.kernelModules = [
  "qnap8528"
  "kvm"
  "kvm_intel"
  "vhost_net"
  "vhost_vsock"
];

# cloud-hypervisor 包
environment.systemPackages = with pkgs; [
  cloud-hypervisor
];

# 如果需要网卡直通，启用 IOMMU
boot.kernelParams = [
  "intel_iommu=on"
  "iommu=pt"
];
```

### 3. 容器配置

```nix
# 启用容器支持
boot.enableContainers = true;

# 示例：VPN 网关容器
containers.vpn-gateway = {
  autoStart = true;
  privateNetwork = true;
  hostBridge = "br0";
  
  config = { config, pkgs, ... }: {
    networking.firewall.enable = false;
    
    # WireGuard
    networking.wireguard.interfaces.wg0 = {
      # ... 配置
    };
    
    # VRRP (keepalived)
    services.keepalived = {
      enable = true;
      # ... 配置
    };
  };
};
```

## 网络拓扑建议

### 方案 A: 桥接模式（推荐）

```
物理网卡 (igc) ─┬─> br0 (桥接)
                 ├─> Host (NAS)
                 ├─> Router VM (tap0)
                 └─> VPN Container (veth)
```

```nix
networking.bridges.br0.interfaces = [ "enp2s0" ];  # 第一个 2.5G 网卡
networking.interfaces.br0.ipv4.addresses = [{
  address = "192.168.1.10";
  prefixLength = 24;
}];
```

### 方案 B: 网卡直通（最高性能）

```
物理网卡 1 (igc) ──> Host (NAS)
物理网卡 2 (igc) ──> Router VM (VFIO 直通)
```

需要在 VM 启动时配置 VFIO 直通。

## 性能调优检查清单

### ✅ 虚拟化性能
- [ ] 启用 `vhost-net`（减少 CPU 开销）
- [ ] 使用 virtio 驱动（而非模拟硬件）
- [ ] 考虑大页内存（Hugepages）
- [ ] 启用 CPU 固定（CPU pinning）

### ✅ 网络性能
- [ ] BBR 拥塞控制
- [ ] 网络多队列（multi-queue）
- [ ] 调整网络缓冲区大小
- [ ] 禁用不必要的 netfilter 模块

### ✅ 存储性能
- [ ] BFQ I/O 调度器
- [ ] 使用 virtio-blk 而非 virtio-scsi
- [ ] 考虑 NVMe 缓存盘

### ✅ 监控和调试
```bash
# 检查 KVM 是否正常
lsmod | grep kvm

# 检查 vhost 模块
lsmod | grep vhost

# 监控 VM 性能
virsh domstats <vm-name>  # 如果使用 libvirt
# 或
cloud-hypervisor --api-socket /path/to/socket info
```

## 故障排查

### VM 网络性能差
```bash
# 检查是否使用 vhost-net
lsmod | grep vhost_net

# 检查 VM 是否使用 virtio
# 在 VM 内部
lspci | grep -i virtio
```

### VRRP 不工作
```bash
# 检查组播支持
ip maddr show

# 检查防火墙是否允许 VRRP
nft list ruleset | grep -i vrrp
# VRRP 使用协议号 112
```

### VPN 性能问题
```bash
# 检查加密加速
grep -i aes /proc/cpuinfo  # 应该看到 aes-ni

# WireGuard 性能测试
iperf3 -s  # 服务器
iperf3 -c <server> --bidir  # 双向测试
```

## 下一步

需要我：
1. 创建完整的优化配置文件（整合所有优化）？
2. 创建 cloud-hypervisor VM 启动脚本示例？
3. 创建 Nix container 配置示例（VPN + VRRP）？
4. 创建网络桥接配置的完整示例？

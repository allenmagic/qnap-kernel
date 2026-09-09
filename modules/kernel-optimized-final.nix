inputs: # 外部传入的 Flake inputs，用以在独立仓库内获取 qnap8528 驱动
{ pkgs, lib, config, ... }:

let
  # 针对 TS-564 多层架构（NAS + Router VM + VPN Container）的优化内核
  # 架构：NixOS Host -> cloud-hypervisor VM (Router) + Nix Container (VPN/VRRP)
  #
  # 内核版本选择：linuxPackages_latest_lts (当前 6.6.x LTS)
  # 推荐 LTS 版本以获得更好的稳定性和长期支持
  myCustomKernel = pkgs.linuxPackages_latest_lts.extend (self: super: {
    kernel = super.kernel.override {

      # 编译器优化：针对 Tremont 架构，使用 O2 保证虚拟化环境稳定性
      stdenv = pkgs.withCFlags [
        "-march=tremont"           # Intel N5095 专属优化
        "-mtune=tremont"           # 微架构调优
        "-O2"                      # O2 更稳定（虚拟化 + 路由环境）
        "-pipe"                    # 使用管道加速编译
        "-fno-semantic-interposition"  # 减少符号解析开销
      ] pkgs.stdenv;

      # 特性级裁剪
      features = {
        iwlwifi = false;           # 无无线网卡
        btusb = false;             # 无蓝牙
        netfilter = true;          # 必需：路由器、NAT、防火墙
      };

      # 精细化内核配置
      structuredExtraConfig = with pkgs.lib.kernel; {

        # ====================================================================
        # CPU 架构优化
        # ====================================================================
        MCORE2 = no;               # 禁用 Core 2 优化
        MATOM = yes;               # 启用 Atom 系列优化（N5095）
        NUMA = no;                 # 单路 CPU，禁用 NUMA

        # ====================================================================
        # 内核压缩和性能基础
        # ====================================================================
        KERNEL_ZSTD = yes;         # ZSTD 压缩（快速解压 + 高压缩比）
        KERNEL_GZIP = no;
        KERNEL_XZ = no;
        KERNEL_LZ4 = no;

        # 定时器频率：100Hz（服务器省电模式）
        HZ_100 = yes;
        HZ_250 = no;
        HZ_1000 = no;
        HZ = freeform "100";

        # 抢占模型：无抢占（服务器吞吐量优先）
        PREEMPT_NONE = yes;
        PREEMPT_VOLUNTARY = no;
        PREEMPT = no;

        # 内存分配器：SLUB（现代默认）
        SLUB = yes;
        SLAB = no;

        # ====================================================================
        # KVM 虚拟化核心（cloud-hypervisor 必需）
        # ====================================================================
        KVM = yes;
        KVM_INTEL = yes;
        HAVE_KVM_IRQCHIP = yes;
        HAVE_KVM_IRQ_ROUTING = yes;

        # vhost 高性能虚拟化
        VHOST = yes;
        VHOST_NET = yes;           # 高性能虚拟网络（关键）
        VHOST_VSOCK = yes;         # VM-Host vsock 通信
        VHOST_SCSI = yes;          # 虚拟 SCSI（可选）

        # VirtIO 驱动完整栈
        VIRTIO = yes;
        VIRTIO_PCI = yes;
        VIRTIO_MMIO = yes;
        VIRTIO_NET = yes;          # 虚拟网卡
        VIRTIO_BLK = yes;          # 虚拟块设备
        VIRTIO_BALLOON = yes;      # 内存气球
        VIRTIO_CONSOLE = yes;      # 虚拟控制台
        VIRTIO_FS = yes;           # virtiofs 共享文件系统
        VIRTIO_VSOCKETS = yes;     # vsock 支持
        VIRTIO_VSOCKETS_COMMON = yes;

        # VFIO（设备直通 - 可选：如果需要网卡直通到 Router VM）
        VFIO = yes;
        VFIO_PCI = yes;
        VFIO_IOMMU_TYPE1 = yes;
        IOMMU_SUPPORT = yes;
        INTEL_IOMMU = yes;
        # INTEL_IOMMU_DEFAULT_ON = yes;  # ⚠️ 仅在需要设备直通时取消注释

        # ====================================================================
        # 网络虚拟化（多层架构核心）
        # ====================================================================

        # TAP/TUN（VM 网络、VPN 必需）
        TUN = yes;
        VETH = yes;                # 虚拟以太网对（容器）
        BRIDGE = yes;              # 网络桥接
        BRIDGE_VLAN_FILTERING = yes;  # VLAN 过滤

        # 高级虚拟网络
        MACVLAN = yes;             # MAC VLAN
        MACVTAP = yes;             # MAC VTAP（可直接给 VM）
        IPVLAN = yes;              # IP VLAN
        VXLAN = yes;               # VXLAN 隧道

        # 网络命名空间（容器隔离）
        NET_NS = yes;

        # ====================================================================
        # VPN 支持
        # ====================================================================

        # WireGuard（内核原生，推荐）
        WIREGUARD = yes;

        # OpenVPN 支持
        CRYPTO_AES_NI_INTEL = yes; # 硬件 AES 加速
        CRYPTO_CHACHA20POLY1305 = yes;  # WireGuard ChaCha20

        # IPsec VPN（可���）
        XFRM = yes;
        XFRM_USER = yes;
        XFRM_INTERFACE = yes;
        INET_ESP = yes;
        INET_IPCOMP = yes;
        INET_XFRM_MODE_TRANSPORT = yes;
        INET_XFRM_MODE_TUNNEL = yes;

        # ====================================================================
        # VRRP 浮动网关支持
        # ====================================================================

        # VRRP 需要组播
        IP_MULTICAST = yes;
        IP_MROUTE = yes;
        IP_MROUTE_MULTIPLE_TABLES = yes;
        IP_PIMSM_V1 = yes;
        IP_PIMSM_V2 = yes;

        # ====================================================================
        # 路由和转发（Router VM 核心功能）
        # ====================================================================

        # 高级路由
        IP_ADVANCED_ROUTER = yes;
        IP_MULTIPLE_TABLES = yes;  # 策略路由
        IP_ROUTE_MULTIPATH = yes;  # 多路径路由
        IP_ROUTE_VERBOSE = yes;

        # IPv6 路由
        IPV6_ROUTER_PREF = yes;
        IPV6_ROUTE_INFO = yes;
        IPV6_MULTIPLE_TABLES = yes;

        # ====================================================================
        # Netfilter 防火墙和 NAT
        # ====================================================================

        NETFILTER = yes;
        NETFILTER_ADVANCED = yes;
        NETFILTER_INGRESS = yes;

        # 连接跟踪
        NF_CONNTRACK = yes;
        NF_CONNTRACK_MARK = yes;
        NF_CONNTRACK_ZONES = yes;
        NF_CONNTRACK_EVENTS = yes;
        NF_CONNTRACK_TIMEOUT = yes;
        NF_CONNTRACK_TIMESTAMP = yes;

        # 连接跟踪协议辅助
        NF_CONNTRACK_FTP = yes;
        NF_CONNTRACK_H323 = yes;
        NF_CONNTRACK_SIP = yes;
        NF_CONNTRACK_PPTP = yes;

        # NAT 核心
        NF_NAT = yes;
        NF_NAT_REDIRECT = yes;
        NF_NAT_MASQUERADE = yes;

        # nftables（现代防火墙框架，推荐）
        NF_TABLES = yes;
        NF_TABLES_IPV4 = yes;
        NF_TABLES_IPV6 = yes;
        NF_TABLES_INET = yes;
        NF_TABLES_BRIDGE = yes;
        NFT_NAT = yes;
        NFT_MASQ = yes;
        NFT_REDIR = yes;
        NFT_CT = yes;
        NFT_FIB = yes;
        NFT_FIB_INET = yes;
        NFT_FIB_IPV4 = yes;
        NFT_FIB_IPV6 = yes;

        # iptables 兼容层（向后兼容）
        IP_NF_IPTABLES = yes;
        IP_NF_FILTER = yes;
        IP_NF_NAT = yes;
        IP_NF_MANGLE = yes;
        IP_NF_RAW = yes;
        IP_NF_TARGET_MASQUERADE = yes;
        IP_NF_TARGET_REDIRECT = yes;

        # IPv6 netfilter
        IP6_NF_IPTABLES = yes;
        IP6_NF_FILTER = yes;
        IP6_NF_MANGLE = yes;
        IP6_NF_NAT = yes;

        # ====================================================================
        # 容器支持（Nix container）
        # ====================================================================

        # 命名空间完整支持
        NAMESPACES = yes;
        UTS_NS = yes;              # 主机名隔离
        IPC_NS = yes;              # IPC 隔离
        USER_NS = yes;             # 用户隔离
        PID_NS = yes;              # 进程隔离
        NET_NS = yes;              # 网络隔离

        # cgroups v2（容器资源控制）
        CGROUPS = yes;
        CGROUP_DEVICE = yes;
        CGROUP_CPUACCT = yes;
        CGROUP_FREEZER = yes;
        CGROUP_SCHED = yes;
        CGROUP_PIDS = yes;
        MEMCG = yes;               # 内存控制
        BLK_CGROUP = yes;          # 块设备控制
        CGROUP_BPF = yes;

        # OverlayFS（容器镜像存储）
        OVERLAY_FS = yes;
        OVERLAY_FS_REDIRECT_DIR = yes;

        # ====================================================================
        # 网络性能优化
        # ====================================================================

        # TCP BBR 拥塞控制（高吞吐量）
        TCP_CONG_BBR = yes;
        DEFAULT_BBR = yes;
        TCP_CONG_CUBIC = yes;      # 备用

        # 网络调度器
        NET_SCH_FQ = yes;          # Fair Queue（BBR 需要）
        NET_SCH_FQ_CODEL = yes;    # 减少缓冲膨胀
        NET_SCH_HTB = yes;         # 分层令牌桶（QoS）
        NET_SCH_PRIO = yes;        # 优先级队列
        NET_SCH_INGRESS = yes;     # 入站流控

        # 网络分类器（QoS）
        NET_CLS = yes;
        NET_CLS_U32 = yes;
        NET_CLS_FW = yes;
        NET_ACT_POLICE = yes;
        NET_ACT_GACT = yes;

        # 网络性能特性
        NET_RX_BUSY_POLL = yes;    # 低延迟轮询
        INET_LRO = yes;            # 大型接收卸载

        # ====================================================================
        # 存储和文件系统（NAS 核心）
        # ====================================================================

        # 存储控制器驱动（静态内置）
        SATA_AHCI = yes;           # Intel AHCI + ASMedia 控制器
        ATA = yes;
        BLK_DEV_SD = yes;
        MMC = yes;                 # eMMC 支持
        MMC_SDHCI = yes;
        MMC_SDHCI_PCI = yes;
        MMC_BLOCK = yes;

        # 文件系统
        BTRFS_FS = yes;            # NAS 主文件系统
        BTRFS_FS_POSIX_ACL = yes;
        BTRFS_FS_CHECK_INTEGRITY = no;  # 禁用以提升性能

        EXT4_FS = yes;             # 系统分区
        EXT4_USE_FOR_EXT2 = yes;
        EXT4_FS_POSIX_ACL = yes;

        XFS_FS = yes;              # 高性能选项
        XFS_QUOTA = yes;
        XFS_POSIX_ACL = yes;

        FAT_FS = yes;              # FAT16/32
        VFAT_FS = yes;
        EXFAT_FS = yes;            # exFAT（现代 USB）
        NTFS3_FS = yes;            # NTFS 读写

        FUSE_FS = yes;             # FUSE 用户态文件系统

        # NFS 服务器（NAS 核心功能）
        NFSD = yes;
        NFSD_V3 = yes;
        NFSD_V4 = yes;
        NFS_V3 = yes;
        NFS_V4 = yes;
        NFS_V4_1 = yes;
        NFS_V4_2 = yes;
        SUNRPC = yes;
        RPCSEC_GSS_KRB5 = module;

        # CIFS/SMB 客户端（挂载远程共享）
        CIFS = module;

        # 软 RAID
        MD = yes;
        MD_RAID0 = yes;
        MD_RAID1 = yes;
        MD_RAID10 = yes;
        MD_RAID456 = yes;

        # LVM 和 Device Mapper
        BLK_DEV_DM = yes;
        DM_SNAPSHOT = yes;
        DM_THIN_PROVISIONING = yes;
        DM_RAID = yes;

        # I/O 调度器：BFQ（NAS 工作负载优化）
        IOSCHED_BFQ = yes;
        BFQ_GROUP_IOSCHED = yes;
        MQ_IOSCHED_DEADLINE = yes;
        MQ_IOSCHED_KYBER = yes;

        # ====================================================================
        # 硬件支持（必须保留）
        # ====================================================================

        # USB 支持
        USB_SUPPORT = yes;
        USB_XHCI_HCD = yes;        # USB 3.x 控制器
        USB_EHCI_HCD = yes;
        HID = yes;                 # USB 键鼠
        USB_STORAGE = yes;         # USB 存储

        # Intel 核显（QuickSync 转码）
        DRM = yes;
        DRM_I915 = yes;
        DRM_I915_GVT = yes;        # Intel GVT-g（GPU 虚拟化，可选）

        # 音频（HDMI 音频输出）
        SOUND = yes;
        SND = yes;
        SND_SOC = yes;
        SND_HDA_INTEL = yes;
        SND_SOC_SOF_TOPLEVEL = yes;
        SND_SOC_SOF_PCI = yes;
        SND_SOC_SOF_INTEL_TOPLEVEL = yes;
        SND_SOC_SOF_INTEL_HDA_GENERIC = yes;
        SND_SOC_INTEL_SOUNDWIRE_LINK_BASELINE = yes;

        # 网卡：Intel I226-V 2.5GbE
        IGC = yes;
        NET_ETHERNET = yes;
        NET_VENDOR_INTEL = yes;

        # 传感器和监控
        SENSORS_CORETEMP = yes;    # CPU 温度
        SENSORS_IT87 = yes;        # QNAP 主板监控芯片

        # Intel Management Engine
        INTEL_MEI = yes;
        INTEL_MEI_ME = yes;
        INTEL_MEI_HDCP = module;
        INTEL_MEI_PXP = module;

        # SPI Flash（固件访问）
        MTD = yes;
        MTD_BLKDEVS = yes;
        MTD_BLOCK = yes;
        SPI = yes;
        SPI_MASTER = yes;
        SPI_INTEL_PCI = yes;
        SPI_NOR = yes;
        MTD_SPI_NOR = yes;

        # ====================================================================
        # 电源管理和节能
        # ====================================================================

        # Intel 节能特性
        INTEL_IDLE = yes;          # 深度 C-State
        X86_INTEL_PSTATE = yes;    # P-State 调频
        NO_HZ_IDLE = yes;          # Tickless idle
        HIGH_RES_TIMERS = yes;

        # CPU 频率调节器：schedutil（推荐）
        CPU_FREQ_DEFAULT_GOV_SCHEDUTIL = yes;
        CPU_FREQ_GOV_PERFORMANCE = yes;
        CPU_FREQ_GOV_POWERSAVE = yes;
        CPU_FREQ_GOV_ONDEMAND = yes;

        # 热管理
        INTEL_RAPL = yes;
        X86_PKG_TEMP_THERMAL = yes;
        INTEL_POWERCLAMP = yes;
        INTEL_SOC_DTS_THERMAL = yes;

        # ====================================================================
        # I2C 和 GPIO（qnap8528 模块依赖）
        # ====================================================================

        I2C = yes;
        I2C_CHARDEV = yes;
        I2C_SMBUS = yes;
        I2C_I801 = yes;            # Intel SMBus 控制器

        PINCTRL = yes;
        PINCTRL_JASPERLAKE = yes;  # Jasper Lake GPIO

        # ====================================================================
        # 加密和安全
        # ====================================================================

        # 硬件加密加速
        CRYPTO_AES_NI_INTEL = yes;
        CRYPTO_GHASH_CLMUL_NI_INTEL = yes;
        CRYPTO_CRC32C_INTEL = yes;
        CRYPTO_SHA256_SSSE3 = yes;
        CRYPTO_SHA512_SSSE3 = yes;

        # WireGuard 加密
        CRYPTO_CHACHA20_X86_64 = yes;
        CRYPTO_POLY1305_X86_64 = yes;

        # 保留安全特性（平衡性能与安全）
        RETPOLINE = yes;           # Spectre v2 缓解
        PAGE_TABLE_ISOLATION = yes; # Meltdown 缓解
        STACKPROTECTOR = yes;
        STACKPROTECTOR_STRONG = yes;

        # ====================================================================
        # 禁用不需要的功能
        # ====================================================================

        # 无线和蓝牙
        WLAN = no;
        WIRELESS = no;
        BLUETOOTH = no;

        # 不需要的硬件
        INFINIBAND = no;
        HAMRADIO = no;
        AGP = no;
        DRM_AMDGPU = no;
        DRM_NOUVEAU = no;
        DRM_RADEON = no;
        HYPERV = no;
        CHROME_PLATFORMS = no;

        # 调试功能（生产环境禁用）
        DEBUG_KERNEL = no;
        DEBUG_INFO = no;
        DEBUG_INFO_DWARF_TOOLCHAIN_DEFAULT = no;
        KASAN = no;
        UBSAN = no;
        LOCKDEP = no;
        PROVE_LOCKING = no;
        SCHED_DEBUG = no;
        SLUB_DEBUG = no;

        # ====================================================================
        # 其他可选功能
        # ====================================================================

        # PPPoE（路由器拨号，如果需要）
        PPPOE = module;
        PPP = module;
        PPP_ASYNC = module;
        PPP_SYNC_TTY = module;

        # VLAN 支持
        VLAN_8021Q = yes;
        VLAN_8021Q_GVRP = yes;

        # 透明大页（提升性能）
        TRANSPARENT_HUGEPAGE = yes;
        TRANSPARENT_HUGEPAGE_MADVISE = yes;

        # 内存压缩
        ZSWAP = yes;
        ZRAM = yes;

        # KSM（内核同页合并，虚拟化有用）
        KSM = yes;
      };
    };
  });
in
{
  # =========================================================================
  # NixOS 模块配置
  # =========================================================================

  # 使用自定义内核
  boot.kernelPackages = myCustomKernel;

  # 加载 qnap8528 外部模块
  boot.extraModulePackages = [
    (inputs.qnap8528.packages.${pkgs.system}.qnap8528.override {
      kernel = config.boot.kernelPackages.kernel;
    })
  ];

  # 启动时加载的模块
  boot.kernelModules = [
    "qnap8528"       # QNAP MCU 控制
    "kvm"            # KVM 虚拟化
    "kvm_intel"      # Intel VT-x
    "vhost_net"      # vhost 网络加速
    "vhost_vsock"    # vsock 通信
  ];

  # 模块参数
  boot.extraModprobeConfig = ''
    options qnap8528 skip_hw_check=1
    options kvm_intel nested=1   # 启用嵌套虚拟化（可选）
  '';

  # Initrd 最小化
  boot.initrd.availableKernelModules = lib.mkForce [
    "xhci_pci"       # USB 3.x 引导
    "ahci"           # SATA 引导
    "nvme"           # NVMe 引导
    "sdhci_pci"      # eMMC 引导
  ];

  # 支持的文件系统
  boot.supportedFilesystems = lib.mkForce [ "vfat" "ext4" "btrfs" "xfs" ];

  # 内核参数（如果需要设备直通，取消下面的注释）
  # boot.kernelParams = [
  #   "intel_iommu=on"
  #   "iommu=pt"
  # ];
}

inputs: # 外部传入的 Flake inputs，用以在独立仓库内获取 qnap8528 驱动
{ pkgs, lib, config, ... }:

let
  # 定义 N5095 (Tremont 架构) 极致裁剪优化的自定义内核
  myCustomKernel = pkgs.linuxPackages_latest.extend (self: super: {
    kernel = super.kernel.override {

      # 1. 编译器硬件加速：压榨 Intel Celeron N5095 架构特性，开启 O3 极致性能优化
      stdenv = pkgs.withCFlags [ "-march=tremont" "-O3" "-pipe" ] pkgs.stdenv;

      # 2. 特性大剪枝：直接关闭不需要的庞大底层子系统，极速缩短 GitHub Actions 编译时间
      features = {
        iwlwifi = false;    # 关闭官方无线网卡驱动集
        btusb = false;      # 关闭蓝牙 USB 驱动集
        netfilter = true;   # 必须保留：NAS 防火墙、NAT、Docker 网络、虚拟化网桥核心
      };

      # 3. 点对点裁剪配置 (.config 核心映射)
      structuredExtraConfig = with pkgs.lib.kernel; {
        # ---- 架构替换 ----
        MCORE2 = no;               # 关闭 2006 年老旧的 Core 2 优化
        MATOM = yes;               # 开启最适配 N5095 的 Atom / 低功耗系列流水线优化

        # ---- 全面关闭无用硬件分类与内核调试 (极致瘦身、降低延迟、减少功耗) ----
        WLAN = no; WIRELESS = no; BLUETOOTH = no;
        INFINIBAND = no; HAMRADIO = no; AGP = no;
        DRM_AMDGPU = no; DRM_NOUVEAU = no; HYPERV = no;
        CHROME_PLATFORMS = no;
        DEBUG_KERNEL = no; SCHED_DEBUG = no; SLUB_DEBUG = no;

        # ---- 存储、核心外设 100% 静态内置 (yes 代表直接打入内核，消灭 .ko 动态加载开销) ----
        BTRFS_FS = yes;            # 阵列常用：Btrfs 文件系统核心
        EXT4_FS = yes;             # 系统常用：Ext4 / jbd2 核心
        FAT_FS = yes; VFAT_FS = yes; # 引导必备：FAT/vfat 格式支持
        BLK_DEV_SD = yes;          # 存储基础：sd_mod (SCSI/SATA 磁盘驱动)
        ATA = yes; SATA_AHCI = yes;  # 盘位核心：TS-564 的 3.5 寸机械盘槽 AHCI 控制器
        MMC = yes; MMC_SDHCI = yes; MMC_BLOCK = yes;  # 引导核心：QNAP 内部板载 eMMC 闪存驱动
        BLK_DEV_DM = yes;          # 存储进阶：LVM2 与 软 RAID 核心支持

        # ---- USB 核心与显卡转码核心静态内置 (⚠️ 必须保留) ----
        USB_SUPPORT = yes;
        USB_XHCI_HCD = yes;        # USB 3.0 / 3.2 核心控制器 (xhci_hcd / xhci_pci)
        HID = yes;                 # 基础输入：USB 键鼠核心支持
        DRM_I915 = yes;            # 核显核心：N5095 Intel UHD Graphics，Jellyfin / Plex 硬件转码 (QuickSync) 核心

        # ---- 音频链条核心静态内置 (⚠️ 必须保留：支持 TS-564 HDMI 音频输出) ----
        SOUND = yes; SND = yes; SND_SOC = yes; SND_HDA_INTEL = yes;
        SND_SOC_SOF_TOPLEVEL = yes; SND_SOC_SOF_PCI = yes;
        SND_SOC_SOF_INTEL_TOPLEVEL = yes; SND_SOC_SOF_INTEL_HDA_GENERIC = yes;
        SND_SOC_INTEL_SOUNDWIRE_LINK_BASELINE = yes;

        # ---- 网络架构静态内置 (双 2.5GbE 网口瞬间就绪) ----
        IGC = yes;                 # 关键：TS-564 板载 Intel i225/i226 2.5G 双网卡原生驱动
        NET_ETHERNET = yes; NET_VENDOR_INTEL = yes;
        BRIDGE = yes; TUN = yes;   # 虚拟网络：Docker 桥接网卡、虚拟机桥接与 VPN 必备支持

        # ---- 极致低功耗、功耗管理与传感器静态内置 ----
        INTEL_IDLE = yes;               # 强迫 Intel CPU 空闲时进入最深的 C-States 省电状态
        X86_INTEL_PSTATE = yes;         # 启用现代 Intel 专属 P-State 节能调频驱动
        NO_HZ_IDLE = yes;               # 动态时钟：CPU 空闲时停止时钟滴答，大幅降低 NAS 待机功耗
        HIGH_RES_TIMERS = yes;          # 高精度定时器支持
        CPU_FREQ_GOV_POWERSAVE = yes;   # 默认使用现代 Intel 推荐的省电(powersave)调频器
        SENSORS_CORETEMP = yes;         # 核心温度：Intel CPU 核心温度监控直接内置
        SENSORS_IT87 = yes;             # 监控芯片：QNAP 板载 IT87xx 硬件监控芯片原生内置

        # ---- ⚠️ qnap8528 模块的底层总线与 GPIO 符号依赖 (必须强制静态内置) ----
        I2C = yes; I2C_CHARDEV = yes; I2C_SMBUS = yes;
        I2C_I801 = yes;                 # 关键总线：Intel 芯片组 SMBus 控制器驱动
        PINCTRL = yes;
        PINCTRL_JASPERLAKE = yes;        # 关键引脚：Jasper Lake 平台 GPIO 核心控制，用于外部驱动通信

        # ====================
        # 新增：基于实际硬件的必需配置
        # ====================

        # ---- NFS 服务器支持 (NAS 核心功能) ----
        NFSD = module;             # NFS 服务器核心（使用 module 可选加载）
        NFSD_V3 = yes;
        NFSD_V4 = yes;
        NFS_V3 = yes;
        NFS_V4 = yes;
        NFS_V4_1 = yes;
        NFS_V4_2 = yes;
        SUNRPC = yes;
        RPCSEC_GSS_KRB5 = module;  # Kerberos 认证支持

        # ---- KVM 虚拟化支持 (⚠️ 必须保留：运行虚拟机) ----
        KVM = yes;
        KVM_INTEL = yes;           # Intel VT-x 支持
        VHOST_NET = yes;           # 高性能虚拟机网络
        VHOST_VSOCK = yes;         # VM 与主机通信
        VIRTIO = yes;
        VIRTIO_PCI = yes;
        VIRTIO_NET = yes;
        VIRTIO_BLK = yes;
        VIRTIO_BALLOON = yes;
        VIRTIO_FS = yes;           # 共享文件系统

        # ---- 虚拟网络增强 (Docker/LXC 容器) ----
        VETH = yes;                # 虚拟以太网对
        MACVLAN = yes;             # MACVLAN 网络
        IPVLAN = yes;              # IPVLAN 网络
        VXLAN = yes;               # VXLAN 隧道

        # ---- 容器和命名空间支持 ----
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
        MEMCG = yes;               # 内存控制组
        BLK_CGROUP = yes;          # 块设备控制组

        # ---- OverlayFS (Docker 镜像存储) ----
        OVERLAY_FS = yes;

        # ---- Intel Management Engine 支持 ----
        INTEL_MEI = yes;
        INTEL_MEI_ME = yes;
        INTEL_MEI_HDCP = module;   # HDCP 内容保护
        INTEL_MEI_PXP = module;    # DRM 保护

        # ---- SPI Flash 和 MTD 支持 (BIOS/固件访问) ----
        MTD = yes;
        MTD_BLKDEVS = yes;
        MTD_BLOCK = yes;
        SPI = yes;
        SPI_MASTER = yes;
        SPI_INTEL_PCI = yes;
        SPI_NOR = yes;
        MTD_SPI_NOR = yes;

        # ---- 加密硬件加速 (性能优化) ----
        CRYPTO_AES_NI_INTEL = yes;
        CRYPTO_GHASH_CLMUL_NI_INTEL = yes;
        CRYPTO_CRC32C_INTEL = yes;
        CRYPTO_SHA256_SSSE3 = yes;
        CRYPTO_SHA512_SSSE3 = yes;

        # ---- 热管理和电源监控 ----
        INTEL_RAPL = yes;
        X86_PKG_TEMP_THERMAL = yes;
        INTEL_POWERCLAMP = yes;
        INTEL_SOC_DTS_THERMAL = yes;

        # ---- 额外文件系统支持 ----
        XFS_FS = yes;              # 高性能文件系统
        EXFAT_FS = yes;            # exFAT 支持（现代 USB 设备）
        NTFS3_FS = yes;            # NTFS 读写支持
        FUSE_FS = yes;             # FUSE 用户态文件系统

        # ---- 高级存储特性 ----
        DM_RAID = yes;             # Device Mapper RAID
        DM_SNAPSHOT = yes;         # LVM 快照
        DM_THIN_PROVISIONING = yes; # 精简配置
        MD = yes;                  # 软 RAID 核心
        MD_RAID0 = yes;
        MD_RAID1 = yes;
        MD_RAID10 = yes;
        MD_RAID456 = yes;
      };
    };
  });
in
{
  # =========================================================================
  # 模块行为定义：当主系统 imports 此文件时，自动重载下列 boot 选项
  # =========================================================================

  # 1. 将系统内核全局替换为上面我们定义的自定义极简内核
  boot.kernelPackages = myCustomKernel;

  # 2. 将来自外部引用的 `qnap8528` 模块挂载到这个自定义内核下进行交叉编译
  boot.extraModulePackages = [
    (inputs.qnap8528.packages.${pkgs.system}.qnap8528.override {
      # 锁定使用上游定制内核的纯净开发头文件（kernel.dev），防止导出符号冲突
      kernel = config.boot.kernelPackages.kernel;
    })
  ];

  # 3. 强制系统在引导的极早期阶段直接加载您的自定义 MCU 模块
  boot.kernelModules = [ "qnap8528" ];

  # 4. 注入您指定的内核模块参数，跳过硬件检查
  boot.extraModprobeConfig = ''
    options qnap8528 skip_hw_check=1
  '';

  # 5. 极致剪枝 Initrd 阶段（挂载根分区前），拒绝多余驱动探测，缩短 NAS 重启阶段的盲区时间
  boot.initrd.availableKernelModules = lib.mkForce [
    "xhci_pci"   # 支持从 USB 设备引导
    "ahci"       # 支持从 SATA 硬盘引导
    "nvme"       # 支持从 NVMe 固态引导
    "sdhci_pci"  # 支持从 QNAP 内部板载 DOM/eMMC 闪存引导
  ];

  # 6. 强行锁定受支持的文件系统，不允许内核加载或探测其他任何冷门文件系统
  boot.supportedFilesystems = lib.mkForce [ "vfat" "ext4" "btrfs" ];
}

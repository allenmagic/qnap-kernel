inputs:
{ pkgs, lib, buildLinux, ... }:

let
  # 基础内核
  baseKernel = pkgs.linuxPackages_6_6.kernel;

  # 自定义配置
  customConfig = with lib.kernel; {
    # 架构优化
    MCORE2 = no;
    MATOM = yes;
    NUMA = no;

    # 压缩
    KERNEL_ZSTD = yes;
    KERNEL_GZIP = no;

    # 性能参数
    HZ_100 = yes;
    HZ = freeform "100";
    PREEMPT_NONE = yes;

    # 禁用不需要的
    WLAN = no; WIRELESS = no; BLUETOOTH = no;
    DEBUG_KERNEL = no; SCHED_DEBUG = no; SLUB_DEBUG = no;

    # 存储
    BTRFS_FS = yes;
    EXT4_FS = yes;
    FAT_FS = yes; VFAT_FS = yes;
    BLK_DEV_SD = yes;
    ATA = yes; SATA_AHCI = yes;
    MMC = yes; MMC_SDHCI = yes; MMC_BLOCK = yes;
    BLK_DEV_DM = yes;

    # USB
    USB_SUPPORT = yes;
    USB_XHCI_HCD = yes;
    HID = yes;

    # 显卡
    DRM_I915 = yes;

    # 音频
    SOUND = yes; SND = yes; SND_SOC = yes; SND_HDA_INTEL = yes;
    SND_SOC_SOF_TOPLEVEL = yes; SND_SOC_SOF_PCI = yes;
    SND_SOC_SOF_INTEL_TOPLEVEL = yes; SND_SOC_SOF_INTEL_HDA_GENERIC = yes;
    SND_SOC_INTEL_SOUNDWIRE_LINK_BASELINE = yes;

    # 网络
    IGC = yes;
    NET_ETHERNET = yes; NET_VENDOR_INTEL = yes;
    BRIDGE = yes; TUN = yes;

    # KVM 虚拟化
    KVM = yes;
    KVM_INTEL = yes;
    VHOST_NET = yes;
    VHOST_VSOCK = yes;
    VIRTIO = yes;
    VIRTIO_PCI = yes;
    VIRTIO_NET = yes;
    VIRTIO_BLK = yes;

    # 网络虚拟化
    VETH = yes;
    MACVLAN = yes;
    IPVLAN = yes;
    VXLAN = yes;

    # VPN
    WIREGUARD = yes;

    # 容器
    NAMESPACES = yes;
    NET_NS = yes;
    CGROUPS = yes;
    OVERLAY_FS = yes;

    # 电源管理
    INTEL_IDLE = yes;
    X86_INTEL_PSTATE = yes;
    NO_HZ_IDLE = yes;
    HIGH_RES_TIMERS = yes;
    CPU_FREQ_GOV_POWERSAVE = yes;
    SENSORS_CORETEMP = yes;
    SENSORS_IT87 = yes;

    # I2C/GPIO (qnap8528 依赖)
    I2C = yes; I2C_CHARDEV = yes; I2C_SMBUS = yes;
    I2C_I801 = yes;
    PINCTRL = yes;
    PINCTRL_JASPERLAKE = yes;
  };
in
  baseKernel.override {
    stdenv = pkgs.withCFlags [
      "-march=tremont"
      "-mtune=tremont"
      "-O2"
      "-pipe"
      "-fno-semantic-interposition"
    ] pkgs.stdenv;

    features = {
      iwlwifi = false;
      btusb = false;
      netfilter = true;
    };

    structuredExtraConfig = customConfig;
  }

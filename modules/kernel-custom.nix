inputs: # 外部传入的 Flake inputs，用以在独立仓库内获取 qnap8528 驱动与已构建的内核
{ pkgs, lib, config, ... }:

let
  # 内核包由 flake.nix 提供：源码取自 nixpkgs LTS，配置来自 NAS 实机
  # localmodconfig 结果（generated/nas-<版本>.config），编译参数在此统一注入。
  inherit (inputs) kernelPackages;
in
{
  # =========================================================================
  # 模块行为定义：当主系统 imports 此文件时，自动重载下列 boot 选项
  # =========================================================================

  # 1. 将系统内核全局替换为上面我们定义的自定义极简内核
  boot.kernelPackages = kernelPackages;

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
  # 注意：TS-564 无 NVMe 硬件（lspci 无 NVMe 控制器，根分区在 /dev/sda2 SATA），
  # 因此内核配置里 BLK_DEV_NVME=n，这里也不能再列 "nvme"（否则模块不存在）。
  boot.initrd.availableKernelModules = lib.mkForce [
    "xhci_pci"   # 支持从 USB 设备引导
    "ahci"       # 支持从 SATA 硬盘引导
    "sdhci_pci"  # 支持从 QNAP 内部板载 DOM/eMMC 闪存引导
  ];

  # 6. 强行锁定受支持的文件系统，不允许内核加载或探测其他任何冷门文件系统
  boot.supportedFilesystems = lib.mkForce [ "vfat" "ext4" "btrfs" ];
}

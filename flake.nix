{
  description = "Dedicated Custom Kernel for QNAP TS-564 (Intel N5095)";

  nixConfig = {
    extra-substituters = [ "https://cachix.org" ];
    extra-trusted-public-keys = [ "your-qnap-cache.cachix.org-1:xxxxxxxxxx=" ];
  };

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    qnap8528.url = "github:allenmagic/qnap8528";
  };

  outputs = { self, nixpkgs, ... }@inputs:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

      # 自定义内核配置 - 使用 default LTS
      customKernel = pkgs.linuxKernel.kernels.linux_default.override {
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

        structuredExtraConfig = with pkgs.lib.kernel; {
          # 虚拟化基础
          KVM = yes;
          KVM_INTEL = yes;

          # VirtIO 支持（QEMU 必需）
          VIRTIO = yes;
          VIRTIO_PCI = yes;
          VIRTIO_BLK = yes;
          VIRTIO_NET = yes;
          VIRTIO_CONSOLE = yes;

          # 存储支持
          BLK_DEV = yes;
          BLK_DEV_SD = yes;
          SCSI = yes;
          SCSI_LOWLEVEL = yes;
          ATA = yes;

          # 文件系统支持
          EXT4_FS = yes;
          BTRFS_FS = yes;
          TMPFS = yes;
          PROC_FS = yes;
          SYSFS = yes;
          DEVTMPFS = yes;
          DEVTMPFS_MOUNT = yes;
        };
      };
    in {
      nixosModules.default = import ./modules/kernel-custom.nix inputs;

      packages.${system} = {
        kernel = customKernel;
      };
    };
}

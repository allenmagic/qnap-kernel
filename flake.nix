{
  description = "Dedicated Custom Kernel for QNAP TS-564 (Intel N5095)";

  # 二进制缓存：CI 构建的内核/模块推到这里，NAS 侧 nix 直接拉取。
  nixConfig = {
    extra-substituters = [ "https://qnap-kernel.cachix.org" ];
    extra-trusted-public-keys = [ "qnap-kernel.cachix.org-1:HwBIYv2RlW2ZHEeuDP+0HRRKABTcjmd8DMAK9vdopL4=" ];
  };

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    qnap8528.url = "github:allenmagic/qnap8528";
  };

  outputs = { self, nixpkgs, ... }@inputs:
    let
      system = "x86_64-linux";
      pkgs = nixpkgs.legacyPackages.${system};

      # nixpkgs 自带的 LTS 内核（当前 6.18.50），只取版本/源码/patch 骨架。
      kernelBase = pkgs.linuxKernel.kernels.linux_default;

      # 由 localmodconfig 从 NAS 实机状态生成的最小配置（见 scripts/snapshot-nas.sh
      # 与 nix build .#genConfig）。文件名带版本号：升级内核后必须重新生成。
      nasConfig = ./generated/nas-${kernelBase.version}.config;

      # 用原始 .config 构建：绕过 nixpkgs 的 generate-config.pl，配置即 NAS 实机
      # 裁剪后的原样结果，不再经过 structuredExtraConfig / autoModules 的二次加工。
      customKernel = pkgs.linuxKernel.manualConfig {
        inherit (kernelBase) version src modDirVersion kernelPatches;

        configfile = nasConfig;

        # 编译器硬件加速：Intel Celeron N5095（Tremont 架构）
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
      };

      kernelPackages = pkgs.linuxPackagesFor customKernel;

      # 生成器：在沙盒里对 NAS 快照跑 make localmodconfig，再叠加 keep-list。
      # 产物是一个 .config 文件，需人工拷到 generated/ 并提交。
      genConfig = pkgs.stdenv.mkDerivation {
        pname = "nas-localmodconfig";
        inherit (kernelBase) version src;

        # pahole 必须存在，否则 olddefconfig 会把 PAHOLE_VERSION 判为 0，
        # 进而把 CONFIG_DEBUG_INFO_BTF 判为不可用（eBPF CO-RE 工具链依赖 BTF）。
        nativeBuildInputs = with pkgs; [ perl bison flex bc gnumake pahole ];

        enableParallelBuilding = true;

        # scripts/config 的 shebang 是 /usr/bin/env，沙盒里不存在
        postPatch = ''
          patchShebangs scripts
        '';

        buildPhase = ''
          runHook preBuild

          echo "==> 用 NAS 当前运行的 .config 作为裁剪基线"
          gunzip -c ${./docs/nas/config.gz} > .config
          make ARCH=x86_64 olddefconfig

          echo "==> make localmodconfig（只保留 lsmod 中已加载的模块）"
          make ARCH=x86_64 LSMOD=${./docs/nas/lsmod.txt} localmodconfig

          echo "==> 叠加 keep-list（拉回快照时未加载但必需的选项）"
          while read -r kind opt _; do
            case "$kind" in
              y|Y) ./scripts/config --file .config --enable "$opt" ;;
              m|M) ./scripts/config --file .config --module "$opt" ;;
              n|N) ./scripts/config --file .config --disable "$opt" ;;
            esac
          done < ${./scripts/keep-list.conf}
          make ARCH=x86_64 olddefconfig

          echo "==> 校验 keep-list 是否全部生效"
          fail=0
          while read -r kind opt _; do
            case "$kind" in
              y|Y) want=y ;; m|M) want=m ;; n|N) want=n ;; *) continue ;;
            esac
            if [ "$want" = n ]; then
              grep -qE "^# CONFIG_''${opt} is not set$" .config \
                || { echo "  [失败] $opt 未按 n 生效"; fail=1; }
            else
              grep -qE "^CONFIG_''${opt}=''${want}$" .config \
                || { echo "  [失败] $opt 未按 ''${want} 生效（符号名/类型可能有误）"; fail=1; }
            fi
          done < ${./scripts/keep-list.conf}
          if [ "$fail" != 0 ]; then
            echo "keep-list 存在未生效项，请修正后重试。"
            exit 1
          fi

          runHook postBuild
        '';

        installPhase = ''
          runHook preInstall
          install -Dm644 .config $out/config
          runHook postInstall
        '';
      };
    in {
      # 完整独立模块：换内核 + 挂 qnap8528 + initrd/文件系统裁剪（单机使用）
      nixosModules.default = import ./modules/kernel-custom.nix (inputs // { inherit kernelPackages; });

      # 只换内核：供已有 qnap8528 集成的宿主（qnap-nixos-nas）使用，
      # 避免与宿主自己的 hardware.qnap8528 overlay 重复挂载模块。
      nixosModules.kernel = { ... }: {
        boot.kernelPackages = kernelPackages;
      };

      packages.${system} = {
        kernel = customKernel;
        # qnap8528 外部模块（对本内核交叉编译）——CI 一并构建，验证内核对
        # 外部模块的符号兼容性并入缓存（消费端能否命中取决于其 qnap8528
        # input rev 是否与本仓库 flake.lock 一致）。
        qnap8528-module = inputs.qnap8528.packages.${system}.qnap8528.override {
          kernel = customKernel;
        };
        inherit genConfig;
      };
    };
}

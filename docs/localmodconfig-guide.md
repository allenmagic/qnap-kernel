# 使用 localmodconfig 优化内核配置

## 什么是 localmodconfig？

`make localmodconfig` 是 Linux 内核提供的一个智能配置工具：
- 读取当前系统 `lsmod` 的输出
- 分析哪些模块和功能正在实际使用
- 自动生成一个**最小化**的 `.config`，只包含当前系统需要的功能
- 比手动配置更准确、更高效

## 为什么要用 localmodconfig？

### 当前方法的问题
1. **手动配置容易遗漏**：可能忘记某个依赖的配置项
2. **过度配置**：可能启用了实际不需要的功能
3. **维护困难**：每次硬件变化都需要手动调整
4. **不精确**：基于猜测而非实际使用情况

### localmodconfig 的优势
1. ✅ **精确**：基于实际运行的系统
2. ✅ **完整**：自动处理依赖关系
3. ✅ **最小化**：只包含真正需要的功能
4. ✅ **可重复**：在相同硬件上结果一致

## 在 NixOS 中使用 localmodconfig

### 方法 1: 使用 NixOS 的 `autoModules` 功能

NixOS 内核包提供了 `autoModules` 选项，它在构建时自动调用 `localmodconfig`：

```nix
inputs: { pkgs, lib, config, ... }:

let
  myCustomKernel = pkgs.linuxPackages_latest.extend (self: super: {
    kernel = super.kernel.override {
      # 编译器优化
      stdenv = pkgs.withCFlags [ "-march=tremont" "-O3" "-pipe" ] pkgs.stdenv;
      
      # 🔥 关键：使用 autoModules
      autoModules = true;  # 自动从 lsmod 生成最小配置
      
      # 仍然可以添加额外的必需配置
      structuredExtraConfig = with pkgs.lib.kernel; {
        # 架构优化
        MCORE2 = no;
        MATOM = yes;
        
        # 强制保留的核心功能
        KVM = yes;
        KVM_INTEL = yes;
        # ... 其他必需配置
      };
    };
  });
in
{ ... }
```

### 方法 2: 从 TS-564 导出配置

在实际的 TS-564 上生成最优配置：

#### Step 1: 在 TS-564 上收集信息
```bash
# 1. 确保加载了所有需要的模块
# 启动所有服务：Docker、NFS、VM、音频、USB 设备等
systemctl start docker
systemctl start nfs-server
# ... 启动其他服务

# 2. 导出当前加载的模块列表
lsmod > /tmp/lsmod-full.txt

# 3. 找到当前内核的配置
zcat /proc/config.gz > /tmp/current-config

# 或者如果没有 CONFIG_IKCONFIG_PROC
cat /boot/config-$(uname -r) > /tmp/current-config
```

#### Step 2: 生成 localmodconfig（在开发机器上）
```bash
# 下载 Linux 内核源码（与 TS-564 相同版本）
cd /tmp
wget https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.x.y.tar.xz
tar xf linux-6.x.y.tar.xz
cd linux-6.x.y

# 复制 TS-564 的 lsmod 输出
scp root@ts564:/tmp/lsmod-full.txt .

# 使用 localmodconfig 生成最小配置
LSMOD=lsmod-full.txt make localmodconfig

# 查看生成的配置
less .config

# 导出为 NixOS 可用的格式
./scripts/config --file .config --print-all > /tmp/kernel-config-optimized.txt
```

#### Step 3: 转换为 NixOS 格式

```bash
# 创建转换脚本
cat > convert-to-nix.sh << 'EOF'
#!/usr/bin/env bash
# 将 .config 转换为 NixOS structuredExtraConfig 格式

echo "# Generated from localmodconfig"
echo "structuredExtraConfig = with pkgs.lib.kernel; {"

while IFS= read -r line; do
  # 跳过注释和空行
  [[ "$line" =~ ^#.*|^$ ]] && continue
  
  # CONFIG_XXX=y
  if [[ "$line" =~ ^CONFIG_([^=]+)=y$ ]]; then
    echo "  ${BASH_REMATCH[1]} = yes;"
  # CONFIG_XXX=m
  elif [[ "$line" =~ ^CONFIG_([^=]+)=m$ ]]; then
    echo "  ${BASH_REMATCH[1]} = module;"
  # CONFIG_XXX is not set
  elif [[ "$line" =~ ^#\ CONFIG_([^\ ]+)\ is\ not\ set$ ]]; then
    echo "  ${BASH_REMATCH[1]} = no;"
  # CONFIG_XXX="value" 或 =123
  elif [[ "$line" =~ ^CONFIG_([^=]+)=(.+)$ ]]; then
    echo "  ${BASH_REMATCH[1]} = freeform \"${BASH_REMATCH[2]}\";"
  fi
done < .config

echo "};"
EOF

chmod +x convert-to-nix.sh
./convert-to-nix.sh > kernel-config-from-localmodconfig.nix
```

### 方法 3: 混合方法（推荐）

结合 localmodconfig 的精确性和手动配置的灵活性：

```nix
inputs: { pkgs, lib, config, ... }:

let
  # 从 localmodconfig 导入基础配置
  localModConfig = import ./localmodconfig-base.nix;
  
  # 手动覆盖和增强
  manualOverrides = with pkgs.lib.kernel; {
    # 架构优化（localmodconfig 不会自动设置）
    MCORE2 = lib.mkForce no;
    MATOM = lib.mkForce yes;
    
    # 确保虚拟化支持（即使当前未运行 VM）
    KVM = lib.mkForce yes;
    KVM_INTEL = lib.mkForce yes;
    VHOST_NET = lib.mkForce yes;
    
    # 确保 USB/HDMI/Audio 永远启用
    USB_XHCI_HCD = lib.mkForce yes;
    DRM_I915 = lib.mkForce yes;
    SND_SOC_SOF_INTEL_HDA_GENERIC = lib.mkForce yes;
    
    # 关闭不需要的（localmodconfig 可能保留的）
    DEBUG_KERNEL = lib.mkForce no;
    WLAN = lib.mkForce no;
    BLUETOOTH = lib.mkForce no;
  };

  myCustomKernel = pkgs.linuxPackages_latest.extend (self: super: {
    kernel = super.kernel.override {
      stdenv = pkgs.withCFlags [ "-march=tremont" "-O3" "-pipe" ] pkgs.stdenv;
      
      structuredExtraConfig = localModConfig // manualOverrides;
    };
  });
in
{ ... }
```

## 完整工作流程

### 推荐流程：基于 TS-564 实际运行生成配置

```bash
# 1. 在 TS-564 上：加载所有需要的功能
ssh root@ts564 << 'EOF'
# 确保所有硬件和服务都在运行
systemctl start docker
systemctl start nfs-server
modprobe kvm
modprobe kvm_intel
# 播放音频测试 HDMI 音频
# 插入 USB 设备
# 挂载所有文件系统类型

# 导出模块列表
lsmod | sort > /tmp/lsmod-production.txt

# 如果可能，导出当前配置
if [ -f /proc/config.gz ]; then
  zcat /proc/config.gz > /tmp/current.config
fi
EOF

# 2. 复制到开发机器
scp root@ts564:/tmp/lsmod-production.txt docs/

# 3. 使用 Nix 构建脚本生成优化配置
# 创建一个专门的构建脚本
```

### 创建自动化构建脚本

```nix
# flake.nix 中添加
apps.${system} = {
  generate-localmodconfig = {
    type = "app";
    program = toString (pkgs.writeShellScript "gen-localmodconfig" ''
      set -e
      LSMOD_FILE="''${1:-docs/lsmod-production.txt}"
      
      if [ ! -f "$LSMOD_FILE" ]; then
        echo "Error: $LSMOD_FILE not found"
        echo "Usage: nix run .#generate-localmodconfig [lsmod-file]"
        exit 1
      fi
      
      echo "Generating kernel config from $LSMOD_FILE..."
      
      # 下载并解压内核源码
      KERNEL_VERSION=$(${pkgs.linuxPackages_latest.kernel}/bin/make -C ${pkgs.linuxPackages_latest.kernel.src} kernelversion)
      
      # 使用 Nix 提供的内核源码
      cd ${pkgs.linuxPackages_latest.kernel.src}
      
      # 运行 localmodconfig
      LSMOD="$LSMOD_FILE" make localmodconfig
      
      # 转换并输出
      echo "Generated config saved to kernel-localmodconfig.nix"
    '');
  };
};
```

## 优势对比

| 特性 | 手动配置 | localmodconfig | 混合方法（推荐）|
|-----|---------|----------------|----------------|
| 准确性 | ⚠️ 中等 | ✅ 高 | ✅ 最高 |
| 完整性 | ⚠️ 容易遗漏 | ✅ 自动处理 | ✅ 保证覆盖 |
| 可维护性 | ❌ 困难 | ✅ 容易 | ✅ 最佳 |
| 灵活性 | ✅ 高 | ⚠️ 受限 | ✅ 最佳 |
| 优化程度 | ⚠️ 中等 | ✅ 高 | ✅ 最高 |

## 注意事项

### localmodconfig 的局限性

1. **只包含当前使用的功能**
   - 如果生成配置时没有运行 VM，KVM 可能被排除
   - 需要确保所有硬件和服务都在运行中

2. **不会做架构优化**
   - 不会自动设置 `-march=tremont`
   - 不会自动选择 `MATOM` vs `MCORE2`

3. **可能保留不需要的调试选项**
   - 需要手动关闭 `DEBUG_KERNEL` 等

### 最佳实践

1. ✅ 在生成配置前启动所有服务和硬件
2. ✅ 使用 `lib.mkForce` 确保关键配置不被覆盖
3. ✅ 保留手动优化部分（编译器标志、架构选择）
4. ✅ 定期更新（硬件或服务变化时）
5. ✅ 版本控制保存生成的配置和 lsmod 输出

## 下一步行动

想要我帮你：
1. 创建自动化的 localmodconfig 生成脚本？
2. 基于现有的 `docs/lsmod-reference.txt` 生成初始配置？
3. 创建混合配置模板？

# NixOS 内核定制工作原理

## 你的配置实际上是如何工作的？

### 简短回答

**你当前的配置是：在 NixOS 已有的内核包基础上进行定制**

- ❌ 不是从 kernel.org 下载源码从零开始
- ✅ 是基于 nixpkgs 提供的内核包进行 override
- ✅ Nix 会自动处理下载、打补丁、配置、编译、打包

### 详细流程解析

#### 你的配置做了什么

```nix
myCustomKernel = pkgs.linuxPackages_latest_lts.extend (self: super: {
  kernel = super.kernel.override {
    # 你的定制
  };
});
```

**这段代码的含义：**

1. **`pkgs.linuxPackages_latest_lts`** 
   - 这是 nixpkgs 预定义的内核包集合
   - 包含：内核源码、默认配置、构建脚本、已知补丁
   - nixpkgs 维护者已经测试过的稳定配置

2. **`.extend (self: super: { ... })`**
   - 扩展（extend）这个包集合
   - 不是替换，是在原有基础上修改

3. **`super.kernel.override { ... }`**
   - override 现有的内核构建配置
   - 修改编译器标志、内核配置选项
   - 保留 nixpkgs 的其他设置（补丁、构建系统等）

#### 实际构建流程

当你运行 `nix build .#packages.x86_64-linux.kernel` 时：

```
1. Nix 从 nixpkgs 获取内核包定义
   ↓
2. 查看你的 override 配置
   ↓
3. 下载内核源码（从 kernel.org 镜像）
   ↓
4. 应用 nixpkgs 的补丁（如果有）
   ↓
5. 生成 .config 文件
   - 从 nixpkgs 的默认配置开始
   - 应用你的 structuredExtraConfig 修改
   ↓
6. 使用你指定的编译器标志编译
   - stdenv = pkgs.withCFlags [...]
   ↓
7. 打包成 Nix 包
   ↓
8. 输出到 /nix/store/
```

### 三种内核定制方法对比

#### 方法 1: Override nixpkgs 内核（你当前使用的）

```nix
pkgs.linuxPackages_latest_lts.extend (self: super: {
  kernel = super.kernel.override {
    structuredExtraConfig = { ... };
  };
});
```

**优点：**
- ✅ 简单，只需修改差异部分
- ✅ 继承 nixpkgs 的稳定配置和补丁
- ✅ 自动处理依赖和构建环境
- ✅ 与 NixOS 生态集成良好

**缺点：**
- ⚠️ 受限于 nixpkgs 提供的选项
- ⚠️ 不能应用自定义补丁（除非通过特殊方法）

**适用场景：** 
- ⭐ 大多数情况（包括你的 NAS）
- 只需要配置调整，不需要修改源码

#### 方法 2: 从头构建内核（buildLinux）

```nix
pkgs.buildLinux {
  version = "6.6.0";
  src = pkgs.fetchurl {
    url = "https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.6.tar.xz";
    sha256 = "...";
  };
  structuredExtraConfig = { ... };
  # 自己提供所有配置
}
```

**优点：**
- ✅ 完全控制
- ✅ 可以应用自定义补丁
- ✅ 可以使用非标准内核版本

**缺点：**
- ❌ 需要自己维护完整的 .config
- ❌ 需要自己处理补丁兼容性
- ❌ 更新内核版本时工作量大

**适用场景：**
- 需要应用厂商特定补丁
- 需要使用修改过的内核源码

#### 方法 3: localmodconfig + override（最优化方案）

```nix
# 第一步：在 TS-564 上生成 localmodconfig
# 第二步：转换为 NixOS 格式
# 第三步：与 override 方法结合

pkgs.linuxPackages_latest_lts.extend (self: super: {
  kernel = super.kernel.override {
    autoModules = true;  # 或导入 localmodconfig 结果
    structuredExtraConfig = { ... };
  };
});
```

**优点：**
- ✅ 最小化内核大小
- ✅ 基于实际使用的模块
- ✅ 仍然继承 nixpkgs 的优势

**缺点：**
- ⚠️ 需要在目标系统上生成配置
- ⚠️ 需要额外的转换步骤

**适用场景：**
- 追求极致优化
- 内核大小或编译时间敏感

### 你的配置实际上做了什么？

#### 第 1 层：选择基础内核

```nix
pkgs.linuxPackages_latest_lts
```

**这一步 Nix 做了什么：**
- 选择 Linux 6.6.x LTS 版本
- 使用 nixpkgs 团队维护的默认配置
- 包含必要的补丁和修复

**你获得了什么：**
- 稳定的 LTS 内核
- 经过 NixOS 社区测试的基础配置
- 自动处理的依赖关系

#### 第 2 层：编译器优化

```nix
stdenv = pkgs.withCFlags [
  "-march=tremont"
  "-mtune=tremont"
  "-O2"
  "-pipe"
  "-fno-semantic-interposition"
] pkgs.stdenv;
```

**这一步做了什么：**
- 修改编译器标志
- Nix 会用这些标志重新编译整个内核
- 不是二进制修改，是源码重新编译

#### 第 3 层：功能裁剪

```nix
features = {
  iwlwifi = false;
  btusb = false;
  netfilter = true;
};
```

**这一步做了什么：**
- nixpkgs 提供的高级功能开关
- 影响多个相关的内核配置项
- 自动处理依赖关系

#### 第 4 层：精细配置

```nix
structuredExtraConfig = with pkgs.lib.kernel; {
  KVM = yes;
  VHOST_NET = yes;
  # ... 200+ 配置项
};
```

**这一步做了什么：**
- 直接修改 Linux 内核的 .config
- 对应 `make menuconfig` 的选项
- Nix 会合并这些配置到基础配置上

### 与传统方法的对比

#### 传统 Linux 内核编译（手动）

```bash
# 1. 下载源码
wget https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-6.6.tar.xz
tar xf linux-6.6.tar.xz
cd linux-6.6

# 2. 配置
make defconfig  # 或 make localmodconfig
make menuconfig # 手动调整

# 3. 编译
make -j$(nproc) CFLAGS="-march=tremont -O2"

# 4. 安装
sudo make modules_install
sudo make install
sudo update-grub
```

**问题：**
- ❌ 手动管理依赖
- ❌ 难以重现（环境差异）
- ❌ 更新麻烦
- ❌ 与系统包管理器脱节

#### NixOS 方法（你的配置）

```bash
# 1. 声明式配置（一个 .nix 文件）
nix build .#packages.x86_64-linux.kernel

# 2. 一切自动化
# - 下载源码
# - 生成配置
# - 编译
# - 打包
```

**优势：**
- ✅ 完全可重现
- ✅ 自动处理依赖
- ✅ 原子化更新
- ✅ 可以回滚
- ✅ 与 NixOS 集成

### nixpkgs 的内核默认配置来自哪里？

**路径：** `nixpkgs/pkgs/os-specific/linux/kernel/common-config.nix`

这个文件定义了：
- 通用的内核配置选项
- 针对不同架构的默认值
- NixOS 需要的最小功能集

**你的 structuredExtraConfig 会覆盖这些默认值**

### 实际的内核构建过程

```
你的 .nix 配置
    ↓
nixpkgs 内核定义 (common-config.nix)
    ↓
合并配置 (你的配置覆盖默认值)
    ↓
生成 .config 文件
    ↓
kernel.org 下载源码
    ↓
应用补丁 (nixpkgs 维护的)
    ↓
编译 (使用你的编译器标志)
    ↓
打包成 Nix 包
    ↓
/nix/store/xxx-linux-6.6.0/
```

### 你能看到实际的构建过程吗？

**可以！**

```bash
# 查看实际生成的 .config
nix build .#packages.x86_64-linux.kernel.configfile
cat result

# 查看构建日志
nix build .#packages.x86_64-linux.kernel --print-build-logs

# 进入构建环境（调试用）
nix develop .#packages.x86_64-linux.kernel
```

### localmodconfig 在 NixOS 中如何工作？

**传统方法：**
```bash
cd linux-6.6
LSMOD=lsmod.txt make localmodconfig
```

**NixOS 方法：**
```nix
kernel = super.kernel.override {
  autoModules = true;  # 启用 localmodconfig
};
```

**但是有个问题：** `autoModules = true` 使用的是**构建机器**的 lsmod，不是目标机器的。

**解决方案：**
1. 在 TS-564 上生成 lsmod 输出
2. 在开发机器上手动运行 localmodconfig
3. 转换结果为 NixOS 配置
4. 与你的 override 配置合并

这就是为什么我在 `docs/localmodconfig-guide.md` 中提供了详细的手动流程。

## 总结

### 你当前的配置是：

**"在 nixpkgs 提供的稳定 LTS 内核基础上，通过声明式配置进行定制"**

- ✅ 不是从零开始编译
- ✅ 不是使用预编译的二进制
- ✅ 是基于源码的可重现构建
- ✅ 继承 nixpkgs 的稳定性
- ✅ 应用你的特定优化

### 这种方法的优势：

1. **稳定性** - 基于 nixpkgs 测试过的配置
2. **可维护性** - 只需维护差异部分
3. **可重现性** - 任何机器都能构建出相同结果
4. **灵活性** - 可以精细调整任何配置项
5. **安全性** - 自动获得 nixpkgs 的安全补丁

### 如果需要更深度定制：

- 应用厂商补丁 → 使用 `buildLinux` + `patches`
- 极致优化 → 结合 localmodconfig
- 修改源码 → fork 内核 + `buildLinux`

但对于你的 NAS 场景，**当前的 override 方法已经是最佳选择**！

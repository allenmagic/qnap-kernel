# 内核版本选择指南

## 当前推荐：Linux LTS (Long Term Support)

配置文件使用 `pkgs.linuxPackages_latest_lts`，即最新的 LTS 内核。

## NixOS 内核版本选项

### 1. LTS 版本（⭐ 推荐用于 NAS）

```nix
# 最新 LTS 版本（当前 6.6.x）
pkgs.linuxPackages_latest_lts

# 或指定具体 LTS 版本
pkgs.linuxPackages_6_6    # Linux 6.6 LTS (支持到 2026-12)
pkgs.linuxPackages_6_1    # Linux 6.1 LTS (支持到 2026-12)
```

**优势：**
- ✅ 长期稳定性保证（通常 2-6 年支持）
- ✅ 只接收关键 bug 修复和安全补丁
- ✅ 适合生产环境和 24/7 运行的 NAS
- ✅ qnap8528 模块兼容性更好

### 2. 最新稳定版（适合桌面/测试）

```nix
# 最新稳定版本（当前 6.11.x 或更新）
pkgs.linuxPackages_latest

# 或指定具体版本
pkgs.linuxPackages_6_11
pkgs.linuxPackages_6_10
```

**特点：**
- 最新功能和硬件支持
- 更新频繁
- 可能有未知问题
- 不推荐用于关键系统

### 3. 硬件启用内核（特殊情况）

```nix
# 包含额外硬件支持的内核
pkgs.linuxPackages_latest_hardened  # 加固版本
```

## 当前配置 (kernel-optimized-final.nix)

```nix
myCustomKernel = pkgs.linuxPackages_latest_lts.extend (self: super: {
  kernel = super.kernel.override {
    # ... 优化配置
  };
});
```

**选择 LTS 的理由：**
1. **稳定性优先**：NAS 需要长期稳定运行
2. **Router VM**：路由功能需要可靠的网络栈
3. **VPN Gateway**：安全和稳定性至关重要
4. **qnap8528 兼容**：外部模块在 LTS 版本上测试更充分
5. **生产环境**：减少因内核更新导致的问题

## 检查当前使用的内核版本

```bash
# 在开发机器上（构建前）
nix eval .#packages.x86_64-linux.kernel.version

# 或
nix-instantiate --eval -E 'with import <nixpkgs> {}; linuxPackages_latest_lts.kernel.version'

# 在 TS-564 上（部署后）
uname -r
```

## 切换内核版本

### 切换到特定 LTS 版本

```nix
# 如果需要固定到 6.6 LTS
myCustomKernel = pkgs.linuxPackages_6_6.extend (self: super: {
  kernel = super.kernel.override {
    # ... 配置保持不变
  };
});
```

### 切换到最新稳定版（不推荐）

```nix
# 如果确实需要最新功能
myCustomKernel = pkgs.linuxPackages_latest.extend (self: super: {
  kernel = super.kernel.override {
    # ... 配置保持不变
  };
});
```

## Linux 内核 LTS 版本时间线

| 版本 | 发布日期 | EOL (结束支持) | 推荐用途 |
|------|---------|---------------|---------|
| 6.6 | 2023-10 | 2026-12 | ⭐ 当前推荐 |
| 6.1 | 2022-12 | 2026-12 | 稳定选择 |
| 5.15 | 2021-10 | 2026-10 | 保守选择 |
| 5.10 | 2020-12 | 2026-12 | 最保守 |

## 内核版本与硬件支持

### Intel N5095 (Jasper Lake) 支持

- **最低要求**: Linux 5.10+
- **完整支持**: Linux 5.15+
- **推荐**: Linux 6.1+ 或 6.6 LTS

**关键驱动支持情况：**
- Intel i915 (核显): 5.10+
- Intel I226-V (网卡): 5.13+
- Sound Open Firmware: 5.10+
- Intel MEI: 5.10+

✅ **Linux 6.6 LTS 完全支持所有 TS-564 硬件**

## qnap8528 模块兼容性

qnap8528 外部模块需要编译到内核，兼容性考虑：

```nix
# 在 flake.nix 或配置中
boot.extraModulePackages = [
  (inputs.qnap8528.packages.${pkgs.system}.qnap8528.override {
    kernel = config.boot.kernelPackages.kernel;
  })
];
```

- ✅ LTS 内核 API 更稳定，模块兼容性更好
- ⚠️ 最新内核可能有 API 变化，需要更新模块

## 升级内核版本的流程

### 1. 本地测试构建

```bash
# 修改配置后
nix build .#packages.x86_64-linux.kernel --print-out-paths

# 检查版本
nix eval .#packages.x86_64-linux.kernel.version
```

### 2. 验证 qnap8528 模块兼容

```bash
# 构建完整的 NixOS 模块（包含外部模块）
nix build .#nixosModules.default
```

### 3. 在测试环境部署

```bash
# 使用 nixos-rebuild test（重启后自动回滚）
sudo nixos-rebuild test --flake .#your-hostname
```

### 4. 验证功能

```bash
# 检查内核版本
uname -r

# 检查模块加载
lsmod | grep qnap8528
lsmod | grep kvm
lsmod | grep vhost

# 测试网络
ip link show
ping -c 4 8.8.8.8

# 测试 VM 启动
# 测试容器启动
```

### 5. 生产部署

```bash
# 如果一切正常
sudo nixos-rebuild switch --flake .#your-hostname
```

## 推荐策略

### NAS 生产环境（⭐ 当前配置）

```nix
# 使用最新 LTS，平衡新功能和稳定性
pkgs.linuxPackages_latest_lts

# 优点：
# - 获得最新 LTS 的改进
# - 自动跟随 LTS 分支更新
# - 安全补丁及时
```

### 极致稳定（保守用户）

```nix
# 固定到特定 LTS 版本
pkgs.linuxPackages_6_6

# 优点：
# - 完全可预测
# - 手动控制升级时机
# - 适合对稳定性要求极高的场景
```

### 追新用户（不推荐 NAS）

```nix
# 使用最新稳定版
pkgs.linuxPackages_latest

# 缺点：
# - 可能遇到新 bug
# - 更新频繁需要重新测试
# - 外部模块兼容性风险
```

## 总结

**当前配置已使用 `linuxPackages_latest_lts`**，这是 NAS 环境的最佳选择：

- ✅ 长期稳定支持
- ✅ 及时的安全更新
- ✅ 良好的硬件支持
- ✅ 外部模块兼容性好
- ✅ 适合生产环境

如果需要更改，只需修改 `modules/kernel-optimized-final.nix` 第 7 行的内核包名称即可。

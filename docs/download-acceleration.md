# Nix 下载加速配置指南

## 当前状态
从日志看，系统已经在使用清华大学镜像：
```
copying path from 'https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store'
```

## 进一步优化方案

### 方案 1: 配置更多 substituters（推荐）

编辑 `~/.config/nix/nix.conf` 或 `/etc/nix/nix.conf`：

```conf
# 添加多个国内镜像源（按优先级排序）
substituters = https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store https://mirrors.ustc.edu.cn/nix-channels/store https://mirror.sjtu.edu.cn/nix-channels/store https://cache.nixos.org

# 信任这些 substituters
trusted-substituters = https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store https://mirrors.ustc.edu.cn/nix-channels/store https://mirror.sjtu.edu.cn/nix-channels/store

# 并行下载数量（加快下载速度）
max-jobs = auto
cores = 0

# HTTP 连接设置
connect-timeout = 5
download-attempts = 3
```

应用配置后重启 nix-daemon：
```bash
sudo systemctl restart nix-daemon
```

### 方案 2: 使用 Cachix（已配置但未启用）

你的 flake.nix 中已经配置了 Cachix，但需要添加 `--accept-flake-config` 才能启用：

```bash
# 重新构建时添加参数
nix build .#packages.x86_64-linux.kernel --accept-flake-config
```

或者在构建机器的全局配置中信任这个 flake：
```bash
# 编辑 ~/.config/nix/nix.conf
echo "accept-flake-config = true" >> ~/.config/nix/nix.conf
```

### 方案 3: 国内主流 Nix 镜像源

**清华大学（当前使用）：**
- https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store
- https://mirrors.tuna.tsinghua.edu.cn/help/nix/

**中科大：**
- https://mirrors.ustc.edu.cn/nix-channels/store

**上海交大：**
- https://mirror.sjtu.edu.cn/nix-channels/store

**北京外国语大学：**
- https://mirrors.bfsu.edu.cn/nix-channels/store

### 方案 4: 配置 HTTP/SOCKS 代理

如果有代理可用：

```bash
# 临时使用（当前会话）
export https_proxy=http://127.0.0.1:7890
export http_proxy=http://127.0.0.1:7890

# 或在 nix.conf 中配置
http-connections = 0  # 0 = 无限制
```

### 方案 5: 增加并行下载（已在进行）

Nix 默认会并行下载，但可以调整：

```conf
# ~/.config/nix/nix.conf
max-jobs = 8           # 最大并行构建任务
cores = 4              # 每个任务使用的核心数
download-attempts = 5  # 下载失败重试次数
```

### 当前构建的优化建议

**立即可用（不中断当前构建）：**

1. **开启另一个终端预热缓存：**
```bash
# 预下载常用包到本地缓存
nix-store --realise /nix/store/4yxdxw3kppr2pbic95p4mri520rkdag2-gcc-15.3.0 &
nix-store --realise /nix/store/cqlx62f919g8xf2f39bmykslpjdh9z0j-rustc-1.97.1 &
```

2. **监控下载速度：**
```bash
# 查看网络使用情况
watch -n 1 'ss -s'
```

**下次构建前配置：**

创建或编辑 `~/.config/nix/nix.conf`：
```bash
mkdir -p ~/.config/nix
cat >> ~/.config/nix/nix.conf << 'EOF'
# 国内镜像源（多个备份）
substituters = https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store https://mirrors.ustc.edu.cn/nix-channels/store https://cache.nixos.org
trusted-substituters = https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store https://mirrors.ustc.edu.cn/nix-channels/store

# 并行设置
max-jobs = auto
cores = 0

# 网络优化
connect-timeout = 5
download-attempts = 3
http-connections = 0

# 信任 flake 配置
accept-flake-config = true
EOF

# 重启 nix-daemon 使配置生效
sudo systemctl restart nix-daemon
```

### 为什么当前下载相对慢？

1. **首次构建** - 需要下载所有依赖（~300MB），后续会使用缓存
2. **大型包** - GCC、Rust、LLVM 都是大型软件包（几十到几百 MB）
3. **网络带宽** - 受限于你的网络速度和镜像服务器带宽

### 预估时间

当前下载阶段：
- 已下载：~30-40%
- 剩余时间：5-10 分钟（取决于网络速度）
- 下载完成后会立即开始编译

**好消息：** 下载完成后，这些依赖会被缓存，下次构建时不需要重新下载！

## 检查当前配置

```bash
# 查看当前使用的 substituters
nix show-config | grep substituters

# 查看下载统计
nix path-info --store https://mirrors.tuna.tsinghua.edu.cn/nix-channels/store --json /nix/store/xxx
```

## 总结

**立即改善（无需重启构建）：**
- ✅ 已在使用清华镜像
- 等待当前下载完成（5-10分钟）

**下次构建优化：**
1. 配置多个镜像源作为备份
2. 启用 `accept-flake-config = true`
3. 调整并行下载参数

当前构建继续，无需中断！

# 命令参考手册

## 本地开发命令

### 构建内核
```bash
# 构建自定义内核包
nix build .#packages.x86_64-linux.kernel --print-out-paths --verbose

# 构建 NixOS 模块配置
nix build .#nixosModules.default

# 检查构建产物大小
du -sh result/
```

### Flake 管理
```bash
# 检查 flake 语法和配置
nix flake check

# 更新所有依赖（nixpkgs 和 qnap8528）
nix flake update

# 只更新特定输入
nix flake lock --update-input nixpkgs
nix flake lock --update-input qnap8528

# 查看 flake 信息
nix flake show
nix flake metadata
```

### 开发调试
```bash
# 进入开发环境
nix develop

# 查看构建日志
nix log .#packages.x86_64-linux.kernel

# 清理构建缓存
nix-collect-garbage -d
```

## 收集系统信息（在 TS-564 上执行）

### 生成模块参考清单
```bash
# 在 TS-564 上运行，获取当前加载的所有内核模块
lsmod > lsmod-output.txt

# 或者获取更详细的信息
lsmod | sort > lsmod-sorted.txt

# 查看特定模块的详细信息
modinfo qnap8528
modinfo igc
modinfo i915
```

### 硬件信息收集
```bash
# 查看 CPU 信息
lscpu
cat /proc/cpuinfo | grep "model name" | head -1

# 查看 PCI 设备（网卡、显卡等）
lspci -v

# 查看 USB 设备
lsusb -v

# 查看块设备（硬盘、SSD）
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,FSTYPE

# 查看网络接口
ip link show
ethtool eth0  # 替换为实际网卡名称

# 查看内核版本和配置
uname -a
zcat /proc/config.gz | grep -i "CONFIG_"  # 如果启用了 CONFIG_IKCONFIG_PROC
```

### 传感器和监控
```bash
# 查看 CPU 温度和风扇速度
sensors

# 查看系统负载
uptime
htop
```

### 存储和文件系统
```bash
# 查看挂载的文件系统
mount | grep -E "ext4|btrfs|vfat"
df -h

# 查看 RAID 状态（如果使用软 RAID）
cat /proc/mdstat
```

## 部署到 TS-564

### 方式 1: 通过 NixOS 配置部署
```bash
# 在 TS-564 的 NixOS 配置中引用此 flake
# 编辑 /etc/nixos/configuration.nix 或 flake.nix:
# inputs.qnap-kernel.url = "github:allenmagic/qnap-kernel";
# imports = [ inputs.qnap-kernel.nixosModules.default ];

# 然后重建系统
sudo nixos-rebuild switch
```

### 方式 2: 测试内核（不立即切换）
```bash
# 构建但不激活
sudo nixos-rebuild build

# 测试启动（重启后自动回滚）
sudo nixos-rebuild test
```

### 方式 3: 从远程构建并部署
```bash
# 在开发机器上构建并推送到 TS-564
nixos-rebuild switch --flake .#your-hostname --target-host root@ts564.local --build-host localhost
```

## Git 工作流程

### 基本提交流程
```bash
# 查看状态
git status

# 添加更改
git add modules/kernel-custom.nix
git add flake.nix

# 提交（会触发 CI 构建）
git commit -m "feat: 添加虚拟化支持配置"

# 推送到 GitHub（触发自动构建和缓存）
git push origin main
```

### 创建功能分支
```bash
# 创建并切换到新分支
git checkout -b feature/optimize-audio

# 完成修改后推送
git push -u origin feature/optimize-audio

# 在 GitHub 上创建 PR（会触发测试构建）
gh pr create --title "优化音频驱动配置" --body "详细描述..."
```

## GitHub Actions 相关

### 手动触发构建
```bash
# 使用 gh CLI 手动触发工作流
gh workflow run "Build and Cache QNAP Custom Kernel"

# 查看工作流运行状态
gh run list

# 查看特定运行的日志
gh run view <run-id> --log
```

### Cachix 配置
```bash
# 设置 Cachix 认证令牌（在 GitHub 仓库设置中）
# Settings -> Secrets and variables -> Actions -> New repository secret
# Name: CACHIX_AUTH_TOKEN
# Value: <your-cachix-token>

# 本地使用 Cachix 缓存
cachix use your-qnap-cache

# 推送构建产物到 Cachix
nix build .#packages.x86_64-linux.kernel
cachix push your-qnap-cache result
```

## 故障排查

### 内核构建失败
```bash
# 查看详细构建日志
nix build .#packages.x86_64-linux.kernel --print-build-logs

# 检查 qnap8528 模块兼容性
nix flake lock --update-input qnap8528
nix build .#packages.x86_64-linux.kernel
```

### 系统无法启动
```bash
# 在 GRUB 启动菜单选择旧版本内核启动

# 启动后回滚到上一个配置
sudo nixos-rebuild switch --rollback

# 查看启动日志
journalctl -b
dmesg | less
```

### 模块加载失败
```bash
# 查看内核日志
dmesg | grep -i error
dmesg | grep qnap8528

# 手动加载模块（测试）
sudo modprobe qnap8528 skip_hw_check=1

# 查看模块加载失败原因
sudo journalctl -xe | grep modprobe
```

## 性能测试

### 内核编译性能对比
```bash
# 记录构建时间
time nix build .#packages.x86_64-linux.kernel --rebuild

# 对比不同优化级别（需要修改 -O3 为 -O2）
# 编辑 modules/kernel-custom.nix 后重新构建
```

### 运行时性能测试
```bash
# 网络性能（在 TS-564 上）
iperf3 -s  # 服务端
iperf3 -c ts564.local -t 60  # 客户端测试 60 秒

# 磁盘 I/O 性能
fio --name=randwrite --ioengine=libaio --iodepth=16 --rw=randwrite --bs=4k --size=1G

# CPU 性能
sysbench cpu --threads=4 --time=60 run
```

## 快速参考

### 最常用命令
```bash
# 本地构建内核
nix build .#packages.x86_64-linux.kernel

# 更新依赖
nix flake update

# 部署到 TS-564
sudo nixos-rebuild switch

# 收集模块清单（在 TS-564 上）
lsmod > lsmod-output.txt

# 查看硬件信息（在 TS-564 上）
lspci -v
sensors
```

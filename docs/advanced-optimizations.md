# 内核手动优化完全指南

针对 QNAP TS-564 (Intel N5095) 的深度优化策略

## 1. 编译器优化标志

### 当前配置
```nix
stdenv = pkgs.withCFlags [ "-march=tremont" "-O3" "-pipe" ] pkgs.stdenv;
```

### 🚀 高级优化选项

#### 选项 A: LTO (链接时优化) - 推荐
```nix
stdenv = pkgs.withCFlags [
  "-march=tremont"
  "-mtune=tremont"           # 针对 Tremont 微架构调优
  "-O3"
  "-pipe"
  "-flto"                    # 链接时优化 (LTO)
  "-fuse-linker-plugin"      # LTO 插件
  "-fno-semantic-interposition"  # 减少符号解析开销
] pkgs.stdenv;
```

**效果：**
- 内核体积减少 5-10%
- 性能提升 2-5%
- 编译时间增加 30-50%

#### 选项 B: 激进优化（适合专用 NAS）
```nix
stdenv = pkgs.withCFlags [
  "-march=tremont"
  "-mtune=tremont"
  "-O3"
  "-pipe"
  "-flto"
  "-fuse-linker-plugin"
  "-fno-semantic-interposition"
  "-fomit-frame-pointer"     # 省略帧指针（牺牲调试能力换性能）
  "-fno-stack-protector"     # 禁用栈保护（提升性能，降低安全性）
  "-ffast-math"              # 激进数学优化（可能影响浮点精度）
] pkgs.stdenv;
```

**⚠️ 警告：** 这会牺牲一些调试能力和安全性

#### 选项 C: 保守优化（平衡性能与稳定性）- 推荐
```nix
stdenv = pkgs.withCFlags [
  "-march=tremont"
  "-mtune=tremont"
  "-O2"                      # O2 而非 O3，更稳定
  "-pipe"
  "-fno-semantic-interposition"
] pkgs.stdenv;
```

### 在 NixOS 中启用 LTO

需要同时配置内核选项：
```nix
structuredExtraConfig = with pkgs.lib.kernel; {
  LTO_CLANG_THIN = yes;      # 使用 Clang ThinLTO（需要 Clang 编译器）
  # 或
  LTO_GCC = yes;             # 使用 GCC LTO
  LTO_MENU = yes;
};
```

## 2. 内核压缩优化

### 压缩算法选择

```nix
structuredExtraConfig = with pkgs.lib.kernel; {
  # 选项 A: ZSTD - 最佳平衡（推荐）
  KERNEL_ZSTD = yes;
  KERNEL_GZIP = no;
  KERNEL_XZ = no;
  KERNEL_LZ4 = no;
  
  # ZSTD 压缩级别（1-22，默认 22）
  ZSTD_COMPRESSION = freeform "19";  # 稍快的解压，略大的体积
  
  # 选项 B: LZ4 - 最快解压（牺牲体积）
  # KERNEL_LZ4 = yes;
  
  # 选项 C: XZ - 最小体积（牺牲速度）
  # KERNEL_XZ = yes;
};
```

**对比：**
| 算法 | 压缩比 | 解压速度 | 启动时间 | 推荐场景 |
|-----|--------|---------|---------|---------|
| GZIP | 中等 | 中等 | 中等 | 兼容性 |
| XZ | 最高 | 慢 | 慢 | 存储受限 |
| LZ4 | 低 | 最快 | 最快 | 频繁重启 |
| **ZSTD** | 高 | 快 | 快 | **NAS 推荐** |

## 3. 定时器频率优化

### HZ 值选择

```nix
structuredExtraConfig = with pkgs.lib.kernel; {
  # 当前默认通常是 250 Hz
  
  # 选项 A: 100 Hz - 最省电（推荐 NAS）
  HZ_100 = yes;
  HZ_250 = no;
  HZ_300 = no;
  HZ_1000 = no;
  HZ = freeform "100";
  
  # 选项 B: 300 Hz - 平衡
  # HZ_300 = yes;
  # HZ = freeform "300";
  
  # 选项 C: 1000 Hz - 低延迟（桌面/游戏）
  # HZ_1000 = yes;
  # HZ = freeform "1000";
};
```

**HZ 值影响：**
- **100 Hz**: 最低功耗，适合 NAS 24/7 运行
- **250 Hz**: 内核默认，平衡
- **300 Hz**: 更好的响应，略高功耗
- **1000 Hz**: 最佳响应，最高功耗（不推荐服务器）

## 4. 内核抢占模型

```nix
structuredExtraConfig = with pkgs.lib.kernel; {
  # 选项 A: 无抢占 - 吞吐量优先（推荐 NAS）
  PREEMPT_NONE = yes;
  PREEMPT_VOLUNTARY = no;
  PREEMPT = no;
  
  # 选项 B: 自愿抢占 - 平衡
  # PREEMPT_VOLUNTARY = yes;
  
  # 选项 C: 完全抢占 - 低延迟（桌面）
  # PREEMPT = yes;
};
```

**NAS 推荐：** `PREEMPT_NONE` - 最大化吞吐量

## 5. 内存分配器优化

```nix
structuredExtraConfig = with pkgs.lib.kernel; {
  # SLUB 是现代内核默认（推荐）
  SLUB = yes;
  SLAB = no;
  SLOB = no;
  
  # SLUB 优化
  SLUB_CPU_PARTIAL = yes;    # CPU 部分页优化
};
```

## 6. I/O 调度器优化

```nix
structuredExtraConfig = with pkgs.lib.kernel; {
  # 对于 NAS 工作负载
  MQ_IOSCHED_KYBER = yes;    # 低延迟调度器
  IOSCHED_BFQ = yes;         # 公平队列调度器（推荐）
  MQ_IOSCHED_DEADLINE = yes; # Deadline 调度器
  
  # BFQ 作为默认
  BFQ_GROUP_IOSCHED = yes;   # BFQ cgroup 支持
  
  # 禁用老旧的单队列调度器
  IOSCHED_CFQ = no;
};
```

## 7. TCP 和网络栈优化

```nix
structuredExtraConfig = with pkgs.lib.kernel; {
  # TCP 拥塞控制算法
  TCP_CONG_BBR = yes;        # Google BBR - 推荐用于 NAS
  DEFAULT_BBR = yes;
  
  # 其他可选算法
  TCP_CONG_CUBIC = yes;      # 传统 CUBIC（备用）
  TCP_CONG_HTCP = yes;
  
  # 网络性能优化
  NET_SCH_FQ = yes;          # Fair Queue 调度器（BBR 需要）
  NET_SCH_FQ_CODEL = yes;    # 减少缓冲膨胀
  
  # 大型接收卸载
  INET_LRO = yes;
  
  # 网络命名空间
  NET_NS = yes;              # Docker/容器必需
};
```

**BBR vs CUBIC：**
- **BBR**: 更好的吞吐量，特别是高延迟网络
- **CUBIC**: 传统算法，更成熟

## 8. 文件系统优化

```nix
structuredExtraConfig = with pkgs.lib.kernel; {
  # Btrfs 优化
  BTRFS_FS = yes;
  BTRFS_FS_POSIX_ACL = yes;
  BTRFS_FS_CHECK_INTEGRITY = no;  # 禁用完整性检查（性能）
  
  # Ext4 优化
  EXT4_FS = yes;
  EXT4_USE_FOR_EXT2 = yes;        # 使用 Ext4 驱动处理 Ext2/3
  EXT4_FS_POSIX_ACL = yes;
  
  # 文件系统缓存
  FSCACHE = yes;
  CACHEFILES = yes;
};
```

## 9. CPU 特定优化

```nix
structuredExtraConfig = with pkgs.lib.kernel; {
  # N5095 (Jasper Lake) 特定
  MCORE2 = no;
  MATOM = yes;               # Atom 系列优化
  
  # 禁用不需要的 CPU 特性
  NUMA = no;                 # N5095 是单路 CPU，禁用 NUMA
  NUMA_BALANCING = no;
  
  # CPU 频率调节器
  CPU_FREQ_DEFAULT_GOV_SCHEDUTIL = yes;  # 推荐：更智能的调频
  CPU_FREQ_GOV_ONDEMAND = no;
  CPU_FREQ_GOV_CONSERVATIVE = no;
  CPU_FREQ_GOV_PERFORMANCE = yes;        # 保留作为备选
  CPU_FREQ_GOV_POWERSAVE = yes;          # 保留作为备选
  
  # Intel P-State 驱动
  X86_INTEL_PSTATE = yes;
  X86_ACPI_CPUFREQ = no;     # 旧驱动，禁用
};
```

## 10. 安全特性优化（性能 vs 安全）

### 保守方案（推荐）
```nix
structuredExtraConfig = with pkgs.lib.kernel; {
  # 保留大部分安全特性
  RETPOLINE = yes;           # Spectre v2 缓解
  PAGE_TABLE_ISOLATION = yes; # Meltdown 缓解
  STACKPROTECTOR = yes;
  STACKPROTECTOR_STRONG = yes;
  
  # 禁用调试相关
  DEBUG_KERNEL = no;
  DEBUG_INFO = no;
  KASAN = no;                # 地址消毒剂
  UBSAN = no;                # 未定义行为消毒剂
};
```

### 激进方案（最大性能，降低安全性）
```nix
structuredExtraConfig = with pkgs.lib.kernel; {
  # ⚠️ 仅用于隔离环境
  RETPOLINE = no;            # 禁用 Spectre 缓解（+2-5% 性能）
  PAGE_TABLE_ISOLATION = no; # 禁用 Meltdown 缓解（+5-10% 性能）
  STACKPROTECTOR = no;
  
  # 禁用所有调试
  DEBUG_KERNEL = no;
  DEBUG_INFO = no;
  KASAN = no;
  UBSAN = no;
  LOCKDEP = no;
  PROVE_LOCKING = no;
};
```

## 11. 模块签名和安全启动

```nix
structuredExtraConfig = with pkgs.lib.kernel; {
  # 如果不需要安全启动，可以禁用
  MODULE_SIG = no;           # 禁用模块签名验证
  MODULE_SIG_FORCE = no;
  SECURITY_LOCKDOWN_LSM = no;
  
  # 或保持启用以获得安全性
  # MODULE_SIG = yes;
  # MODULE_SIG_ALL = yes;
  # MODULE_SIG_SHA256 = yes;
};
```

## 12. 内存管理优化

```nix
structuredExtraConfig = with pkgs.lib.kernel; {
  # 透明大页
  TRANSPARENT_HUGEPAGE = yes;
  TRANSPARENT_HUGEPAGE_ALWAYS = no;
  TRANSPARENT_HUGEPAGE_MADVISE = yes;  # 按需使用
  
  # 内存压缩
  ZSWAP = yes;               # 交换压缩
  ZRAM = yes;                # 压缩 RAM
  
  # KSM (内核同页合并) - 对虚拟化有用
  KSM = yes;
  
  # CMA (连续内存分配器)
  CMA = yes;
  DMA_CMA = yes;
};
```

## 13. 电源管理深度优化

```nix
structuredExtraConfig = with pkgs.lib.kernel; {
  # Intel 特定电源管理
  INTEL_IDLE = yes;
  INTEL_IDLE_STATES_SUPPORT = yes;
  
  # 运行时电源管理
  PM_RUNTIME = yes;
  PM_ADVANCED_DEBUG = no;    # 禁用调试
  
  # 设备电源管理
  USB_AUTOSUSPEND = yes;
  SATA_MOBILE_LPM_POLICY = freeform "3";  # 最大省电
  
  # CPU 空闲状态
  CPU_IDLE = yes;
  CPU_IDLE_GOV_LADDER = yes;
  CPU_IDLE_GOV_MENU = yes;
  
  # 动态时钟
  NO_HZ_FULL = no;           # 全 tickless（服务器不需要）
  NO_HZ_IDLE = yes;          # 空闲 tickless（推荐）
};
```

## 14. 完整的推荐配置模板

### 🏆 最优方案：性能与稳定性平衡

```nix
inputs: { pkgs, lib, config, ... }:

let
  myCustomKernel = pkgs.linuxPackages_latest.extend (self: super: {
    kernel = super.kernel.override {
      
      # 编译器优化：LTO + Tremont 特化
      stdenv = pkgs.withCFlags [
        "-march=tremont"
        "-mtune=tremont"
        "-O2"                    # O2 更稳定
        "-pipe"
        "-fno-semantic-interposition"
      ] pkgs.stdenv;
      
      features = {
        iwlwifi = false;
        btusb = false;
        netfilter = true;
      };

      structuredExtraConfig = with pkgs.lib.kernel; {
        # 架构优化
        MCORE2 = no;
        MATOM = yes;
        NUMA = no;               # 单路 CPU 禁用
        
        # 压缩：ZSTD
        KERNEL_ZSTD = yes;
        KERNEL_GZIP = no;
        
        # 定时器：100Hz 省电
        HZ_100 = yes;
        HZ = freeform "100";
        
        # 抢占：服务器模式
        PREEMPT_NONE = yes;
        PREEMPT_VOLUNTARY = no;
        
        # I/O 调度器：BFQ
        IOSCHED_BFQ = yes;
        BFQ_GROUP_IOSCHED = yes;
        
        # TCP：BBR
        TCP_CONG_BBR = yes;
        DEFAULT_BBR = yes;
        NET_SCH_FQ = yes;
        
        # CPU 调频：schedutil
        CPU_FREQ_DEFAULT_GOV_SCHEDUTIL = yes;
        
        # 禁用调试
        DEBUG_KERNEL = no;
        DEBUG_INFO = no;
        
        # 保留安全特性
        RETPOLINE = yes;
        PAGE_TABLE_ISOLATION = yes;
        STACKPROTECTOR_STRONG = yes;
        
        # ... 其他配置（存储、USB、音频等）
      };
    };
  });
in
{ ... }
```

## 15. 性能测试对比

优化前后应该进行的测试：

```bash
# 启动时间
systemd-analyze

# 网络吞吐量
iperf3 -s  # 服务器
iperf3 -c <server> -t 60  # 客户端

# 磁盘 I/O
fio --name=test --ioengine=libaio --rw=randrw --bs=4k --numjobs=4 --size=1G

# CPU 性能
sysbench cpu --threads=4 run

# 内存带宽
sysbench memory --threads=4 run

# 功耗（如果有监控）
sensors | grep Package
```

## 总结：优化优先级

### 🥇 高优先级（推荐立即应用）
1. ✅ `-march=tremont -mtune=tremont` - CPU 架构优化
2. ✅ `KERNEL_ZSTD` - 压缩算法
3. ✅ `HZ_100` - 定时器频率（NAS）
4. ✅ `TCP_CONG_BBR` - 网络性能
5. ✅ `PREEMPT_NONE` - 服务器抢占模型
6. ✅ `NUMA = no` - 禁用单路 CPU 的 NUMA

### 🥈 中优先级（根据需求）
1. ⚠️ LTO - 编译时间换性能
2. ⚠️ `CPU_FREQ_DEFAULT_GOV_SCHEDUTIL` - 更智能的调频
3. ⚠️ `IOSCHED_BFQ` - I/O 调度器

### 🥉 低优先级（高级用户）
1. 禁用安全缓解措施（⚠️ 安全风险）
2. `-O3` vs `-O2` 选择
3. 透明大页优化

需要我基于这些优化创建一个完整的配置文件吗？

# NixOS Gateway

基于 NixOS 构建的高性能透明代理网关与旁路由系统。

本项目结合 Disko 声明式磁盘分区、CachyOS 优化内核、sing-box TProxy 透明转发与模块化基座配置，采用 npins 进行轻量级依赖锁定，并提供开箱即用的全自动无人值守安装镜像。

---

## 核心特性

- **透明代理与流量分流**
  - 基于 sing-box 与 nftables 实现 TProxy 模式流量劫持。
  - 支持 DNS 防污染与国内外域名智能分流，无缝对接本地 SOCKS5 上游代理。

- **内核与存储优化**
  - 集成 CachyOS 优化内核，默认启用 BBRv3 拥塞控制算法与 CAKE 队列管理机制。
  - 基于 Disko 管理 Btrfs 磁盘布局，并开启 zstd 透明压缩。

- **模块化基座设计 (`modules/base`)**
  - **内存调优**：提供 Aggressive / Balanced / Conservative 多档位配置，启用 MGLRU 与 zstd zramSwap。
  - **容器生态**：支持 Podman 与 Docker 容器引擎，提供 Rootless 容器支持、容器 DNS 解析与防火墙自动集成。
  - **统一网络**：基于 systemd-networkd 统一抽象网络接口、静态 IP、IPv6 DHCP、路由规则及协议栈优先级。
  - **自动维护**：内置 NixOS 垃圾回收（GC）、定时升级与远程 Git 配置同步。

- **全自动无人值守安装**
  - 预打包 NixOS 离线闭包，启动镜像后自动执行磁盘分区、格式化、系统部署并重启。

- **现代化依赖管理**
  - 采用 [npins](https://github.com/andir/npins) 锁定依赖版本，避免 Flakes 繁重依赖与传统 Channels 的不稳定性。

- **完备的质量保障体系**
  - 覆盖配置静态断言检查、ISO 镜像评估构建与 KVM 虚拟机运行时集成测试。

---

## 目录结构

```text
.
├── AGENTS.md                   # AI 协作与仓库开发规范
├── configuration.nix           # 主机核心配置（网关系统定义）
├── iso.nix                     # 全自动无人值守安装 ISO 构建定义
├── docker-compose.yml          # 本地容器化开发环境配置
│
├── docs/                       # 项目详细文档
│   └── npins/                  # npins 依赖管理与测试指南
│       ├── cli.md              # npins 命令行工具使用指南
│       ├── usage.md            # npins 依赖引入与覆盖指南
│       └── testing.md          # 静态检查与 VM 测试指南
│
├── modules/                    # 自定义 NixOS 模块库
│   └── base/                   # 系统基础模块
│       ├── default.nix         # 基础模块总入口与通用设置
│       ├── container.nix       # 容器引擎模块 (Podman / Docker)
│       ├── memory.nix          # 内存与内核参数调优模块
│       ├── network.nix         # 统一 systemd-networkd 网络抽象模块
│       └── update.nix          # 自动维护、GC 与 Git 同步模块
│
├── npins/                      # npins 依赖锁定配置
│   ├── default.nix             # 依赖加载入口（工具自动生成）
│   └── sources.json            # 依赖锁定源定义 (nixpkgs, dot-exts 等)
│
└── tests/                      # 自动化测试套件
    ├── default.nix             # 测试入口
    ├── static.nix              # 主机配置静态断言测试
    ├── installer.nix           # ISO 镜像构建与静态检查
    ├── vmtest.nix              # NixOS 虚拟机运行时测试
    └── run.sh                  # 测试执行脚本
```

---

## 依赖管理 (npins)

本项目使用 [npins](https://github.com/andir/npins) 进行轻量级依赖版本锁定。

### 常用命令

```bash
# 查看依赖状态
npins show

# 更新全部依赖
npins update

# 更新指定依赖
npins update dot-exts

# 校验依赖哈希完整性
npins verify
```

详细操作规范请参阅 [npins CLI 指南](docs/npins/cli.md) 与 [npins 产物使用指南](docs/npins/usage.md)。

---

## 快速上手

### 1. 启动本地开发环境

项目提供了 Docker Compose 开发容器，可挂载当前目录进行 Nix 开发与调试：

```bash
# 启动开发容器
docker compose up -d dev

# 进入容器或通过 SSH 连接 (端口: 2222)
ssh root@localhost -p 2222
```

### 2. 定制主机配置

根据实际硬件拓扑与网络规划，修改 `configuration.nix` 中的关键配置：

- **目标安装磁盘**：

  ```nix
  # 修改为目标设备实际路径（如 /dev/sda 或 /dev/nvme0n1）
  exts.hardware.disk.btrfs.device = "/dev/sda";
  ```

- **网卡与 IP 地址分配**：

  ```nix
  base.network.interfaces.eth0 = {
    dhcp = "ipv6";
    ipv4 = {
      addresses = [
        {
          address = "192.168.2.5";
          prefixLength = 24;
        }
      ];
      gateway = "192.168.2.1";
    };
  };
  ```

- **上游代理端口**：

  默认上游 SOCKS5 代理地址为 `127.0.0.1:2080`。如需修改，请调整 `networking.proxy`、`base.update.proxy` 及 `services.sing-box` 中的对应端口。

---

## 测试与验证

在提交配置更改或发布镜像前，建议运行测试套件验证配置有效性：

```bash
# 运行完整测试套件（静态检查 + ISO 构建评估 + VM 测试）
bash tests/run.sh
```

分项单独测试：

```bash
# 1. 静态配置断言测试
nix-build tests/static.nix --no-out-link

# 2. ISO 镜像构建静态评估
nix-build tests/installer.nix --no-out-link

# 3. 虚拟机集成测试 (需要系统具备 /dev/kvm 虚拟化支持)
nix-build tests/vmtest.nix --no-out-link
```

详细测试方法及测试用例编写请参考 [项目测试指南](docs/npins/testing.md)。

---

## 构建与部署

### 1. 构建全自动安装 ISO

运行以下命令构建无人值守安装镜像：

```bash
nix-build iso.nix -o result
```

构建完成后，生成的 `.iso` 镜像文件位于 `result/iso/` 目录下。

### 2. 部署流程

1. **写入介质**：将生成的 ISO 镜像写入 U 盘或挂载至物理机/虚拟机 CD-ROM。
2. **引导启动**：设置目标设备优先从安装镜像引导启动。
3. **自动安装**：系统引导后将自动执行无人值守流水线：
   - 检查并等待目标磁盘就绪；
   - 执行 Disko 脚本完成 GPT 分区、Btrfs 格式化与子卷挂载；
   - 离线写入 NixOS 系统闭包；
   - 安装完成后自动重启并引导进入新系统。

---

## 模块配置参考

### Base 基础模块 (`modules/base`)

| 模块 | 配置项 | 说明 |
| :--- | :--- | :--- |
| **通用设置** | `base.enable` | 是否启用基础系统配置（时区、语言、SSH 服务及命令行增强） |
| **内存优化** | `base.memory.mode` | 内存优化模式：`aggressive` (<1G)、`balanced` (<2G)、`conservative` (>=4G)、`none` |
| **容器引擎** | `base.container.podman` | 启用 Podman 引擎、Docker 兼容套接字与容器 DNS 自动解析 |
| **容器引擎** | `base.container.docker` | 启用 Docker 守护进程与 Rootless 支持 |
| **网络管理** | `base.network` | 启用 systemd-networkd 统一网络抽象、多网卡配置与 DNS 解析策略 |
| **自动维护** | `base.update` | 启用 Nix 垃圾回收 (GC)、系统自动升级及远程 Git 配置同步 |

### 扩展模块 (`dot-exts`)

| 模块 | 配置项 | 说明 |
| :--- | :--- | :--- |
| **Btrfs 磁盘** | `exts.hardware.disk.btrfs` | 基于 Disko 的 Btrfs 磁盘分区方案，自动创建 ESP 分区与压缩子卷 |
| **CachyOS 内核** | `exts.kernel.cachyos` | 启用 CachyOS 内核包及 BBRv3 / CAKE 优化参数 |

---

## CI/CD 自动化流程

项目通过 GitHub Actions 提供持续集成与交付支持：

- **CI 检查工作流 (`.github/workflows/ci.yml`)**
  在代码提交或创建 PR 时，自动运行静态断言检查、ISO 构建评估与 KVM 虚拟机集成测试。

- **版本发布工作流 (`.github/workflows/release.yml`)**
  支持手动触发或定时运行，自动构建安装镜像、执行多卷压缩并发布至 GitHub Releases。

- **依赖更新工作流 (`.github/workflows/update-npins.yml`)**
  定时检查并升级 npins 依赖锁定源，验证测试通过后自动提交 PR。

---

## 许可证

本项目基于 [MIT 许可证](LICENSE) 开源。详细条款请参阅 [LICENSE](LICENSE) 文件。

# Nas Companion V2 — 一键安装交付包

目标体验（Linux NAS）：

```bash
curl -fsSL <固定下载地址>/install.sh | bash
```

执行后自动完成：检测 Linux 架构 → 下载对应安装包 → SHA-256 校验 →
解压 → 启动 nas-installer 进入 Xiaoya-style 安装菜单。无需 clone Git、
无需安装 Go、无需手工编译。

## 交付内容（本目录）

| 文件 | 说明 |
|---|---|
| `install.sh` | 一键安装脚本（bash，Linux amd64/arm64） |
| `nas-companion-linux-amd64.tar.gz` | Linux x86-64 安装包（bin/nas-installer + hub/ 构建上下文） |
| `nas-companion-linux-arm64.tar.gz` | Linux AArch64 安装包 |
| `SHA256SUMS` | 两个安装包的 SHA-256 校验和 |

安装包内部布局（与 `nas/packaging/package.sh` 产出一致）：

```text
nas-companion/
  bin/nas-installer      # 安装器（静态链接，CGO_ENABLED=0）
  hub/                   # V2 Hub 构建上下文（源码 + Dockerfile），
                         # 安装器运行时通过 <bin>/../hub 定位并本地构建镜像
```

## 公开下载（已发布）

本目录 4 个文件已发布到公开 Delivery 仓库
[github.com/w876499651-ctrl/nas-companion-downloads](https://github.com/w876499651-ctrl/nas-companion-downloads)
（无需 GitHub 登录、无需 Token）。`install.sh` 默认
`BASE_URL = https://raw.githubusercontent.com/w876499651-ctrl/nas-companion-downloads/main`。

一行安装（Linux，自动检测架构 → 下载 → SHA-256 校验 → 解压 → 启动菜单）：

```bash
curl -fsSL https://raw.githubusercontent.com/w876499651-ctrl/nas-companion-downloads/main/install.sh | bash
```

覆盖安装/指定目录/只装不启动：见下方环境变量。

## install.sh 可配置项（环境变量，均可选）

| 变量 | 默认 | 说明 |
|---|---|---|
| `NAS_COMPANION_BASE_URL` | 公开 Delivery 仓库 raw 地址 | 产物基础 URL |
| `NAS_COMPANION_INSTALL_DIR` | `$HOME/.nas-companion` | 安装目录 |
| `NAS_COMPANION_NO_LAUNCH=1` | 关 | 只安装不自动进入菜单 |

## 验证结果（mock 环境，未操作真实 NAS）

| 项 | 结果 |
|---|---|
| 交叉编译 linux/amd64 + linux/arm64 | ✅ 两者均可正常交叉构建（CGO_ENABLED=0 静态） |
| ELF 架构 | ✅ amd64=EM_X86_64，arm64=EM_AARCH64 |
| tar 内 nas-installer 权限 | ✅ `-rwxr-xr-x`（--mode=0755，跨平台打包仍保 exec 位） |
| 下载逻辑（本地 HTTP mock） | ✅ 按架构下载对应 tar.gz + SHA256SUMS |
| 架构识别 | ✅ x86_64/amd64→amd64；aarch64/arm64→arm64；mips→明确报错 |
| SHA-256 校验 | ✅ 通过；损坏包→校验失败并中止，不写入任何文件 |
| OS 守卫 | ✅ 非 Linux 明确报错 |
| 解压 + 布局 | ✅ bin/nas-installer + hub/Dockerfile 完整 |
| Installer 进入菜单 | ✅ 同一打包布局的安装器启动渲染完整 Xiaoya 菜单（1-13+0） |

注：Linux 二进制在本 Windows 开发机无法直接执行（WSL 被安全策略禁用、
禁止在真实 NAS 执行），菜单启动以同一打包布局的 host 构建实测；
Linux 二进制的可执行性由 tar 0755 模式 + install.sh 内 `chmod +x` 保证，
建议在任意 Linux 主机（非生产 NAS）上最终确认一次。

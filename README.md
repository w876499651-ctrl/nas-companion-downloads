# Nas Companion V2 — 一键安装交付包

目标体验（Linux NAS）：

```bash
curl -fsSL https://cdn.jsdelivr.net/gh/w876499651-ctrl/nas-companion-downloads@v1.0.0/install.sh | bash
```

执行后自动完成：检测 Linux 架构 → 从**不可变版本 tag** 下载对应安装包 → SHA-256 校验 →
解压 → 启动 nas-installer 进入 Xiaoya-style 安装菜单。无需 clone Git、
无需安装 Go、无需手工编译。

> **版本一致性保证**：安装包（`tar.gz`）与校验和（`SHA256SUMS`）始终从
> **同一个不可变 git tag** 下载，禁止使用 mutable 的 `@main`。这从根本上杜绝了
> CDN 分别缓存不同文件导致的"新校验和 + 旧安装包"混合问题。

## 交付内容（本目录）

| 文件 | 说明 |
|---|---|
| `install.sh` | 一键安装脚本（bash，Linux amd64/arm64），内部固定 `ARTIFACT_REF` |
| `nas-companion-linux-amd64.tar.gz` | Linux x86-64 安装包（bin/nas-installer + hub/ 构建上下文） |
| `nas-companion-linux-arm64.tar.gz` | Linux AArch64 安装包 |
| `SHA256SUMS` | 两个安装包的 SHA-256 校验和 |
| `scripts/release.sh` | 不可变版本发布脚本（打 tag → 推送 → 校验远程一致性） |
| `tests/test-mixed-cache.sh` | 混合缓存自动测试（证明设计不会产生新旧文件混用） |

安装包内部布局（与 `nas/packaging/package.sh` 产出一致）：

```text
nas-companion/
  bin/nas-installer      # 安装器（静态链接，CGO_ENABLED=0）
  hub/                   # V2 Hub 构建上下文（源码 + Dockerfile），
                         # 安装器运行时通过 <bin>/../hub 定位并本地构建镜像
```

## 不可变产物版本设计

### 为什么不用 `@main`

jsDelivr 对 `@main`（mutable branch ref）下的**每个文件独立缓存**。发布时若
`SHA256SUMS` 已更新但 `tar.gz` 仍为 CDN 旧缓存，就会出现校验和与安装包不属于
同一提交的情况，导致 SHA-256 校验失败（真实 NAS 已复现）。

### 解决方案：单一 `ARTIFACT_REF`

`install.sh` 内定义唯一版本变量：

```bash
ARTIFACT_REF="v1.0.0"
```

**所有下载通道**（主源 + 全部备用源）的 URL 都嵌入同一个 `ARTIFACT_REF`：

| 优先级 | 通道 | URL 模板 | 说明 |
|---|---|---|---|
| 1（主） | jsDelivr anycast | `https://cdn.jsdelivr.net/gh/<repo>@<tag>/<file>` | 全球加速，默认 |
| 2（备用） | jsDelivr G-Core | `https://gcore.jsdelivr.net/gh/<repo>@<tag>/<file>` | **可信第二通道**，不同 CDN 运营商，绕过 anycast 路由问题 |
| 3（最后） | GitHub Raw | `https://raw.githubusercontent.com/<repo>/<tag>/<file>` | 部分 NAS 网络不稳定（SSL_ERROR_SYSCALL），仅作兜底 |

关键性质：

- **tarball 与 SHA256SUMS 必属同一提交**：两者 URL 都拼入同一个 `ARTIFACT_REF`。
- **主备切换不混版本**：从 cdn.jsdelivr.net 切到 gcore.jsdelivr.net 只换 CDN 运营商，版本不变。
- **旧 bootstrap 自洽**：即使 CDN 缓存了旧版 `install.sh`，它引用的是旧 tag，旧 tag 下文件永远一致。
- **不绕过 SHA-256**：校验失败立即中止，不写入任何文件。

## 一行安装（Linux）

```bash
curl -fsSL https://cdn.jsdelivr.net/gh/w876499651-ctrl/nas-companion-downloads@v1.0.0/install.sh | bash
```

执行后单条命令直接进入可交互 Installer（自动从 `/dev/tty` 读取输入），
不需要再执行第二条命令。

> ⚠️ **已废弃**：以下 `@main` 命令不再推荐，可能导致安装包与校验和不一致：
> ```bash
> curl -fsSL https://cdn.jsdelivr.net/gh/w876499651-ctrl/nas-companion-downloads@main/install.sh | bash
> ```

默认安装目录为 `/opt/nas-companion`（NAS 惯例；不依赖 `$HOME`，因为部分
NAS 用户没有可用的 home 目录）。普通用户执行时，脚本会**自动通过 sudo**
完成创建目录 / 解压 / 赋权 / 启动 Installer（sudo 密码从真实终端输入）；
已经是 root 时不会重复 sudo。无需在命令中手写 sudo、环境变量或安装路径。

覆盖安装/指定目录/只装不启动：见下方环境变量。

## install.sh 可配置项（环境变量，均可选）

| 变量 | 默认 | 说明 |
|---|---|---|
| `NAS_COMPANION_BASE_URL` | 三通道自动回退（均使用 `ARTIFACT_REF`） | 产物基础 URL（需包含不可变 ref，如 `...@v1.0.0`）；显式设置后不追加备用源 |
| `NAS_COMPANION_INSTALL_DIR` | `/opt/nas-companion`（脚本自动 sudo） | 安装目录（显式覆盖） |
| `NAS_COMPANION_NO_LAUNCH=1` | 关 | 只安装不自动进入菜单 |
| `NAS_COMPANION_KEEP_TMP=1` | 关 | 保留临时目录（仅自动验证用） |

## 发布流程（维护者）

每次发布新版本遵循以下步骤，确保不可变 tag 与自洽产物：

### 前置条件

1. 新安装包已构建：`nas-companion-linux-amd64.tar.gz`、`nas-companion-linux-arm64.tar.gz`
2. 生成校验和：`sha256sum nas-companion-linux-*.tar.gz > SHA256SUMS`
3. 本地校验通过：`sha256sum -c SHA256SUMS`

### 步骤

```bash
# 1. 更新 install.sh 中的 ARTIFACT_REF 为新版本
#    编辑 install.sh，将 ARTIFACT_REF="v1.0.0" 改为 ARTIFACT_REF="v1.1.0"

# 2. 提交变更
git add install.sh SHA256SUMS nas-companion-linux-*.tar.gz
git commit -m "release: v1.1.0"
git push origin main

# 3. 运行发布脚本（打不可变 tag + 推送 + CDN purge + 远程一致性校验）
./scripts/release.sh v1.1.0
```

`scripts/release.sh` 自动完成：

1. 校验本地 `SHA256SUMS` 与 tarball 一致
2. 校验 `install.sh` 的 `ARTIFACT_REF` 与目标版本一致
3. 检查工作区干净
4. 创建并推送 git tag（不可变，禁止重复使用）
5. 请求 jsDelivr CDN purge（保险；新 tag 首次访问会自动回源）
6. 从远程下载 tarball + SHA256SUMS 并校验一致性
7. 输出新的唯一安装命令

### 发布后验证

```bash
# 在任意 Linux 主机（非生产 NAS）执行新命令，确认安装成功
curl -fsSL https://cdn.jsdelivr.net/gh/w876499651-ctrl/nas-companion-downloads@v1.1.0/install.sh | bash
```

## 自动测试

```bash
bash tests/test-mixed-cache.sh
```

测试覆盖：

| 测试 | 验证点 |
|---|---|
| 单一 `ARTIFACT_REF` | install.sh 中只有一个版本定义，且不是 `main` |
| 所有 URL 嵌入同一 ref | 主源 + 备用源均使用 `ARTIFACT_REF`，无 `@main` |
| SHA 校验拒绝不匹配 | 新 SHA + 旧 tarball → 非零退出，中止安装 |
| SHA 校验接受匹配 | 一致 tarball + SHA → 零退出 |
| 混合缓存模拟 | 同 ref 通过；跨 ref 混合（vA tarball + vB SHA）失败 |
| 设计证明 | `fetch_any` 仅用 `BASE_URL`/`FALLBACK_URLS`，无逐文件 ref 覆盖 |

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
| 不可变 ref 下载 | ✅ tarball + SHA256SUMS 均从同一 `ARTIFACT_REF` 获取 |
| 多通道同 ref 回退 | ✅ cdn.jsdelivr.net → gcore.jsdelivr.net → GitHub Raw，均使用同一 tag |
| 混合缓存防护 | ✅ `tests/test-mixed-cache.sh` 证明设计不产生新旧混用 |
| 单命令进入交互菜单 | ✅ exec 前自动重接 `/dev/tty`，curl \| bash 一条命令直达菜单 |
| 默认安装目录 `/opt/nas-companion` | ✅ HOME 不存在/不可写的 NAS 用户也可装 |
| 自动 sudo 提权 | ✅ 非 root 自动 sudo 完成 mkdir/解压/chmod/启动；root 时不重复 sudo |

注：Linux 二进制在本 Windows 开发机无法直接执行（WSL 被安全策略禁用、
禁止在真实 NAS 执行），菜单启动以同一打包布局的 host 构建实测；
Linux 二进制的可执行性由 tar 0755 模式 + install.sh 内 `chmod +x` 保证，
建议在任意 Linux 主机（非生产 NAS）上最终确认一次。

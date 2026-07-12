# Phicomm N1 ImmortalWrt

可审计、可重复的斐讯 N1 ImmortalWrt 固件配方。仓库只保存构建配置和脚本；编译与 N1 镜像封装可以由 GitHub Actions 的 Ubuntu runner 完成，也可以在本地 Docker Desktop 中手动执行。

## 固件内容

- ImmortalWrt 25.12.1，`armsr/armv8/generic`
- LuCI、简体中文与默认 Argon 主题
- PassWall 2 与简体中文
- Xray、sing-box 与 Hysteria 2 原生客户端
- PassWall 2 节点覆盖 SOCKS/HTTP、Shadowsocks、VMess、VLESS、Trojan、VLESS+REALITY、Hysteria 2、TUIC、AnyTLS、ShadowTLS、SSH 与 WireGuard
- 斐讯 N1 BCM43455 SDIO Wi-Fi 的驱动选择、无线脚本、`iw`/`iwinfo`、监管数据库以及 WPA2/WPA3 用户层
- ZeroTier 与 LuCI 页面（默认关闭、未配置网络）
- ttyd、htop、nano、tcpdump、iperf3、SFTP 与常用存储工具
- ophub Phicomm N1 / S905D 启动层与稳定内核

HomeProxy、Nikki、AdGuard Home 和旧版 PassWall 均未加入，避免代理、DNS及防火墙管理冲突。SSR、Simple-Obfs、独立 Shadowsocks-Rust 与独立 NaiveProxy 也未重复加入；当前 Xray 与 sing-box 已覆盖主要现代协议。

## 固定版本

所有源码 commit、内核版本、默认 IP 和分区大小都记录在 [`versions.env`](versions.env)。默认管理地址是 `192.168.10.1/24`；BOOTFS/ROOTFS 为 `256/2048 MiB`。

该公开镜像不包含代理节点、订阅地址、ZeroTier Network ID、密码或其他私密配置。

## 手动构建

### GitHub Actions 构建

1. 打开仓库的 **Actions** 页面。
2. 选择 **Build Phicomm N1 ImmortalWrt**。
3. 点击 **Run workflow**，确认从 `main` 分支运行。
4. 等待单一构建任务完成；不要重复并行触发，也不要在失败时连续重跑。
5. 从 **Releases** 下载 `.img.gz` 与 `SHA256SUMS`，在写盘前核对校验值。

工作流只有 `workflow_dispatch` 手动入口；不响应 push、PR 或定时事件。它只构建一台 N1 和一个内核，并设置并发互斥与 330 分钟超时，以遵守 GitHub Actions 的合理使用要求。

编译和 N1 打包是两个独立 job。成功编译的标准 `generic-rootfs.tar.gz`、配置、清单和日志会作为工作流 Artifact 保留 7 天。如果只有后面的打包或发布 job 失败，请在该次运行中选择 **Re-run failed jobs**；GitHub 会复用已经保存的 rootfs，不会再次执行耗时的 ARM64 编译。只有发起一次全新的 workflow run 才会从头编译。

### 本地 Docker 构建

本地 Docker 构建用于更快调试和生成临时镜像；GitHub Actions 仍然是正式 release 通道。本流程只创建一个专用镜像、一个专用 volume 和一个本地输出目录，不会修改 Docker Desktop 设置，不会清理已有镜像、容器或 volume，也不会操作 U 盘或 eMMC。

Docker Desktop 需要先由你手动启动，并在本仓库根目录打开 PowerShell。第一次先构建本地编译环境镜像并创建专用 volume：

```powershell
New-Item -ItemType Directory -Force local-output

docker build `
  --platform linux/amd64 `
  -t n1-immortalwrt-builder:25.12.1 `
  -f Dockerfile.local .

docker volume create n1-immortalwrt-build-work
```

个人本地使用时，推荐创建一个长期保留的构建容器：

```powershell
docker run -dit `
  --name n1-immortalwrt-build `
  --platform linux/amd64 `
  --privileged `
  -v n1-immortalwrt-build-work:/work `
  -v ${PWD}:/recipe:ro `
  -v ${PWD}\local-output:/output `
  n1-immortalwrt-builder:25.12.1 `
  sleep infinity
```

以后每次要重新构建镜像时，执行：

```powershell
docker exec -it n1-immortalwrt-build bash /recipe/scripts/local-build-inside-docker.sh
```

如果你只想要一次性干净运行，也可以不用长期容器：

```powershell
docker run --rm `
  --name n1-immortalwrt-build `
  --platform linux/amd64 `
  --privileged `
  -v n1-immortalwrt-build-work:/work `
  -v ${PWD}:/recipe:ro `
  -v ${PWD}\local-output:/output `
  n1-immortalwrt-builder:25.12.1
```

三个挂载点的含义：

- `/work`：Docker volume，保存 ImmortalWrt 源码、下载缓存、feeds、ccache、编译中间文件和临时 release。
- `/recipe`：当前 Windows 仓库目录的只读挂载，容器只能读取构建配方，不能改仓库文件。
- `/output`：Windows 的 `local-output` 目录，容器只把最终产物写回这里。

最终数据流是：

```text
/work/openwrt + /work/packer
        ↓
/work/release
        ↓
/output
        ↓
<repo>\local-output
```

`--privileged` 是给 ophub 打包步骤使用的，因为生成完整 `.img.gz` 通常需要 loop/mount 能力。这个容器只挂载上面三个路径；不要额外挂载宿主机磁盘。`local-output` 是专用产物目录，脚本在复制新产物前会清空该目录内容，避免新旧镜像混在一起。

如果只是修改包选择、默认 IP、`files/` 初始配置或 `scripts/local-build-inside-docker.sh`，不需要重新 `docker build`。长期容器里的 `/recipe` 是运行时挂载的当前仓库，所以直接重新执行 `docker exec ... bash /recipe/scripts/local-build-inside-docker.sh` 即可。

如果 `Dockerfile.local` 后续新增了 apt 依赖，最可复现的做法仍然是重新 `docker build`。但个人临时调试时，也可以进入长期容器手动安装依赖：

```powershell
docker exec -it n1-immortalwrt-build bash
```

进入容器后执行：

```bash
sudo apt-get update
sudo apt-get install -y <package-name>
```

这种手动安装只存在于当前容器里，不会记录到仓库；确认依赖确实需要长期保留时，再同步写回 `Dockerfile.local`。

构建成功后，`local-output` 中应至少包含：

- `openwrt_amlogic_s905d_*.img.gz`
- `SHA256SUMS`
- `immortalwrt.config`
- `immortalwrt.manifest`
- `build.log.gz`
- `versions.env`

不要对本项目执行 `docker system prune`、`docker image prune` 或 `docker volume prune`。如果以后确实要删除本项目专用资源，请先确认不再需要本地缓存和输出。

## eMMC 安装前提

不要把 commit `c6e3acd` 之前生成的镜像写入 eMMC。早期镜像虽然可以从 U 盘启动，但缺少 ophub 安装器运行所需的 `bash`、`fdisk`、`uuidgen`、`btrfs-progs` 和 `dosfstools`；安装脚本会先重建分区，再调用这些工具，因此不能安全使用。

从 `c6e3acd` 开始，构建会把上述工具及 `e2fsprogs` 明确编入 rootfs，并同时检查软件清单和归档内容。任一安装依赖缺失时，Action 会停止，不发布新的 N1 镜像。

即使构建成功，也必须先从 U 盘启动新镜像并再次确认根分区位于 `/dev/sda2`、eMMC 为 `/dev/mmcblk2`、型号为 `Phicomm-N1`，然后才能按照当前镜像中 `/usr/sbin/openwrt-install-amlogic` 的实际提示安装。不要使用 LuCI 的“备份与更新”页面写入完整 `.img.gz`。

## 首次 U 盘测试

> 写镜像会清空目标 U 盘。仓库和工作流不会自动操作你的磁盘，也不会写入 N1 eMMC。

1. 使用 Rufus、balenaEtcher 或 USBImager 将 `.img.gz`/解压后的 `.img` 写入 U 盘。
2. 第一次测试时，不要把 N1 接入现有局域网；镜像默认启用 DHCP。
3. 将电脑与 N1 单独连接，把电脑设置为 `192.168.10.x/24`，或使用 N1 分配的地址。
4. 打开 `http://192.168.10.1`，首次登录后立即设置 root 密码。
5. 验证有线网卡、BCM43455 无线、LuCI、PassWall 2、Xray、sing-box、Hysteria 2、DNS、分流及重启持久性。
6. U盘测试全部通过并完成旧系统备份前，不执行任何 eMMC 安装命令。

## 安全与来源

构建仅使用 ImmortalWrt、Openwrt-Passwall 和 ophub 的公开源码，并锁定到 [`versions.env`](versions.env) 与 [`config/feeds.conf.default`](config/feeds.conf.default) 中的 commit。GitHub Actions 和 ophub Action 同样固定 SHA，不追踪 `main`。

更新任何版本时，应在独立提交中同步更新版本锁、feeds、配置验证和 README，然后重新进行完整 U 盘验收。

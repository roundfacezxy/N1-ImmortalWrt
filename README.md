# Phicomm N1 ImmortalWrt

可审计、可重复的斐讯 N1 ImmortalWrt 固件配方。仓库只保存构建配置和脚本；编译与 N1 镜像封装由 GitHub Actions 的 Ubuntu runner 完成，本地不需要 Docker。

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

1. 打开仓库的 **Actions** 页面。
2. 选择 **Build Phicomm N1 ImmortalWrt**。
3. 点击 **Run workflow**，确认从 `main` 分支运行。
4. 等待单一构建任务完成；不要重复并行触发，也不要在失败时连续重跑。
5. 从 **Releases** 下载 `.img.gz` 与 `SHA256SUMS`，在写盘前核对校验值。

工作流只有 `workflow_dispatch` 手动入口；不响应 push、PR 或定时事件。它只构建一台 N1 和一个内核，并设置并发互斥与 330 分钟超时，以遵守 GitHub Actions 的合理使用要求。

编译和 N1 打包是两个独立 job。成功编译的标准 `generic-rootfs.tar.gz`、配置、清单和日志会作为工作流 Artifact 保留 7 天。如果只有后面的打包或发布 job 失败，请在该次运行中选择 **Re-run failed jobs**；GitHub 会复用已经保存的 rootfs，不会再次执行耗时的 ARM64 编译。只有发起一次全新的 workflow run 才会从头编译。

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

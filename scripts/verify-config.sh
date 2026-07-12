#!/usr/bin/env bash
set -euo pipefail

config_file="${1:-.config}"

required=(
  CONFIG_TARGET_armsr
  CONFIG_TARGET_armsr_armv8
  CONFIG_TARGET_armsr_armv8_DEVICE_generic
  CONFIG_PACKAGE_luci
  CONFIG_PACKAGE_luci-theme-argon
  CONFIG_PACKAGE_luci-app-passwall2
  CONFIG_PACKAGE_luci-i18n-passwall2-zh-cn
  CONFIG_PACKAGE_luci-app-passwall2_Basic_Core_All
  CONFIG_PACKAGE_luci-app-passwall2_Nftables_Transparent_Proxy
  CONFIG_PACKAGE_luci-app-passwall2_INCLUDE_Hysteria
  CONFIG_PACKAGE_hysteria
  CONFIG_PACKAGE_sing-box
  CONFIG_SING_BOX_BUILD_QUIC
  CONFIG_SING_BOX_BUILD_UTLS
  CONFIG_SING_BOX_BUILD_WIREGUARD
  CONFIG_DRIVER_11AC_SUPPORT
  CONFIG_PACKAGE_kmod-brcmfmac
  CONFIG_BRCMFMAC_SDIO
  CONFIG_PACKAGE_kmod-cfg80211
  CONFIG_PACKAGE_wifi-scripts
  CONFIG_PACKAGE_iw
  CONFIG_PACKAGE_iwinfo
  CONFIG_PACKAGE_wireless-regdb
  CONFIG_PACKAGE_wpad-basic-mbedtls
  CONFIG_PACKAGE_zerotier
  CONFIG_PACKAGE_luci-app-zerotier
  CONFIG_PACKAGE_bash
  CONFIG_PACKAGE_btrfs-progs
  CONFIG_PACKAGE_dosfstools
  CONFIG_PACKAGE_e2fsprogs
  CONFIG_PACKAGE_fdisk
  CONFIG_PACKAGE_uuidgen
)

for symbol in "${required[@]}"; do
  grep -qx "${symbol}=y" "${config_file}" || {
    echo "Required build symbol is missing: ${symbol}" >&2
    exit 1
  }
done

if grep -qx 'CONFIG_PACKAGE_luci-app-passwall=y' "${config_file}"; then
  echo 'Legacy luci-app-passwall must not be selected.' >&2
  exit 1
fi

for excluded in \
  CONFIG_PACKAGE_luci-app-passwall2_Basic_Core_Xray \
  CONFIG_PACKAGE_luci-app-passwall2_Basic_Core_SingBox \
  CONFIG_PACKAGE_luci-app-passwall2_Iptables_Transparent_Proxy; do
  if grep -qx "${excluded}=y" "${config_file}"; then
    echo "Conflicting PassWall 2 option selected: ${excluded}" >&2
    exit 1
  fi
done

echo 'Configuration checks passed.'

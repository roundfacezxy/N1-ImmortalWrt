#!/usr/bin/env bash
set -euo pipefail

config_file="${1:-.config}"

required=(
  CONFIG_TARGET_armsr
  CONFIG_TARGET_armsr_armv8
  CONFIG_TARGET_armsr_armv8_DEVICE_generic
  CONFIG_PACKAGE_luci
  CONFIG_PACKAGE_luci-app-passwall2
  CONFIG_PACKAGE_luci-i18n-passwall2-zh-cn
  CONFIG_PACKAGE_luci-app-passwall2_Basic_Core_Xray
  CONFIG_PACKAGE_luci-app-passwall2_Nftables_Transparent_Proxy
  CONFIG_PACKAGE_luci-app-passwall2_INCLUDE_Hysteria
  CONFIG_PACKAGE_hysteria
  CONFIG_PACKAGE_zerotier
  CONFIG_PACKAGE_luci-app-zerotier
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
  CONFIG_PACKAGE_luci-app-passwall2_Basic_Core_SingBox \
  CONFIG_PACKAGE_luci-app-passwall2_Basic_Core_All \
  CONFIG_PACKAGE_luci-app-passwall2_Iptables_Transparent_Proxy; do
  if grep -qx "${excluded}=y" "${config_file}"; then
    echo "Conflicting PassWall 2 option selected: ${excluded}" >&2
    exit 1
  fi
done

echo 'Configuration checks passed.'

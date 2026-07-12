#!/usr/bin/env bash
set -euo pipefail

RECIPE_DIR="${RECIPE_DIR:-/recipe}"
WORK_DIR="${WORK_DIR:-/work}"
OUTPUT_DIR="${OUTPUT_DIR:-/output}"
BUILD_JOBS="${BUILD_JOBS:-$(nproc)}"

log() {
  printf '\n[%s] %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*"
}

require_file() {
  test -f "$1" || {
    echo "Required file is missing: $1" >&2
    exit 1
  }
}

require_dir() {
  test -d "$1" || {
    echo "Required directory is missing: $1" >&2
    exit 1
  }
}

require_dir "${RECIPE_DIR}"
require_dir "${WORK_DIR}"
require_dir "${OUTPUT_DIR}"
test -w "${WORK_DIR}" || {
  echo "Work directory is not writable: ${WORK_DIR}" >&2
  exit 1
}
test -w "${OUTPUT_DIR}" || {
  echo "Output directory is not writable: ${OUTPUT_DIR}" >&2
  exit 1
}

require_file "${RECIPE_DIR}/versions.env"
require_file "${RECIPE_DIR}/config/feeds.conf.default"
require_file "${RECIPE_DIR}/config/n1.seed.config"
require_file "${RECIPE_DIR}/scripts/verify-config.sh"

# shellcheck disable=SC1091
source "${RECIPE_DIR}/versions.env"

OPENWRT_DIR="${WORK_DIR}/openwrt"
PACKER_DIR="${WORK_DIR}/packer"
RELEASE_DIR="${WORK_DIR}/release"

mkdir -p "${WORK_DIR}" "${OUTPUT_DIR}"
rm -rf "${RELEASE_DIR}"
mkdir -p "${RELEASE_DIR}"

log "Preparing pinned ImmortalWrt source"
if [[ ! -d "${OPENWRT_DIR}/.git" ]]; then
  git clone --filter=blob:none --no-checkout https://github.com/immortalwrt/immortalwrt.git "${OPENWRT_DIR}"
fi
git -C "${OPENWRT_DIR}" fetch --depth=1 origin "${IMMORTALWRT_COMMIT}"
git -C "${OPENWRT_DIR}" checkout --detach "${IMMORTALWRT_COMMIT}"
test "$(git -C "${OPENWRT_DIR}" rev-parse HEAD)" = "${IMMORTALWRT_COMMIT}"

log "Installing pinned feeds and configuration"
cp "${RECIPE_DIR}/config/feeds.conf.default" "${OPENWRT_DIR}/feeds.conf.default"
rm -rf "${OPENWRT_DIR}/files"
cp -a "${RECIPE_DIR}/files" "${OPENWRT_DIR}/files"
(
  cd "${OPENWRT_DIR}"
  ./scripts/feeds update -a
  ./scripts/feeds install -a
  test -L package/feeds/passwall2/luci-app-passwall2
  test -L package/feeds/passwall_packages/hysteria
  cp "${RECIPE_DIR}/config/n1.seed.config" .config
  make defconfig
  bash "${RECIPE_DIR}/scripts/verify-config.sh" .config
  cp .config "${RELEASE_DIR}/immortalwrt.config"
)
cp "${RECIPE_DIR}/versions.env" "${RELEASE_DIR}/versions.env"

log "Downloading source archives"
make -C "${OPENWRT_DIR}" download -j"${BUILD_JOBS}"

log "Compiling ARM64 rootfs with ${BUILD_JOBS} jobs"
(
  cd "${OPENWRT_DIR}"
  set -o pipefail
  make -j"${BUILD_JOBS}" V=s 2>&1 | tee "${RELEASE_DIR}/build.log"
)
gzip -9 -f "${RELEASE_DIR}/build.log"

log "Verifying and collecting rootfs outputs"
mapfile -t rootfs_candidates < <(find "${OPENWRT_DIR}/bin/targets/armsr/armv8" -maxdepth 1 -type f \
  -name '*-generic-rootfs.tar.gz' ! -name '*-targz-rootfs.tar.gz')
mapfile -t manifest_candidates < <(find "${OPENWRT_DIR}/bin/targets/armsr/armv8" -maxdepth 1 -type f \
  -name '*-generic.manifest')
(( ${#rootfs_candidates[@]} == 1 )) || {
  echo "Expected exactly one standard generic rootfs; found ${#rootfs_candidates[@]}." >&2
  printf '%s\n' "${rootfs_candidates[@]}" >&2
  exit 1
}
(( ${#manifest_candidates[@]} == 1 )) || {
  echo "Expected exactly one package manifest; found ${#manifest_candidates[@]}." >&2
  printf '%s\n' "${manifest_candidates[@]}" >&2
  exit 1
}

rootfs="${rootfs_candidates[0]}"
manifest="${manifest_candidates[0]}"
for package in \
  luci-app-passwall2 xray-core sing-box hysteria \
  luci-theme-argon kmod-brcmfmac wifi-scripts iw iwinfo \
  wireless-regdb wpad-basic-mbedtls zerotier luci-app-zerotier \
  bash btrfs-progs dosfstools e2fsprogs fdisk uuidgen; do
  grep -Eq "^${package}[[:space:]-]" "${manifest}" || {
    echo "Package missing from manifest: ${package}" >&2
    exit 1
  }
done

cp "${rootfs}" "${RELEASE_DIR}/"
cp "${manifest}" "${RELEASE_DIR}/immortalwrt.manifest"
find "${OPENWRT_DIR}/bin/targets/armsr/armv8" -maxdepth 1 -name '*.bom.cdx.json' \
  -exec cp -t "${RELEASE_DIR}" {} +
find "${OPENWRT_DIR}/bin/packages" -type f \( \
  -name 'luci-app-passwall2*.apk' -o \
  -name 'luci-i18n-passwall2-zh-cn*.apk' -o \
  -name 'sing-box*.apk' -o \
  -name 'hysteria*.apk' -o \
  -name 'luci-theme-argon*.apk' -o \
  -name 'wpad-basic-mbedtls*.apk' -o \
  -name 'zerotier*.apk' -o \
  -name 'luci-app-zerotier*.apk' \
\) -exec cp -t "${RELEASE_DIR}" {} +

tar -tzf "${rootfs}" > "${RELEASE_DIR}/rootfs.contents"
grep -Eq '(^|\./)usr/bin/hysteria$' "${RELEASE_DIR}/rootfs.contents"
grep -Eq '(^|\./)usr/bin/sing-box$' "${RELEASE_DIR}/rootfs.contents"
grep -Eq '(^|\./)lib/netifd/wireless/mac80211\.sh$' "${RELEASE_DIR}/rootfs.contents"
grep -Eq '(^|\./)usr/sbin/hostapd$' "${RELEASE_DIR}/rootfs.contents"
grep -Eq '(^|\./)www/luci-static/argon/' "${RELEASE_DIR}/rootfs.contents"
grep -Eq '(^|\./)bin/bash$' "${RELEASE_DIR}/rootfs.contents"
grep -Eq '(^|\./)usr/bin/uuidgen$' "${RELEASE_DIR}/rootfs.contents"
grep -Eq '(^|\./)usr/(s?bin)/mkfs\.btrfs$' "${RELEASE_DIR}/rootfs.contents"
grep -Eq '(^|\./)usr/sbin/mkfs\.fat$' "${RELEASE_DIR}/rootfs.contents"
grep -Eq '(^|\./)usr/sbin/mkfs\.ext4$' "${RELEASE_DIR}/rootfs.contents"
grep -Eq '(^|\./)usr/sbin/fdisk$' "${RELEASE_DIR}/rootfs.contents"

log "Preparing pinned ophub packer"
if [[ ! -d "${PACKER_DIR}/.git" ]]; then
  git clone --filter=blob:none --no-checkout https://github.com/ophub/amlogic-s9xxx-openwrt.git "${PACKER_DIR}"
fi
git -C "${PACKER_DIR}" fetch --depth=1 origin "${OPHUB_PACKER_COMMIT}"
git -C "${PACKER_DIR}" checkout --detach "${OPHUB_PACKER_COMMIT}"
test "$(git -C "${PACKER_DIR}" rev-parse HEAD)" = "${OPHUB_PACKER_COMMIT}"

log "Packaging Phicomm N1 image"
rm -rf "${PACKER_DIR}/openwrt-armsr" "${PACKER_DIR}/openwrt/out"
mkdir -p "${PACKER_DIR}/openwrt-armsr"
cp "${rootfs}" "${PACKER_DIR}/openwrt-armsr/"
(
  cd "${PACKER_DIR}"
  sudo ./remake \
    -b s905d \
    -r ophub/kernel \
    -u stable \
    -k "${OPHUB_KERNEL_VERSION}" \
    -a false \
    -p "${DEFAULT_IP}" \
    -s "${IMAGE_SIZE}" \
    -n roundfacezxy
)
sudo chown -R "$(id -u):$(id -g)" "${PACKER_DIR}/openwrt" "${PACKER_DIR}/openwrt-armsr" 2>/dev/null || true

mapfile -t images < <(find "${PACKER_DIR}/openwrt/out" -type f -name '*.img.gz')
if (( ${#images[@]} != 1 )); then
  echo "Expected exactly one N1 image, found ${#images[@]}." >&2
  printf '%s\n' "${images[@]}" >&2
  exit 1
fi
image_name="$(basename "${images[0]}")"
[[ "${image_name,,}" == *s905d* ]] || {
  echo "Packaged image does not identify the selected s905d/N1 board: ${image_name}" >&2
  exit 1
}
gzip -t "${images[0]}"
cp "${images[0]}" "${RELEASE_DIR}/"

log "Creating checksums and copying release artifacts to /output"
(
  cd "${RELEASE_DIR}"
  find . -type f ! -name SHA256SUMS -print0 | sort -z | xargs -0 sha256sum > SHA256SUMS
  sha256sum -c SHA256SUMS
)
rm -rf "${OUTPUT_DIR:?}/"*
cp -a "${RELEASE_DIR}/." "${OUTPUT_DIR}/"

log "Done. Local artifacts are available in ${OUTPUT_DIR}."

#!/usr/bin/env bash
#
# Build an OpenWrt release's ImageBuilder with the devices in this repo added.
#
#   ./build.sh <openwrt-version | snapshot> <target> <subtarget> <out-dir>
#   ./build.sh 25.12.6 ramips mt76x8 out
#   ./build.sh snapshot ramips mt76x8 out
#
# Every devices/<board>/ holds a DTS (and any dtsi it includes), a patch against
# the OpenWrt tree, and optionally package/, OpenWrt packages the device needs
# that the release does not have. All are applied to the release tag, only
# those devices are enabled, and <out-dir> receives the ImageBuilder (with
# those packages in it), each device's plain-OpenWrt images, and a sha256sums
# in the same format downloads.openwrt.org publishes.
#
# The kmods still come from downloads.openwrt.org. A kmod installs only against
# the kernel it was built for, identified by a hash of the kernel config (the
# vermagic). So the tree is set up the way the release's buildbot set it up:
# its config.buildinfo, and its feeds at the commits in feeds.buildinfo. Both
# matter, because every selected kmod merges its own symbols into the kernel
# config: turning off ALL_KMODS, or leaving out a feed's kmods, changes the
# hash. A device adds a DTS and an image recipe and touches neither, and a
# device kmod is built out of tree, so it adds nothing to the config. The result
# is checked below rather than assumed: a mismatch builds fine and then fails
# every kmod at `make image`.
#
# Linux, on a case-sensitive filesystem.

set -euo pipefail

VERSION="${1:?usage: build.sh <openwrt-version | snapshot> <target> <subtarget> <out-dir>}"
TARGET="${2:?}" SUBTARGET="${3:?}"
OUT="$(mkdir -p "${4:?}" && cd "$4" && pwd)"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SRC="${OPENWRT_SRC:-${ROOT}/.build/openwrt}"

log() { printf '\033[36m==>\033[0m %s\n' "$*"; }
die() { printf '\033[31merror\033[0m %s\n' "$*" >&2; exit 1; }

# A snapshot is main at the commit the buildbot last built the target from,
# which is what upstream reviews a device against. Its kmods, feeds and config
# are published the same way a release's are, so everything below holds.
if [ "${VERSION}" = snapshot ]; then
  RELEASE="https://downloads.openwrt.org/snapshots/targets/${TARGET}/${SUBTARGET}"
  REF="$(curl -fsSL "${RELEASE}/version.buildinfo")"
  # It names the commit by its short hash, which a shallow fetch cannot take.
  REF="$(curl -fsSL -H 'Accept: application/vnd.github.sha' \
    ${GITHUB_TOKEN:+-H "Authorization: Bearer ${GITHUB_TOKEN}"} \
    "https://api.github.com/repos/openwrt/openwrt/commits/${REF#*-}")"
  FETCH="${REF}"
else
  RELEASE="https://downloads.openwrt.org/releases/${VERSION}/targets/${TARGET}/${SUBTARGET}"
  REF="v${VERSION}"
  FETCH="refs/tags/${REF}:refs/tags/${REF}"
fi

# OpenWrt's configure scripts refuse root without this.
[ "$(id -u)" = 0 ] && export FORCE_UNSAFE_CONFIGURE=1

if [ ! -d "${SRC}/.git" ]; then
  log "Cloning OpenWrt ${REF}"
  # CI caches .build/openwrt/dl (actions/cache), which on a warm run recreates
  # ${SRC} without a .git — so a plain clone lands on a non-empty directory and
  # dies. Clone into a temp dir and fold any cached dl/ back in. One commit
  # deep: the build runs `git log` on every package directory, and a partial
  # clone answers each of those by fetching from GitHub, which ran a snapshot
  # build past six hours before the toolchain finished.
  rm -rf "${SRC}.tmp"
  git init -q "${SRC}.tmp"
  git -C "${SRC}.tmp" fetch -q --depth 1 https://github.com/openwrt/openwrt.git "${FETCH}"
  git -C "${SRC}.tmp" checkout -q "${REF}"
  [ -d "${SRC}/dl" ] && mv "${SRC}/dl" "${SRC}.tmp/dl"
  rm -rf "${SRC}"
  mv "${SRC}.tmp" "${SRC}"
fi
cd "${SRC}"
[ "$(git rev-parse HEAD)" = "$(git rev-parse -q --verify "${REF}^{commit}")" ] \
  || die "${SRC} is not a checkout of ${REF}"

# Back to the pristine tag, keeping dl/, the feeds and the build dirs.
git checkout -q -- .
git clean -fdq -e /package/feeds -- target package

devices=""
for dir in "${ROOT}"/devices/*/; do
  log "Applying $(basename "${dir}")"
  cp "${dir}"*.dts* "target/linux/${TARGET}/dts/"
  git apply "${dir}openwrt.patch"
  [ -d "${dir}package" ] && cp -R "${dir}package/." package/
  devices="${devices} $(sed -n 's/^+define Device\/\(.*\)$/\1/p' "${dir}openwrt.patch")"
done
[ -n "${devices// }" ] || die "no devices found"

log "Installing the release's feeds"
curl -fsSL -o feeds.conf "${RELEASE}/feeds.buildinfo"
./scripts/feeds update -a >/dev/null
./scripts/feeds install -a >/dev/null

log "Configuring from the release's config.buildinfo"
curl -fsSL -o .config "${RELEASE}/config.buildinfo"
# The release config names every device in the target explicitly, so they are
# removed rather than overridden: this builds ours and nobody else's.
sed -i '/^CONFIG_TARGET_DEVICE_/d' .config
{
  echo "# CONFIG_TARGET_ALL_PROFILES is not set"
  echo "CONFIG_TARGET_MULTI_PROFILE=y"
  for d in ${devices}; do
    echo "CONFIG_TARGET_DEVICE_${TARGET}_${SUBTARGET}_DEVICE_${d}=y"
  done
  echo "CONFIG_IB=y"
  echo "# CONFIG_IB_STANDALONE is not set"
  echo "# CONFIG_SDK is not set"
  echo "# CONFIG_MAKE_TOOLCHAIN is not set"
  # Not ALL_KMODS or COLLECT_KERNEL_DEBUG: see the vermagic note at the top.
  echo "# CONFIG_ALL_NONSHARED is not set"
} >> .config
make defconfig >/dev/null

for d in ${devices}; do
  grep -qx "CONFIG_TARGET_DEVICE_${TARGET}_${SUBTARGET}_DEVICE_${d}=y" .config \
    || die "device ${d} did not survive defconfig; is its recipe in the patch valid?"
done

log "Building the toolchain and the kernel"
make download -j8 >/dev/null
make -j"$(nproc)" tools/install toolchain/install
make -j"$(nproc)" target/linux/compile

# Checked as soon as the kernel is built, since everything after this is
# the long part and would be wasted on a kernel no release kmod will load into.
vermagic="$(cat build_dir/target-*/linux-${TARGET}_${SUBTARGET}/linux-*/.vermagic)"
# A snapshot keeps the kmods of its last few kernels side by side.
kmods="$(curl -fsSL "${RELEASE}/kmods/" | sed -n 's/.*href="\([0-9][^"/]*\)\/".*/\1/p')"
echo "${kmods}" | grep -q -- "-${vermagic}\$" \
  || die "vermagic ${vermagic} does not match the release's kmods (${kmods//$'\n'/ })"
log "vermagic ${vermagic} matches the release's kmods"

log "Building"
# A kmod from a feed that fails to compile costs nothing here, since its
# symbols reached the kernel config when it was selected; the release's kmods
# are what get installed.
make -j"$(nproc)" IGNORE_ERRORS=m || make -j1 V=s IGNORE_ERRORS=m

bin="bin/targets/${TARGET}/${SUBTARGET}"

# The ImageBuilder's local repository (packages/) only gets the kernel, libc
# and base-files; every other package is fetched from the release. A device
# kmod exists nowhere but here, so it is added to that repository, beside the
# kernel it was built against. IGNORE_ERRORS=m would also have passed one that
# failed to build, which is caught here rather than in someone's image build.
ib="$(ls "${bin}"/openwrt-imagebuilder-*.tar.zst)"
ibname="$(basename "${ib}" .tar.zst)"
stage="$(mktemp -d)"
mkdir -p "${stage}/${ibname}/packages"
for pkg in "${ROOT}"/devices/*/package/*/; do
  [ -f "${pkg}Makefile" ] || continue
  kmod="kmod-$(sed -n 's/^PKG_NAME:=//p' "${pkg}Makefile")"
  file="$(find "${bin}/packages" -name "${kmod}[-_][0-9]*" | head -n1)"
  [ -n "${file}" ] || die "${kmod} did not build"
  cp "${file}" "${stage}/${ibname}/packages/"
  log "Adding $(basename "${file}") to the ImageBuilder"
done
if [ -n "$(ls -A "${stage}/${ibname}/packages")" ]; then
  zstd -dqf "${ib}" -o "${stage}/ib.tar"
  ( cd "${stage}" && tar -rf ib.tar "${ibname}"/packages/* )
  zstd -qf -T0 -19 --rm "${stage}/ib.tar" -o "${ib}"
fi
rm -rf "${stage}"

cp "${bin}"/openwrt-imagebuilder-*.tar.zst "${bin}"/*-initramfs-kernel.bin \
   "${bin}"/*-squashfs-sysupgrade.bin "${OUT}/"
( cd "${OUT}" && sha256sum -b -- *.tar.zst *.bin > sha256sums )
log "Artifacts in ${OUT}:"
cat "${OUT}/sha256sums"

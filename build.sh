#!/usr/bin/env bash
#
# Build the OGC + tishy-FRL kernel RPMs. Runs inside a Fedora environment (a
# fedora:NN container in CI and via build-local.sh; see that script for local
# use). Produces binary kernel RPMs in ./rpms/.
#
# Environment:
#   OGC_VERSION   OGC kernel tag to build (default: contents of KERNEL_VERSION)
#   BUILDNUM      RPM build number for Release (default: 1)
#   JOBS          parallel make jobs (default: nproc)
#   CCACHE_DIR    if set, compile through ccache (big speedup on rebuilds)
#   SKIP_DEPS     if set to 1, skip `dnf builddep` (deps already installed)

set -euo pipefail

cd "$(dirname "$0")"

OGC_VERSION="${OGC_VERSION:-$(tr -d '[:space:]' < KERNEL_VERSION)}"
BUILDNUM="${BUILDNUM:-1}"

KERNEL_VERSION="${OGC_VERSION%-ogc*}"
MAJOR_VERSION="${KERNEL_VERSION%%.*}.x"
OGC_REV="${OGC_VERSION##*-ogc}"
BASE_KVER="${KERNEL_VERSION%.*}"
STABLE_KVER="${KERNEL_VERSION##*.}"
if [ "$STABLE_KVER" = "0" ]; then
    TAR_KVER="$BASE_KVER"
else
    TAR_KVER="$KERNEL_VERSION"
fi

echo "Building OGC ${OGC_VERSION} (linux-${TAR_KVER}, build ${BUILDNUM})"

# The rpmbuild tree lives outside the source checkout by default. Locally the
# checkout is a bind mount whose setgid/ACL group is unmappable in the rootless
# user namespace, so the spec's `cp -a` calls in %install fail with EPERM when
# preserving ownership onto it; container-local storage avoids that (and is
# discarded with the container).
TOPDIR="${RPM_TOPDIR:-/var/tmp/kernel-tishy-rpmbuild}"

# Substitute the version macros into a working copy of the spec so repeated
# runs don't accumulate edits on the tracked file.
mkdir -p "$TOPDIR/SPECS"
sed \
    -e "s/@@BASEKVER@@/${BASE_KVER}/" \
    -e "s/@@STABLEKVER@@/${STABLE_KVER}/" \
    -e "s/@@OGCVER@@/${OGC_REV}/" \
    -e "s/@@BUILDNUM@@/${BUILDNUM}/" \
    fedora/kernel.spec > "$TOPDIR/SPECS/kernel.spec"

if [ "${SKIP_DEPS:-0}" != "1" ]; then
    dnf -y builddep "$TOPDIR/SPECS/kernel.spec"
    dnf -y install gnupg2 wget python3
    [ -n "${CCACHE_DIR:-}" ] && dnf -y install ccache
fi

# Download and verify the vanilla kernel tarball and the OGC monolithic patch.
# Cached downloads (gitignored) are reused but still re-verified.
[ -f "linux-${TAR_KVER}.tar.xz" ] || \
    wget -q "https://cdn.kernel.org/pub/linux/kernel/v${MAJOR_VERSION}/linux-${TAR_KVER}.tar.xz"
[ -f "linux-${TAR_KVER}.tar.sign" ] || \
    wget -q "https://cdn.kernel.org/pub/linux/kernel/v${MAJOR_VERSION}/linux-${TAR_KVER}.tar.sign"
[ -f monolithic.patch ] || \
    wget -q "https://github.com/OpenGamingCollective/linux/releases/download/v${OGC_VERSION}/monolithic.patch"
[ -f monolithic.patch.sig ] || \
    wget -q "https://github.com/OpenGamingCollective/linux/releases/download/v${OGC_VERSION}/monolithic.patch.sig"

# Import kernel.org signing keys (Linus Torvalds & Greg Kroah-Hartman) and the
# OGC monolithic patch signing key, then verify both artifacts.
gpg --keyserver hkps://keyserver.ubuntu.com --recv-keys \
    ABAF11C65A2970B130ABE3C479BE3E4300411886 \
    647F28654894E3BD457199BE38DBBDC86092693E
gpg --import public.key
xz -dc "linux-${TAR_KVER}.tar.xz" | gpg --verify "linux-${TAR_KVER}.tar.sign" -
gpg --verify monolithic.patch.sig monolithic.patch

# Generate the merged config on a monolithic-patched tree, then olddefconfig it
# to catch config problems before the long build. The FRL patches add no Kconfig
# symbols, so they are applied only inside rpmbuild %prep.
rm -rf "linux-${TAR_KVER}"
tar -xf "linux-${TAR_KVER}.tar.xz"
( cd "linux-${TAR_KVER}" && patch -Np1 < ../monolithic.patch )
python3 merge-config.py \
    --config fedora/config \
    --set config/fedora.config.set --set config/ogc.config.set \
    --unset config/fedora.config.unset --unset config/ogc.config.unset \
    --unset config/tishy.config.unset \
    --output "linux-${TAR_KVER}/.config"
( cd "linux-${TAR_KVER}" && make olddefconfig )

# Assemble the rpmbuild tree and build.
mkdir -p "$TOPDIR"/{BUILD,BUILDROOT,RPMS,SOURCES,SRPMS}
cp "linux-${TAR_KVER}.tar.xz" "$TOPDIR/SOURCES/"
cp monolithic.patch "$TOPDIR/SOURCES/"
cp fedora/kvm_stat.logrotate "$TOPDIR/SOURCES/"
cp patches/0001-fix-amd-color-manager.patch "$TOPDIR/SOURCES/"
cp patches/0002-fix-dc-plane-cm-build-error.patch "$TOPDIR/SOURCES/"
cp patches/0003-hdmi-frl.patch "$TOPDIR/SOURCES/"
cp patches/0004-hdmi-vrr.patch "$TOPDIR/SOURCES/"
cp "linux-${TAR_KVER}/.config" "$TOPDIR/SOURCES/config"

if [ -n "${CCACHE_DIR:-}" ]; then
    export PATH="/usr/lib64/ccache:${PATH}"
    export CCACHE_DIR
    ccache --max-size=15G >/dev/null 2>&1 || true
    echo "ccache enabled (dir: ${CCACHE_DIR})"
fi

JOBS="${JOBS:-$(nproc)}"
rpmbuild --define "_topdir ${TOPDIR}" --define "_smp_mflags -j${JOBS}" \
    -ba "$TOPDIR/SPECS/kernel.spec"

# Collect the binary kernel RPMs (excluding debug packages) for packaging.
# Clean first: a leftover rpms/ from a previous build would put two kernel
# versions in the OCI image and break the tishy-deck install glob.
rm -rf rpms
mkdir -p rpms
find "$TOPDIR/RPMS" -type f -name 'kernel-*.rpm' \
    ! -name '*debuginfo*' ! -name '*debugsource*' -exec cp -t rpms/ {} +
versions=$(ls rpms/kernel-core-*.rpm | wc -l)
if [ "$versions" -ne 1 ]; then
    echo "Error: expected exactly one kernel-core RPM in rpms/, found ${versions}" >&2
    exit 1
fi
echo "Built RPMs:"
ls -1 rpms/

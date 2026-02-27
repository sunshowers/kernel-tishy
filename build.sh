#!/bin/bash

#
# Key preparation
#

set -e

CCACHE_USE=${CCACHE_USE:-1}

# Check we are in a container before we nuke the pesign dir
if [ -z "$container" ]; then
    echo "Error: This script should be run inside the build container."
    exit 1
fi

# Use two keys. In the action, these will get prefilled with the public
# keys from this directory

mkdir -p certs
for key in 101 102; do
    if [ ! -f certs/ubmok$key.priv ] || [ ! -f certs/ubmok$key.der ]; then
        echo "!! Warning. Creating ubmok$key for test build."
        openssl req -new -x509 -newkey rsa:2048 -keyout certs/ubmok$key.priv -out certs/ubmok$key.der -nodes -days 36500 -subj "/CN=ubluetestkey$key/"
    fi

    # Create pkcs12 file
    if [ ! -f certs/ubmok$key.p12 ]; then
        openssl pkcs12 -export -out certs/ubmok$key.p12 -inkey certs/ubmok$key.priv -in certs/ubmok$key.der -passout pass:
    fi
done


# Create NSS database and enroll keys
rm -rf ./certs/pki/ubluesign
mkdir -p ./certs/pki/ubluesign
certutil -N -d sql:./certs/pki/ubluesign --empty-password

# Import pkcs12 files
for key in 101 102; do
    certutil -A -d sql:./certs/pki/ubluesign -n "ubmok$key" -t "CT,C,C" -i certs/ubmok$key.der
    pk12util -i certs/ubmok$key.p12 -d sql:./certs/pki/ubluesign -W ""
done

# List keys
echo "Secure Boot Key status:"
certutil -L -d sql:./certs/pki/ubluesign

#
# Sources preparation
#

# Get the tarfile_release value from the spec file and download it.
ARCH=${ARCH:-x86_64}
TARFILE_RELEASE=$(sed -n 's/^%define[[:space:]]\+tarfile_release[[:space:]]\+//p' kernel.spec)

echo "TARFILE_RELEASE is $TARFILE_RELEASE"

echo "$TARFILE_RELEASE" > .tarfile-release

if [ -z "$TARFILE_RELEASE" ]; then
    echo "Error: Could not determine TARFILE_RELEASE from kernel.spec"
    exit 1
fi

linuxfn="linux-${TARFILE_RELEASE}.tar.xz"

if [ ! -f "$linuxfn" ]; then
    echo "Downloading $linuxfn"
    curl -L -o "$linuxfn" "https://cdn.kernel.org/pub/linux/kernel/v6.x/linux-${TARFILE_RELEASE}.tar.xz"
fi

#
# Build
#

FEDORA_VERSION=${FEDORA_VERSION:-43}

echo "Starting build for Fedora $FEDORA_VERSION, arch $ARCH"
unset ARCH # There seems to be an issue here

sudo rm -rf /etc/pki/pesign
sudo cp -r certs/pki/ubluesign /etc/pki/pesign
sudo chown -R root:root /etc/pki/pesign
sudo chmod -R 755 /etc/pki/pesign

if [ "$CCACHE_USE" -eq 1 ]; then
    echo "Using ccache for build"
    export PATH="/usr/lib64/ccache:/usr/lib/ccache:$PATH"
    export CC="ccache gcc"
    export CXX="ccache g++"
    export CCACHE_MAXSIZE="5G"
    export CCACHE_DIR="$(pwd)/ccache"
fi

# Build without nvidia and zfs. Use --with bazzite for the build
# configuration (disables debug, realtime, selftests, etc.) and --with
# ubsb for secure boot signing. Disable config checks because we're
# using 6.17-era config files on a 6.19 kernel; make olddefconfig
# handles the actual build correctly.
rpmbuild \
  --define '_topdir   %(pwd)/build' \
  --define '_builddir %{_topdir}/BUILD' \
  --define '_rpmdir   %{_topdir}/RPMS' \
  --define '_srcrpmdir %{_topdir}/SRPMS' \
  --define '_sourcedir %(pwd)/' \
  --define '_specdir  %(pwd)/' \
  --with bazzite --with ubsb --without configchecks \
  -ba kernel.spec &

trap 'pkill --signal=SIGKILL -P $$; exit 130' INT
wait

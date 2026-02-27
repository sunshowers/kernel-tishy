#!/bin/bash

set -e

ARCH=${ARCH:-x86_64}
FEDORA_VERSION=${FEDORA_VERSION:-43}

# Create buildah from scratch
BOCI=$(buildah from scratch)

# Trap to remove on errors
trap 'buildah rm $BOCI' ERR

# Mount the filesystem
MOCI=$(buildah mount $BOCI)

# Copy only binary RPMs (exclude src.rpm) directly into rpms/
find "./build/RPMS/$ARCH" -type f -name "kernel-*.rpm" ! -name "*.src.rpm" -exec cp -t "$MOCI/" {} +

# Unmount the filesystem
buildah unmount $BOCI

buildah config \
    --label "org.tishy.kernel.version=$(cat .tarfile-release)" \
    $BOCI

# Commit the image
buildah commit $BOCI kernel-f${FEDORA_VERSION}
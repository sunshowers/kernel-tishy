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

# Commit the image
buildah commit \
    --annotation "org.bazzite.kernel.nvidia=$(cat .nvidia-release)" \
    --annotation "org.bazzite.kernel.nvidia_lts=$(cat .nvidia-lts-release)" \
    --annotation "org.bazzite.kernel.zfs=$(cat .zfs-release)" \
     $BOCI kernel-f${FEDORA_VERSION}

# Get digest
DIGEST=$(buildah images --noheading --format "{{.Digest}}" nvidia-oci-f${FEDORA_VERSION})
echo "OCI Image created with digest: $DIGEST"

echo $DIGEST > .oci-digest
#!/bin/bash

# Package the built kernel RPMs into a minimal, FROM-able OCI image with the
# RPMs at the image root. The tishy-deck build bind-mounts this image's
# filesystem and installs the RPMs (see ../tishy/Containerfile.deck).

set -euo pipefail

FEDORA_VERSION=${FEDORA_VERSION:-43}
RPM_DIR=${RPM_DIR:-./rpms}
KERNEL_VERSION=$(tr -d '[:space:]' < KERNEL_VERSION)

if ! compgen -G "${RPM_DIR}/kernel-*.rpm" > /dev/null; then
    echo "Error: no kernel-*.rpm found in ${RPM_DIR}" >&2
    exit 1
fi

# Create buildah container from scratch.
BOCI=$(buildah from scratch)

# Remove the working container on error.
trap 'buildah rm "$BOCI"' ERR

# Mount the filesystem and copy the binary RPMs to the image root.
MOCI=$(buildah mount "$BOCI")
find "$RPM_DIR" -type f -name "kernel-*.rpm" ! -name "*.src.rpm" -exec cp -t "$MOCI/" {} +
buildah unmount "$BOCI"

buildah config \
    --label "org.tishy.kernel.version=${KERNEL_VERSION}" \
    "$BOCI"

# Commit the image under the name the workflow pushes.
buildah commit "$BOCI" "kernel-f${FEDORA_VERSION}"

#!/usr/bin/env bash
#
# Build kernel-tishy locally using a Fedora container via podman, then package
# the RPMs into a FROM-able OCI image. Much faster than CI on a big machine.
#
# Environment:
#   FEDORA_VERSION  Fedora container / image tag suffix (default: 43)
#   JOBS            parallel make jobs (default: nproc inside the container)
#   OGC_VERSION     override the KERNEL_VERSION file
#   BUILDNUM        RPM build number (default: 1)
#   IMAGE           output image tag
#                   (default: localhost/kernel-tishy:latest-f<ver>-x86_64)
#
# After it finishes, build tishy-deck against the local image:
#   cd ../tishy && podman build -f Containerfile.deck \
#     --build-arg KERNEL_REF=<IMAGE> -t tishy-deck:local .

set -euo pipefail
cd "$(dirname "$0")"

FEDORA_VERSION="${FEDORA_VERSION:-43}"
IMAGE="${IMAGE:-localhost/kernel-tishy:latest-f${FEDORA_VERSION}-x86_64}"
CCACHE_HOST="${CCACHE_HOST:-$HOME/.cache/kernel-tishy-ccache}"
mkdir -p "$CCACHE_HOST"

run_env=(-e CCACHE_DIR=/ccache)
[ -n "${JOBS:-}" ] && run_env+=(-e "JOBS=${JOBS}")
[ -n "${OGC_VERSION:-}" ] && run_env+=(-e "OGC_VERSION=${OGC_VERSION}")
[ -n "${BUILDNUM:-}" ] && run_env+=(-e "BUILDNUM=${BUILDNUM}")

echo "== Building kernel RPMs in fedora:${FEDORA_VERSION} =="
podman run --rm \
    -v "$PWD":/workspace:z -w /workspace \
    -v "$CCACHE_HOST":/ccache:z \
    "${run_env[@]}" \
    "fedora:${FEDORA_VERSION}" \
    bash build.sh

echo "== Packaging OCI image ${IMAGE} =="
KERNEL_VERSION_LABEL="$(tr -d '[:space:]' < KERNEL_VERSION)"
ctxfile=$(mktemp)
printf 'FROM scratch\nCOPY rpms/*.rpm /\n' > "$ctxfile"
podman build -f "$ctxfile" \
    --label "org.tishy.kernel.version=${KERNEL_VERSION_LABEL}" \
    -t "$IMAGE" .
rm -f "$ctxfile"

echo
echo "Done. Kernel image: ${IMAGE}"
echo "Build tishy-deck against it with:"
echo "  cd ../tishy && podman build -f Containerfile.deck --build-arg KERNEL_REF=${IMAGE} -t tishy-deck:local ."

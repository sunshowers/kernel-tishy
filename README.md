# kernel-tishy

Custom kernel for [tishy-deck](https://github.com/sunshowers/tishy): an
[OpenGamingCollective (OGC)](https://github.com/OpenGamingCollective/kernel-packages)
Fedora kernel with AMD HDMI FRL + VRR patches layered on top, published as a
FROM-able OCI image.

## What it builds

1. Downloads and GPG-verifies vanilla `linux-<version>.tar.xz` from
   `cdn.kernel.org`.
2. Downloads and verifies the OGC `monolithic.patch` for the matching
   `v<version>-ogc<rev>` tag from
   [`OpenGamingCollective/linux`](https://github.com/OpenGamingCollective/linux).
3. Applies the OGC patch, then the tishy HDMI FRL + VRR patches (see
   [`patches/README.md`](patches/README.md)).
4. Merges the Fedora + OGC config fragments and builds RPMs from
   [`fedora/kernel.spec`](fedora/kernel.spec).
5. Packages the RPMs into `ghcr.io/sunshowers/kernel-tishy:latest-f43-x86_64`
   (RPMs at the image root), which the tishy-deck build consumes.

The kernel version is pinned in [`KERNEL_VERSION`](KERNEL_VERSION)
(currently `7.1.3-ogc3`) and can be overridden via the workflow dispatch input.

## Layout

```
KERNEL_VERSION              OGC tag to build (e.g. 7.1.3-ogc3)
public.key                  OGC monolithic.patch signing key
fedora/kernel.spec          OGC Fedora kernel spec + tishy FRL patches
fedora/config               base kernel config (see "Config provenance")
config/*.config.{set,unset} Fedora + OGC + tishy config fragments
patches/                    HDMI FRL + VRR patches (see patches/README.md)
build.sh                    build core, shared by CI and local builds
build-local.sh              local build via podman + fedora container
merge-config.py             config fragment merge (kernel-configurator logic)
oci.sh                      packages built RPMs into the scratch OCI image
.github/workflows/build.yml CI: build RPMs, package + push OCI image
```

## Config provenance

`fedora/config` is **not** OGC kernel-packages' current `fedora/config`. Their
commit `33f30ad` ("chore: Update Fedora kernel config", 2026-06-29) regenerated
the file and dropped ~1,573 previously-enabled options; after `make
olddefconfig` resolves defaults, ~525 stay silently off, including
`CONFIG_IA32_EMULATION` (32-bit binaries — Steam), `CONFIG_KVM_AMD`/
`CONFIG_KVM_INTEL`, IOMMU support, and most AMD ACP audio codecs. Every OGC
artifact tagged `v7.1.2-ogc1` or later is built from the broken config; the
last good config is commit `ea2f210` (2026-05-18), which produced the
`7.0.9-ogc3.2` builds that Bazzite ships (Bazzite consumes OGC's prebuilt
artifacts via `ublue-os/akmods` and has no kernel config of its own).

Instead, `fedora/config` here is the complete resolved config of a known-good
OGC build (`7.0.9-ogc3.2.fc44`, extracted from `/proc/config.gz` on a running
machine; see the file's header) — i.e., OGC's `ea2f210` config after
`olddefconfig`. On version bumps, `make olddefconfig` resolves new options with
their defaults — same as OGC's own flow. If OGC fixes their config upstream,
re-vendoring it is fine after diffing for the options above.

## Building a new version

Update [`KERNEL_VERSION`](KERNEL_VERSION) to a published
`OpenGamingCollective/linux` tag and push, or run the workflow manually with the
`version` input. See the `update-kernel` skill in the tishy repo for the full
procedure, including refreshing the FRL patches.

## Secure Boot

The kernel modules are signed with an ephemeral key generated at build time; the
`vmlinuz` is not signed for Secure Boot. Run with Secure Boot disabled, or
enroll a custom key.

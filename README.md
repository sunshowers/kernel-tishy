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
fedora/config               OGC base Fedora config
config/*.config.{set,unset} Fedora + OGC config fragments
patches/                    HDMI FRL + VRR patches (see patches/README.md)
oci.sh                      packages built RPMs into the scratch OCI image
.github/workflows/build.yml CI: build RPMs, package + push OCI image
```

## Building a new version

Update [`KERNEL_VERSION`](KERNEL_VERSION) to a published
`OpenGamingCollective/linux` tag and push, or run the workflow manually with the
`version` input. See the `update-kernel` skill in the tishy repo for the full
procedure, including refreshing the FRL patches.

## Secure Boot

The kernel modules are signed with an ephemeral key generated at build time; the
`vmlinuz` is not signed for Secure Boot. Run with Secure Boot disabled, or
enroll a custom key.

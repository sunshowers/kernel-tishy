# HDMI FRL + VRR patches

These patches add AMD HDMI FRL (Fixed Rate Link) and the associated VRR support
to the OGC Fedora kernel. They are applied in `fedora/kernel.spec` as `Patch1`
through `Patch4`, in order, on top of the OGC `monolithic.patch`.

## Provenance

The patches originate from [`github.com/John-Gee/7-1-frl`](https://github.com/John-Gee/7-1-frl),
a CachyOS 7.1.2 `PKGBUILD` that layers AMD display work onto the kernel. The
files here correspond to that repo's `source` array (the CachyOS build harness
and NVIDIA/ZFS bits are not used):

| File | Upstream file | Notes |
| --- | --- | --- |
| `0001-fix-amd-color-manager.patch` | `0001-fix-amd-color-manager.patch` | verbatim |
| `0002-fix-dc-plane-cm-build-error.patch` | `0002-fix-dc-plane-cm-build-error.patch` | verbatim |
| `0003-hdmi-frl.patch` | `hdmi_frl_amdnext.patch` | **adapted** (see below) |
| `0004-hdmi-vrr.patch` | `hdmi_vrr_amdnext.patch` | verbatim |

## Adaptation of `0003-hdmi-frl.patch`

The upstream `hdmi_frl_amdnext.patch` was generated against an amd-staging
("amdnext") tree. On the OGC stable base (`v7.1.3-ogc3`), 175 of its 176 files
apply cleanly; only `drivers/gpu/drm/amd/display/amdgpu_dm/amdgpu_dm.c` has two
hunks that miss, because OGC's stable base differs from amd-staging:

1. OGC renamed `hfvsif_infopacket` to `vsp_infopacket`, shifting the context of
   the hunk that guards `mod_build_hf_vsif_infopacket`.
2. OGC's stable base lacks the amd-staging HDMI-VRR / `pcon_allowed` block that
   the other missing hunk tweaked.

Both hunks make the same kind of change the rest of the patch makes everywhere:
replacing an exact `== SIGNAL_TYPE_HDMI_TYPE_A` comparison with
`dc_is_hdmi_signal(...)` so that FRL-signalled sinks are treated as HDMI. The
adapted patch resolves them to the equivalent one-line swaps against OGC's code:

- `if (stream->signal == SIGNAL_TYPE_HDMI_TYPE_A)` → `if (dc_is_hdmi_signal(stream->signal))`
- `} else if (drm_edid && sink->sink_signal == SIGNAL_TYPE_HDMI_TYPE_A) {` →
  `} else if (drm_edid && dc_is_hdmi_signal(sink->sink_signal)) {`

The amd-staging-only "prefer HDMI VRR" refinement is not present on the OGC base
and is not reintroduced. Only the `amdgpu_dm.c` diff block was regenerated; every
other file's diff is byte-identical to upstream. The adapted patch applies with
zero rejects against `v7.1.3-ogc3`.

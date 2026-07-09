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
and is not reintroduced.

Additionally, one dead hunk was removed from the
`drivers/gpu/drm/amd/display/dc/clk_mgr/dcn401/dcn401_clk_mgr.c` block: upstream
adds three variable declarations (`otg_master`, `frl_present`, `i`) to
`dcn401_build_update_display_clocks_sequence()` that nothing ever uses (a
leftover from an earlier patch revision). The block's real change (routing HDMI
FRL signals to the HPO encoder path) is kept.

## Werror

The patch set does not build under `CONFIG_DRM_WERROR` (which OGC's base config
enables): besides the dead variables above, `dcn30_frl_reg_defs.h` intentionally
shadows 78 register macros that linux 7.1's `dcn_3_6_0`/`dcn_4_1_0` offset
headers also define, relying on last-definition-wins per translation unit (the
ASIC offset headers are included after it in the `dcn36`/`dcn401` resource
files, so the ASIC-correct values win there). CachyOS, where the patch is
developed, does not enable `CONFIG_DRM_WERROR`; `config/tishy.config.unset`
disables it to match.

Only those two file blocks differ from upstream; every other file's diff is
byte-identical. The adapted patch applies with zero rejects against
`v7.1.3-ogc3`.

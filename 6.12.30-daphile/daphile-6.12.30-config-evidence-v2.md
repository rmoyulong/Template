# Daphile official 6.12.30 kernel reconstruction — evidence report v2

## 1. Reference artifacts

- Official kernel image SHA256: `225f6522feb3d49aede7da41e04aec288774e5efedc0eaca39e7bb6494b7e312`
- Official kernel release string: `6.12.30-daphile (root@server) #1 SMP PREEMPT_RT Sat May 24 07:45:53 UTC 2025`
- Official modules package root: `6.12.30-daphile/`
- Direct archive recount: 1,829 `.ko.xz` files; `modules.builtin` has 379 lines.
- HDA module vermagic: `6.12.30-daphile SMP preempt_rt mod_unload`.
- HDA module ELF `.comment`: `GCC: (Gentoo 14.2.1_p20241221 p7) 14.2.1 20241221`.
- Upstream stable v6.12.30 release tag points to commit `e0e2f78243385e7188a57fcfceb6a19f723f1dff` in the stable/RT tree; kernel.org announced the 6.12.30 source release on 2025-05-22.

## 2. Directly established configuration values

| Config symbol | Value | Evidence |
|---|---:|---|
| `CONFIG_X86_64` | `y` | Official x86_64 kernel image and module ABI |
| `CONFIG_SMP` | `y` | Official release string and module vermagic include SMP |
| `CONFIG_PREEMPT_RT` | `y` | Official release string includes PREEMPT_RT; vermagic includes preempt_rt |
| `CONFIG_EXPERT` | `y` | v6.12.30 Kconfig: PREEMPT_RT depends on EXPERT |
| `CONFIG_MODULES` | `y` | Official modules tree is present and loadable |
| `CONFIG_MODULE_UNLOAD` | `y` | Official module vermagic includes `mod_unload` |
| `CONFIG_SOUND` | `y` | `kernel/sound/soundcore.ko` in modules.builtin |
| `CONFIG_SND` | `y` | `kernel/sound/core/snd.ko` in modules.builtin |
| `CONFIG_SND_PCM` | `y` | `kernel/sound/core/snd-pcm.ko` in modules.builtin |
| `CONFIG_SND_TIMER` | `y` | `kernel/sound/core/snd-timer.ko` in modules.builtin |
| `CONFIG_SND_HRTIMER` | `y` | `kernel/sound/core/snd-hrtimer.ko` in modules.builtin |
| `CONFIG_SND_ALOOP` | `y` | `kernel/sound/drivers/snd-aloop.ko` in modules.builtin |
| `CONFIG_HIGH_RES_TIMERS` | `y` | SND_HRTIMER Kconfig dependency |
| `CONFIG_PCI` | `y` | HDA PCI controller driver dependency path |
| `CONFIG_SND_PCI` | `y` | HDA PCI controller depends on SND_PCI; this is the PCI sound parent |
| `CONFIG_INPUT` | `y` | Realtek HDA codec depends on INPUT; input core is built-in |
| `CONFIG_SND_HDA` | `m` | `sound/pci/hda/snd-hda-codec.ko.xz` exists; v6.12.30 Makefile maps CONFIG_SND_HDA to this object |
| `CONFIG_SND_HDA_CORE` | `m` | `sound/hda/snd-hda-core.ko.xz` exists |
| `CONFIG_SND_HDA_INTEL` | `m` | `sound/pci/hda/snd-hda-intel.ko.xz` exists |
| `CONFIG_SND_HDA_GENERIC` | `m` | `sound/pci/hda/snd-hda-codec-generic.ko.xz` exists |
| `CONFIG_SND_HDA_CODEC_REALTEK` | `m` | `sound/pci/hda/snd-hda-codec-realtek.ko.xz` exists |
| `CONFIG_SND_HDA_CODEC_HDMI` | `m` | `sound/pci/hda/snd-hda-codec-hdmi.ko.xz` exists |
| `CONFIG_SND_INTEL_DSP_CONFIG` | `m` | `sound/hda/snd-intel-dspcfg.ko.xz` exists |

## 3. Important naming correction

The module filename `snd-hda-codec-generic.ko` corresponds to Kconfig symbol **`CONFIG_SND_HDA_GENERIC`**, not `CONFIG_SND_HDA_CODEC_GENERIC`. The latter symbol name should not be used. Similarly, `snd-hda-codec.ko` is the object built from `CONFIG_SND_HDA`.

## 4. Sound built-in/module boundary from the official package

Built-in sound objects include:
- `kernel/sound/soundcore.ko`
- `kernel/sound/core/snd.ko`
- `kernel/sound/core/snd-pcm.ko`
- `kernel/sound/core/snd-timer.ko`
- `kernel/sound/core/snd-hrtimer.ko`
- `kernel/sound/drivers/snd-aloop.ko`

HDA and codec modules include:
- `snd-hda-intel.ko.xz`
- `snd-hda-codec.ko.xz`
- `snd-hda-codec-realtek.ko.xz`
- `snd-hda-codec-generic.ko.xz`
- `snd-hda-codec-hdmi.ko.xz`
- `snd-hda-core.ko.xz`
- `snd-intel-dspcfg.ko.xz`

The archive also contains many unrelated ALSA/ASoC modules; their presence reflects a broad distribution kernel build, not the hardware in the J1800 machine.

## 5. HDA behavior already verified separately

- PCI ID `8086:0f04` is the Intel Bay Trail HDA controller and is matched by the Bay Trail capability path.
- Bay Trail driver capabilities include `AZX_DCAPS_COUNT_LPIB_DELAY` through `AZX_DCAPS_INTEL_PCH_BASE`.
- `position_fix=-1` and `bdl_pos_adj=-1` mean automatic position method and default BDL adjustment; for BYT the driver's default BDL adjustment is 32.
- Position Buffer is tried first; invalid position buffer readings can cause fallback to LPIB. If fallback happens, the per-stream LPIB delay callback is cleared. A valid Position Buffer path can use LPIB-derived delay correction.
- These are source/driver behavior facts, not extra `.config` switches to set.

## 6. Not recoverable from the current artifacts

Do not guess these as official values yet:
- `CONFIG_HZ` frequency and `CONFIG_NO_HZ` mode
- clocksource and clock-event selection defaults
- optional IRQ threading/debug settings beyond the RT mode evidence
- CPU frequency policy and idle settings
- HDA power-save, preallocation, debug, reconfiguration, and optional codec settings not proven by a direct module/object mapping
- DMA allocation details and `CONFIG_SND_DMA_SGBUF`
- PCI ASPM, IOMMU and platform power-management defaults
- the many unrelated driver/filesystem/network options

The official image has no embedded IKCONFIG; `/proc/config.gz` was unavailable and the installed build directory lacks generated config headers and `Module.symvers`. Therefore the complete original `.config` cannot be reconstructed byte-for-byte from the current evidence.

## 7. Build policy

1. Use the exact upstream Linux `v6.12.30` source release as the baseline, not 7.3.3.
2. Keep this fragment as evidence-backed constraints only; it is not a complete `.config`.
3. Do not use the polluted `/boot/config-6.12.30-daphile` copy as an official reference.
4. Do not infer `HZ`, NO_HZ, IOMMU, DMA, or power-save settings from `x86_64_defconfig`.
5. After a candidate config is generated, compare the resulting module/builtin inventory against the official package before compiling.
6. Preserve the original Daphile kernel as the boot fallback and install the rebuilt kernel under a distinct release suffix.

## 8. Source references

- Stable v6.12.30 tag and commit: https://kernel.googlesource.com/pub/scm/linux/kernel/git/rt/linux-rt-devel/+/refs/tags/v6.12.30
- Linux 6.12.30 release announcement and source archive: https://www.spinics.net/lists/announce-kernel/msg05183.html
- Kernel documentation on configuration targets: https://docs.kernel.org/admin-guide/README.html

#!/usr/bin/env bash
# Run from the root of a clean Linux v6.12.30 source tree.
# Place the two .lsmod inventory files beside this script or adjust paths.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
MODS="$ROOT/daphile-6.12.30-official-modules.lsmod"
BUILTINS="$ROOT/daphile-6.12.30-official-builtin.lsmod"

[[ -f "$MODS" && -f "$BUILTINS" ]] || {
  echo "Missing official module inventory files in $ROOT" >&2
  exit 1
}
[[ -x scripts/kconfig/streamline_config.pl ]] || {
  echo "Run this script from the root of a Linux v6.12.30 source tree" >&2
  exit 1
}

# Pass A: determine which tristate objects were built-in in the official kernel.
make allmodconfig
cp .config .config.allmodconfig
LSMOD="$BUILTINS" make localyesconfig
cp .config .config.builtin-probe

# Keep only symbols that changed from =m in allmodconfig to =y when the
# official built-in object list was supplied. This avoids copying unrelated
# allmodconfig defaults into the built-in override fragment.
awk '
  FNR==NR {
    if ($0 ~ /^CONFIG_[A-Za-z0-9_]+=m$/) {
      split($0, a, "="); was_m[a[1]]=1
    }
    next
  }
  /^CONFIG_[A-Za-z0-9_]+=y$/ {
    split($0, a, "=")
    if (a[1] in was_m) print
  }
' .config.allmodconfig .config.builtin-probe | sort -u > .daphile-builtin-y.fragment

# Pass B: keep the official .ko inventory modular, using the official list
# as the LSMOD input to the kernel's own localmodconfig dependency resolver.
make allmodconfig
LSMOD="$MODS" make localmodconfig

# Overlay only the =y transitions proven by modules.builtin.
./scripts/kconfig/merge_config.sh -m -O . .config .daphile-builtin-y.fragment

# Kernel image compression: ZSTD
./scripts/config --enable KERNEL_ZSTD
./scripts/config --disable KERNEL_GZIP
./scripts/config --disable KERNEL_BZIP2
./scripts/config --disable KERNEL_LZMA
./scripts/config --disable KERNEL_XZ
./scripts/config --disable KERNEL_LZO
./scripts/config --disable KERNEL_LZ4
./scripts/config --disable KERNEL_UNCOMPRESSED

# Confirmed distribution-wide ABI/runtime facts. Do not set HZ/NO_HZ/ASPM/
# IOMMU/DMA/HDA power-save here: those values are not recovered yet.
./scripts/config --enable EXPERT
./scripts/config --enable SMP
./scripts/config --enable MODULES
./scripts/config --enable MODULE_UNLOAD
./scripts/config --enable PCI
./scripts/config --enable INPUT
./scripts/config --enable HIGH_RES_TIMERS
./scripts/config --enable PREEMPT_RT
./scripts/config --set-str LOCALVERSION "-daphile-rebuild"
./scripts/config --disable LOCALVERSION_AUTO

# Preserve the known J1800 HDA stack as modules, and ALSA core as built-in.
# Kconfig dependency resolution will normalize the selected symbols.
./scripts/config --enable SOUND
./scripts/config --enable SND
./scripts/config --enable SND_PCM
./scripts/config --enable SND_TIMER
./scripts/config --enable SND_HRTIMER
./scripts/config --enable SND_ALOOP
./scripts/config --enable SND_PCI
./scripts/config --module SND_HDA
./scripts/config --module SND_HDA_CORE
./scripts/config --module SND_HDA_INTEL
./scripts/config --module SND_HDA_GENERIC
./scripts/config --module SND_HDA_CODEC_REALTEK
./scripts/config --module SND_HDA_CODEC_HDMI
./scripts/config --module SND_INTEL_DSP_CONFIG

KCONFIG_WARN_UNKNOWN_SYMBOLS=1 make olddefconfig

cp .config .config.daphile-6.12.30-reconstructed

echo "Created .config.daphile-6.12.30-reconstructed"
echo "Review key values:"
grep -E '^(CONFIG_(X86_64|SMP|EXPERT|PREEMPT_RT|MODULES|MODULE_UNLOAD|HZ|HZ_[0-9]+|NO_HZ|HIGH_RES_TIMERS|SOUND|SND|SND_PCM|SND_TIMER|SND_HRTIMER|SND_ALOOP|SND_HDA|SND_HDA_CORE|SND_HDA_INTEL|SND_HDA_GENERIC|SND_HDA_CODEC_REALTEK|SND_HDA_CODEC_HDMI|SND_INTEL_DSP_CONFIG|LOCALVERSION))=' .config || true

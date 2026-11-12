#!/usr/bin/env bash
# Candidate config reconstruction/audit for upstream Linux v6.12.30.
# Run from the root of a clean v6.12.30 source tree.
# This is an evidence-constrained CANDIDATE, not the missing official .config.
set -Eeuo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODS="$ROOT/daphile-6.12.30-official-modules.lsmod"
BUILTINS="$ROOT/daphile-6.12.30-official-builtin.lsmod"
FRAGMENT="$ROOT/daphile-6.12.30-confirmed-v2.fragment"
OUT="${AUDIT_OUT:-$PWD/daphile-config-audit}"
for f in "$MODS" "$BUILTINS" "$FRAGMENT"; do
  [[ -s "$f" ]] || { echo "Missing/empty evidence file: $f" >&2; exit 1; }
done
[[ -x scripts/kconfig/streamline_config.pl && -x scripts/config ]] || {
  echo "Run from the root of a clean Linux v6.12.30 source tree" >&2; exit 1;
}
[[ "$(make -s kernelversion)" == "6.12.30" ]] || { echo "Expected Linux 6.12.30" >&2; exit 1; }
mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
MOD_COUNT=$(awk 'NR>1 && NF {n++} END {print n+0}' "$MODS")
BUILTIN_COUNT=$(awk 'NR>1 && NF {n++} END {print n+0}' "$BUILTINS")
run_local() {
  local list="$1" target="$2" rc
  set +e
  yes "" | env LSMOD="$list" make "$target"
  rc=${PIPESTATUS[1]}
  set -e
  [[ $rc -eq 0 ]] || { echo "make $target failed: $rc" >&2; exit "$rc"; }
}
echo "Official inventory input counts: modules=$MOD_COUNT builtins=$BUILTIN_COUNT"
make allmodconfig
cp .config "$OUT/config.allmodconfig"
run_local "$BUILTINS" localyesconfig
cp .config "$OUT/config.builtin-probe"
awk '
  FNR==NR {
    if ($0 ~ /^CONFIG_[A-Za-z0-9_]+=m$/) { split($0,a,"="); was_m[a[1]]=1 }
    next
  }
  /^CONFIG_[A-Za-z0-9_]+=y$/ {
    split($0,a,"="); if (a[1] in was_m) print
  }
' "$OUT/config.allmodconfig" "$OUT/config.builtin-probe" |
  sort -u > "$OUT/inferred-builtin-y.fragment"
make allmodconfig
run_local "$MODS" localmodconfig
cp .config "$OUT/config.localmodconfig"
# Apply inferred built-ins AND evidence-backed fragment; neither is a full config.
scripts/kconfig/merge_config.sh -m -O . .config \
  "$OUT/inferred-builtin-y.fragment" "$FRAGMENT"
# Project-specific requirements agreed for this rebuild.
scripts/config --enable PREEMPT_RT
scripts/config --enable HIGH_RES_TIMERS
scripts/config --enable HZ_250
scripts/config --enable KERNEL_ZSTD
for sym in KERNEL_GZIP KERNEL_BZIP2 KERNEL_LZMA KERNEL_XZ KERNEL_LZO KERNEL_LZ4 KERNEL_UNCOMPRESSED; do
  scripts/config --disable "$sym"
done
scripts/config --set-str LOCALVERSION "-daphile-rebuild"
scripts/config --disable LOCALVERSION_AUTO
# Preserve permissive loading of unsigned package modules.
scripts/config --set-str SYSTEM_TRUSTED_KEYS ""
scripts/config --set-str SYSTEM_REVOCATION_KEYS ""
scripts/config --disable MODULE_SIG_ALL
scripts/config --disable MODULE_SIG_FORCE
scripts/config --disable IMA_APPRAISE_MODSIG
KCONFIG_WARN_UNKNOWN_SYMBOLS=1 make olddefconfig
make syncconfig
cp .config "$OUT/config.candidate"
sha256sum "$OUT/config.candidate" | tee "$OUT/config.sha256"
{
  echo "Linux source: $(make -s kernelversion)"
  echo "Kernel release: $(make -s kernelrelease)"
  echo "Official .ko inventory entries: $MOD_COUNT"
  echo "Official built-in inventory entries: $BUILTIN_COUNT"
  echo "Candidate config SHA256: $(sha256sum "$OUT/config.candidate" | awk '{print $1}')"
  echo
  echo "[Required project settings]"
  grep -E '^(CONFIG_(PREEMPT_RT|HIGH_RES_TIMERS|HZ_250|HZ|KERNEL_ZSTD|LOCALVERSION|LOCALVERSION_AUTO|MODULE_SIG_ALL|MODULE_SIG_FORCE|SYSTEM_TRUSTED_KEYS|SYSTEM_REVOCATION_KEYS))=' .config || true
  echo
  echo "[Review flags; not automatically treated as proven faults]"
  grep -E '^(CONFIG_(MAXSMP|NR_CPUS|ACPI_REDUCED_HARDWARE_ONLY|BOOT_CONFIG|BOOT_CONFIG_EMBED|BOOT_CONFIG_FORCE|X86_INTEL_MID|X86_INTEL_TSX_MODE|X86_INTERNODE_CACHE_SHIFT|HYPERV|IRQ_TIME_ACCOUNTING))=' .config || true
  echo
  echo "[Explicitly unset review flags]"
  grep -E '^# CONFIG_(MAXSMP|ACPI_REDUCED_HARDWARE_ONLY|BOOT_CONFIG|BOOT_CONFIG_EMBED|BOOT_CONFIG_FORCE|HYPERV|IRQ_TIME_ACCOUNTING) is not set$' .config || true
} | tee "$OUT/audit-report.txt"
grep -qx 'CONFIG_PREEMPT_RT=y' .config
grep -qx 'CONFIG_HZ_250=y' .config
grep -qx 'CONFIG_HZ=250' .config
grep -qx 'CONFIG_KERNEL_ZSTD=y' .config
grep -qx 'CONFIG_LOCALVERSION="-daphile-rebuild"' .config
! grep -qE '^CONFIG_(KERNEL_GZIP|KERNEL_BZIP2|KERNEL_LZMA|KERNEL_XZ|KERNEL_LZO|KERNEL_LZ4|KERNEL_UNCOMPRESSED)=y$' .config
! grep -qE '^CONFIG_MODULE_SIG_(ALL|FORCE)=y$|^CONFIG_IMA_APPRAISE_MODSIG=y$' .config
echo "CONFIG AUDIT CANDIDATE GENERATED (NO KERNEL COMPILE PERFORMED)"
echo "Output directory: $OUT"

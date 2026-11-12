#!/usr/bin/env bash
# Evidence-constrained candidate reconstruction for upstream Linux v6.12.30.
# This does NOT recover the missing official .config and does NOT compile a kernel.
set -Eeuo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
MODS="$ROOT/daphile-6.12.30-official-modules.lsmod"
BUILTINS="$ROOT/daphile-6.12.30-official-builtin.lsmod"
BUILTIN_PATHS="$ROOT/daphile-6.12.30-official-builtin.paths"
FRAGMENT="$ROOT/daphile-6.12.30-confirmed-v2.fragment"
OUT="${AUDIT_OUT:-$PWD/daphile-config-audit}"

for f in "$MODS" "$BUILTINS" "$BUILTIN_PATHS" "$FRAGMENT"; do
  [[ -s "$f" ]] || { echo "Missing/empty evidence file: $f" >&2; exit 1; }
done
[[ -x scripts/kconfig/streamline_config.pl && -x scripts/config ]] || {
  echo "Run from the root of a clean Linux v6.12.30 source tree" >&2; exit 1;
}
[[ "$(make -s kernelversion)" == "6.12.30" ]] || {
  echo "Expected Linux 6.12.30" >&2; exit 1;
}

mkdir -p "$OUT"
OUT="$(cd "$OUT" && pwd)"
MOD_COUNT=$(awk 'NR>1 && NF {n++} END {print n+0}' "$MODS")
BUILTIN_COUNT=$(awk 'NR>1 && NF {n++} END {print n+0}' "$BUILTINS")
BUILTIN_PATH_COUNT=$(awk 'NF {n++} END {print n+0}' "$BUILTIN_PATHS")

# The lsmod-style inventories are parsed by streamline_config.pl using only
# the first field; Size/Used-by values are placeholders, not runtime evidence.
inventory_names() {
  awk 'NR>1 && NF {print $1}' "$1" | LC_ALL=C sort -u
}
inventory_names "$BUILTINS" > "$OUT/builtin-inventory.names"
inventory_names "$MODS" > "$OUT/module-inventory.names"
if [[ "$BUILTIN_COUNT" -ne "$BUILTIN_PATH_COUNT" ]]; then
  echo "Built-in inventory count ($BUILTIN_COUNT) != .paths count ($BUILTIN_PATH_COUNT)" >&2
  exit 1
fi
if [[ "$(wc -l < "$OUT/builtin-inventory.names")" -ne "$BUILTIN_COUNT" ]]; then
  echo "Duplicate built-in module names detected" >&2
  exit 1
fi
if [[ "$(wc -l < "$OUT/module-inventory.names")" -ne "$MOD_COUNT" ]]; then
  echo "Duplicate loadable module names detected" >&2
  exit 1
fi

run_local() {
  local list="$1" target="$2" rc
  set +e
  yes "" | env LSMOD="$list" make "$target" \
    > "$OUT/$target.stdout.log" 2> "$OUT/$target.stderr.log"
  rc=${PIPESTATUS[1]}
  set -e
  if [[ $rc -ne 0 ]]; then
    echo "make $target failed: $rc (see $OUT/$target.stderr.log)" >&2
    exit "$rc"
  fi
  # Keep streamline_config.pl unresolved-object warnings visible and countable.
  grep -E 'config not found|did not have configs|WARNING:' \
    "$OUT/$target.stderr.log" > "$OUT/$target.warnings.log" || true
}

echo "Official inventory input counts: modules=$MOD_COUNT builtins=$BUILTIN_COUNT"
make allmodconfig
cp .config "$OUT/config.allmodconfig"

# Infer only symbols changed from m to y by localyesconfig using the official
# built-in-object inventory. This is a heuristic, not an official config dump.
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
  LC_ALL=C sort -u > "$OUT/inferred-builtin-y.fragment"

# Independently retain options required by the official loadable-module list.
make allmodconfig
run_local "$MODS" localmodconfig
cp .config "$OUT/config.localmodconfig"

# Merge the inferred built-ins and the small evidence-backed project fragment.
scripts/kconfig/merge_config.sh -m -O . .config \
  "$OUT/inferred-builtin-y.fragment" "$FRAGMENT"

# Project requirements explicitly agreed for this rebuild.
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

# Restore only values with a known original-config comparison.
scripts/config --disable MAXSMP
scripts/config --set-val NR_CPUS 8
scripts/config --disable ACPI_REDUCED_HARDWARE_ONLY
scripts/config --disable X86_VSMP
scripts/config --set-val X86_INTERNODE_CACHE_SHIFT 6
# BOOTTIME_TRACING selects BOOT_CONFIG in kernel/trace/Kconfig. It is not
# present in the official built-in inventory and is not needed for this build.
scripts/config --disable BOOTTIME_TRACING
scripts/config --disable BOOT_CONFIG
scripts/config --disable BOOT_CONFIG_EMBED
scripts/config --disable BOOT_CONFIG_FORCE
scripts/config --disable X86_INTEL_TSX_MODE_OFF
scripts/config --enable X86_INTEL_TSX_MODE_AUTO

# Record the state after scripts/config and before Kconfig normalization.
cp .config "$OUT/config.pre-olddefconfig"
{
  echo "[BOOT_CONFIG before olddefconfig]"
  grep -E '^(CONFIG_BOOT_CONFIG=|# CONFIG_BOOT_CONFIG is not set$)' .config || true
} > "$OUT/boot-config-state.log"
if grep -qE '^CONFIG_(BOOT_CONFIG|BOOTTIME_TRACING)=y$' .config; then
  echo "ERROR: scripts/config --disable BOOT_CONFIG did not take effect" >&2
  exit 1
fi

KCONFIG_WARN_UNKNOWN_SYMBOLS=1 make olddefconfig \
  2> "$OUT/olddefconfig.stderr.log"
make syncconfig

# Record whether Kconfig normalization re-enabled any forbidden option.
cp .config "$OUT/config.post-olddefconfig"
{
  echo "[BOOT_CONFIG after olddefconfig + syncconfig]"
  grep -E '^(CONFIG_BOOT_CONFIG=|# CONFIG_BOOT_CONFIG is not set$)' .config || true
} >> "$OUT/boot-config-state.log"
if grep -qE '^CONFIG_(BOOT_CONFIG|BOOTTIME_TRACING)=y$' .config; then
  echo "ERROR: BOOT_CONFIG was re-enabled by Kconfig normalization" >&2
  echo "See $OUT/boot-config-state.log and config.post-olddefconfig" >&2
  exit 1
fi

cp .config "$OUT/config.candidate"
sha256sum "$OUT/config.candidate" | tee "$OUT/config.sha256"

{
  echo "Linux source: $(make -s kernelversion)"
  echo "Kernel release: $(make -s kernelrelease)"
  echo "Official loadable .ko inventory entries: $MOD_COUNT"
  echo "Official built-in inventory entries: $BUILTIN_COUNT"
  echo "Official built-in .paths entries: $BUILTIN_PATH_COUNT"
  echo "Unique inferred builtin y symbols: $(wc -l < "$OUT/inferred-builtin-y.fragment")"
  echo "localyesconfig warnings: $(wc -l < "$OUT/localyesconfig.warnings.log")"
  echo "localmodconfig warnings: $(wc -l < "$OUT/localmodconfig.warnings.log")"
  echo "Candidate config SHA256: $(sha256sum "$OUT/config.candidate" | awk '{print $1}')"
  echo
  echo "[Required project settings]"
  grep -E '^(CONFIG_(PREEMPT_RT|HIGH_RES_TIMERS|HZ_250|HZ|KERNEL_ZSTD|LOCALVERSION|LOCALVERSION_AUTO|MODULE_SIG_ALL|MODULE_SIG_FORCE|SYSTEM_TRUSTED_KEYS|SYSTEM_REVOCATION_KEYS))=' .config || true
  echo
  echo "[Known original values restored]"
  grep -E '^(CONFIG_NR_CPUS=[0-9]+|CONFIG_X86_INTERNODE_CACHE_SHIFT=[0-9]+|CONFIG_X86_INTEL_TSX_MODE_AUTO=y)$' .config || true
  echo
  echo "[Known original options expected unset]"
  grep -E '^# CONFIG_(MAXSMP|ACPI_REDUCED_HARDWARE_ONLY|BOOT_CONFIG|BOOT_CONFIG_EMBED|BOOT_CONFIG_FORCE|X86_INTEL_TSX_MODE_OFF) is not set$' .config || true
  echo
  echo "[Unsupported optional tracing selector disabled]"
  grep -E '^# CONFIG_BOOTTIME_TRACING is not set$' .config || true
  echo
  echo "[Review only; not changed without sufficient evidence]"
  grep -E '^(CONFIG_(X86_INTEL_MID|HYPERV|IRQ_TIME_ACCOUNTING))=' .config || true
  echo
  echo "[Unresolved localyesconfig/localmodconfig warnings]"
  cat "$OUT/localyesconfig.warnings.log" "$OUT/localmodconfig.warnings.log"
} | tee "$OUT/audit-report.txt"

# Fail on required project settings or known-value restoration regressions.
grep -qx 'CONFIG_PREEMPT_RT=y' .config
grep -qx 'CONFIG_HIGH_RES_TIMERS=y' .config
grep -qx 'CONFIG_HZ_250=y' .config
grep -qx 'CONFIG_HZ=250' .config
grep -qx 'CONFIG_KERNEL_ZSTD=y' .config
grep -qx 'CONFIG_LOCALVERSION="-daphile-rebuild"' .config
grep -qx 'CONFIG_NR_CPUS=8' .config
grep -qx 'CONFIG_X86_INTERNODE_CACHE_SHIFT=6' .config
if grep -qx 'CONFIG_X86_VSMP=y' .config; then
  echo "ERROR: CONFIG_X86_VSMP must be disabled" >&2
  exit 1
fi
grep -qx 'CONFIG_X86_INTEL_TSX_MODE_AUTO=y' .config

if grep -qE '^CONFIG_(MAXSMP|ACPI_REDUCED_HARDWARE_ONLY|BOOT_CONFIG|BOOT_CONFIG_EMBED|BOOT_CONFIG_FORCE|X86_INTEL_TSX_MODE_OFF|BOOTTIME_TRACING)=y$' .config; then
  echo "ERROR: a known-original-unset option or unsupported BOOT_CONFIG selector is enabled:" >&2
  grep -E '^CONFIG_(MAXSMP|ACPI_REDUCED_HARDWARE_ONLY|BOOT_CONFIG|BOOT_CONFIG_EMBED|BOOT_CONFIG_FORCE|X86_INTEL_TSX_MODE_OFF|BOOTTIME_TRACING)=y$' .config >&2
  exit 1
fi
if grep -qE '^CONFIG_(KERNEL_GZIP|KERNEL_BZIP2|KERNEL_LZMA|KERNEL_XZ|KERNEL_LZO|KERNEL_LZ4|KERNEL_UNCOMPRESSED)=y$' .config; then
  echo "ERROR: an unapproved kernel compression option is enabled:" >&2
  grep -E '^CONFIG_(KERNEL_GZIP|KERNEL_BZIP2|KERNEL_LZMA|KERNEL_XZ|KERNEL_LZO|KERNEL_LZ4|KERNEL_UNCOMPRESSED)=y$' .config >&2
  exit 1
fi
if grep -qE '^CONFIG_MODULE_SIG_(ALL|FORCE)=y$|^CONFIG_IMA_APPRAISE_MODSIG=y$' .config; then
  echo "ERROR: a disallowed module-signature option is enabled:" >&2
  grep -E '^CONFIG_MODULE_SIG_(ALL|FORCE)=y$|^CONFIG_IMA_APPRAISE_MODSIG=y$' .config >&2
  exit 1
fi

echo "CONFIG AUDIT CANDIDATE GENERATED (NO KERNEL COMPILE PERFORMED)"
echo "Output directory: $OUT"

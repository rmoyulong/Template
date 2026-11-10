#!/usr/bin/env bash
set -euo pipefail

# Usage:
#   ./apply_migration.sh /path/to/linux-7.3.3
# Run from an extracted, clean Linux 7.3.3 source tree.

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
SRC="${1:-$PWD}"
SRC="$(cd -- "$SRC" && pwd)"
FRAGMENT="$SCRIPT_DIR/inferred-7.3.3.config"

if [[ ! -f "$SRC/Makefile" || ! -d "$SRC/scripts/kconfig" ]]; then
  echo "ERROR: '$SRC' does not look like a Linux kernel source tree." >&2
  exit 1
fi

version="$(awk '/^VERSION =/ {v=$3} /^PATCHLEVEL =/ {p=$3} /^SUBLEVEL =/ {s=$3} END {print v "." p "." s}' "$SRC/Makefile")"
if [[ "$version" != "7.3.3" ]]; then
  echo "ERROR: expected Linux 7.3.3 source, detected '$version'." >&2
  exit 1
fi

cd "$SRC"

if [[ -e .config ]]; then
  echo "ERROR: existing .config found. Use a clean source tree or move .config away first." >&2
  exit 1
fi

echo "[1/5] Generating x86_64 baseline..."
make ARCH=x86 x86_64_defconfig

cp .config .config.x86_64_defconfig

echo "[2/5] Merging Daphile evidence-backed fragment..."
"$SRC/scripts/kconfig/merge_config.sh" -m .config "$FRAGMENT"

cp .config .config.pre_olddefconfig

echo "[3/5] Resolving Kconfig dependencies/defaults..."
make ARCH=x86 olddefconfig

cp .config .config.daphile-7.3.3

echo "[4/5] Recording configuration differences..."
if [[ -x scripts/diffconfig ]]; then
  scripts/diffconfig .config.x86_64_defconfig .config.daphile-7.3.3 \
    > config_diff_from_x86_64_defconfig.txt || true
fi

# Record requested symbols which did not survive Kconfig resolution.
python3 - "$FRAGMENT" .config.daphile-7.3.3 > config_migration_check.txt <<'PY'
import re, sys
fragment, final = sys.argv[1:]
def read(path):
    out = {}
    for line in open(path, encoding="utf-8", errors="replace"):
        m = re.match(r"^(CONFIG_[A-Z0-9_]+)=(.*)$", line.strip())
        if m:
            out[m.group(1)] = m.group(2)
        else:
            m = re.match(r"^# (CONFIG_[A-Z0-9_]+) is not set$", line.strip())
            if m:
                out[m.group(1)] = "n"
    return out
wanted, got = read(fragment), read(final)
for key, value in wanted.items():
    actual = got.get(key, "<absent>")
    status = "OK" if actual == value else "CHECK"
    print(f"{status:5} {key}: requested={value}, final={actual}")
PY

echo "[5/5] Done."
echo "Final config: $SRC/.config.daphile-7.3.3"
echo "Review:       $SRC/config_migration_check.txt"
echo "Diff:         $SRC/config_diff_from_x86_64_defconfig.txt"
echo
echo "IMPORTANT: review every CHECK entry and build/test on target hardware."

# Daphile 6.12.30 config reconstruction workflow

This is a reconstruction from the official 6.12.30 kernel image and module package, not a recovered original `.config`.

## Files

- `daphile-6.12.30-confirmed-v2.fragment`: direct evidence-backed config values.
- `daphile-6.12.30-official-modules.lsmod`: all 1,829 module names from official `modules.tar.gz`, formatted for the kernel's `LSMOD` input.
- `daphile-6.12.30-official-builtin.lsmod`: all 379 built-in object names from official `modules.builtin`, formatted for `LSMOD`.
- `reconstruct-daphile-6.12.30-config.sh`: two-pass reconstruction helper for a clean Linux v6.12.30 source tree.
- `daphile-6.12.30-config-evidence-v2.md`: evidence and unresolved configuration values.

## Why use the inventory lists

The official module package gives more information than a short hand-written fragment:

- A `.ko.xz` file proves that the corresponding object was built as a module.
- An entry in `modules.builtin` proves that the corresponding object was built into the kernel.
- Linux's `localmodconfig` / `localyesconfig` scripts map module/object names back to Kconfig symbols by reading that exact source tree's Kconfig and Makefiles.

The helper therefore uses the official object inventory to infer Kconfig selections instead of guessing hundreds of driver options by name. It performs two passes: first identify tristate options that must be built-in, then preserve the official `.ko` inventory as modules. The resulting configuration is still an approximation because module inventories do not reveal every non-module option, compiler flag, default, or distribution-specific setting.

## Run

From a clean Linux v6.12.30 source tree, put the helper and both `.lsmod` files in the same directory (for example, the GitHub workspace root), then run:

```bash
bash /path/to/reconstruct-daphile-6.12.30-config.sh
```

The script expects to be run with the current working directory set to the root of the kernel source tree. It writes `.config.daphile-6.12.30-reconstructed` after `olddefconfig`.

Review the final values and compare the generated module/builtin inventory with the official package before compiling. Do not overwrite or remove the original Daphile kernel or its module directory; install the test build under the distinct `-daphile-rebuild` release suffix.

## Known unresolved values

Do not treat the helper's defaults as official values for `HZ`, `NO_HZ`, clocksource, IRQ policy beyond PREEMPT_RT, CPU idle/frequency policy, HDA power saving, DMA allocation, PCI ASPM, or IOMMU. These still need independent evidence.

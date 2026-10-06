---
name: submodule-and-kernel-tree-rules
description: Submodule governance and discipline for the upstream linux kernel tree.
trigger: always_on
---
# Submodule & Linux Kernel Tree Guidelines

1. **Submodule Pointer Discipline**:
   - The `linux` directory is a git submodule tracking `Ultimaker/linux.git`.
   - Never commit changes directly to the submodule from this repository checkout.
   - Kernel source modifications, driver additions, and upstream backports must be committed, reviewed, and merged in `Ultimaker/linux.git` first.
   - Submodule pointer updates in this repository must be in a standalone, dedicated commit referencing the Jira ticket (e.g. `[EMB-370] Update linux submodule`).

2. **Kernel Patches & Defconfig**:
   - Standalone patches in `patches/` are applied during kernel build via `build.sh`.
   - Any configuration change must be validated against `configs/sx8m_defconfig`.

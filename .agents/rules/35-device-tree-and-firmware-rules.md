---
name: device-tree-and-firmware-rules
description: Device tree selection, Ultimainboard 5 display mapping, and proprietary firmware sourcing rules.
trigger: glob
glob: "{dts/**,proprietary_firmware/**}"
paths:
  - "dts/**"
  - "proprietary_firmware/**"
---
# Device Tree & Firmware Guidelines

1. **Device Tree Selection Invariants**:
   - Before modifying device trees in `dts/`, consult [dts/Readme.md](dts/Readme.md) — it is the authored convention for Ultimainboard 5 display selection.
   - Display mappings:
     - Ulticontroller 4.0 at 1024x600 (Factor 4, Factor 4+, NGP): `dts/ulticontroller4.0-lvds-1024x600.dts`.
     - Ulticontroller 3.2 LVDS at 800x320 (S6 and S8): `dts/ulticontroller3.2-lvds-800x320.dts`.
   - Both device tree sources must include `ultimainboard5-lvds.dtsi` which includes IMX8 definitions (`congatec/imx8mm-cgtsx8m-lvds.dtsi`).
   - U-Boot requires a device tree named `cgtsx8m-ultimain5.dtb` in the boot partition, symlinked by `debian/postinst` based on the article number in `/etc/ultimaker_firmware`.

2. **Proprietary Firmware Sourcing**:
   - Consult [proprietary_firmware/Readme.md](proprietary_firmware/Readme.md).
   - Proprietary firmware binaries must originate from upstream linux-firmware (`git://git.kernel.org/pub/scm/linux/kernel/git/firmware/linux-firmware.git`).
   - The WiFi regulatory DB must remain a symlink to the upstream database provided by the Debian `wireless-regdb` package.

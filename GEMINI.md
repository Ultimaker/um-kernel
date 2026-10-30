<!-- @generated from AGENTS.md. Edit AGENTS.md instead. -->

# Agent Guide: um-kernel

This file provides critical context, commands, and invariants for AI agents working in the `um-kernel` repository.

## 1. Branch & Platform Matrix

| Branch | Default? | Target SOM & Kernel Submodule | Defconfig & Arch | Kernel Image & DTs | Output Package |
| :--- | :---: | :--- | :--- | :--- | :--- |
| **`master/imx8`** | **Yes (`HEAD`)** | **Congatec i.MX8M Mini** (`cgtsx8m` - Linux 6.6 LTS) | `configs/sx8m_defconfig` (`arm64`, `UM_ARCH="imx8mm"`) | `/boot/uImage-sx8m`, monolithic `.dtb`s | `um-kernel_<ver>-imx8mm_arm64.deb` |
| **`master/cm4`** | No | **Raspberry Pi CM4** (`bcm2711` - Linux 6.17 + 32bpp `XRGB8888` fbdev) | `configs/bcm2711_defconfig` (`arm64`, `UM_ARCH="cm4"`) | `/boot/uImage-cm4` (`kernel8.img`), `/boot/overlays/*.dtbo` | `um-kernel_<ver>-cm4_arm64.deb` |
| **`master/imx6`** | No | **MSC i.MX6DL** (`imx6dl` - S3, S5R2, S7) | `armhf` (`UM_ARCH="imx6dl"`) | `/boot/uImage-imx6dl`, `.dtb`s | `um-kernel_<ver>-imx6dl_armhf.deb` |
| **`master/sun7i`** | No | **Olimex Allwinner A20** (`sun7i` - UM3, S5R1) | `armhf` (`UM_ARCH="sun7i"`) | `/boot/uImage-sun7i`, `.dtb`s | `um-kernel_<ver>-sun7i_armhf.deb` |

## 2. Build, Lint, and Configuration Commands

- **Initialize Submodule**:
  ```bash
  git submodule update --init --recursive
  ```
- **Full Build (Env Check + ShellCheck + Kernel/DTB/Initramfs + `.deb`)**:
  ```bash
  RELEASE_VERSION="498.5.0-dev" ./build_for_ultimaker.sh
  ```
- **ShellCheck Linting Only (Fast Gate)**:
  ```bash
  ./build_for_ultimaker.sh -a shellcheck
  ```
- **Kernel & Package Build Only (Skip ShellCheck Container)**:
  ```bash
  RELEASE_VERSION="498.5.0-dev" ./build_for_ultimaker.sh -a build
  ```
- **Interactive Kernel `menuconfig` (auto-saves back to `KCONFIG`)**:
  ```bash
  ./build_for_ultimaker.sh menuconfig
  ```

## 3. Critical Code-Path Invariants (Do Not Break)

1. **Built-in Drivers (`=y`) in `configs/bcm2711_defconfig` for Initramfs**:
   - Because the UltiMaker boot splash (`umsplash.fb`) and boot-time USB firmware updates (`start_update.sh`) execute inside the kernel's embedded `initramfs` (`CONFIG_INITRAMFS_SOURCE="initramfs/initramfs.lst"`) *before* the rootfs is mounted, all display (`CONFIG_DRM=y`, `CONFIG_DRM_VC4=y`, `CONFIG_DRM_V3D=y`, `CONFIG_DRM_PANEL_LVDS=y`, `CONFIG_DRM_TI_SN65DSI83=y`), I2C (`CONFIG_I2C_BCM2835=y`, `CONFIG_I2C_BRCMSTB=y`, `CONFIG_I2C_CHARDEV=y`), GPIO/LED (`CONFIG_GPIO_PCA953X=y`, `CONFIG_GPIO_PCA9570=y`, `CONFIG_LEDS_PCA963X=y`), EEPROM (`CONFIG_EEPROM_AT24=y`), USB hub (`CONFIG_USB_HUB_USB251XB=y`), SquashFS (`CONFIG_SQUASHFS=y`), and FAT32/exFAT NLS (`CONFIG_EXFAT_FS=y`, `CONFIG_NLS_ISO8859_1=y`, `CONFIG_NLS_UTF8=y`) drivers MUST remain built-in (`=y`).
2. **Coexisting i.MX8 `.dtb` and CM4 `.dtbo` Sources in `dts/`**:
   - `dts/ulticontroller3.2-lvds-800x320.dts` and `dts/ulticontroller4.0-lvds-1024x600.dts` must keep `#include "ultimainboard5-lvds.dtsi"` and `&i2c2` for i.MX8.
   - CM4 uses the overlay files `dts/ulticontroller.dts`, `dts/ulticontroller-800x320.dts`, and `dts/ulticontroller-ngp.dts` (and base `dts/ultimainboard5-cm4.dts`). `dtb_build()` in `build.sh` filters which files are compiled based on `UM_ARCH`.
3. **Keep Default `BOM_NUMBER="227380"` in `initramfs/init.sh`**:
   - Hardware compatibility validation is performed inside `jedi-system-update` (`10_detect_type.sh`) by reading the carrier EEPROM directly via `i2ctransfer`, NOT from the `BOM_NUMBER` CLI argument passed to `start_update.sh`.
   - `start_update.sh` uses the `BOM_NUMBER` argument to select the screen resolution directory for update progress images (`/etc/jedi_system_update/images/${BOM_NUMBER}/`). Defaulting `BOM_NUMBER="227380"` ensures 1024x600 update progress images are shown if the EEPROM cannot be read during early boot.
4. **Keep `target_storage="$(get_emmc_dev)"` Independent of the Update Source Device in `initramfs/init.sh`**:
   - Never override `target_storage` with the block device where `um-update.swu` was found (`${dev%p[0-9]*}`), because on i.MX8 an external recovery SD card is `/dev/mmcblk0p2` while the internal eMMC is `/dev/mmcblk2`. `get_emmc_dev()` already returns `/dev/mmcblk0` on CM4 and `/dev/mmcblk2` on i.MX8.
5. **Keep `mount "${boot_part}" /boot 2>/dev/null || true` in `debian/preinst`**:
   - Provides mount-failure tolerance during chroot package unpacking/installation (where `/boot` is a directory inside the chroot rather than a separate mountable block device).

---

_Last updated: 2026-10-30_

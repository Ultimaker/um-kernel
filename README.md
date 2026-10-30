Copyright © UltiMaker 2016–2026

# um-kernel — UltiMaker Linux Kernel, Device Trees, & Initramfs Package

`um-kernel` contains the Linux kernel configurations, Device Tree sources and overlays, embedded early-boot `initramfs`, proprietary firmware blobs, and Debian packaging scripts for UltiMaker 3D printers. It compiles the kernel source tree from the `linux/` submodule ([Ultimaker/linux](https://github.com/Ultimaker/linux)) inside a Docker container and produces a versioned `um-kernel` Debian package (`.deb`).

---

## 1. Branch & Platform Support Matrix

Because different System-on-Modules (SOMs) rely on distinct vendor BSP kernel trees in the `linux/` submodule, `um-kernel` maintains dedicated `master/*` branches per SOM family while sharing a unified `initramfs/`, `dts/`, and `debian/` wrapper structure:

| Branch | Default? | Target SOM & Kernel Submodule | Defconfig & Arch | Kernel Image & DTs | Output Package | Status |
| :--- | :---: | :--- | :--- | :--- | :--- | :--- |
| **`master/imx8`** | **Yes (`HEAD`)** | **Congatec i.MX8M Mini** (`cgtsx8m`)<br>• Linux 6.6 LTS (`cgtimx8mm__lf-6.6.y`) | `configs/sx8m_defconfig`<br>(`arm64`, `UM_ARCH="imx8mm"`) | `/boot/uImage-sx8m`<br>Monolithic `.dtb`s (`cgtsx8m-ultimain5.dtb` symlink) | `um-kernel_<ver>-imx8mm_arm64.deb` | **Active** (Factor 4, Factor 4+, S6, S8, NGP) |
| **`master/cm4`** | No | **Raspberry Pi Compute Module 4** (`bcm2711`)<br>• Linux 6.17 (`rpi-6.17.y` + 32bpp `XRGB8888` fbdev) | `configs/bcm2711_defconfig`<br>(`arm64`, `UM_ARCH="cm4"`) | `/boot/uImage-cm4` (`kernel8.img`)<br>Overlays in `/boot/overlays/*.dtbo` | `um-kernel_<ver>-cm4_arm64.deb` | **Active** (CM4 variants of Factor 4, 4+, S6, S8, NGP) |
| **`master/imx6`** | No | **MSC i.MX6DL** (`imx6dl`) | `armhf` (`UM_ARCH="imx6dl"`) | `/boot/uImage-imx6dl` + `.dtb`s | `um-kernel_<ver>-imx6dl_armhf.deb` | **Legacy** (S3, S5R2, S7 — use historical tags) |
| **`master/sun7i`** | No | **Olimex Allwinner A20** (`sun7i-a20`) | `armhf` (`UM_ARCH="sun7i"`) | `/boot/uImage-sun7i` + `.dtb`s | `um-kernel_<ver>-sun7i_armhf.deb` | **Legacy** (UM3, S5R1 — use historical tags) |

---

## 2. Repository Layout

* **`configs/`**:
  * `sx8m_defconfig`: Kernel configuration for Congatec i.MX8M Mini (`master/imx8`).
  * `bcm2711_defconfig`: Kernel configuration for Raspberry Pi CM4 (`master/cm4`), with built-in (`=y`) DRM/VC4/V3D/LVDS (`ti-sn65dsi83`, `panel-lvds`), touchscreen (`edt-ft5x06`, `goodix`), I2C, GPIO expander (`pca953x`, `pca9570`), LED (`leds-pca963x`), EEPROM (`at24`), USB hub (`usb251xb`), SquashFS, and FAT32/exFAT NLS drivers required by the embedded initramfs.
* **`dts/`**:
  * **i.MX8 Monolithic Device Trees** (compiled when `UM_ARCH="imx8mm"`):
    * `ulticontroller4.0-lvds-1024x600.dts` (Factor 4, Factor 4+, NGP)
    * `ulticontroller3.2-lvds-800x320.dts` (S6, S8)
    * `ultimainboard5-lvds.dtsi` (base Ultimainboard 5 i.MX8 definitions)
  * **CM4 Device Tree Overlays & Base DTS** (compiled when `UM_ARCH="cm4"`):
    * `ulticontroller.dts` -> `/boot/overlays/ulticontroller.dtbo` (Factor 4 / 4+ 1024x600)
    * `ulticontroller-800x320.dts` -> `/boot/overlays/ulticontroller-800x320.dtbo` (S6 / S8 800x320)
    * `ulticontroller-ngp.dts` -> `/boot/overlays/ulticontroller-ngp.dtbo` (NGP 1024x600)
    * `ultimainboard5-cm4.dts` -> `/boot/ultimainboard5-cm4.dtb`
    * Plus standard Raspberry Pi base overlays compiled from `linux/arch/arm/boot/dts/overlays/` (`dwc2`, `vc4-kms-v3d`, `vc4-kms-v3d-pi4`, `i2c0`, `i2c1`, `i2c3`, `uart3`, `uart4`, `pcie-32bit-dma`, `overlay_map.dtb`).
  * See [dts/Readme.md](dts/Readme.md) for full details on Device Tree and overlay selection.
* **`initramfs/`**:
  * `initramfs.lst` & `init.sh`: Embedded early-userspace initramfs bundled directly into the kernel image (`CONFIG_INITRAMFS_SOURCE="initramfs/initramfs.lst"`).
  * Displays the boot splash (`umsplash.fb` on `/dev/fb0`), dynamically resolves the eMMC device (`/dev/mmcblk0` on CM4 vs `/dev/mmcblk2` on i.MX8) and carrier EEPROM I2C bus (`i2c-3` on CM4 vs `i2c-1` on i.MX8), supports factory USB EEPROM provisioning (`article_number` and `country_code_lock`), and executes boot-time USB/SD firmware updates (`um-update.swu` / `um-restore.swu`).
* **`debian/`**:
  * `control`, `preinst`, `postinst`, `triggers`: Debian package scripts.
  * `debian/postinst` reads `article_numbers:` and `som:` from `/etc/ultimaker_firmware`: on CM4 (`som: cm4`), it configures `dtoverlay=<overlay>` in `/boot/config.txt`; on i.MX8, it creates the `/boot/cgtsx8m-ultimain5.dtb` symlink.
* **`proprietary_firmware/`**:
  * Closed-source firmware binaries (e.g. `imx/sdma/`, `rtw88/` WiFi firmware, and upstream `regulatory.db`) packaged into `/lib/firmware/`.
* **`linux/`**:
  * Git submodule pointing to `Ultimaker/linux.git`.

---

## 3. Building, Configuring, & Linting

All builds run inside Docker (`ghcr.io/ultimaker/um-kernel:v3`) via `./build_for_ultimaker.sh`:

```bash
# Initialize the linux submodule (first time or after switching branches):
git submodule update --init --recursive

# Full build (environment check + ShellCheck + kernel/DTB/initramfs compile + .deb package):
RELEASE_VERSION="498.5.0-dev" ./build_for_ultimaker.sh

# Run ShellCheck linting only:
./build_for_ultimaker.sh -a shellcheck

# Build kernel package only (skip ShellCheck container):
RELEASE_VERSION="498.5.0-dev" ./build_for_ultimaker.sh -a build

# Run interactive kernel menuconfig and save updated defconfig:
./build_for_ultimaker.sh menuconfig
```

### Output Artifacts
*(Note: When `RELEASE_VERSION` ends with `-dev`, `build.sh` places `-${UM_ARCH}` before `-dev`).*
* **On `master/imx8`**: `./um-kernel_<ver>-imx8mm_arm64.deb` (or `./um-kernel_<ver>-imx8mm-dev_arm64.deb` for `-dev` builds; also in `_build/`).
* **On `master/cm4`**: `./um-kernel_<ver>-cm4_arm64.deb` (or `./um-kernel_<ver>-cm4-dev_arm64.deb` for `-dev` builds; also in `_build/`).

For AI agent conventions and code-path invariants, see [AGENTS.md](AGENTS.md).

### Device Tree Selection

We have device trees and overlays for displays supported by **Ultimainboard 5**:

#### i.MX8 SoM (Congatec SMARC):
- *Ulticontroller 4.0 at 1024x600* (Factor 4, Factor 4+, NGP): `ulticontroller4.0-lvds-1024x600.dts`
- *Ultricontroller 3.2 LVDS* at 800x320 (S6 and S8): `ulticontroller3.2-lvds-800x320.dts`

Both device trees include the Ultimainboard 5 device tree: `ultimainboard5-lvds.dtsi` (which includes `congatec/imx8mm-cgtsx8m-lvds.dtsi`).

The *UBoot* will look for a device tree file named **`cgtsx8m-ultimain5.dtb`** in the boot partition.
In order to boot the correct DT, the um-kernel post install script will get the **first** recipe
article number (from the file `/etc/ultimaker_firmware`) and will set a symlink named
`cgtsx8m-ultimain5.dtb` pointing to one of those 2 device trees that should be used by this article number.

#### Raspberry Pi Compute Module 4/5 (CM4 / CM5):
- *Ulticontroller Overlay (Raspberry Pi OS / Bookworm)*: `ulticontroller.dts` (compiles to `ulticontroller.dtbo`)
  - Provides MIPI DSI1 to TI SN65DSI84 bridge (`<&dsi1>`, I2C1 `0x2d`)
  - Configures 1024x600 panel-lvds with VESA-24 mapping
  - Configures I2C0 Ulticontroller: `pca9536@41` (GPIO expander with `disp_rst_hog`), `pca9632@60` (backlight LED, default-on), `ft5426@38` (touchscreen polling mode), `24c32@50` (EDID)
  - Configures I2C3 Ultimainboard 5: `tca6416@20` (GPIO expander with `lvds_pwr_en_hog`), `carrierdata@57`, `pca9633@62` (cabin lights)
  - Installed to `/boot/firmware/overlays/ulticontroller.dtbo` and loaded via `/boot/firmware/config.txt`:
    ```ini
    enable_uart=1
    dtoverlay=i2c0,pins_0_1
    dtoverlay=i2c1,pins_44_45
    dtoverlay=i2c3,pins_2_3
    dtoverlay=ulticontroller
    ```
- *Full CM4 Board Device Tree*: `ultimainboard5-rpi-cm4.dts` (for custom kernel builds)

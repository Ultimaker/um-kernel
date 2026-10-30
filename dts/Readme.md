### Device Tree & Overlay Selection (`dts/`)

We maintain device trees and overlays for all displays and Ultimainboard 5 configurations across both supported 64-bit System-on-Modules (**Congatec i.MX8M Mini** and **Raspberry Pi Compute Module 4**).

During package installation (`debian/postinst`), the script reads `article_numbers:` and `som:` from `/etc/ultimaker_firmware`:

---

#### 1. Congatec i.MX8M Mini SOM (`som: imx8` or omitted — `master/imx8`)

* **Ulticontroller 4.0 (1024x600 — Factor 4, Factor 4+, NGP: `227380`, `105*`, `109*`)**: `ulticontroller4.0-lvds-1024x600.dts`
* **Ulticontroller 3.2 LVDS (800x320 — S6, S8: `106*`, `107*`)**: `ulticontroller3.2-lvds-800x320.dts`

Both device trees include `ultimainboard5-lvds.dtsi` (which includes `congatec/imx8mm-cgtsx8m-lvds.dtsi`). U-Boot loads `/boot/cgtsx8m-ultimain5.dtb`, which `debian/postinst` symlinks to the matching `.dtb` file.

---

#### 2. Raspberry Pi Compute Module 4 SOM (`som: cm4` — `master/cm4`)

On CM4, VideoCore firmware boots `/boot/kernel8.img` (`uImage-cm4`) with `/boot/bcm2711-rpi-cm4.dtb` and applies `.dtbo` overlays from `/boot/overlays/` as configured in `/boot/config.txt`:

* **`ulticontroller.dts` (`ulticontroller.dtbo` — Factor 4 / Factor 4+: `227380`, `105*`)**:
  * Configures MIPI DSI1 (`&dsi1`) to TI SN65DSI84 LVDS bridge (`0x2d` on `&i2c1`) and USB2514B hub (`0x2c` on `&i2c1`)
  * Configures 1024x600 `panel-lvds` (`vesa-24`, 51.2064 MHz pixel clock)
  * Configures `&i2c0` Ulticontroller peripherals: `pca9536@41` (`disp_rst_hog`), `pca9632@60` (backlight), `ft5426@38` (touchscreen), `24c32@50` (EDID)
  * Configures `&i2c3` Ultimainboard 5 peripherals: `tca6416@20` (`lvds_pwr_en_hog`, `vcc24_mot_en_hog`, `vcc24_ph_en_hog`, `hdmi_pwr_en_hog`), `carrierdata@57`, `pca9633@62` (cabin lights)
* **`ulticontroller-800x320.dts` (`ulticontroller-800x320.dtbo` — S6 / S8: `106*`, `107*`)**:
  * Configures 800x320 `panel-lvds` (`vesa-24`, 25.82 MHz pixel clock) and `pca9570@24` GPIO expander on `&i2c0`
* **`ulticontroller-ngp.dts` (`ulticontroller-ngp.dtbo` — NGP: `109*`)**:
  * Configures 1024x600 `panel-lvds` with `LVDS_PWR_EN` regulator / `DISP_RST` enable-gpios sequencing, `gt928@5d` (Goodix) and `ft5426@38` touchscreen nodes, and dual `usb2514b@2c` hubs on `&i2c1` and `&i2c3`
* **`ultimainboard5-cm4.dts` (`ultimainboard5-cm4.dtb`)**:
  * Full standalone CM4 board Device Tree including `broadcom/bcm2711-rpi-cm4.dts`

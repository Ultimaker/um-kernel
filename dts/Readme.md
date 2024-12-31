### Device Tree Selection

We have 2 device trees, one for each display currently supported by **Ultimainboard 5**:

- *Ulticontroller 4* at 1024x600 (Factor 4, Falcon): `ulticontroller4.0-lvds-1024x600.dts`
- *Ultricontroller 3.2 LVDS* at 800x600 (S6 and S8): `ulticontroller3.2-lvds-800x320.dts`

Both device trees sources includes the Ultimainboard 5 device tree: `ultimainboard5-lvds.dtsi`.
And this one includes the remaining IMX8 definitions (`congatec/imx8mm-cgtsx8m-lvds.dtsi`).

The *UBoot* will look for a device tree file named **`cgtsx8m-ultimain5.dtb`** in the boot partition.
In order to boot the correct DT, the um-kernel post install script will get the **first** recipe
article number (from the file `/etc/ultimaker_firmware`) and will set a symlink named
`cgtsx8m-ultimain5.dtb` pointing to one of those 2 device trees that should be used by this article number.

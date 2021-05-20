# Check the boot partition file system first, so that we can determine if we should use fat or ext4 functions (e.g. fatload or ext4load)
setenv fs_check 'if fatls mmc ${mmcdev}:${mmcpart} /; then setenv fs_type fat; else setenv fs_type ext4; fi'

# Debug function to see if the previous command works
setenv listbootpart 'echo listing bootpart ...; ${fs_type}ls mmc ${mmcdev}:${mmcpart} /;'

# Reprogram or set the filesystem specific functions to use the fs_type prefix
setenv loadbootscript 'echo listing bootpart ...; ${fs_type}load mmc ${mmcdev}:${mmcpart} ${loadaddr} ${script};'
setenv loadfdt 'echo Loading fdt ...; ${fs_type}load mmc ${mmcdev}:${mmcpart} ${fdt_addr} ${fdt_file}'
setenv loadimage 'echo Loading kernel image ...; ${fs_type}load mmc ${mmcdev}:${mmcpart} ${loadaddr} ${image}'

# Set our own mmc boot defines to support booting from internal or external flash
setenv boot_devs 'mmc0 mmc1'
setenv mmc0root '/dev/mmcblk1p2 rootwait rw'
setenv mmc1root '/dev/mmcblk2p2 rootwait rw'
setenv mmc0_boot 'setenv mmcdev 0; setenv mmcroot ${mmc0root}; run fs_check; run mmc_boot'
setenv mmc1_boot 'setenv mmcdev 1; setenv mmcroot ${mmc1root}; run fs_check; run mmc_boot'
setenv mmcargs 'echo Setting mmc args ... ; setenv bootargs ${jh_clk} console=${console} root=${mmcroot} cma=${cma_settings}'

# Set the proper boot files
setenv fdt_file imx8mm-cgtsx8m-ultimain5.0-lvds-1024x600.dtb
setenv image uImage-sx8m

# Set the Linux console to use the J8 console connector on the mainboard, keep in mind that a virgin SOM uses the connector on the SOM itself, therefore you will not see the U-Boot console output
setenv console 'ttymxc3,115200 earlycon=ec_imx6q,0x30A60000,115200'

# Setup the bootcmd to dynamically setup the boot procedure 
setenv mmcboot 'echo Booting from mmc ...; run mmcargs; run loadfdt; booti ${loadaddr} - ${fdt_addr};'
setenv mmc_boot 'mmc dev ${mmcdev}; mmc rescan; run loadimage; run mmcboot;'
setenv bootcmd 'for btype in ${boot_devs}; do echo Attempting ${btype} boot...; if run ${btype}_boot; then; exit; fi; done; run netboot'

saveenv
reset

# Important note: the virgin SOM has the loadbootscript command set to use fatload.
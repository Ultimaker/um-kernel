#!/bin/bash

# This script builds the kernel, kernel modules, device trees and boot scripts for the A20 linux system that we use.

# Check for a valid cross compiler. When unset, the kernel tries to build itself
# using arm-none-eabi-gcc, so we need to ensure it exists. Because printenv and
# which can cause bash -e to exit, so run this before setting this up.
if [ "${CROSS_COMPILE}" == "" ]; then
    if [ "$(which arm-none-eabi-gcc)" != "" ]; then
        CROSS_COMPILE=arm-none-eabi-
    fi
    if [ "$(which arm-linux-gnueeabihf-gcc)" != "" ]; then
        CROSS_COMPILE=arm-linux-gnueeabihf-
    fi
    if [ "${CROSS_COMPILE}" == "" ]; then
        echo "No suiteable cross-compiler found."
        echo "One can be set explicitly via the environment variable CROSS_COMPILE='arm-linux-gnueabihf-' for example."
        exit 1
    fi
fi
export CROSS_COMPILE=${CROSS_COMPILE}

set -e
set -u

# Initialize repositories
git submodule init
git submodule update

if [ -z ${RELEASE_VERSION+x} ]; then
	RELEASE_VERSION=9999.99.99
fi

# Which kernel to build
KERNEL=`pwd`/linux

# Which kernel config to build.
BUILDCONFIG="opinicus"

# Build the kernel
KCONFIG=`pwd`/configs/${BUILDCONFIG}_config
KERNEL_BUILD=`pwd`/_build_armhf/${BUILDCONFIG}-linux
mkdir -p ${KERNEL_BUILD}
pushd ${KERNEL}
# Configure the kernel
ARCH=arm make O=${KERNEL_BUILD} KCONFIG_CONFIG=${KCONFIG}
# Build the uImage file for a bootable kernel
ARCH=arm LOADADDR=0x40008000 make O=${KERNEL_BUILD} KCONFIG_CONFIG=${KCONFIG} uImage
# Build modules
ARCH=arm make O=${KERNEL_BUILD} KCONFIG_CONFIG=${KCONFIG} modules
popd

# Build the debian package
DEB_DIR=`pwd`/debian
# Remove old modules
rm -r ${DEB_DIR}/lib 2> /dev/null || true
mkdir -p "${DEB_DIR}/boot"
cp ${KERNEL_BUILD}/arch/arm/boot/uImage "${DEB_DIR}/boot/uImage-sun7i-a20-opinicus_v1"
pushd ${KERNEL}
ARCH=arm make O=${KERNEL_BUILD} KCONFIG_CONFIG=${KCONFIG} INSTALL_MOD_PATH="${DEB_DIR}" modules_install
popd

# Build the device trees that we need
mkdir -p ${KERNEL_BUILD}/dtb
for dts in $(find dts/ -name '*.dts' -exec basename {} \;); do
	dt=${dts%.dts}
	echo "Building devicetree blob ${dt}"
	cpp -nostdinc -undef -D__DTS__ -x assembler-with-cpp \
		-I${KERNEL}/include -I${KERNEL}/arch/arm/boot/dts \
		-o ${KERNEL_BUILD}/dtb/.${dt}.dtb.tmp dts/${dts}
	dtc -I dts -o "${DEB_DIR}/boot/${dt}.dtb" -O dtb ${KERNEL_BUILD}/dtb/.${dt}.dtb.tmp
done

# Generate the boot splash script
gcc -Wall -Werror -std=c99 scripts/ultimaker_boot_splash_generator.c -o scripts/ultimaker_boot_splash_generator
BOOTSPLASH_COMMANDS=$(scripts/ultimaker_boot_splash_generator)

# Create the bootscripts for these kernels
cat > "${DEB_DIR}/boot/boot_mmc.cmd" <<-EOT
setenv bootargs console=tty0 root=/dev/mmcblk0p2 ro rootwait rootfstype=ext4 console=ttyS0,115200 earlyprintk
setenv fdt_high 0xffffffff
${BOOTSPLASH_COMMANDS}
ext4load mmc 0 0x46000000 uImage-sun7i-a20-opinicus_v1
ext4load mmc 0 0x49000000 sun7i-a20-opinicus_emmc_v1.dtb
bootm 0x46000000 - 0x49000000
EOT
mkimage -A arm -O linux -T script -C none -a 0x43100000 -n "Boot script" -d "${DEB_DIR}/boot/boot_mmc.cmd" "${DEB_DIR}/boot/boot_mmc.scr"

cat > "${DEB_DIR}/boot/boot_installer.cmd" <<-EOT
setenv bootargs console=tty0 root=/dev/mmcblk0p2 ro rootwait rootfstype=ext4 console=ttyS0,115200 earlyprintk
setenv fdt_high 0xffffffff
${BOOTSPLASH_COMMANDS}
ext4load mmc 0 0x46000000 uImage-sun7i-a20-opinicus_v1
ext4load mmc 0 0x49000000 sun7i-a20-opinicus_emmc_v1.dtb
bootm 0x46000000 - 0x49000000
EOT
mkimage -A arm -O linux -T script -C none -a 0x43100000 -n "Boot script" -d "${DEB_DIR}/boot/boot_installer.cmd" "${DEB_DIR}/boot/boot_installer.scr"

cat > "${DEB_DIR}/boot/boot_emmc.cmd" <<-EOT
setenv bootargs console=tty0 root=/dev/mmcblk0p2 ro rootwait rootfstype=f2fs console=ttyS0,115200 earlyprintk
setenv fdt_high 0xffffffff
${BOOTSPLASH_COMMANDS}
ext4load mmc 0 0x46000000 uImage-sun7i-a20-opinicus_v1
ext4load mmc 0 0x49000000 sun7i-a20-opinicus_emmc_v1.dtb
bootm 0x46000000 - 0x49000000
EOT
mkimage -A arm -O linux -T script -C none -a 0x43100000 -n "Boot script" -d "${DEB_DIR}/boot/boot_emmc.cmd" "${DEB_DIR}/boot/boot_emmc.scr"

# Create a debian control file to pack up a debian package
mkdir -p "${DEB_DIR}/DEBIAN"
cat > "${DEB_DIR}/DEBIAN/control" <<-EOT
Package: um-kernel
Conflicts: linux-sunxi
Replaces: linux-sunxi
Version: ${RELEASE_VERSION}
Architecture: armhf
Maintainer: Anonymous <root@monolith.ultimaker.com>
Section: kernel
Priority: optional
Homepage: http://www.kernel.org/
Description: Linux kernel, kernel modules, binary device trees and boot scripts. All in a single package.
EOT

fakeroot dpkg-deb --build "${DEB_DIR}" um-kernel-${RELEASE_VERSION}.deb

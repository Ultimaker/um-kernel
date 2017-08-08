#!/bin/bash

# This script builds the kernel, kernel modules, device trees and boot scripts for the A20 linux system that we use.

# Check for a valid cross compiler. When unset, the kernel tries to build itself
# using arm-none-eabi-gcc, so we need to ensure it exists. Because printenv and
# which can cause bash -e to exit, so run this before setting this up.
if [ "${CROSS_COMPILE}" == "" ]; then
    if [ "$(which arm-none-eabi-gcc)" != "" ]; then
        CROSS_COMPILE="arm-none-eabi-"
    fi
    if [ "$(which arm-linux-gnueabihf-gcc)" != "" ]; then
        CROSS_COMPILE="arm-linux-gnueabihf-"
    fi
    if [ "${CROSS_COMPILE}" == "" ]; then
        echo "No suiteable cross-compiler found."
        echo "One can be set explicitly via the environment variable CROSS_COMPILE='arm-linux-gnueabihf-' for example."
        exit 1
    fi
fi
export CROSS_COMPILE=${CROSS_COMPILE}

if [ "${MAKEFLAGS}" == "" ]; then
    echo -e -n "\e[1m"
    echo "Makeflags not set, hint, to speed up compilation time, increase the number of jobs. For example:"
    echo "MAKEFLAGS='-j 4' ${0}"
    echo -e "\e[0m"
fi

set -e
set -u

# Which kernel to build
KERNEL=`pwd`/linux

# Which kernel config to build.
BUILDCONFIG="opinicus"

# Location of the debian package contents
DEB_DIR=`pwd`/debian

# Setup internal variables
KCONFIG=`pwd`/configs/${BUILDCONFIG}_config
KERNEL_BUILD=`pwd`/_build_armhf/${BUILDCONFIG}-linux

# Set the release version if it's not passed to the script
RELEASE_VERSION=${RELEASE_VERSION:-9999.99.99}

# Initialize repositories
git submodule init
git submodule update

kernel_build_command() {
    mkdir -p ${KERNEL_BUILD}
    pushd ${KERNEL}
    ARCH=arm CROSS_COMPILE="${CROSS_COMPILE}" make O=${KERNEL_BUILD} KCONFIG_CONFIG=${KCONFIG} $*
    popd
}

kernel_build() {
    # Configure the kernel
    kernel_build_command
    # Build the uImage file for a bootable kernel
    kernel_build_command LOADADDR=0x40008000 uImage
    # Build modules
    kernel_build_command modules
}

dtb_build() {
    if [[ -z $DEB_DIR ]]; then echo "You are an idiot"; exit 1; fi

    rm -rf ${KERNEL_BUILD}/dtb
    mkdir -p ${KERNEL_BUILD}/dtb
    rm -rf ${DEB_DIR}/boot/*.dtb
    mkdir -p ${DEB_DIR}/boot
    # Build the device trees that we need
    for dts in $(find dts/ -name '*.dts' -exec basename {} \;); do
        dt=${dts%.dts}
        echo "Building devicetree blob ${dt}"
        cpp -nostdinc -undef -D__DTS__ -x assembler-with-cpp \
            -I${KERNEL}/include -I${KERNEL}/arch/arm/boot/dts \
            -o ${KERNEL_BUILD}/dtb/.${dt}.dtb.tmp dts/${dts}
        dtc -I dts -o "${DEB_DIR}/boot/${dt}.dtb" -O dtb ${KERNEL_BUILD}/dtb/.${dt}.dtb.tmp
    done

    while IFS='' read -r LINE || [[ -n "$LINE" ]]; do
        if [[ $LINE != "#"* && $LINE != "" ]]; then
            ARTICLE_FULL=$(cut -d':' -f1 <<< "${LINE}")
            DTS=$(cut -d':' -f2 <<<"${LINE}")

            ARTICLE_NUMBER=$(cut -d'-' -f1 <<< "${ARTICLE_FULL}")
            ARTICLE_REV=$(cut -d'-' -s -f2 <<< "${ARTICLE_FULL}")

            ARTICLE_NUMBER_HEX=$(printf "%x\n" ${ARTICLE_NUMBER})
            ARTICLE_REV_HEX=$(printf "%x\n" ${ARTICLE_REV})

            if [[ -z "${ARTICLE_REV}" ]]; then
                NAME=${ARTICLE_NUMBER_HEX}.dtb
            else
                NAME=${ARTICLE_NUMBER_HEX}-${ARTICLE_REV_HEX}.dtb
            fi
            ln -s ${DTS}.dtb ${DEB_DIR}/boot/${NAME}
            echo "Created link for article ${ARTICLE_NUMBER} ${ARTICLE_REV}"
        fi
    done < "dts/article.links"
}

bootscript_build() {
    if [[ -z $DEB_DIR ]]; then echo "You are an idiot"; exit 1; fi

    mkdir -p ${DEB_DIR}/boot

    # Generate the boot splash script
    gcc -Wall -Werror -std=c99 scripts/ultimaker_boot_splash_generator.c -o scripts/ultimaker_boot_splash_generator
    BOOTSPLASH_COMMANDS=$(scripts/ultimaker_boot_splash_generator)

    # Create the bootscripts for these kernels
    ROOT_DEV=mmcblk0p2 ROOT_FS=ext4 BOOTSPLASH_COMMANDS="${BOOTSPLASH_COMMANDS}" envsubst '${ROOT_DEV} ${ROOT_FS} ${BOOTSPLASH_COMMANDS}' < scripts/bootscript.cmd > "${DEB_DIR}/boot/boot_mmc.cmd"
    ROOT_DEV=mmcblk0p2 ROOT_FS=ext4 BOOTSPLASH_COMMANDS="${BOOTSPLASH_COMMANDS}" envsubst '${ROOT_DEV} ${ROOT_FS} ${BOOTSPLASH_COMMANDS}' < scripts/bootscript.cmd > "${DEB_DIR}/boot/boot_installer.cmd"
    ROOT_DEV=mmcblk1p2 ROOT_FS=f2fs BOOTSPLASH_COMMANDS="${BOOTSPLASH_COMMANDS}" envsubst '${ROOT_DEV} ${ROOT_FS} ${BOOTSPLASH_COMMANDS}' < scripts/bootscript.cmd > "${DEB_DIR}/boot/boot_emmc.cmd"

    # Convert the bootscripts into proper u-boot script images
    for CMD_FILE in $(find ${DEB_DIR}/boot/ -name '*.cmd' -exec basename {} \;); do
        SCR_FILE="${CMD_FILE%.*}.scr"
        mkimage -A arm -O linux -T script -C none -a 0x43100000 -n "Boot script" -d "${DEB_DIR}/boot/${CMD_FILE}" "${DEB_DIR}/boot/${SCR_FILE}"
    done
}

deb_build() {
    if [[ -z $DEB_DIR ]]; then echo "You are an idiot"; exit 1; fi

    # Remove old modules
    rm -r ${DEB_DIR}/lib 2> /dev/null || true
    mkdir -p "${DEB_DIR}/boot"
    # Install kernel image and modules
    cp ${KERNEL_BUILD}/arch/arm/boot/uImage "${DEB_DIR}/boot/uImage-sun7i-a20-opinicus_v1"
    kernel_build_command INSTALL_MOD_PATH="${DEB_DIR}" modules_install

    # Create a debian control file to pack up a debian package
    mkdir -p "${DEB_DIR}/DEBIAN"
    RELEASE_VERSION="${RELEASE_VERSION}" envsubst '${RELEASE_VERSION}' < scripts/debian_control > "${DEB_DIR}/DEBIAN/control"

    # Build the debian package
    fakeroot dpkg-deb --build "${DEB_DIR}" um-kernel-${RELEASE_VERSION}.deb
}

case ${1-} in
um-kernel)
    kernel_build
    ;;
um-dtbs)
    dtb_build
    ;;
um-bootscript)
    bootscript_build
    ;;
um-deb)
    deb_build
    ;;
"")
    kernel_build
    dtb_build
    script_build
    deb_build
    ;;
um-*)
    echo "Unknown argument to build script."
    echo "Use:"
    echo "\t$1 um-kernel"
    echo "\t$1 um-dtbs"
    echo "\t$1 um-bootscript"
    echo "\t$1 um-deb"
    echo "\t$1 menuconfig"
    echo "\t$1"
    ;;
*)
    kernel_build_command ${*}
    ;;
esac

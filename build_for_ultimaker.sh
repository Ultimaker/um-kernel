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
BUILDCONFIG=${BUILDCONFIG:-opinicus}

# Location of the debian package contents
DEB_DIR=`pwd`/debian

# Setup internal variables
KCONFIG=`pwd`/configs/${BUILDCONFIG}_config
KERNEL_BUILD=`pwd`/_build_armhf/${BUILDCONFIG}-linux

INITRAMFS_MODULES=""
INITRAMFS_COMPRESSION="${INITRAMFS_COMPRESSION:-.lzo}"
INITRAMFS_ROOT_GID=${INITRAMFS_ROOT_GID:-0}
INITRAMFS_ROOT_UID=${INITRAMFS_ROOT_UID:-0}
INITRAMFS_SOURCE="${INITRAMFS_SOURCE:-initramfs/initramfs.lst}"
INITRAMFS_IMG="${KERNEL_BUILD}/initramfs.cpio${INITRAMFS_COMPRESSION}"

GEN_INIT_CPIO="${KERNEL_BUILD}/usr/gen_init_cpio"
GEN_INITRAMFS_LIST="${KERNEL}/scripts/gen_initramfs_list.sh"

BB_PKG="http://ftp.nl.debian.org/debian/pool/main/b/busybox/busybox-static_1.22.0-19+b3_armhf.deb"
BB_BIN="busybox"

DEPMOD="${DEPMOD:-/sbin/depmod}"
if [ ! -x "${DEPMOD}" ]; then
    DEPMOD="busybox depmod"
    if [ ! -x "${DEPMOD}" ]; then
        echo "No depmod binary available. Cannot continue."
        exit 1
    fi
fi

# Set the release version if it's not passed to the script
RELEASE_VERSION=${RELEASE_VERSION:-9999.99.99}

# Initialize repositories
git submodule init
git submodule update

##
# busybox_get() - Obtain a statically linked busybox binary
# param1:	Writable path where to store the retrieved binary
#
# Busybox is downloaded from the global variable ${BB_PKG}.
#
busybox_get()
{
    local BB_DIR=$(mktemp -d)
    local BB_AR="${BB_DIR}/busybox-static_armhf.deb"
    local DEST_DIR="${1}"
    local cwd=$(pwd)

    if [ ! -d "${DEST_DIR}" ]; then
        echo "No initramfs dir set to download busybox into."
        exit 1
    fi

    if [ -z "${BB_DIR}" ]; then
        echo "Unable to create temporary directory to get busybox."
        exit 1
    fi

    wget -q "${BB_PKG}" -O "${BB_AR}"
    cd "${BB_DIR}" # ar always extracts to the cwd
    ar -x "${BB_AR}" "data.tar.xz"
    cd "${cwd}"
    tar -xf "${BB_DIR}/data.tar.xz" --strip=2 -C "${DEST_DIR}" "./bin/${BB_BIN}"
    rm -r "${BB_DIR}"
    if [ ! -x "${DEST_DIR}/${BB_BIN}" ]; then
        echo "Failed to get busybox."
        exit 1
    fi
}

##
# initramfs_prepare() - Prepare the initramfs tree
#
# To be able to create a initramfs in the temporary build directory, where
# the kernel expects these files due to INITRAMFS_SOURCE being set, we need
# to copy the source initramfs files and put some expected binaries in place.
#
initramfs_prepare()
{
    local INITRAMFS_SRC_DIR="$(pwd)/initramfs"
    local INITRAMFS_DST_DIR="${KERNEL_BUILD}/initramfs"
    local INITRAMFS_MODULES_DIR="${KERNEL_BUILD}/initramfs/lib/modules"
    local INITRAMFS_DEST="${INITRAMFS_DST_DIR}/$(basename ${INITRAMFS_SOURCE})"
    local KERNELRELEASE=""

    kernel_build_modules
    KERNELRELEASE=$(cat "${KERNEL_BUILD}/include/config/kernel.release")
    if [ -z "${KERNELRELEASE}" ]; then
        echo "Unable to get kernel release version."
        exit 1
    fi

    if [ -d "${INITRAMFS_DST_DIR}" ]; then
        rm -rf "${INITRAMFS_DST_DIR}"
    fi
    cp -a "${INITRAMFS_SRC_DIR}/" "${INITRAMFS_DST_DIR}"

    if [ ! -x "${INITRAMFS_DST_DIR}/${BB_BIN}" ]; then
        busybox_get "${INITRAMFS_DST_DIR}"
    fi

    if [ -d "${INITRAMFS_MODULES_DIR}" ]; then
        rm -rf "${INITRAMFS_MODULES_DIR}"
    fi
    if [ -n "${INITRAMFS_MODULES}" ]; then
        mkdir -p "${INITRAMFS_MODULES_DIR}/${KERNELRELEASE}"
        echo -e "\n# kernel modules" >> "${INITRAMFS_DEST}"
        echo "dir /lib/modules/ 0755 0 0" >> "${INITRAMFS_DEST}"
        echo "dir /lib/modules/${KERNELRELEASE}/ 0755 0 0" >> "${INITRAMFS_DEST}"
    fi

    for module in ${INITRAMFS_MODULES}; do
        if [ -z "$(find "${KERNEL_BUILD}/drivers/" -name "${module}" -print -exec cp "{}" "${INITRAMFS_MODULES_DIR}/${KERNELRELEASE}" \;)" ]; then
            echo "Kernel ${module} not available."
            exit 1
        fi
        echo "file /lib/modules/${KERNELRELEASE}/${module} ${INITRAMFS_MODULES_DIR}/${KERNELRELEASE}/${module} 0755 0 0" >> "${INITRAMFS_DEST}"
    done

    if [ -n "${INITRAMFS_MODULES}" ] && ! ${DEPMOD} -b "${INITRAMFS_DST_DIR}" ${KERNELRELEASE}; then
        echo "Failed to generate module dependencies."
        exit 1
    fi
    for moddep in ${INITRAMFS_MODULES_DIR}/${KERNELRELEASE}/modules.*; do
        if [ -f "${moddep}" ]; then
            moddep=$(basename ${moddep})
            echo "file /lib/modules/${KERNELRELEASE}/${moddep} ${INITRAMFS_MODULES_DIR}/${KERNELRELEASE}/${moddep} 0755 0 0" >> "${INITRAMFS_DEST}"
        fi
    done
}

##
# initramfs_build() - Build an initramfs cpio archive
#
# Create a initramfs archive file to be loaded separately. This is useful
# when not using a built-in initramfs.
#
initramfs_build()
{
    local cwd=""

    initramfs_prepare

    if [ ! -x "${GEN_INIT_CPIO}" ]; then
        kernel_build
    fi
    if [ ! -x "${GEN_INIT_CPIO}" ]; then
        echo "Kernel failed to create gen_init_cpio."
        exit 1
    fi

    cwd=$(pwd)
    cd "${KERNEL_BUILD}"
    ${GEN_INITRAMFS_LIST} \
        -o "${INITRAMFS_IMG}" \
        -u "${INITRAMFS_ROOT_UID}" \
        -g "${INITRAMFS_ROOT_GID}" \
        "${INITRAMFS_SOURCE}"
    cd "${cwd}"
}

kernel_build_command() {
    mkdir -p ${KERNEL_BUILD}
    pushd ${KERNEL}
    ARCH=arm CROSS_COMPILE="${CROSS_COMPILE}" make O=${KERNEL_BUILD} KCONFIG_CONFIG=${KCONFIG} $*
    popd
}

kernel_build() {
    initramfs_prepare
    # Configure the kernel
    kernel_build_command
    # Build the uImage file for a bootable kernel
    kernel_build_command LOADADDR=0x40008000 uImage
}

##
# kernel_build_modules() - Build the kernel modules
#
# Compiles only the kernel modules, not the kernel itself, as they may be
# needed to be put in the initramfs image.
#
kernel_build_modules()
{
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
um-kernel_modules)
    kernel_build_modules
    ;;
um-kernel)
    kernel_build
    ;;
um-initramfs)
    initramfs_build
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
    kernel_build_modules
    kernel_build
    dtb_build
    bootscript_build
    initramfs_build
    deb_build
    ;;
um-*)
    echo "Unknown argument to build script."
    echo "Use:"
    echo -e "\t$0 um-kernel_modules"
    echo -e "\t$0 um-kernel"
    echo -e "\t$0 um-initramfs"
    echo -e "\t$0 um-dtbs"
    echo -e "\t$0 um-bootscript"
    echo -e "\t$0 um-deb"
    echo -e "\t$0 menuconfig"
    echo -e "\t$0"
    ;;
*)
    kernel_build_command ${*}
    ;;
esac

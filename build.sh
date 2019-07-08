#!/bin/bash
# shellcheck disable=SC1117

# This script builds the kernel, kernel modules, device trees and boot scripts for the A20 linux system that we use.

# Check for a valid cross compiler. When unset, the kernel tries to build itself
# using arm-none-eabi-gcc, so we need to ensure it exists. Because printenv and
# which can cause bash -e to exit, so run this before setting this up.
if [ "${CROSS_COMPILE}" == "" ]; then
    if [ "$(command -v arm-none-eabi-gcc)" != "" ]; then
        CROSS_COMPILE="arm-none-eabi-"
    fi
    if [ "$(command -v arm-linux-gnueabihf-gcc)" != "" ]; then
        CROSS_COMPILE="arm-linux-gnueabihf-"
    fi
    if [ "${CROSS_COMPILE}" == "" ]; then
        echo "No suiteable cross-compiler found."
        echo "One can be set explicitly via the environment variable CROSS_COMPILE='arm-linux-gnueabihf-' for example."
        exit 1
    fi
fi
export CROSS_COMPILE="${CROSS_COMPILE}"

if [ "${MAKEFLAGS}" == "" ]; then
    echo -e -n "\e[1m"
    echo "Makeflags not set, hint, to speed up compilation time, increase the number of jobs. For example:"
    echo "MAKEFLAGS='-j 4' ${0}"
    echo -e "\e[0m"
fi

set -eu

CWD="$(pwd)"

# Which kernel to build
LINUX_SRC_DIR=${CWD}/linux

# Which kernel config to build.
BUILDCONFIG="opinicus"

# Setup internal variables
KCONFIG="${CWD}/configs/${BUILDCONFIG}_config"
KERNEL_BUILD_DIR="${CWD}/_build_armhf/${BUILDCONFIG}-linux"
BUILD_OUTPUT_DIR="${CWD}/_build_armhf/"
DEBIAN_DIR="${BUILD_OUTPUT_DIR}/debian"
BOOT_FILE_OUTPUT_DIR="${DEBIAN_DIR}/boot"

INITRAMFS_MODULES_REQUIRED="sunxi_wdt.ko ssd1307fb.ko drm.ko sun4i-backend.ko sun4i-drm.ko sun4i-tcon.ko sun4i-drm-hdmi.ko sun4i-hdmi-i2c.ko"
INITRAMFS_SOURCE="${INITRAMFS_SOURCE:-initramfs/initramfs.lst}"

BB_PKG="http://dl-cdn.alpinelinux.org/alpine/latest-stable/main/armhf/busybox-static-1.30.1-r2.apk"
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
RELEASE_VERSION="${RELEASE_VERSION:-9999.99.99}"

##
# busybox_get() - Obtain a statically linked busybox binary
# param1:	Writable path where to store the retrieved binary
#
# Busybox is downloaded from the global variable ${BB_PKG}.
busybox_get()
{
    BB_DIR="$(mktemp -d)"
    BB_APK="${BB_DIR}/busybox-static_armhf.apk"
    DEST_DIR="${1}"

    if [ ! -d "${DEST_DIR}" ]; then
        echo "No initramfs dir set to download busybox into."
        exit 1
    fi

    if [ ! -d "${BB_DIR}" ]; then
        echo "Unable to create temporary directory to get busybox."
        exit 1
    fi

    if ! wget -q "${BB_PKG}" -O "${BB_APK}"; then
        echo "Unable to download the busybox package '${BB_PKG}'. Update the download URL."
        exit 1
    fi

    tar -xf "${BB_APK}" --strip=1 -C "${BB_DIR}" "bin/busybox.static"
    mv "${BB_DIR}/busybox.static" "${DEST_DIR}/${BB_BIN}"
    rm -r "${BB_DIR}"

    if [ ! -x "${DEST_DIR}/${BB_BIN}" ]; then
        echo "Failed to get busybox."
        exit 1
    fi
}

##
# initramfs_add_modules()
#
# In initramfs we can make drivers available by adding them to
# the 'INITRAMFS_MODULES_REQUIRED' variable. This function
# will check for dependencies in the installed modules 'modules.dep' file
# and add the requested modules and its dependencies to initramfs.
initramfs_add_modules()
{
    echo "Adding initramfs modules."

    KERNEL_RELEASE=$(cat "${KERNEL_BUILD_DIR}/include/config/kernel.release")

    if [ ! -d "${DEBIAN_DIR}/lib" ] || [ -z "${KERNEL_RELEASE}" ] || \
        [ ! -f "${DEBIAN_DIR}/lib/modules/${KERNEL_RELEASE}/modules.dep" ]; then
        echo "Error, no modules installed, cannot continue."
        exit 1
    fi

    if [ -d "${INITRAMFS_MODULES_DIR}" ] && [ -z "${INITRAMFS_MODULES_DIR##*/initramfs/lib/modules*}" ]; then
        rm -rf "${INITRAMFS_MODULES_DIR}"
    fi

    if [ -n "${INITRAMFS_MODULES_REQUIRED}" ]; then
        mkdir -p "${INITRAMFS_MODULES_DIR}/${KERNEL_RELEASE}"
        {
            echo -e "\n# kernel modules"
            echo "dir /lib/modules/ 0755 0 0"
            echo "dir /lib/modules/${KERNEL_RELEASE}/ 0755 0 0"
        } >> "${INITRAMFS_DEST}"

        MODULES_DIR="${DEBIAN_DIR}/lib/modules/${KERNEL_RELEASE}"
        INITRAMFS_MODULES="${INITRAMFS_MODULES_REQUIRED}"

        for module in ${INITRAMFS_MODULES_REQUIRED}; do
            dependencies="$(grep "${module}:" "${MODULES_DIR}/modules.dep" | sed -e "s|^.*:\s*||")"
            for dependency in ${dependencies}; do
                dep_module="$(basename "${dependency}")"
                echo "Adding dependency: '${dep_module}' for module: '${module}'"
                if [ -n "${INITRAMFS_MODULES##*${dep_module}*}" ]; then
                    INITRAMFS_MODULES="${INITRAMFS_MODULES} ${dep_module}"
                fi
            done
        done
    fi

    for module in ${INITRAMFS_MODULES}; do
        if [ -z "$(find "${MODULES_DIR}" -name "${module}" -print -exec cp "{}" "${INITRAMFS_MODULES_DIR}/${KERNEL_RELEASE}" \;)" ]; then
            echo "Error: kernel module: '${module}' not available."
            exit 1
        fi

        echo "Adding kernel module: '${module}' to initrd."
        echo "file /lib/modules/${KERNEL_RELEASE}/${module} ${INITRAMFS_MODULES_DIR}/${KERNEL_RELEASE}/${module} 0755 0 0" >> "${INITRAMFS_DEST}"
    done

    if [ -n "${INITRAMFS_MODULES}" ] && ! ${DEPMOD} -ab "${INITRAMFS_DST_DIR}" "${KERNEL_RELEASE}"; then
        echo "Failed to generate module dependencies."
        exit 1
    fi

    for moddep in "${INITRAMFS_MODULES_DIR}/${KERNEL_RELEASE}/modules."*; do
        if [ -f "${moddep}" ]; then
            moddep="$(basename "${moddep}")"
            echo "file /lib/modules/${KERNEL_RELEASE}/${moddep} ${INITRAMFS_MODULES_DIR}/${KERNEL_RELEASE}/${moddep} 0755 0 0" >> "${INITRAMFS_DEST}"
        fi
    done

    echo "Finished adding initramfs modules."
}

##
# initramfs_prepare() - Prepare the initramfs tree
#
# To be able to create an initramfs in the temporary build directory, where
# the kernel expects these files due to 'INITRAMFS_SOURCE' being set, we need
# to copy the source initramfs files and put some expected binaries in place.
initramfs_prepare()
{
    echo "Preparing initramfs."

    INITRAMFS_SRC_DIR="${CWD}/initramfs"
    INITRAMFS_DST_DIR="${KERNEL_BUILD_DIR}/initramfs"
    INITRAMFS_MODULES_DIR="${KERNEL_BUILD_DIR}/initramfs/lib/modules"
    INITRAMFS_DEST="${INITRAMFS_DST_DIR}/$(basename "${INITRAMFS_SOURCE}")"

    if [ -d "${INITRAMFS_DST_DIR}" ]; then
        rm -rf "${INITRAMFS_DST_DIR}"
    fi

    mkdir -p "${INITRAMFS_DST_DIR}"

    cp -a "${INITRAMFS_SRC_DIR}/"* "${INITRAMFS_DST_DIR}"

    if [ ! -x "${INITRAMFS_DST_DIR}/${BB_BIN}" ]; then
        busybox_get "${INITRAMFS_DST_DIR}"
    fi

    echo "Finished preparing initramfs."
}

##
# kernel_build_command() - Wrapper function for Kernel build commands
#
# Wrap the argument into a Linux Kernel cross-compile command.
kernel_build_command()
{
    if [ ! -d "${KERNEL_BUILD_DIR}" ]; then
        mkdir -p "${KERNEL_BUILD_DIR}"
    fi

    cd "${LINUX_SRC_DIR}"
    ARCH=arm CROSS_COMPILE="${CROSS_COMPILE}" make O="${KERNEL_BUILD_DIR}" KCONFIG_CONFIG="${KCONFIG}" "${@}"
    cd "${CWD}"
}

##
# kernel_build() - Build the Linux Kernel image
#
# Builds the Kernel
# Installs the modules in the build output lib directory
# Creates the 'initramfs'
# Creates a uImage binary in the build output boot directory.
kernel_build()
{
    echo "Building Kernel."

    # Prepare the initramfs 1st time
    initramfs_prepare
    # Configure the kernel
    kernel_build_command
    # Build the Kernel modules and generate dependency list
    kernel_modules_install
    # New that all modules have been build and the dependency file is properly generated,
    # we can add the required Kernel modules to initramfs
    initramfs_add_modules
    # Build the uImage file for a bootable kernel
    kernel_build_command LOADADDR=0x40008000 uImage

    # Install Kernel image

    if [ -d "${BOOT_FILE_OUTPUT_DIR}" ] && [ -z "${BOOT_FILE_OUTPUT_DIR##*_build_armhf*}" ]; then
        rm -r "${BOOT_FILE_OUTPUT_DIR}"
    fi
    mkdir -p "${BOOT_FILE_OUTPUT_DIR}"

    cp "${KERNEL_BUILD_DIR}/arch/arm/boot/uImage" "${BOOT_FILE_OUTPUT_DIR}/uImage-sun7i-a20-opinicus_v1"
    echo "Finished building Kernel."
}

##
# kernel_modules_install() - Install the Kernel modules
#
# Generates a 'lib/modules/[Kernel version]' directory structure
# in the build output directory.
kernel_modules_install()
{
    echo "Install Kernel modules."

    KERNEL_RELEASE=$(cat "${KERNEL_BUILD_DIR}/include/config/kernel.release")

    if [ -z "${KERNEL_RELEASE}" ]; then
        echo "Error, unable to get kernel release version, cannot continue."
        exit 1
    fi

    if [ -d "${DEBIAN_DIR}/lib/modules" ] && [ -z "${BOOT_FILE_OUTPUT_DIR##*_build_armhf*}" ]; then
        rm -r "${DEBIAN_DIR}/lib/modules"
    fi

    kernel_build_command INSTALL_MOD_PATH="${DEBIAN_DIR}" modules_install

    if ! "${DEPMOD}" -ab "${DEBIAN_DIR}" "${KERNEL_RELEASE}"; then
        echo "Error, failed to generate module dependencies."
    fi

    echo "Finished installing Kernel modules."
}

##
# dtb_build() - Compile product specific device-tree binary files
dtb_build()
{
    echo "Building Device-trees."

    if [ -d "${KERNEL_BUILD_DIR}/dtb" ]; then
        rm -rf "${KERNEL_BUILD_DIR}/dtb"
    fi

    mkdir -p "${KERNEL_BUILD_DIR}/dtb"

    if [ ! -d "${BOOT_FILE_OUTPUT_DIR}" ]; then
        mkdir -p "${BOOT_FILE_OUTPUT_DIR}"
    fi

    rm -rf "${BOOT_FILE_OUTPUT_DIR}/"*".dtb"

    # Build the device trees that we need
    for dts in "dts/"*".dts"; do
        dts="$(basename "${dts}")"
        dt="${dts%.dts}"
        echo "Building devicetree blob '${dt}'"
        cpp -nostdinc -undef -D__DTS__ -x assembler-with-cpp \
            -I "${LINUX_SRC_DIR}/include" -I "${LINUX_SRC_DIR}/arch/arm/boot/dts" \
            -o "${KERNEL_BUILD_DIR}/dtb/.${dt}.dtb.tmp" "dts/${dts}"
        dtc -I dts -o "${BOOT_FILE_OUTPUT_DIR}/${dt}.dtb" -O dtb "${KERNEL_BUILD_DIR}/dtb/.${dt}.dtb.tmp"
    done


    echo "Finished building Device-trees."
}

bootscript_build()
{
    echo "Building boot scripts."
    if [ ! -d "${BOOT_FILE_OUTPUT_DIR}" ]; then
        mkdir -p "${BOOT_FILE_OUTPUT_DIR}"
    fi

    # Generate the boot splash script
    gcc -Wall -Werror -std=c99 "scripts/ultimaker_boot_splash_generator.c" -o "scripts/ultimaker_boot_splash_generator"
    BOOTSPLASH_COMMANDS="$(scripts/ultimaker_boot_splash_generator)"

    # Create the boot-scripts for these Kernels
    ROOT_DEV=mmcblk0p2 ROOT_FS=ext4 BOOTSPLASH_COMMANDS="${BOOTSPLASH_COMMANDS}" envsubst "\${ROOT_DEV},\${ROOT_FS},\${BOOTSPLASH_COMMANDS}" < scripts/bootscript.cmd > "${BOOT_FILE_OUTPUT_DIR}/boot_mmc.cmd"
    ROOT_DEV=mmcblk0p2 ROOT_FS=ext4 BOOTSPLASH_COMMANDS="${BOOTSPLASH_COMMANDS}" envsubst "\${ROOT_DEV},\${ROOT_FS},\${BOOTSPLASH_COMMANDS}" < scripts/bootscript.cmd > "${BOOT_FILE_OUTPUT_DIR}/boot_installer.cmd"
    ROOT_DEV=mmcblk1p2 ROOT_FS=f2fs BOOTSPLASH_COMMANDS="${BOOTSPLASH_COMMANDS}" envsubst "\${ROOT_DEV},\${ROOT_FS},\${BOOTSPLASH_COMMANDS}" < scripts/bootscript.cmd > "${BOOT_FILE_OUTPUT_DIR}/boot_emmc.cmd"

    # Convert the boot-scripts into proper U-Boot script images
    for CMD_FILE in "${BOOT_FILE_OUTPUT_DIR}/"*".cmd"; do
        SCR_FILE="$(basename "${CMD_FILE%.*}.scr")"
        mkimage -A arm -O linux -T script -C none -a 0x43100000 -n "Boot script" -d "${CMD_FILE}" "${BOOT_FILE_OUTPUT_DIR}/${SCR_FILE}"
    done
    echo "Finished building boot scripts."
}

deb_build()
{
    echo "Building Debian package."
    mkdir -p "${DEBIAN_DIR}/DEBIAN"

    if [ ! -d "${BOOT_FILE_OUTPUT_DIR}" ]; then
        echo "Error, boot directory not created, no boot files to package."
        exit 1
    fi

    if ! ls "${BOOT_FILE_OUTPUT_DIR}/uImage"* 1> /dev/null 2>&1; then
        echo "Error, no Kernel binary installed, run 'kernel' build first."
        exit 1
    fi

    if [ ! -d "${DEBIAN_DIR}/lib" ] || [ ! -f "${DEBIAN_DIR}/lib/modules/${KERNEL_RELEASE}/modules.dep" ]; then
        echo "Error, no modules installed, run 'kernel' build first."
        exit 1
    fi

    if ! ls "${BOOT_FILE_OUTPUT_DIR}/"*".scr" 1> /dev/null 2>&1; then
        echo "Error, no boot-script files installed, run 'bootscript' build first."
        exit 1
    fi

    if ! ls "${BOOT_FILE_OUTPUT_DIR}/"*".dtb" 1> /dev/null 2>&1; then
        echo "Error, no Kernel device-tree files installed, run 'dtbs' build first."
        exit 1
    fi

    # Create a Debian control file to pack up a Debian package
    RELEASE_VERSION="${RELEASE_VERSION}" envsubst "\${RELEASE_VERSION}" < scripts/debian_control > "${DEBIAN_DIR}/DEBIAN/control"

    # Build the Debian package
    fakeroot dpkg-deb --build "${DEBIAN_DIR}" "um-kernel-${RELEASE_VERSION}.deb"

    echo "Finished building Debian package."
}

usage()
{
    echo ""
    echo "This is the build script for Linux Kernel related build artifacts and configure the Kernel."
    echo ""
    echo "  Usage: ${0} [kernel|dtbs|bootscript|deb]"
    echo "  For Kernel config modification use: ${0} menuconfig"
    echo ""
    echo "  -c Clean the build output directory '_build_armhf'."
    echo "  -h Print this help text and exit"
    echo ""
    echo "  By default the script can be executed with 'no' arguments, all required artifacts"
    echo "  will be build resulting in a 'um-kernel-[RELEASE_VERSION].deb' package."
    echo "  Either one of the above optional arguments can be passed to the script to build that"
    echo "  specific artifact."
    echo ""
    echo "  The package release version can be passed by passing 'RELEASE_VERSION' through the run environment."
}

while getopts ":ch" options; do
    case "${options}" in
    c)
        if [ -d "${BUILD_OUTPUT_DIR}" ] && [ -z "${BUILD_OUTPUT_DIR##*_build_armhf*}" ]; then
            rm -rf "${BUILD_OUTPUT_DIR}"
        fi
        echo "Cleaned up '${BUILD_OUTPUT_DIR}'."
        exit 0
        ;;
    h)
        usage
        exit 0
        ;;
    :)
        echo "Option -${OPTARG} requires an argument."
        exit 1
        ;;
    ?)
        echo "Invalid option: -${OPTARG}"
        exit 1
        ;;
    esac
done
shift "$((OPTIND - 1))"


if [ "${#}" -gt 1 ]; then
    echo "Too many arguments."
    usage
    exit 1
fi

if [ "${#}" -eq 0 ]; then
    kernel_build
    dtb_build
    bootscript_build
    deb_build
    exit 0
fi

case "${1-}" in
    kernel)
        kernel_build
        ;;
    dtbs)
        dtb_build
        ;;
    bootscript)
        bootscript_build
        ;;
    deb)
        kernel_build
        dtb_build
        bootscript_build
        deb_build
        ;;
    menuconfig)
        kernel_build_command menuconfig
        ;;
    *)
        echo "Error, unknown build option given"
        usage
        exit 1
        ;;
esac

exit 0

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
        echo "No suitable cross-compiler found."
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

ARCH="armhf"
UM_ARCH="imx6dl" # Empty string, or sun7i for R1, or imx6dl for R2

# common directory variablesS
SYSCONFDIR="${SYSCONFDIR:-/etc}"
SRC_DIR="$(pwd)"
BUILD_DIR_TEMPLATE="_build"
BUILD_DIR="${BUILD_DIR:-${SRC_DIR}/${BUILD_DIR_TEMPLATE}}"

# Debian package information
PACKAGE_NAME="${PACKAGE_NAME:-um-kernel}"
RELEASE_VERSION="${RELEASE_VERSION:-999.999.999}"

# Which kernel to build
LINUX_SRC_DIR=${SRC_DIR}/linux

# Which kernel config to build.
BUILDCONFIG="msc-sm2-imx6dl-ultimain4.2"

# Setup internal variables
KCONFIG="${SRC_DIR}/configs/${BUILDCONFIG}_config"
KERNEL_BUILD_DIR="${BUILD_DIR}/${BUILDCONFIG}-linux"
KERNEL_IMAGE="uImage-${BUILDCONFIG}"
DEBIAN_DIR="${BUILD_DIR}/debian"
BOOT_FILE_OUTPUT_DIR="${DEBIAN_DIR}/boot"

INITRAMFS_MODULES_REQUIRED="ci_hdrc_imx.ko ci_hdrc.ko usbmisc_imx.ko usb-otg-fsm.ko phy-mxs-usb.ko \
    dw_hdmi-imx.ko dw-hdmi.ko etnaviv.ko imxdrm.ko imx-ipu-v3.ko loop.ko imx2_wdt.ko"
INITRAMFS_SOURCE="${INITRAMFS_SOURCE:-initramfs/initramfs.lst}"

BB_VERSION="1.31.0"
BB_URL="https://busybox.net/downloads/busybox-${BB_VERSION}.tar.bz2"
BB_BIN="busybox"
BB_PKG="busybox-${BB_VERSION}.tar.bz2"
BB_DIR="busybox-${BB_VERSION}"

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

# Add the UM_ARCH to release version keeping a possible -dev on the most right side
if [[ ${RELEASE_VERSION} == *'-dev' ]]; then
    RELEASE_VERSION="${RELEASE_VERSION/-dev/-${UM_ARCH}-dev}"
else
    RELEASE_VERSION="${RELEASE_VERSION}-${UM_ARCH}"
fi;

##
# busybox_get() - Download and build the Busybox package
# param1:   Writable path where to store the Busybox binary
#
# Busybox is downloaded from the global variable ${BB_PKG}.
busybox_get()
{
    DEST_DIR="${1}"

    if [ ! -d "${DEST_DIR}" ]; then
        echo "No initramfs dir set to download busybox into."
        exit 1
    fi

    if [ ! -f "${BB_PKG}" ]; then
        if ! wget -q "${BB_URL}"; then
            echo "Unable to download the busybox package '${BB_URL}'. Update the download URL."
            exit 1
        fi
    fi

    if [ ! -d "${BB_DIR}" ]; then
        if ! tar xvjf "${BB_PKG}" > /dev/null 2>&1; then
            echo "Unable to extract Busybox package '${BB_PKG}'."
            exit 1
        fi
    fi

    cd "${BB_DIR}"
    cp "${SRC_DIR}/configs/busybox_defconfig" ".config"

    ARCH=arm CROSS_COMPILE="${CROSS_COMPILE}" make

    mv "${BB_BIN}" "${DEST_DIR}/${BB_BIN}"
    cd "${SRC_DIR}"

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
                if [ -n "${INITRAMFS_MODULES##*"${dep_module}"*}" ]; then
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

    INITRAMFS_SRC_DIR="${SRC_DIR}/initramfs"
    INITRAMFS_DST_DIR="${KERNEL_BUILD_DIR}/initramfs"
    INITRAMFS_MODULES_DIR="${KERNEL_BUILD_DIR}/initramfs/lib/modules"
    INITRAMFS_DEST="${INITRAMFS_DST_DIR}/$(basename "${INITRAMFS_SOURCE}")"

    if [ -d "${INITRAMFS_DST_DIR}" ]; then
        rm -rf "${INITRAMFS_DST_DIR}"
    fi

    mkdir -p "${INITRAMFS_DST_DIR}"

    cp -a "${INITRAMFS_SRC_DIR}/"* "${INITRAMFS_DST_DIR}"

    busybox_get "${INITRAMFS_DST_DIR}"

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
    cd "${SRC_DIR}"
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
    kernel_build_command LOADADDR=0x10004000 uImage

    # Install Kernel image

    if [ -d "${BOOT_FILE_OUTPUT_DIR}" ] && [ -z "${BOOT_FILE_OUTPUT_DIR##*_build*}" ]; then
        rm -r "${BOOT_FILE_OUTPUT_DIR}"
    fi
    mkdir -p "${BOOT_FILE_OUTPUT_DIR}"

    cp "${KERNEL_BUILD_DIR}/arch/arm/boot/uImage" "${BOOT_FILE_OUTPUT_DIR}/${KERNEL_IMAGE}"
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

    if [ -d "${DEBIAN_DIR}/lib/modules" ] && [ -z "${BOOT_FILE_OUTPUT_DIR##*_build*}" ]; then
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
#
# In the U-Boot stage the boot script is executed, that in turn reads
# the machine article number from the I2C EEPROM. This article number
# is in Hexadecimal format. The boot-script will then load a device-tree
# with corresponding article number into memory.
#
# This function will parse a file called article.links and compile the device-tree
# binaries described above.
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

insert_gpio_pin_definitions_scripts()
{

    mkdir -p "${DEBIAN_DIR}/usr/bin/"
    cp "${SRC_DIR}/scripts/avr-gpio-start" "${DEBIAN_DIR}/usr/bin/"

    mkdir -p "${DEBIAN_DIR}/etc/systemd/system/"
    cp "${SRC_DIR}/scripts/rc.gpio.service" "${DEBIAN_DIR}/etc/systemd/system/"


    echo "##### Listing original dir: ${SRC_DIR}/scripts/ ######"
    ls -lha "${SRC_DIR}/scripts/"
    
    mkdir -p "${DEBIAN_DIR}/DEBIAN/"
    cp "${SRC_DIR}/scripts/postinst" "${DEBIAN_DIR}/DEBIAN/"

    echo "##### Listing dest dir: ${DEBIAN_DIR}/DEBIAN/ ######"
    ls -lha "${DEBIAN_DIR}/DEBIAN/"

    mount
}

create_debian_package()
{
    echo "Building Debian package."

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

    if ! ls "${BOOT_FILE_OUTPUT_DIR}/"*".dtb" 1> /dev/null 2>&1; then
        echo "Error, no Kernel device-tree files installed, run 'dtbs' build first."
        exit 1
    fi

    mkdir -p "${DEBIAN_DIR}/DEBIAN"
    sed -e 's|@ARCH@|'"${ARCH}"'|g' \
        -e 's|@PACKAGE_NAME@|'"${PACKAGE_NAME}"'|g' \
        -e 's|@RELEASE_VERSION@|'"${RELEASE_VERSION}"'|g' \
        "${SRC_DIR}/debian/control.in" > "${DEBIAN_DIR}/DEBIAN/control"

    DEB_PACKAGE="${PACKAGE_NAME}_${RELEASE_VERSION}_${ARCH}.deb"

    # Build the Debian package
    dpkg-deb --build "${DEBIAN_DIR}" "${BUILD_DIR}/${DEB_PACKAGE}"

    echo "Finished building Debian package."
    echo "To check the contents of the Debian package run 'dpkg-deb -c um-kernel*.deb'"
}

usage()
{
    echo ""
    echo "This is the build script for Linux Kernel related build artifacts and configure the Kernel."
    echo ""
    echo "  Usage: ${0} [kernel|dtbs|deb]"
    echo "  For Kernel config modification use: ${0} menuconfig"
    echo ""
    echo "  -c Clean the build output directory '_build'."
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
        if [ -d "${BUILD_DIR}" ] && [ -z "${BUILD_DIR##*_build*}" ]; then
            rm -rf "${BUILD_DIR}"
        fi
        echo "Cleaned up '${BUILD_DIR}'."
        if [ -d "${BB_DIR}" ] && [ -z "${BB_DIR##*busybox-*}" ]; then
            rm -rf "${BB_DIR}"
        fi
        echo "Cleaned up '${BB_DIR}'."
        if [ -f "${BB_PKG}" ]; then
            unlink "${BB_PKG}"
        fi
        echo "Removed '${BB_PKG}'."
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
    insert_gpio_pin_definitions_scripts
    create_debian_package
    exit 0
fi

case "${1-}" in
    kernel)
        kernel_build
        ;;
    dtbs)
        dtb_build
        ;;
    deb)
        kernel_build
        dtb_build
        insert_gpio_pin_definitions_scripts
        create_debian_package
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

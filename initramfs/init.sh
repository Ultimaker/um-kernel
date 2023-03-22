#!/bin/sh
#
# Copyright (C) 2018 Ultimaker B.V.
# Author: 2018 Olliver Schinagl <oliver@schinagl.nl>
# Author: 2019 Raymond Siudak <raysiudak@gmail.com>
#

set -eu

ROOT_MOUNT="/mnt/root"
UPDATE_IMAGE="um-update.swu"
UPDATE_IMG_MOUNT="/mnt/update_img"
UPDATE_SRC_MOUNT="/mnt/update"
PROVISIONING_USB_MOUNT="/mnt/usb"
RESCUE_SHELL="no"
FORCE_RESTORE_MODE="no"

PREFIX="${PREFIX:-/usr/}"
EXEC_PREFIX="${PREFIX}"
SBINDIR="${EXEC_PREFIX}/sbin"

EMMC_DEV="/dev/mmcblk2"

SYSTEM_UPDATE_ENTRYPOINT="start_update.sh"
UPDATE_DEVICES="/dev/mmcblk[0-9]p[0-9]"

#uc2 : UltiController 2 (UM3,UM3E) This UltiController is not considered here anymore
#uc3 : UltiController 3 (S5,S5r2,S3)
#uc4 : UltiController 4 (Colorado)
DISPLAY_TYPE="uc4"
UM_SPLASH="/SplashUM.fb"
FB_DEVICE="/dev/fb0"


BB_BIN="/bin/busybox"
CMDS=" \
    [ \
    break \
    continue \
    echo \
    exec \
    findfs \
    i2ctransfer \
    mktemp \
    modprobe \
    mount \
    mv \
    poweroff \
    readlink \
    reboot \
    shutdown \
    sleep \
    switch_root \
    umount \
    watchdog \
"
WATCHDOG_DEV="/dev/watchdog"

init="/sbin/init"
root=""
nfs_root=""
rootflags=""
rootfstype="auto"
rwmode=""

update_tmpfs_mount=""

shutdown()
{
    while true; do
        poweroff
        echo "Please remove power to complete shutdown."
        sleep 10s
    done
}

restart()
{
    echo "Rebooting in 5 seconds ..."
    sleep 5s
    reboot
    modprobe imx2_wdt || true
    if [ -w "${WATCHDOG_DEV}" ]; then
        watchdog -T 1 -t 60 -F "${WATCHDOG_DEV}"
    fi
    echo "Failed to reboot, shutting down instead."
    shutdown
}

restore_complete_loop()
{
    while true; do
        echo "Restore complete, remove the recovery SD card and powercycle the printer."
        sleep 30s
    done 
}

rescue_shell()
{
    set +eu
    ${BB_BIN} echo ""
    ${BB_BIN} echo "##################################################"
    ${BB_BIN} echo "#                   ▄▄▄      ▄▄▄                 #"
    ${BB_BIN} echo "#                   ███████▄▄███▄                #"
    ${BB_BIN} echo "#                 ▄███  ▄▄   ▄▄ ▐█               #"
    ${BB_BIN} echo "#              ▄██  ██ ▀▀▀   ▀▀▀▐█▄              #"
    ${BB_BIN} echo "#              ███▄▄██  ▄▄▄▄▄▄▄ ▐██              #"
    ${BB_BIN} echo "#               ██████ ▀       ▀ ▐█              #"
    ${BB_BIN} echo "#            ▄████▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀█▄           #"
    ${BB_BIN} echo "#          ████▐█ ▐████████████████▌▐██▄         #"
    ${BB_BIN} echo "#        ▐███▌▄▄█ ▐████████████████▌▐█▄█         #"
    ${BB_BIN} echo "#         ███████ ███████▀▀ ▀██████▌▐██▌         #"
    ${BB_BIN} echo "#         ███████ █████████ ██▐████▌▐██▌         #"
    ${BB_BIN} echo "#        ▄███████ ██████▄██████████▌▐█▀█         #"
    ${BB_BIN} echo "#        ████  ▐█ ▐████████████████▌▐█ █▌        #"
    ${BB_BIN} echo "#        ▀███ ███   ▀▀▀▀            ▐██▀         #"
    ${BB_BIN} echo "#           ▀▀████▄▄████████████████▀            #"
    ${BB_BIN} echo "#             ▐████████▀▀████▀▀▌  █▌             #"
    ${BB_BIN} echo "#            ▄██████  █  ▐███▄▄█▄▄██             #"
    ${BB_BIN} echo "#            ████████▀▀▀█▀████▀    ██            #"
    ${BB_BIN} echo "#            █████████    ▐███     ██            #"
    ${BB_BIN} echo "#              ▀███▄█▄▄▄▄▄███▀▀▀▀▀▀▀             #"
    ${BB_BIN} echo "#                                                #"
    ${BB_BIN} echo "# Starting busybox rescue and recovery shell.    #"
    ${BB_BIN} echo "# Tip: type help<enter> for available commands.  #"
    ${BB_BIN} echo "#                                                #"
    ${BB_BIN} echo "##################################################"
    exec ${BB_BIN} sh
}

critical_error()
{
    echo "A critical error has occurred, entering recovery mode."
    rescue_shell
    shutdown
}

boot_root()
{
    root_device="${root}"
    if [ "${rootfstype}" = "nfs" ]
    then
        root_device="${nfs_root}"
    fi
    echo "Mounting ${root_device}."
    mount -t "${rootfstype}" -o exec,suid,dev,noatime,"${rootflags},${rwmode}" "${root_device}" "${ROOT_MOUNT}"
    kernel_umount

    test_init="${init}"
    if [ -L "${ROOT_MOUNT}/${init}" ]; then
       test_init="${ROOT_MOUNT}/$(readlink "${ROOT_MOUNT}/${init}")"
    fi
    if [ ! -x "${test_init}" ]; then
        echo "Error, no such file '${test_init}'."
        critical_error
        restart
    fi

    echo "Starting linux on ${root_device} of type ${rootfstype} with init=${init}."
    exec switch_root "${ROOT_MOUNT}" "${init}"
}

set_display_splash()
{
    echo "Setting display image."

    splash_img="${UM_SPLASH}"

    if [ -f "${splash_img}" ] && [ -c "${FB_DEVICE}" ]; then
        cat "${splash_img}" > "${FB_DEVICE}" || true
    else
        echo "Unable to output image: '${splash_img}' to: '${FB_DEVICE}'."
    fi
}

isBootingRestoreImage()
{
    # The partition label 'recovery_data' is an interface between, the recover image creator and executor,
    # i.e. jedi-build and um-kernel initrd.
    findfs LABEL=recovery_data 
}

check_and_set_eeprom_data()
{
    dev="/dev/sda1"
    article_number_file="${PROVISIONING_USB_MOUNT}/article_number"
    country_code_lock_file="${PROVISIONING_USB_MOUNT}/country_code_lock"

    # Get the article number from EEPROM
    art_num=$(i2ctransfer -y 3 w2@0x57 0x01 0x00 r4)
    echo "---> Article number read from EEPROM: >${art_num}<"

    # Get the country code lock from EEPROM
    country_code_lock=$(i2ctransfer -y 3 w2@0x57 0x01 0x18 r2)
    echo "--> Country code lock read from EEPROM: >${country_code_lock}<"

    retries=5
    while [ "${retries}" -gt 0 ]; do
        if [ ! -b "${dev}" ]; then
            retries="$((retries - 1))"
            sleep 1
            continue
        fi

        echo "Attempting to mount '${dev}'."
        if ! mount -t f2fs,ext4,vfat,auto -o exec,noatime "${dev}" "${PROVISIONING_USB_MOUNT}"; then
            return 0
        fi

        if [ ! -r "${article_number_file}" ] && [ ! -r "${country_code_lock_file}" ]; then
            umount "${dev}"
            echo "No article number file or country code lock file found on '${dev}', skipping."
            return 0
        fi

        if [ -r "${article_number_file}" ]; then
            article_number="$(cat "${article_number_file}")"
            echo "Trying to write article nr: '${article_number}'."
            # shellcheck disable=SC2086
            if ! i2ctransfer -y 3 w6@0x57 0x01 0x00 ${article_number}; then
                umount "${dev}"
                echo "Failed to write article number to EEPROM, skipping."
                return 0
            fi
        fi

        if [ -r "${country_code_lock_file}" ]; then
            country_code="$(cat "${country_code_lock_file}")"
            echo "Trying to write country code lock: '${country_code}'."
            # shellcheck disable=SC2086
            if ! i2ctransfer -y 3 w4@0x57 0x01 0x18 ${country_code}; then
                umount "${dev}"
                echo "Failed to write country code lock to EEPROM, skipping."
                return 0
            fi
        fi

        umount "${dev}"
        retries=0
    done
}

find_and_run_update()
{
    SOFTWARE_INSTALL_MODE="update"
    if isBootingRestoreImage || [ "${FORCE_RESTORE_MODE}" = "yes" ]; then
        SOFTWARE_INSTALL_MODE="restore"
    fi

    echo "Checking for updates ..."
    for dev in ${UPDATE_DEVICES}; do
        if [ ! -b "${dev}" ]; then
            continue
        fi

        echo "Attempting to mount '${dev}'."
        if ! mount -t f2fs,ext4,vfat,auto -o exec,noatime "${dev}" "${UPDATE_SRC_MOUNT}"; then
            continue
        fi

        if [ ! -r "${UPDATE_SRC_MOUNT}/${UPDATE_IMAGE}" ]; then
            umount "${dev}"
            echo "No update image '${UPDATE_IMAGE}' found on '${dev}', trying next."
            continue
        fi

        update_tmpfs_mount="$(mktemp -d)"
        echo "Found '${UPDATE_IMAGE}' on '${dev}', moving to tmpfs."

        # When we are restoring we want to keep the update image on the SD card.
        if [ "${SOFTWARE_INSTALL_MODE}" = "restore" ]; then
            if ! cp "${UPDATE_SRC_MOUNT}/${UPDATE_IMAGE}" "${update_tmpfs_mount}"; then
                echo "Error, update failed: unable to copy ${UPDATE_IMAGE} to ${update_tmpfs_mount}."
                critical_error
                break
            fi
        else
            if ! mv "${UPDATE_SRC_MOUNT}/${UPDATE_IMAGE}" "${update_tmpfs_mount}"; then
                echo "Error, update failed: unable to move ${UPDATE_IMAGE} to ${update_tmpfs_mount}."
                critical_error
                break
            fi
        fi

        echo "Attempting to unmount '${UPDATE_SRC_MOUNT}' before performing the update."
        if ! umount "${UPDATE_SRC_MOUNT}"; then
            echo "Error, update failed: unable to unmount ${UPDATE_SRC_MOUNT}."
            critical_error
            break
        fi

        echo "Attempting to mount '${update_tmpfs_mount}/${UPDATE_IMAGE}' to '${UPDATE_IMG_MOUNT}'."
        if ! mount "${update_tmpfs_mount}/${UPDATE_IMAGE}" ${UPDATE_IMG_MOUNT}; then
            echo "Error, update failed: unable to mount '${update_tmpfs_mount}/${UPDATE_IMAGE}'."
            critical_error
            break;
        fi

        echo "Successfully mounted '${UPDATE_IMAGE}', looking for '${UPDATE_IMG_MOUNT}/${SBINDIR}/${SYSTEM_UPDATE_ENTRYPOINT}' script."
        if [ ! -x "${UPDATE_IMG_MOUNT}/${SBINDIR}/${SYSTEM_UPDATE_ENTRYPOINT}" ]; then
            echo "Error, update failed: no '${UPDATE_IMG_MOUNT}/${SBINDIR}/${SYSTEM_UPDATE_ENTRYPOINT}' script found on '${UPDATE_IMG_MOUNT}'."
            critical_error
            break
        fi

        echo "Copying '${UPDATE_IMG_MOUNT}/${SBINDIR}/${SYSTEM_UPDATE_ENTRYPOINT}' from the update image."
        if ! cp "${UPDATE_IMG_MOUNT}/${SBINDIR}/${SYSTEM_UPDATE_ENTRYPOINT}" "${update_tmpfs_mount}/"; then
            echo "Error, copy of '${UPDATE_IMG_MOUNT}/${SBINDIR}/${SYSTEM_UPDATE_ENTRYPOINT}' to '${update_tmpfs_mount}' failed."
            critical_error
            break
        fi

        echo "Copied update script from image, cleaning up."
        if ! umount "${UPDATE_IMG_MOUNT}"; then
            echo "Warning: unable to unmount '${UPDATE_IMG_MOUNT}'."
        fi

        echo "Got '${SYSTEM_UPDATE_ENTRYPOINT}' script, trying to execute."
        if ! "${update_tmpfs_mount}/${SYSTEM_UPDATE_ENTRYPOINT}" "${update_tmpfs_mount}/${UPDATE_IMAGE}" "${EMMC_DEV}" "${DISPLAY_TYPE}" "${SOFTWARE_INSTALL_MODE}"; then
            echo "Error, update failed: executing '${update_tmpfs_mount}/${SYSTEM_UPDATE_ENTRYPOINT} ${update_tmpfs_mount}/${UPDATE_IMAGE} ${EMMC_DEV} ${DISPLAY_TYPE} ${SOFTWARE_INSTALL_MODE}'."
            critical_error
            break
        fi

        # After restore do not remove the file and loop endlessly
        if [ "${SOFTWARE_INSTALL_MODE}" = "restore" ]; then
           restore_complete_loop
        fi

        if ! rm "${update_tmpfs_mount}/${UPDATE_IMAGE:?}"; then
            echo "Warning, unable to remove '${update_tmpfs_mount}/${UPDATE_IMAGE}'."
        fi

        restart
    done
    echo "No updates found."
}

parse_cmdline()
{
    if [ ! -r "/proc/cmdline" ]; then
        echo "Unable to read /proc/cmdline to parse boot arguments."
        exit 1
    fi

    # shellcheck disable=SC2013
    # Disabled because it is not possible in a while read loop
    for cmd in $(cat /proc/cmdline); do
        case "${cmd}" in
        nfsroot=*)
            nfs_root="${cmd#*=}"
        ;;
        rescue)
            RESCUE_SHELL="yes"
        ;;
        restore)
            FORCE_RESTORE_MODE="yes"
        ;;
        ro)
            rwmode="ro"
        ;;
        rw)
            rwmode="rw"
        ;;
        rootdelay=*)
            sleep "${cmd#*=}"
        ;;
        root=*)
            _root="${cmd#*=}"
            _prefix="${_root%%=*}"

            if [ "${_prefix}" = "UUID" ] || \
               [ "${_prefix}" = "PARTUUID" ] || \
               [ "${_prefix}" = "LABEL" ] || \
               [ "${_prefix}" = "PARTLABEL" ]; then
                root=$(findfs "${_root}")
            else
                root="${cmd#*=}"
            fi
        ;;
        rootflags=*)
            rootflags="${cmd#*=}"
        ;;
        rootfstype=*)
            rootfstype="${cmd#*=}"
        ;;
        init=*)
            init="${cmd#*=}"
        ;;
        esac
    done
}

kernel_mount()
{
    mount -t devtmpfs   -o nosuid,mode=0755 udev    /dev
    mount -t proc       -o nodev,noexec,nosuid  proc    /proc
    mount -t sysfs      -o nodev,noexec,nosuid  sysfs   /sys
}

kernel_umount()
{
    umount /sys
    umount /proc
    umount /dev
}

toolcheck()
{
    echo "Checking command availability."
    for cmd in ${CMDS}; do
        command -V "${cmd}"
    done
}

busybox_setup()
{
    "${BB_BIN}" --install -s
}

trap critical_error EXIT

busybox_setup
toolcheck
kernel_mount
parse_cmdline
if [ "${RESCUE_SHELL}" = "yes" ]; then
    rescue_shell
fi
set_display_splash
find_and_run_update
check_and_set_eeprom_data

echo
echo "INITRAMFS: Handing over to the main system:"
boot_root

critical_error
exit 1

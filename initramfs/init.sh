#!/bin/sh
#
# Copyright (C) 2018 Ultimaker B.V.
# Copyright (C) 2018 Olliver Schinagl <oliver@schinagl.nl>
#
# SPDX-License-Identifier: AGPL-3.0+

set -eu

ROOT_MOUNT="/mnt/root"
UPDATE_IMAGE="um-update.swu"
UPDATE_IMG_MOUNT="/mnt/update_img"
UPDATE_SRC_MOUNT="/mnt/update"

PREFIX="${PREFIX:-/usr/}"
EXEC_PREFIX="${PREFIX}"
SBINDIR="${EXEC_PREFIX}/sbin"

SYSTEM_UPDATE_ENTRYPOINT="start_update.sh"
UPDATE_DEVICES="/dev/mmcblk[0-9]p[0-9]"
BB_BIN="/bin/busybox"
CMDS=" \
    [ \
    break \
    continue \
    echo \
    exec \
    findfs \
    mktemp \
    modprobe \
    mount \
    mv \
    poweroff \
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
    modprobe sunxi_wdt || true
    if [ -w "${WATCHDOG_DEV}" ]; then
        watchdog -T 1 -t 60 -F "${WATCHDOG_DEV}"
    fi
    echo "Failed to reboot, shutting down instead."
    shutdown
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
    echo "Mounting ${root}."
    mount -t "${rootfstype}" -o exec,suid,dev,noatime,"${rootflags},${rwmode}" "${root}" "${ROOT_MOUNT}"
    kernel_umount
    echo "Starting linux on ${root} of type ${rootfstype} with init=${init}."
    exec switch_root "${ROOT_MOUNT}" "${init}"
}

find_and_run_update()
{
    echo "Checking for updates ..."
    for dev in ${UPDATE_DEVICES}; do
        if [ ! -b "${dev}" ]; then
            continue
        fi

        base_dev="${dev%p[0-9]}"

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
        if ! mv "${UPDATE_SRC_MOUNT}/${UPDATE_IMAGE}" "${update_tmpfs_mount}"; then
            echo "Error, update failed: unable to move ${UPDATE_IMAGE} to ${update_tmpfs_mount}."
            critical_error
            break;
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
            break;
        fi

        echo "Copying '${UPDATE_IMG_MOUNT}/${SBINDIR}/${SYSTEM_UPDATE_ENTRYPOINT}' from the update image."
        if ! cp "${UPDATE_IMG_MOUNT}/${SBINDIR}/${SYSTEM_UPDATE_ENTRYPOINT}" "${update_tmpfs_mount}/"; then
            echo "Error, copy of '${UPDATE_IMG_MOUNT}/${SBINDIR}/${SYSTEM_UPDATE_ENTRYPOINT}' to '${update_tmpfs_mount}' failed."
            critical_error
            break;
        fi

        echo "Copied update script from image, cleaning up."
        if ! umount "${UPDATE_IMG_MOUNT}"; then
            echo "Warning: unable to unmount '${UPDATE_IMG_MOUNT}'."
        fi

        echo "Got '${SYSTEM_UPDATE_ENTRYPOINT}' script, trying to execute."
        if ! "${update_tmpfs_mount}/${SYSTEM_UPDATE_ENTRYPOINT}" "${update_tmpfs_mount}/${UPDATE_IMAGE}" "${base_dev}"; then
            echo "Error, update failed: executing '${update_tmpfs_mount}/${SYSTEM_UPDATE_ENTRYPOINT} ${update_tmpfs_mount}/${UPDATE_IMAGE} ${base_dev}'."
            critical_error
            break;
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
    # Disabled because it is nos possible in a while read loop
    for cmd in $(cat /proc/cmdline); do
        case "${cmd}" in
        rescue)
            rescue_shell
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

find_and_run_update

boot_root

critical_error
exit 1

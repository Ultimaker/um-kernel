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
RESCUE_SHELL="no"

PREFIX="${PREFIX:-/usr/}"
EXEC_PREFIX="${PREFIX}"
SBINDIR="${EXEC_PREFIX}/sbin"

SYSTEM_UPDATE_ENTRYPOINT="start_update.sh"
UPDATE_DEVICES="/dev/mmcblk[0-9]p[0-9]"

#uc2 : UltiController 2 (UM3,UM3E) This UltiController is not considered here anymore
#uc3 : UltiController 3 (S5,S5r2,S3)
DISPLAY_TYPE="uc3"
UMSPLASH="/umsplash_png.fb"
FB_DEVICE="/dev/fb0"

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
    echo "Mounting ${root}."
    mount -t "${rootfstype}" -o exec,suid,dev,noatime,"${rootflags},${rwmode}" "${root}" "${ROOT_MOUNT}"
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

    echo "Starting linux on ${root} of type ${rootfstype} with init=${init}."
    exec switch_root "${ROOT_MOUNT}" "${init}"
}

probe_module()
{
    if ! modprobe -v "${1}"; then
        echo "Failed to probe module: '${1}', removing."
        rmmod "${1}.ko" || true
        return
    fi
}

enable_framebuffer_device()
{
    echo "Enable frame-buffer driver."

    modules="drm rc_core cec fb_sys_fops cfbfillrect syscopyarea cfbimgblt sysfillrect \
             sysimgblt cfbcopyarea drm_kms_helper sun4i_drm_hdmi sun4i-drm-hdmi sun4i-hdmi-i2c \
             sun4i-tcon sun4i-backend sun4i-drm"
    for module in ${modules}; do
        if ! probe_module "${module}"; then
            echo "Error, registering framebuffer device."
            return
        fi
    done

    if [ -f "${UMSPLASH}" ] && [ -c "${FB_DEVICE}" ]; then
        cat "${UMSPLASH}" > "${FB_DEVICE}" || true
    else
        echo "Unable to output image: '${UMSPLASH}' to: '${FB_DEVICE}'."
    fi
}

isBootingRestoreImage()
{
    # The partition label 'recovery_data' is an interface between, the recover image creator and executor,
    # i.e. jedi-build and um-kernel initrd.
    findfs LABEL=recovery_data 
}

find_and_run_update()
{
    SOFTWARE_INSTALL_MODE="update"
    if isBootingRestoreImage; then
        SOFTWARE_INSTALL_MODE="restore"
    fi

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

        # We need to change the storage device to update when we are running the restore image.
    	if isBootingRestoreImage; then
    	    # The kernel will enumerate the MMC device we boot from as 0, therefore if we boot from SD then the internal eMMC is 1;
    	    base_dev="/dev/mmcblk1"
        fi

        echo "Got '${SYSTEM_UPDATE_ENTRYPOINT}' script, trying to execute."
        if ! "${update_tmpfs_mount}/${SYSTEM_UPDATE_ENTRYPOINT}" "${update_tmpfs_mount}/${UPDATE_IMAGE}" "${base_dev}" "${DISPLAY_TYPE}" "${SOFTWARE_INSTALL_MODE}"; then
            echo "Error, update failed: executing '${update_tmpfs_mount}/${SYSTEM_UPDATE_ENTRYPOINT} ${update_tmpfs_mount}/${UPDATE_IMAGE} ${base_dev} ${DISPLAY_TYPE} ${SOFTWARE_INSTALL_MODE}'."
            echo "Trying old interface firmwares <= 5.2.x."
            # Old interface depended on U-Boot for passing the article number and it did not have support for te restore image.
            # Passing article number 9051 will show Ulticontroller 3 update images"
            if ! "${update_tmpfs_mount}/${SYSTEM_UPDATE_ENTRYPOINT}" "${update_tmpfs_mount}/${UPDATE_IMAGE}" "${base_dev}" "9051"; then
                echo "Error, update failed: executing '${update_tmpfs_mount}/${SYSTEM_UPDATE_ENTRYPOINT} ${update_tmpfs_mount}/${UPDATE_IMAGE} ${base_dev} 9051'."
                critical_error
                break
            fi
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
        rescue)
            RESCUE_SHELL="yes"
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
enable_framebuffer_device
if [ "${RESCUE_SHELL}" = "yes" ]; then
    rescue_shell
fi
find_and_run_update
boot_root

critical_error
exit 1

#!/bin/sh
#
# Copyright (C) 2018 Ultimaker B.V.
# Copyright (C) 2018 Olliver Schinagl <oliver@schinagl.nl>
#
# SPDX-License-Identifier: AGPL-3.0+

set -eu

ROOT_MOUNT="/mnt/root"
UPDATE_MOUNT="/mnt/update"
TOOLBOX_MOUNT="/mnt/toolbox"
TOOLBOX_IMAGE="${UPDATE_MOUNT}/um-update_toolbox.xz.img"
SYSTEM_UPDATE_ENTRYPOINT="${TOOLBOX_MOUNT}/sbin/startup.sh"
UPDATE_DEVICES="/dev/sd[a-z][0-9] /dev/mmcblk[0-9]p[0-9]"
BB_BIN="/bin/busybox"
WATCHDOG_DEV="/dev/watchdog"

init="/sbin/init"
root=""
rootflags=""
rootfstype="auto"
rwmode=""

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
	${BB_BIN} echo -en "\n" \
		"##################################################\n" \
		"#                   ▄▄▄      ▄▄▄                 #\n" \
		"#                   ███████▄▄███▄                #\n" \
		"#                 ▄███  ▄▄   ▄▄ ▐█               #\n" \
		"#              ▄██  ██ ▀▀▀   ▀▀▀▐█▄              #\n" \
		"#              ███▄▄██  ▄▄▄▄▄▄▄ ▐██              #\n" \
		"#               ██████ ▀       ▀ ▐█              #\n" \
		"#            ▄████▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀█▄           #\n" \
		"#          ████▐█ ▐████████████████▌▐██▄         #\n" \
		"#        ▐███▌▄▄█ ▐████████████████▌▐█▄█         #\n" \
		"#         ███████ ███████▀▀ ▀██████▌▐██▌         #\n" \
		"#         ███████ █████████ ██▐████▌▐██▌         #\n" \
		"#        ▄███████ ██████▄██████████▌▐█▀█         #\n" \
		"#        ████  ▐█ ▐████████████████▌▐█ █▌        #\n" \
		"#        ▀███ ███   ▀▀▀▀            ▐██▀         #\n" \
		"#           ▀▀████▄▄████████████████▀            #\n" \
		"#             ▐████████▀▀████▀▀▌  █▌             #\n" \
		"#            ▄██████  █  ▐███▄▄█▄▄██             #\n" \
		"#            ████████▀▀▀█▀████▀    ██            #\n" \
		"#            █████████    ▐███     ██            #\n" \
		"#              ▀███▄█▄▄▄▄▄███▀▀▀▀▀▀▀             #\n" \
		"#                                                #\n" \
		"# Starting busybox rescue and recovery shell.    #\n" \
		"# Tip: type help<enter> for available commands.  #\n" \
		"#                                                #\n" \
		"##################################################\n"
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
	mount -t "${rootfstype}" -o exec,suid,dev,noatime,"${rootflags}","${rwmode}" "${root}" "${ROOT_MOUNT}"
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

		echo "Attempting to mount '${dev}'."
		if ! mount -t f2fs,ext4,vfat,auto -o exec,noatime "${dev}" "${UPDATE_MOUNT}"; then
			continue
		fi

		if [ ! -x "${TOOLBOX_IMAGE}" ]; then
			umount "${dev}"
			echo "No update toolbox image '${TOOLBOX_IMAGE}' found on '${dev}', trying next."
			continue
		fi

		echo "Found '${TOOLBOX_IMAGE}' on '${dev}', attempting to mount."
		if ! mount "${TOOLBOX_IMAGE}" "${TOOLBOX_MOUNT}"; then
			echo "Update failed: Unable to mount '${TOOLBOX_IMAGE}'."
			critical_error
			break;
		fi

		echo "Successfully mounted '${TOOLBOX_IMAGE}', looking for '${SYSTEM_UPDATE_ENTRYPOINT}' script."
		if [ ! -x "${SYSTEM_UPDATE_ENTRYPOINT}" ]; then
			echo "Update failed: No '${SYSTEM_UPDATE_ENTRYPOINT}' script found on '${TOOLBOX_MOUNT}'."
			critical_error
			break;
		fi

		echo "Found '${SYSTEM_UPDATE_ENTRYPOINT}' script on ${dev}, trying to execute."
		if ! "${SYSTEM_UPDATE_ENTRYPOINT}"; then
			echo "Update failed: Error executing '${SYSTEM_UPDATE_ENTRYPOINT}'."
			critical_error
			break;
		fi

		echo "Update finished, attempting to unmount '${TOOLBOX_MOUNT}'."
		if ! umount "${TOOLBOX_MOUNT}"; then
			echo "Update failed: Unable to unmount '${TOOLBOX_MOUNT}'."
			critical_error
			break;
		fi

		echo "Attempting to remove '${TOOLBOX_IMAGE}'."
		if ! chmod -x "${TOOLBOX_IMAGE}" || ! rm -f "${TOOLBOX_IMAGE}"; then
			echo "Update failed: Failed to remove '${TOOLBOX_IMAGE}'."
			critical_error
			break;
		fi

		umount "${dev}"
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
	mount -t devtmpfs	-o nosuid,mode=0755	udev	/dev
	mount -t proc		-o nodev,noexec,nosuid	proc	/proc
	mount -t sysfs		-o nodev,noexec,nosuid	sysfs	/sys
}

kernel_umount()
{
	umount /sys
	umount /proc
	umount /dev
}

busybox_setup()
{
	${BB_BIN} --install -s
}

trap critical_error EXIT

busybox_setup
kernel_mount
parse_cmdline

find_and_run_update

boot_root

critical_error
exit 1

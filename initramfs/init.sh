#!/bin/busybox sh
#
# Copyright (C) 2018 Ultimaker B.V.
# Copyright (C) 2018 Olliver Schinagl <oliver@schinagl.nl>
#
# SPDX-License-Identifier: AGPL-3.0+

set -eu

ROOT_MOUNT="/mnt/root"
UPDATE_MOUNT="/mnt/update"
UPDATE_SCRIPT="${UPDATE_MOUNT}/um_update.sh"
UPDATE_DEVICES="/dev/sd[a-z][0-9] /dev/mmcblk[0-9]p[0-9]"
BB_BIN="/bin/busybox"

init="/sbin/init"
root=""
rootflags=""
rootfstype="auto"
rwmode=""

shutdown()
{
	while [ 1 ]; do
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
	mount -t ${rootfstype} -o exec,suid,dev,noatime,$rootflags,$rwmode "${root}" "${ROOT_MOUNT}"
	kernel_umount
	echo "Starting linux on ${root} of type ${rootfstype} with init=${init}."
	exec switch_root /mnt/root "${init}"
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
		root=*)
			local _root="${cmd#*=}"
			local _prefix="${_root%%=*}"

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

boot_root

critical_error
exit 1

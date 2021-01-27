#!/bin/sh

if [ "${ACTION}" = "add" ]; then
    systemctl stop *okuda*
    echo "Keybord detected, loading fbcon module" > /dev/kmsg
    modprobe fbcon > /dev/kmsg
elif [ "${ACTION}" = "remove" ]; then
    echo 0 > /sys/class/vtconsole/vtcon1/bind
    echo "Keybord removed, unloading fbcon module" > /dev/kmsg
    modprobe -r fbcon > /dev/kmsg
    systemctl start *okuda*                                       
fi

#!/usr/bin/python3

import os
import subprocess

gpm_config_template = """
#  /etc/gpm.conf - configuration file for gpm(1)
#
#  If mouse response seems to be to slow, try using
#  responsiveness=15. append can contain any random arguments to be
#  appended to the commandline.
#
#  If you edit this file by hand, please be aware it is sourced by
#  /etc/init.d/gpm and thus all shell meta characters must be
#  protected from evaluation (i.e. by quoting them).
#
#  This file is used by /etc/init.d/gpm and can be modified by
#  "dpkg-reconfigure gpm" or by hand at your option.
#
device={mouse_device_id}
responsiveness=
repeat_type=none
type=evdev
append=''
sample_rate=
"""

#/dev/input/by-id/usb-Logitech_USB_Optical_Mouse-event-mouse

def is_dev_mode():
    # dbus-send --system --dest=nl.ultimaker.system --type=method_call --print-reply=literal /nl/ultimaker/system nl.ultimaker.isDeveloperModeActive
    cmd = "dbus-send --system --dest=nl.ultimaker.system --type=method_call --print-reply=literal /nl/ultimaker/system nl.ultimaker.isDeveloperModeActive"
    completed_process = subprocess.run(cmd.split(), capture_output=True)
    return b"true" in completed_process.stdout

def detect_device_id(device_folder, ends_with):
    for (dirpath, dirnames, filenames) in os.walk(device_folder):
        for filename in filenames:
            if filename.endswith(ends_with):
                return os.path.join(dirpath, filename)
    return None

def detect_mouse_id():
    return detect_device_id("/dev/input/by-id", "-mouse")

def detect_keyboard_id():
    return detect_device_id("/dev/input/by-id", "-kbd")

def setup_mouse():
    detected_mouse_id = detect_mouse_id()
    if detected_mouse_id is not None:
        print("Mouse found at [%s] and writing that in /etc/gpm.conf..." % detected_mouse_id)
        config_file_contents = gpm_config_template.format(mouse_device_id=detected_mouse_id)
        with open("/etc/gpm.conf", "w") as gpm_config:
            gpm_config.writelines(config_file_contents)
        print("(Re)starting gpm...")
        subprocess.run("systemctl restart gpm".split())
    else:
        print("No mouse found")


"""
    systemctl stop *okuda*
    echo "Keybord detected, loading fbcon module" > /dev/kmsg
    modprobe fbcon > /dev/kmsg

"""
def enable_fbcon():
    os.system("systemctl stop oku*")
    os.system("echo \"Keyboard detected, loading fbcon module\" > /dev/kmsg")
    os.system("modprobe fbcon > /dev/kmsg")


"""
    echo 0 > /sys/class/vtconsole/vtcon1/bind
    echo "Keybord removed, unloading fbcon module" > /dev/kmsg
    modprobe -r fbcon > /dev/kmsg
    systemctl start *okuda*                                       
"""
def disable_fbcon():
    #os.spawnl(os.P_DETACH, "systemctl start oku*")
    os.system("echo \"Keyboard removed, unloading fbcon module\" > /dev/kmsg")
    os.system("echo 0 > /sys/class/vtconsole/vtcon0/bind")
    #subprocess.run("modprobe -r fbcon".split())
    os.system("modprobe -r fbcon")
    os.system("systemctl start oku*")


if __name__ == "__main__":
    if not is_dev_mode():
        print("Not dev mode - do nothing")
        exit(0)
    keyboard_device_id = detect_keyboard_id()
    if keyboard_device_id is not None:
        print("Keyboard detected at [%s]" % keyboard_device_id)
        setup_mouse()
        enable_fbcon()
        print("end of program")
    else:
        print("No keyboard detected")
        disable_fbcon()
        print("end of program")

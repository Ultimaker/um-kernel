#!/bin/sh

# Small shell script to export gpio pins to userspace.
# The kernel device tree normally does not allow gpios to be exported to userspace
# So we applied the following hack:
#  We've added custom device tree nodes in the device tree, in the form of:
#   gpio_exports {
#       [gpio_name] {
#           pin_nr = "[nr]";
#           direction = "[output:input]";
#       };
#   };
#
#   These nodes end up in /sys/firmware/devicetree/*/gpio_exports/
#   From this script, we iterate over those nodes and export the gpios to userspace.
#   We export these to /dev/gpio/ and set the permissions so they are world writable.

mkdir -p /dev/gpio 2> /dev/null

BASE_PATH=/sys/firmware/devicetree/
for DT in `/bin/ls ${BASE_PATH}`; do
    if [ -d "${BASE_PATH}/${DT}/gpio_exports" ]; then
        for GPIO_NAME in `/bin/ls ${BASE_PATH}/${DT}/gpio_exports/`; do
            PATH="${BASE_PATH}/${DT}/gpio_exports/${GPIO_NAME}"
            if [ -d "${PATH}" ]; then
                DIRECTION=`/bin/cat ${PATH}/direction` 
                PIN_NR=`/bin/cat ${PATH}/pin_nr` 

                if [ "${DIRECTION}" = "output" ]; then
                    echo "Creating output gpio: ${GPIO_NAME}"
                    echo ${PIN_NR} > /sys/class/gpio/export
                    echo "out" > /sys/class/gpio/gpio${PIN_NR}/direction
                    /bin/ln -s /sys/class/gpio/gpio${PIN_NR}/value /dev/gpio/${GPIO_NAME}
                elif [ "${DIRECTION}" = "input" ]; then
                    echo "Creating input gpio: ${GPIO_NAME}"
                    echo ${PIN_NR} > /sys/class/gpio/export
                    echo "in" > /sys/class/gpio/gpio${PIN_NR}/direction
                    /bin/ln -s /sys/class/gpio/gpio${PIN_NR}/value /dev/gpio/${GPIO_NAME}
                else
                    echo "Unknown gpio direction: ${GPIO_NAME} ${DIRECTION}"
                fi
            fi
        done
    fi
done

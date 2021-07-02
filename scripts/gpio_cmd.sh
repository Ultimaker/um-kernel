#!/bin/bash

usage()
{
    echo ""
    echo "This script is a wrapper for the libgpiod tools"
    echo ""
    echo "  Usage: ${0} read|set|clear pin-name"
    echo ""
    echo "  read  Configure the pin as input and return its current value"
    echo "  set   Configure the pin as output at a High Level"
    echo "  clear Configure the pin as outout at a Low Level."
    echo ""
    echo "  pin-name must be listed in one of the gpio controllers"
    echo "  in the device tree."
    echo ""
    echo "  It will exit 0 if success or 1 if error."
    echo ""
}

ACTION="${1}"
PIN_NAME="${2}"

# Exit if one of the 2 required arguments (action and pin-name) are empty
if [ -z "${ACTION}" ] || [ -z "${PIN_NAME}" ]; then
    usage
    exit 1
fi

PIN_INFO="$(gpiofind "${PIN_NAME}")"
if [ "${?}" -gt 0 ]; then
    echo "ERROR: pin-name not found!"
    exit 1
fi

case "${ACTION}" in
    "read")
        gpioget ${PIN_INFO}
        exit 0
        ;;

    "set")
        gpioset ${PIN_INFO}=1
        exit 0
        ;;

    "clear")
        gpioset ${PIN_INFO}=0
        exit 0
        ;;

    *)
        echo "ERROR: Invalid action!"
        usage
        exit 1
        ;;
esac

#!/bin/bash

set -eu

cd /sys/class/gpio

if [ ! -d "gpio103" ]; then
    echo 103 > "export"
    echo out > gpio103/direction
fi

if [ ! -d "gpio124" ]; then
    echo 124 > "export"        
    echo out > gpio124/direction
fi 

if [ "${1}" = "on" ]; then
    echo 1 > gpio124/value
    echo 1 > gpio103/value
    sleep 1               
    echo 0 > gpio103/value
elif [ "${1}" = "off" ]; then
    echo 0 > gpio124/value
    echo 1 > gpio103/value
    sleep 1               
    echo 0 > gpio103/value
fi 

exit 0

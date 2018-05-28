#!/bin/bash

REPO_ROOT=$(pwd)
PACKAGE_NAME="um-kernel"
DOCKER_IMAGE_NAME="${PACKAGE_NAME}_build"
DOCKER_CONTAINER_NAME="kernel_build"

if ! ( which docker ); then
    echo -e -n "\e[1;31m"
    echo "Docker not installed, unable to continue"
    echo -e "\e[0m"
    exit 1
fi

if [[ -d "${REPO_ROOT}/linux/.git" ]]; then
    echo -e -n "\e[1;31m"
    echo "Git submodules not initialized, execute: git submodule update --init --recursive"
    echo -e "\e[0m"
    exit 1
fi

if [[ "${CROSS_COMPILE}" == "" ]]; then
    if [[ "$(which arm-none-eabi-gcc)" != "" ]]; then
        CROSS_COMPILE="arm-none-eabi-"
    fi
    if [[ "$(which arm-linux-gnueabihf-gcc)" != "" ]]; then
        CROSS_COMPILE="arm-linux-gnueabihf-"
    fi
    if [[ "${CROSS_COMPILE}" == "" ]]; then
        echo -e -n "\e[1;31m"
        echo "No suiteable cross-compiler found."
        echo "One can be set explicitly via the environment variable CROSS_COMPILE='arm-linux-gnueabihf-' for example."
        echo -e "\e[0m"
        exit 1
    fi
fi
export CROSS_COMPILE=${CROSS_COMPILE}

if [ "${MAKEFLAGS}" == "" ]; then
    echo -e -n "\e[1;33m"
    echo "Makeflags not set, setting makeflags to default 'nproc +1'"
    echo -e "\e[0m"
    export MAKEFLAGS="-j $(expr `nproc` + 1)"
fi

docker build . -t ${DOCKER_IMAGE_NAME}
docker run --name ${DOCKER_CONTAINER_NAME} --rm -e MAKEFLAGS="${MAKEFLAGS}" -v "${REPO_ROOT}/_build_armhf":/workspace/_build_armhf  ${DOCKER_IMAGE_NAME} all
cp _build_armhf/*.deb .
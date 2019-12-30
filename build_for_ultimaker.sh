#!/bin/sh
#
# SPDX-License-Identifier: AGPL-3.0+
#
# Copyright (C) 2019 Ultimaker B.V.
#

set -eu

LOCAL_REGISTRY_IMAGE="um_kernel"

SRC_DIR="$(pwd)"
PREFIX="/usr"
RELEASE_VERSION="${RELEASE_VERSION:-9999.99.99}"
DOCKER_WORK_DIR="/build"
BUILD_DIR_TEMPLATE="_build"
BUILD_DIR="${BUILD_DIR_TEMPLATE}"

ARMv7_MAGIC="7f454c4601010100000000000000000002002800"

run_env_check="yes"
run_linters="yes"
run_tests="yes"

ARCH="${ARCH:-armhf}"

CROSS_COMPILE="${CROSS_COMPILE:-""}"

INITRAMFS_SOURCE="${INITRAMFS_SOURCE:-initramfs/initramfs.lst}"
DEPMOD="${DEPMOD:-/sbin/depmod}"

run_env_check="yes"
run_linters="yes"
run_tests="yes"

update_docker_image()
{
    echo "Building local Docker build environment."
    echo "!! Make sure you implement a proper 'buildenv_check.sh' script.!!"
    echo "This script should check your docker env, in order to get early feedback."
    docker build ./docker_env -t "${LOCAL_REGISTRY_IMAGE}"
}

setup_emulation_support()
{
    for emu in /proc/sys/fs/binfmt_misc/*; do
        if [ ! -r "${emu}" ]; then
            continue
        fi

        if grep -q "${ARMv7_MAGIC}" "${emu}"; then
            ARM_EMU_BIN="$(sed 's|interpreter ||;t;d' "${emu}")"
            break
        fi
    done

    if [ ! -x "${ARM_EMU_BIN}" ]; then
        echo "Unusable ARMv7 interpreter '${ARM_EMU_BIN}'."
        echo "Install an arm-emulator, such as qemu-arm-static for example."
        exit 1
    fi

    export ARM_EMU_BIN
}

run_in_docker()
{
    docker run \
        --privileged \
        --rm \
        -it \
        -u "$(id -u)" \
        -e "ARM_EMU_BIN=${ARM_EMU_BIN}" \
        -e "BUILD_DIR=${DOCKER_WORK_DIR}/${BUILD_DIR}" \
        -e "ARCH=${ARCH}" \
        -e "PREFIX=${PREFIX}" \
        -e "RELEASE_VERSION=${RELEASE_VERSION}" \
        -e "INITRAMFS_SOURCE=${INITRAMFS_SOURCE}" \
        -e "DEPMOD=${DEPMOD}" \
        -e "MAKEFLAGS=-j$(($(getconf _NPROCESSORS_ONLN) - 1))" \
        -v "${SRC_DIR}:${DOCKER_WORK_DIR}" \
        -v "${ARM_EMU_BIN}:${ARM_EMU_BIN}:ro" \
        -w "${DOCKER_WORK_DIR}" \
        "${LOCAL_REGISTRY_IMAGE}" \
        "${@}"
}

env_check()
{
    run_in_docker "./docker_env/buildenv_check.sh"
}

run_build()
{
    git submodule update --init --recursive --depth 1
    run_in_docker "./build.sh" "${@}"
}

run_tests()
{
    echo "There are no tests available for this repository."
}

run_linters()
{
    run_shellcheck
}

run_shellcheck()
{
    docker run \
        --rm \
        -v "$(pwd):${DOCKER_WORK_DIR}" \
        -w "${DOCKER_WORK_DIR}" \
        "registry.hub.docker.com/koalaman/shellcheck-alpine:stable" \
        "./run_shellcheck.sh"
}

usage()
{
    echo "Usage: ${0} [OPTIONS]"
    echo "  -c   Clean the workspace"
    echo "  -C   Skip run of build environment checks"
    echo "  -h   Print usage"
    echo "  -l   Skip code linting"
    echo "  -t   Skip tests"
    echo
    echo "Other options will be passed on to build.sh"
    echo "Run './build.sh -h' for more information."
}

while getopts ":cChlt" options; do
    case "${options}" in
    c)
        run_build "${@}"
        exit 0
        ;;
    C)
        run_env_check="no"
        ;;
    h)
        usage
        exit 0
        ;;
    l)
        run_linters="no"
        ;;
    t)
        run_tests="no"
        ;;
    :)
        echo "Option -${OPTARG} requires an argument."
        exit 1
        ;;
    ?)
        echo "Invalid option: -${OPTARG}"
        exit 1
        ;;
    esac
done
shift "$((OPTIND - 1))"

if ! command -V docker; then
    echo "Docker not found, docker-less builds are not supported."
    exit 1
fi

setup_emulation_support

update_docker_image

if [ "${run_env_check}" = "yes" ]; then
    env_check
fi

if [ "${run_linters}" = "yes" ]; then
    run_linters
fi

run_build "${@}"

if [ "${run_tests}" = "yes" ]; then
    run_tests
fi

exit 0

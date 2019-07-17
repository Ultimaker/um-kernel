#!/bin/sh
#
# SPDX-License-Identifier: AGPL-3.0+
#
# Copyright (C) 2019 Ultimaker B.V.
#

set -eu

CI_REGISTRY_IMAGE="${CI_REGISTRY_IMAGE:-registry.gitlab.com/ultimaker/embedded/platform/um-kernel}"
CI_REGISTRY_IMAGE_TAG="${CI_REGISTRY_IMAGE_TAG:-latest}"
# Which kernel config to build.
BUILDCONFIG=${BUILDCONFIG:-opinicus}

ARCH="${ARCH:-armhf}"

PREFIX="/usr"
RELEASE_VERSION="${RELEASE_VERSION:-}"
CROSS_COMPILE="${CROSS_COMPILE:-""}"
DOCKER_WORK_DIR="${WORKDIR:-/build}"

INITRAMFS_SOURCE="${INITRAMFS_SOURCE:-initramfs/initramfs.lst}"
DEPMOD="${DEPMOD:-/sbin/depmod}"

run_env_check="yes"
run_linter="yes"
run_tests="yes"

update_docker_image()
{
    if ! docker pull "${CI_REGISTRY_IMAGE}:${CI_REGISTRY_IMAGE_TAG}" 2> /dev/null; then
        echo "Unable to update docker image '${CI_REGISTRY_IMAGE}:${CI_REGISTRY_IMAGE_TAG}', building locally instead."
        docker build . -t "${CI_REGISTRY_IMAGE}:${CI_REGISTRY_IMAGE_TAG}"
    fi
}

run_in_docker()
{
    docker run \
        --rm \
        -it \
        -u "$(id -u)" \
        -v "$(pwd):${DOCKER_WORK_DIR}" \
        -e "ARCH=${ARCH}" \
        -e "PREFIX=${PREFIX}" \
        -e "RELEASE_VERSION=${RELEASE_VERSION}" \
        -e "CROSS_COMPILE=${CROSS_COMPILE}" \
        -e "INITRAMFS_SOURCE=${INITRAMFS_SOURCE}" \
        -e "DEPMOD=${DEPMOD}" \
        -e "MAKEFLAGS=-j$(($(getconf _NPROCESSORS_ONLN) - 1))" \
        -w "${DOCKER_WORK_DIR}" \
        "${CI_REGISTRY_IMAGE}:${CI_REGISTRY_IMAGE_TAG}" \
        "${@}"
}

run_in_shell()
{
    ARCH="${ARCH}" \
    PREFIX="${PREFIX}" \
    RELEASE_VERSION="${RELEASE_VERSION}" \
    CROSS_COMPILE="${CROSS_COMPILE}" \
    INITRAMFS_SOURCE="${INITRAMFS_SOURCE}" \
    DEPMOD="${DEPMOD}" \
    eval "${@}"
}

run_script()
{
    if ! command -v docker; then
        echo "Docker not found, docker-less builds are not supported."
        echo "Are you sure you want to continue? (y/n)"
        read -r __sure
        echo ""
        if [ "${__sure}" != "y" ]; then
            exit 1
        fi

        echo "Attempting native build ..."
        run_in_shell "${@}"
    else
        run_in_docker "${@}"
    fi
}

env_check()
{
    run_script "test/buildenv_check.sh"
}

run_build()
{
    git submodule update --init --recursive
    run_script "./build.sh" "${@}"
}

run_tests()
{
    echo "There are no tests available for this repository."
}

run_linter()
{
    "./run_linter.sh"
}

usage()
{
    echo "Usage: ${0} [OPTIONS]"
    echo "  -C   Skip run of build environment checks"
    echo "  -h   Print usage"
    echo "  -l   Skip linter of shell scripts"
    echo "  -t   Skip run of tests"
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
        run_linter="no"
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

if command -V docker; then
    update_docker_image
fi

if [ "${run_env_check}" = "yes" ]; then
    env_check
fi

if [ "${run_linter}" = "yes" ]; then
    run_linter
fi

run_build "${@}"

if [ "${run_tests}" = "yes" ]; then
    run_tests
fi

exit 0

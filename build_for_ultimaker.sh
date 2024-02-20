#!/bin/bash
#
# Copyright (C) 2020 Ultimaker B.V.
#

set -eu

ARCH="${ARCH:-arm64}"
PREFIX="/usr"
RELEASE_VERSION="${RELEASE_VERSION:-999.999.999}"
DOCKER_WORK_DIR="/build"

INITRAMFS_SOURCE="${INITRAMFS_SOURCE:-initramfs/initramfs.lst}"
DEPMOD="${DEPMOD:-/sbin/depmod}"

rebuild_docker="no"
run_env_check="yes"
run_shellcheck="yes"
run_linters="yes"
run_tests="yes"
action="none"

env_check()
{
    run_in_docker "./docker_env/buildenv_check.sh"
    return
}

run_build()
{
    git submodule update --init --recursive || {
        git submodule deinit --all -f
        rm -rf .git/modules
        git submodule update --init --recursive --depth 1
    }

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
    echo "  -c   Skip run of build environment checks"
    echo "  -h   Print usage"
    echo "  -l   Skip code linting"
    echo "  -t   Skip tests"
    echo
    echo "Other options will be passed on to build.sh"
    echo "Run './build.sh -h' for more information."
}

while getopts ":cdhlsta:" options; do
    case "${options}" in
    a)
        action="${OPTARG}"
        ;;
    c)
        run_env_check="no"
        ;;
    d)
        rebuild_docker="yes"
        ;;
    h)
        usage
        exit 0
        ;;
    l)
        run_linters="no"
        ;;
    s)
        run_env_check="no"
        run_linters="no"
        run_tests="no"
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

if ! command -V docker > /dev/null; then
    echo "Docker not found, docker-less builds are not supported."
    exit 1
fi

source ./make_docker.sh um-kernel

if [[ "${rebuild_docker}" == "yes" || "${action}" == "docker_build" ]]; then
    DOCKER_IMAGE_NAME="${DOCKER_IMAGE_NAME:-um-kernel}"
    DOCKER_IMAGE_VERSION="${DOCKER_IMAGE_VERSION:-latest}"
    build_docker
fi;

case "${action}" in
    shellcheck)
        run_shellcheck
        exit 0
        ;;
    build)
        run_build
        exit 0
        ;;
    docker_build)
        exit 0
        ;;
    none)
        ;;
    ?)
        echo "Invalid action: -${OPTARG}"
        exit 1
        ;;
esac

if [ "${run_env_check}" = "yes" ]; then
    env_check
fi

if [ "${run_shellcheck}" = "yes" ]; then
    run_shellcheck
fi
    
if [ "${run_linters}" = "yes" ]; then
    run_linters
fi

if [ "${run_tests}" = "yes" ]; then
    run_tests
fi

run_build "${@}"

exit 0

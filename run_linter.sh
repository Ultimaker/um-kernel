#!/bin/sh
#
# Copyright (C) 2019 Ultimaker B.V.
#
# SPDX-License-Identifier: LGPL-3.0+

set -eu

DOCKER_WORK_DIR="${DOCKER_WORK_DIR:-/build}"
SHELLCHECK_ARGS="-x -C -f tty"

usage()
{
    echo "Usage: ${0} [OPTIONS]"
    echo "Run this repository's linter"
    echo "  -h   Print usage"
}

run_in_shell()
{
    eval "${@}"
}

run_shellcheck()
{
    if command -v "docker" 1> /dev/null; then
        SHELLCHECK_CMD="docker run \
            --rm \
            -v \"$(pwd):${DOCKER_WORK_DIR}\" \
            -w \"${DOCKER_WORK_DIR}\" \
            registry.hub.docker.com/koalaman/shellcheck:stable"
    else
        echo "You need Docker to run the shellcheck linter."
        return
    fi

    SCRIPTS="$(find "./scripts/" "./test/" -name '*.sh')"
    for shellcheck_script in "./"*".sh" ${SCRIPTS}; do
        if [ ! -r "${shellcheck_script}" ]; then
            echo "--------------------------------------------------------------------------------"
            echo "Warning, skipping shellcheck '${shellcheck_script}'."
            echo "--------------------------------------------------------------------------------"
            continue
        fi

        echo "Running shellcheck on '${shellcheck_script}'"
        eval "${SHELLCHECK_CMD}" "${SHELLCHECK_ARGS}" "${shellcheck_script}" || true
    done
}

main()
{
    while getopts ":h" options; do
        case "${options}" in
        h)
            usage
            exit 0
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

    run_shellcheck
}

main "${@}"

exit 0

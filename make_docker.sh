#!/bin/sh
# ! make_docker.sh has to be sh, not bash as the docker image that runs it does not
# include bash
#
# Copyright (C) 2021 Ultimaker B.V.

set -eu

# When releasing a new docker image, update the version below to match the one uploaded to cloudsmith
DOCKER_IMAGE_RELEASED="v1"
DOCKER_IMAGE_CACHE="ghcr.io/ultimaker/um-kernel"

set_docker_image_name_version()
{
    DOCKER_IMAGE_NAME="${DOCKER_IMAGE_NAME:-${DOCKER_IMAGE_CACHE}}"
    DOCKER_IMAGE_VERSION="${DOCKER_IMAGE_VERSION:-${DOCKER_IMAGE_RELEASED}}"
}

build_docker()
{
    set_docker_image_name_version

    echo "Building image ${DOCKER_IMAGE_NAME}:${DOCKER_IMAGE_VERSION}"
    docker build --cache-from "${DOCKER_IMAGE_CACHE}" \
                 --build-arg BUILDKIT_INLINE_CACHE=1 \
                 -f docker_env/Dockerfile -t "${DOCKER_IMAGE_NAME}:${DOCKER_IMAGE_VERSION}" .

    if ! docker run --rm --privileged "${DOCKER_IMAGE_NAME}:${DOCKER_IMAGE_VERSION}" "./buildenv_check.sh"; then
        echo "Something is wrong with the build environment, please check your Dockerfile."
        docker image rm "${DOCKER_IMAGE_NAME}"
        exit 1
    fi
}

# This section actually runs the parameters in the docker image
DOCKER_WORK_DIR="${WORKDIR:-/build}"
PREFIX="/usr"

run_in_docker()
{
    set_docker_image_name_version
    echo "Running '${*}' in docker."
    # In order to run local kernel config tools, like menuconfig, we need to attach a tty to the docker,
    # but that will fail in CI. So we first check if we have a tty and then add the "-t" argument. The
    # standart input attach ("-i") is safe to keep there, even in CI.
    terminal_arg="-i";
    if tty; then
        terminal_arg="-it"        
    fi;
    docker run \
        --rm \
        --privileged \
        "${terminal_arg}" \
        -u "$(id -u):$(id -g)" \
        -v "$(pwd):${DOCKER_WORK_DIR}" \
        -v /etc/localtime:/etc/localtime:ro \
        -v /etc/timezone:/etc/timezone:ro \
        -e "PREFIX=${PREFIX}" \
        -e "RELEASE_VERSION=${RELEASE_VERSION:-999.999.999}" \
        -e "ONLY_CHECK_STAGED=${ONLY_CHECK_STAGED:-}" \
        -e "CALLER_UID=$(id -u)" \
        -e "CALLER_GID=$(id -g)" \
        -w "${DOCKER_WORK_DIR}" \
        "${DOCKER_IMAGE_NAME}:${DOCKER_IMAGE_VERSION}" \
        "${@:-}"
}

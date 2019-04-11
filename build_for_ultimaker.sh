#!/bin/sh
#
# SPDX-License-Identifier: AGPL-3.0+
#
# Copyright (C) 2019 Ultimaker B.V.
#

set -eu

CI_REGISTRY_IMAGE="${CI_REGISTRY_IMAGE:-registry.gitlab.com/ultimaker/embedded/platform/um-kernel}"
CI_REGISTRY_IMAGE_TAG="${CI_REGISTRY_IMAGE_TAG:-latest}"

WORKDIR="${WORKDIR:-/build}"

trap cleanup EXIT

cleanup() {
	echo "Cleanup is not yet implemented."
}

git submodule update --init --recursive

if ! command -V docker; then
	echo "Docker not found, attempting native build."

	./build.sh "${@}"
	exit 0
fi

echo "Starting build using ${CI_REGISTRY_IMAGE}:${CI_REGISTRY_IMAGE_TAG}."
update_docker_image()
{
    if ! docker pull "${CI_REGISTRY_IMAGE}:${CI_REGISTRY_IMAGE_TAG}" 2> /dev/null; then
        echo "Unable to update docker image '${CI_REGISTRY_IMAGE}:${CI_REGISTRY_IMAGE_TAG}', building locally instead."
        docker build . -t "${CI_REGISTRY_IMAGE}:${CI_REGISTRY_IMAGE_TAG}"
    fi
}

update_docker_image

docker run --rm -i -t -h "$(hostname)" -u "$(id -u)" \
	   -e "MAKEFLAGS=-j$(($(getconf _NPROCESSORS_ONLN) - 1))" \
	   -v "$(pwd):${WORKDIR}" \
	   -w "${WORKDIR}" \
	   "${CI_REGISTRY_IMAGE}:${CI_REGISTRY_IMAGE_TAG}" \
	   ./build.sh "${@}"

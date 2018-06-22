#!/bin/sh
#
# SPDX-License-Identifier: AGPL-3.0+
#
# Copyright (C) 2018 Ultimaker B.V.
# Copyright (C) 2018 Olliver Schinagl <oliver@schinagl.nl>
#

CI_REGISTRY_IMAGE="${CI_REGISTRY_IMAGE:-registry.gitlab.com/olliver/um-kernel}"
CI_REGISTRY_IMAGE_TAG="${CI_REGISTRY_IMAGE_TAG:-latest}"

WORKDIR="${WORKDIR:-/build}"

set -eu

FAKE_WHOAMI="$(mktemp --suffix=.sh)"
cleanup() {
	rm "${FAKE_WHOAMI}"
}

fake_whoami() {
	cat <<- EOT > "${FAKE_WHOAMI}"
		#!/bin/sh

		if [ "\$(id -u)" -ge 1000 ]; then
		  echo "$(whoami)"
		else
		  whoami "\${@}"
		fi
	EOT

	chmod +x "${FAKE_WHOAMI}"
}

trap cleanup EXIT

git submodule update --init --recursive

if ! command -V docker; then
	echo "Docker not found, attempting native build."

	./build.sh "${@}"
	exit 0
fi

echo "Starting build using ${CI_REGISTRY_IMAGE}:${CI_REGISTRY_IMAGE_TAG}."
docker pull "${CI_REGISTRY_IMAGE}:${CI_REGISTRY_IMAGE_TAG}"
fake_whoami
docker run --rm -i -t -h "$(hostname)" -u "$(id -u)" \
	   -e "MAKEFLAGS=-j$(($(getconf _NPROCESSORS_ONLN) - 1))" \
	   -v "$(pwd):${WORKDIR}" \
	   -v "${FAKE_WHOAMI}:/usr/bin/whoami" \
	   -w "${WORKDIR}" \
	   "${CI_REGISTRY_IMAGE}:${CI_REGISTRY_IMAGE_TAG}" \
	   ./build.sh "${@}"

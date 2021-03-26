#!/bin/sh

set -eu

LINUX_DIR="/linux"

if ! [ -f /.dockerenv ]; then
	echo "ERROR: This script should only be run inside of a docker environment!"
	exit 1
fi

mkdir -p "${LINUX_DIR}"

cd "${LINUX_DIR}"

git init

git remote add origin https://github.com/Ultimaker/linux

git fetch origin 03f4a7a993691a5cd76ec0f942c15e5721d3b7ca

git reset --hard FETCH_HEAD

#!/bin/sh
#
# SPDX-License-Identifier: AGPL-3.0+
#
# Copyright (C) 2018 Ultimaker B.V.
# Copyright (C) 2018 Olliver Schinagl <oliver@schinagl.nl>
#

set -eu

git submodule update --init --recursive

./build.sh "${@}"

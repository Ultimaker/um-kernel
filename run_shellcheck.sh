#!/bin/sh
# ! run_shellcheck.sh has to be sh, not bash as the docker image that runs it does not
# include bash
#
# Copyright (C) 2019-2022 Ultimaker B.V.
#

# This script is mandatory in a repository, to make sure the shell scripts are correct and of good quality.

set -eu

SHELLCHECK_FAILURE="false"

# Add your scripts or search paths here
SHELLCHECK_PATHS=" \
*.sh \
./docker_env/*.sh \
ci/*.sh \
initramfs/*.sh
"

# shellcheck disable=SC2086
SCRIPTS="$(find ${SHELLCHECK_PATHS} -name '*.sh')"

for script in ${SCRIPTS}; do
    if [ ! -r "${script}" ]; then
        echo_line
        echo "WARNING: skipping shellcheck for '${script}'."
        echo_line
        continue
    fi

    echo "Running shellcheck on '${script}'"
    shellcheck -x -C -f tty "${script}" || SHELLCHECK_FAILURE="true"
done

if [ "${SHELLCHECK_FAILURE}" = "true" ]; then
    echo "WARNING: One or more scripts did not pass shellcheck."
    exit 1
fi

echo "All scripts passed shellcheck."

exit 0

#!/bin/sh
# shellcheck disable=SC1117

set -eu

if docker inspect --type image "${CI_REGISTRY_IMAGE}:${CI_COMMIT_SHA}" 1> /dev/null; then
  docker rmi -f "${CI_REGISTRY_IMAGE}:${CI_COMMIT_SHA}"
fi

exit 0

#!/bin/sh
# shellcheck disable=SC1117

set -eu

if [ "${CI_COMMIT_REF_NAME}" = "master" ]; then
  echo "Running on 'master' branch, comparing against previous commit..."
  CHANGES=$(git log --name-only --pretty="" origin/master...HEAD~ -- | grep "Dockerfile\|.dockerignore\|docker_env" | sort -u)
else
  echo "NOT running on 'master' branch, comparing against 'master'"
  CHANGES=$(git log --name-only --pretty="" origin/master...HEAD -- | grep "Dockerfile\|.dockerignore\|docker_env" | sort -u)
fi

if [ -n "${CHANGES}" ]; then
  echo "The following Docker-related files have changed:"
  echo "${CHANGES}"
  docker build --rm -t "${CI_REGISTRY_IMAGE}:${CI_COMMIT_SHA}" .
  if ! docker run --rm --privileged -e "ARM_EMU_BIN=${ARM_EMU_BIN}" -v "${ARM_EMU_BIN}:${ARM_EMU_BIN}:ro" "${CI_REGISTRY_IMAGE}:${CI_COMMIT_SHA}" "/test/buildenv_check.sh"; then
    echo "Something is wrong with the build environment, please check your Dockerfile."
    exit 1
  fi
  if [ "${CI_COMMIT_REF_NAME}" = "master" ]; then
    echo "Uploading new Docker image to the Gitlab registry"
    docker login -u gitlab-ci-token -p "${CI_JOB_TOKEN}" "${CI_REGISTRY}"
    docker tag  "${CI_REGISTRY_IMAGE}:${CI_COMMIT_SHA}" "${CI_REGISTRY_IMAGE}:latest"
    docker push "${CI_REGISTRY_IMAGE}:latest"
  fi
  exit 0
fi

echo "No Dockerfile changes..."
docker tag "${CI_REGISTRY_IMAGE}:latest" "${CI_REGISTRY_IMAGE}:${CI_COMMIT_SHA}"

exit 0

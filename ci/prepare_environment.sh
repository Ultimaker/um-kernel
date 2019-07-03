#!/bin/sh
if git whatchanged --name-only --pretty="" master...HEAD | grep "Dockerfile\|.dockerignore"; then
  echo "Dockerfile changes detected..."
  docker build --rm -t "${CI_REGISTRY_IMAGE}:${CI_COMMIT_SHA}" .
  docker run --rm "${CI_REGISTRY_IMAGE}:${CI_COMMIT_SHA}" "/test/buildenv_check.sh"
  exit 0
fi

echo "No Dockerfile changes..."
docker tag "${CI_REGISTRY_IMAGE}:latest" "${CI_REGISTRY_IMAGE}:${CI_COMMIT_SHA}"
exit 0

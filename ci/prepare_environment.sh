#!/bin/sh
if git whatchanged --name-only --pretty="" master...HEAD | grep "Dockerfile\|.dockerignore"; then
  echo "Dockerfile changes detected..."
  docker build --rm -t "${CI_REGISTRY_IMAGE}:${CI_COMMIT_SHA}" .
  docker run --rm "$CI_COMMIT_SHA:$CI_PIPELINE_ID" "/test/buildenv_check.sh"
else
  echo "No Dockerfile changes..."
  docker login -u gitlab-ci-token -p "${CI_JOB_TOKEN}" "${CI_REGISTRY}"
  docker tag "${CI_REGISTRY_IMAGE}:latest" "${CI_REGISTRY_IMAGE}:${CI_COMMIT_SHA}"
  docker push "${CI_REGISTRY_IMAGE}:${CI_COMMIT_SHA}"
fi
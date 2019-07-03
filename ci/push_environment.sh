#!/bin/sh
docker login -u gitlab-ci-token -p "${CI_JOB_TOKEN}" "${CI_REGISTRY}"
docker tag  "${CI_REGISTRY_IMAGE}:${CI_COMMIT_SHA}" "${CI_REGISTRY_IMAGE}:latest"
docker push "${CI_REGISTRY_IMAGE}:latest"
exit 0

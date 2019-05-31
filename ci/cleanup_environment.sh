#!/bin/sh
if git whatchanged --name-only --pretty="" master...HEAD | grep "Dockerfile\|.dockerignore"; then
  if docker inspect --type image "${CI_REGISTRY_IMAGE}:${CI_COMMIT_SHA}" 1> /dev/null; then
    docker rmi "${CI_REGISTRY_IMAGE}:${CI_COMMIT_SHA}"
  fi
fi
exit 0

#!/bin/bash

if ! ( which docker ); then
    echo "Docker not installed, unable to continue"
    exit 1
fi

REPO_ROOT=$(pwd)
PACKAGE_NAME="um-kernel"
DOCKER_IMAGE_NAME="${PACKAGE_NAME}_build"
DOCKER_CONTAINER_NAME="kernel_build"

# Initialize repositories
git submodule init
git submodule update

# Start clean
sudo rm -rf ./_build_armhf 2> /dev/null
sudo rm ./${PACKAGE_NAME}-*.deb 2> /dev/null

if [[ -n $(docker ps -l | grep ${DOCKER_CONTAINER_NAME}) ]];then
    echo "First remove the existing container"
    docker rm -f ${DOCKER_CONTAINER_NAME} > /dev/null
fi

docker build -f Dockerfile . -t ${DOCKER_IMAGE_NAME}
docker run --name ${DOCKER_CONTAINER_NAME} --privileged --cap-add=ALL -it -d -v ${REPO_ROOT}:/workspace ${DOCKER_IMAGE_NAME} bash
docker exec ${DOCKER_CONTAINER_NAME} bash -c 'cd /workspace ; ./build.sh'
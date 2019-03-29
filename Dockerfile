FROM registry.hub.docker.com/library/debian:stable-slim

LABEL Maintainer="o.schinagl@ultimaker.com" \
      Comment="Ultimaker kernel build environment"

RUN apt-get update && \
    apt-get install -y \
        bc \
        device-tree-compiler \
        fakeroot \
        gcc \
        gcc-arm-none-eabi \
        gettext \
        kmod \
        libssl-dev \
        lzop \
        make \
        ncurses-dev \
        u-boot-tools \
        wget \
        xz-utils \
    && \
    apt-get clean && \
    rm -rf /var/cache/apt/*

ENV CROSS_COMPILE="arm-none-eabi-"
COPY tests/buildenv.sh /tests/buildenv.sh

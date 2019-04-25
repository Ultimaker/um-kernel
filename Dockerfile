FROM registry.hub.docker.com/library/debian:jessie-slim

LABEL Maintainer="software-embedded-platform@ultimaker.com" \
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
COPY test/buildenv_check.sh /test/buildenv_check.sh

FROM registry.hub.docker.com/library/debian:buster-slim

LABEL Maintainer="software-embedded-platform@ultimaker.com" \
      Comment="Ultimaker kernel build environment"

RUN apt-get update && \
    apt-get install -y \
        bc \
	bison \
        bzip2 \
        curl \
        device-tree-compiler \
        flex \
        gcc \
        gcc-aarch64-linux-gnu \
        git \
        gettext \
        fakeroot \
        kmod \
        libssl-dev \
        lzop \
        make \
        ncurses-dev \
        openssh-client \
        perl \
        u-boot-tools \
        wget \
        xz-utils \
    && \
    apt-get clean && \
    rm -rf /var/cache/apt/*

COPY buildenv_check.sh buildenv_check.sh

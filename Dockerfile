FROM debian:stable-slim

RUN apt-get update && \
    apt-get install -y \
    bc \
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
    xz-utils

COPY dts /workspace/dts
COPY configs /workspace/configs
COPY initramfs /workspace/initramfs
COPY scripts/ /workspace/scripts
COPY build.sh /workspace/
COPY linux /workspace/linux

WORKDIR /workspace

ENV CROSS_COMPILE="arm-none-eabi-"
ENTRYPOINT ["./build.sh"]
CMD []

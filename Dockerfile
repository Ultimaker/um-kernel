# Download base image debian latest stable
FROM debian:latest

# Install package dependencies
RUN apt-get update && apt-get install -y curl libssl-dev bc wget lzop u-boot-tools gettext crossbuild-essential-armhf kmod

# Setup the build environment
RUN mkdir /workspace
ENV CROSS_COMPILE="arm-linux-gnueabihf-"
ENV MAKEFLAGS="-j 5"
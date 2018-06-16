[![pipeline status](https://gitlab.com/olliver/um-kernel/badges/master/pipeline.svg)](https://gitlab.com/olliver/um-kernel/commits/master)

This repository contains the Ultimaker package build script for the linux kernel

The layout of the repository is as follows.

configs
-------
The configs directory contains our kernel configuration. We currently have
just one for our Ultimaker 3 platform, opinicus.config.

dts
---
The dts directory contains our device tree's. While in the future this may be
dropped and replaced with overlays for the lime2, for now we have a full
device tree file for our Ultimaker 3 platform. There are 2 variants however,
one for eMMC based storage, and one for NAND based storage. The NAND based dts
file is a symlink for now, until all our dependencies for this package
disappear.

scripts
------
The scripts directory contains some tools and scripts for our build process.
Currently it houses the boot splash generator, which is a small utility that
generates the i2c commands to create a splashscreen on the Ultimaker 3
display.

linux
-----
This is the linux kernel source tree. Ideally, this contains no changes to the
upstream kernel. Currently we have a small amount of patches on top of the
stable linux kernel.

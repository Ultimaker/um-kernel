#!/bin/sh

set -eu

TEST_DIR=$(mktemp -d)

CROSS_COMPILE="${CROSS_COMPILE:-""}"

COMMANDS=" \
    basename \
    bc \
    bzip2 \
    cpp \
    cut \
    dtc \
    envsubst \
    gcc \
    gettext \
    grep \
    fakeroot \
    kmod \
    lzop \
    make \
    mkimage \
    mktemp \
    openssl \
    pod2html \
    pod2man \
    pod2text \
    sed \
    ssh-keyscan \
    tar \
    wget \
    xz \
"

LIBRARIES=" \
    libssl \
    libncurses \
"

result=0

echo_line(){
    echo "--------------------------------------------------------------------------------"
}

check_compiler()
{
    echo_line
    echo "Verifying if the compiler is available and working"

    if [ "${CROSS_COMPILE}" = "" ]; then
        if [ "$(command -v aarch64-linux-gnu-gcc)" != "" ]; then
            CROSS_COMPILE="aarch64-linux-gnu-"
        fi
        if [ "$(command -v arm-none-eabi-gcc)" != "" ]; then
            CROSS_COMPILE="arm-none-eabi-"
        fi
        if [ "$(command -v arm-linux-gnueabihf-gcc)" != "" ]; then
            CROSS_COMPILE="arm-linux-gnueabihf-"
        fi
        if [ "${CROSS_COMPILE}" = "" ]; then
            echo "No suiteable cross-compiler found."
            echo "One can be set explicitly via the environment variable CROSS_COMPILE='arm-linux-gnueabihf-' for example."
            result=1
            return
        else
            echo "CROSS_COMPILE was automatically set to: ${CROSS_COMPILE}"
        fi
    else
        echo "CROSS_COMPILE was manually set to: ${CROSS_COMPILE}"
    fi

    { PATH="${PATH}:/sbin:/usr/sbin:/usr/local/sbin" command -V "${CROSS_COMPILE}gcc" && \
      PATH="${PATH}:/sbin:/usr/sbin:/usr/local/sbin" command -V "${CROSS_COMPILE}objdump"; } || \
        { result=1 && return ;}

    echo "int main(void) { return 0; }" > "${TEST_DIR}/compiler_test.c"
    { "${CROSS_COMPILE}gcc" -o "${TEST_DIR}/compiler_test.o" -c "${TEST_DIR}/compiler_test.c" -Wall -Werror && \
      "${CROSS_COMPILE}objdump" -dS "${TEST_DIR}/compiler_test.o" 1> /dev/null; } || \
        { echo "The compiler does not function as expected" && result=1 && return; }

    echo "The compiler is working properly"
}

check_command_installation()
{
    for pkg in ${COMMANDS}; do
        PATH="${PATH}:/sbin:/usr/sbin:/usr/local/sbin" command -V "${pkg}" || result=1
    done
}

check_library_installation()
{
    for lib in ${LIBRARIES}; do
        echo "${lib}:"
        PATH="${PATH}:/sbin:/usr/sbin:/usr/local/sbin" ldconfig -p | grep "${lib}" || \
            { echo "        ${lib} could not be found" && result=1; }
    done
}

cleanup()
{
       if [ "$(dirname "${TEST_DIR}")" != "/tmp" ]; then
               exit 1
       fi
       rm -rf "${TEST_DIR}"
}

trap cleanup EXIT

echo_line
echo "Verifying build environment commands:"
check_command_installation
echo_line
echo "Verifying build environment libraries:"
check_library_installation
check_compiler

if [ "${result}" -ne 0 ]; then
    echo "ERROR: Missing preconditions, cannot continue."
    exit 1
fi

echo "Build environment OK"
echo_line

exit 0

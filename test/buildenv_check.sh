#!/bin/sh

set -eux

TEST_DIR=$(mktemp -d)

cleanup() {
       if [ "$(dirname "${TEST_DIR}")" != "/tmp" ]; then
               exit 1
       fi
       rm -rf "${TEST_DIR}"
}

trap cleanup EXIT

echo "Testing if the compiler works"

echo "int main(void) { return 0; }" > "${TEST_DIR}/compiler_test.c"
"${CROSS_COMPILE}gcc" -o "${TEST_DIR}/compiler_test.o" -c "${TEST_DIR}/compiler_test.c" -Wall -Werror
"${CROSS_COMPILE}objdump" -dS "${TEST_DIR}/compiler_test.o" 1> /dev/null

exit 0

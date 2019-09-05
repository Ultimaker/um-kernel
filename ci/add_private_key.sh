#!/bin/sh
# Note that because this script is run in the current shell (using `.` or `source),
# it can't have exit 0 at the end!

eval "$(ssh-agent -s)"
echo "${SSH_PRIVATE_KEY}" | tr -d '\r' | ssh-add - > /dev/null

mkdir -p ~/.ssh
chmod 700 ~/.ssh

ssh-keyscan gitlab.com >> ~/.ssh/known_hosts
chmod 644 ~/.ssh/known_hosts

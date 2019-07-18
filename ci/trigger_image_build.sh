#!/bin/sh

set -eu

if JSON=$(curl --fail -s -X POST -F "token=${TRIGGER_BUILD_TOKEN}" -F "ref=${CI_COMMIT_REF_NAME}" "https://gitlab.com/api/v4/projects/12084297/trigger/pipeline");then
  echo "${JSON}" | jq '"Started pipeline at: " + .web_url'
else
  echo "Couldn't start image build, possible reasons for this are:"
  echo " - You didn't enter a valid trigger token as TRIGGER_BUILD_TOKEN in the Gitlab CI settings for this project."
  echo " - No branch named '${CI_COMMIT_REF_NAME}' exists on jedi-build."
  echo " - '${CI_COMMIT_REF_NAME}' exists on jedi-build, but is not configured for CI (i.e., the branch has no '.gitlab-ci.yml')."
fi

exit 0

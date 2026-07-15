#!/usr/bin/env bash

set -euo pipefail

CUSTOM_IMAGE="${CUSTOM_IMAGE:-docker.io/jbarozet/nac-demo:0.2.1}"
RUNNER_NAME="${RUNNER_NAME:-Podman Runner}"
GITLAB_INTERNAL_URL="${GITLAB_INTERNAL_URL:-http://gitlab-server}"

if [[ -z "${REG_TOKEN:-}" ]]; then
  if [[ ! -t 0 ]]; then
    echo "REG_TOKEN is required when running non-interactively." >&2
    exit 1
  fi

  printf "Runner authentication token (glrt-...): " >&2
  IFS= read -r -s REG_TOKEN
  printf "\n" >&2
fi

if [[ "$REG_TOKEN" != glrt-* ]]; then
  echo "Invalid runner token: expected a value beginning with glrt-." >&2
  exit 1
fi

trap 'unset REG_TOKEN' EXIT

podman exec -i gitlab-runner gitlab-runner register \
  --non-interactive \
  --url "$GITLAB_INTERNAL_URL" \
  --token "$REG_TOKEN" \
  --executor "docker" \
  --docker-image "$CUSTOM_IMAGE" \
  --docker-pull-policy "if-not-present" \
  --description "$RUNNER_NAME" \
  --clone-url "$GITLAB_INTERNAL_URL" \
  --docker-host "unix:///var/run/docker.sock" \
  --docker-network-mode "gitlabnet" \
  --docker-volumes "/var/run/docker.sock:/var/run/docker.sock" \
  --docker-volumes "/cache"

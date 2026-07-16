#!/usr/bin/env bash

set -euo pipefail

CUSTOM_IMAGE="${CUSTOM_IMAGE:-docker.io/jbarozet/nac-demo:0.2.1}"
RUNNER_NAME="${RUNNER_NAME:-Podman Ubuntu Runner}"
RUNNER_USER="${RUNNER_USER:-gitlab-runner}"

if [[ -z "${GITLAB_URL:-}" ]]; then
  echo "GITLAB_URL is required (for example, http://192.168.64.2)." >&2
  exit 1
fi

GITLAB_URL="${GITLAB_URL%/}"

if ! command -v gitlab-runner >/dev/null 2>&1; then
  echo "gitlab-runner is not installed on this Ubuntu host." >&2
  exit 1
fi

if ! id "$RUNNER_USER" >/dev/null 2>&1; then
  echo "Runner user '$RUNNER_USER' does not exist." >&2
  exit 1
fi

RUNNER_UID="$(id -u "$RUNNER_USER")"
PODMAN_SOCKET="${PODMAN_SOCKET:-/run/user/${RUNNER_UID}/podman/podman.sock}"

if ! sudo -u "$RUNNER_USER" test -S "$PODMAN_SOCKET"; then
  echo "Podman socket not found at $PODMAN_SOCKET." >&2
  echo "Enable the rootless socket for '$RUNNER_USER' before registering." >&2
  exit 1
fi

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

sudo gitlab-runner register \
  --non-interactive \
  --url "$GITLAB_URL" \
  --token "$REG_TOKEN" \
  --executor "docker" \
  --docker-image "$CUSTOM_IMAGE" \
  --docker-pull-policy "if-not-present" \
  --description "$RUNNER_NAME" \
  --clone-url "$GITLAB_URL" \
  --env "FF_NETWORK_PER_BUILD=1" \
  --docker-host "unix://$PODMAN_SOCKET" \
  --docker-volumes "/cache"

sudo systemctl restart gitlab-runner
sudo gitlab-runner verify

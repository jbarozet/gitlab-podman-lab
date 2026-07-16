#!/usr/bin/env bash

set -euo pipefail

# Pinned lab versions can be overridden explicitly for a planned upgrade.
GITLAB_VERSION="${GITLAB_VERSION:-19.1.2-ce.0}"
RUNNER_VERSION="${RUNNER_VERSION:-19.1.1-1}"
RUNNER_HELPER_VERSION="${RUNNER_HELPER_VERSION:-$RUNNER_VERSION}"
RUNNER_USER="${RUNNER_USER:-gitlab-runner}"

# Stop before making changes unless this is an Ubuntu Linux host.
if [[ "$(uname -s)" != "Linux" ]]; then
  echo "This script must run on Ubuntu Server." >&2
  exit 1
fi

if [[ ! -r /etc/os-release ]]; then
  echo "Cannot identify the Linux distribution." >&2
  exit 1
fi

# shellcheck disable=SC1091
source /etc/os-release

if [[ "${ID:-}" != "ubuntu" ]]; then
  echo "Unsupported distribution: expected Ubuntu, found ${ID:-unknown}." >&2
  exit 1
fi

if [[ -z "${GITLAB_URL:-}" ]]; then
  echo "GITLAB_URL is required (for example, http://192.168.64.2)." >&2
  exit 1
fi

GITLAB_URL="${GITLAB_URL%/}"
GITLAB_REGISTRY_URL="${GITLAB_REGISTRY_URL:-${GITLAB_URL}:5005}"
GITLAB_REGISTRY_URL="${GITLAB_REGISTRY_URL%/}"

# Both URLs become persistent GitLab configuration, so reject ambiguous values.
case "$GITLAB_URL" in
  http://*|https://*) ;;
  *)
    echo "GITLAB_URL must begin with http:// or https://." >&2
    exit 1
    ;;
esac

case "$GITLAB_REGISTRY_URL" in
  http://*|https://*) ;;
  *)
    echo "GITLAB_REGISTRY_URL must begin with http:// or https://." >&2
    exit 1
    ;;
esac

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "$TMP_DIR"' EXIT

# Show the effective settings before the first privileged operation.
echo "Installing native GitLab lab on ${PRETTY_NAME:-Ubuntu}"
echo "GitLab URL:          $GITLAB_URL"
echo "Registry URL:        $GITLAB_REGISTRY_URL"
echo "GitLab CE version:   $GITLAB_VERSION"
echo "GitLab Runner:       $RUNNER_VERSION"
echo "Runner helpers:      $RUNNER_HELPER_VERSION"
echo
echo "The GitLab package can take a long time to configure."
echo "Do not interrupt apt or start another apt process."

# Ubuntu images can default official repositories to HTTP, but some networks
# block or time out port 80. Use HTTPS for ports.ubuntu.com on ARM64 and the
# archive/security repositories on amd64. Ubuntu 24.04 normally uses
# ubuntu.sources; sources.list supports older layouts.
APT_SOURCE_FILES=(
  /etc/apt/sources.list.d/ubuntu.sources
  /etc/apt/sources.list
)
APT_SOURCE_BACKUP_DIR="/var/backups/gitlab-podman-lab"

for apt_source_file in "${APT_SOURCE_FILES[@]}"; do
  if [[ ! -f "$apt_source_file" ]]; then
    continue
  fi

  # Move backups created by an earlier script version out of APT's source path.
  legacy_apt_source_backup="${apt_source_file}.before-gitlab-podman-lab"
  apt_source_backup="$APT_SOURCE_BACKUP_DIR/$(basename "$apt_source_file")"

  if [[ -f "$legacy_apt_source_backup" ]]; then
    sudo install -d -m 0755 "$APT_SOURCE_BACKUP_DIR"
    if [[ -e "$apt_source_backup" ]]; then
      apt_source_backup="${apt_source_backup}.legacy"
    fi
    sudo mv "$legacy_apt_source_backup" "$apt_source_backup"
  fi

  if sudo grep -Eq \
    'http://(ports\.ubuntu\.com/ubuntu-ports|archive\.ubuntu\.com/ubuntu|security\.ubuntu\.com/ubuntu)' \
    "$apt_source_file"; then
    apt_source_backup="$APT_SOURCE_BACKUP_DIR/$(basename "$apt_source_file")"

    # Keep one copy of the distribution-provided repository configuration.
    if [[ ! -e "$apt_source_backup" ]]; then
      sudo install -d -m 0755 "$APT_SOURCE_BACKUP_DIR"
      sudo cp --preserve=mode,ownership,timestamps \
        "$apt_source_file" "$apt_source_backup"
    fi

    echo "Changing official Ubuntu repositories to HTTPS in $apt_source_file."
    sudo sed -i \
      -e 's|http://ports.ubuntu.com/ubuntu-ports|https://ports.ubuntu.com/ubuntu-ports|g' \
      -e 's|http://archive.ubuntu.com/ubuntu|https://archive.ubuntu.com/ubuntu|g' \
      -e 's|http://security.ubuntu.com/ubuntu|https://security.ubuntu.com/ubuntu|g' \
      "$apt_source_file"
  fi
done

# IPv4-only APT is opt-in for networks with broken IPv6 connectivity.
APT_UPDATE_OPTIONS=(--error-on=any)

if [[ "${APT_FORCE_IPV4:-0}" == "1" ]]; then
  echo "Forcing IPv4 for APT repository access."
  APT_UPDATE_OPTIONS=(-o Acquire::ForceIPv4=true "${APT_UPDATE_OPTIONS[@]}")
fi

# Fail instead of letting APT continue with stale indexes after a mirror error.
if ! sudo apt-get update "${APT_UPDATE_OPTIONS[@]}"; then
  echo "Ubuntu package indexes could not be downloaded." >&2
  echo "Check the VM's internet connection and configured APT mirrors." >&2
  exit 1
fi
sudo apt-get install -y ca-certificates curl openssh-server
sudo systemctl enable --now ssh

# Install the pinned GitLab CE Linux package from GitLab's official repository.
curl --fail --location --show-error --silent \
  "https://packages.gitlab.com/install/repositories/gitlab/gitlab-ce/script.deb.sh" \
  --output "$TMP_DIR/gitlab-ce-repository.sh"
sudo bash "$TMP_DIR/gitlab-ce-repository.sh"

sudo env EXTERNAL_URL="$GITLAB_URL" \
  apt-get install -y "gitlab-ce=$GITLAB_VERSION"
sudo apt-mark hold gitlab-ce

# Add the lab registry settings once and preserve existing administrator values.
if sudo grep -Eq '^[[:space:]]*registry_external_url[[:space:]]' \
  /etc/gitlab/gitlab.rb; then
  echo "Keeping the existing registry_external_url in /etc/gitlab/gitlab.rb."
else
  printf "\n# GitLab Podman lab registry\n" | sudo tee -a \
    /etc/gitlab/gitlab.rb >/dev/null
  printf "gitlab_rails['registry_enabled'] = true\n" | sudo tee -a \
    /etc/gitlab/gitlab.rb >/dev/null
  printf "registry_external_url '%s'\n" "$GITLAB_REGISTRY_URL" | sudo tee -a \
    /etc/gitlab/gitlab.rb >/dev/null
fi

sudo gitlab-ctl reconfigure

# Install the native Runner, its exactly matched helpers, and rootless Podman.
curl --fail --location --show-error --silent \
  "https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.deb.sh" \
  --output "$TMP_DIR/gitlab-runner-repository.sh"
sudo bash "$TMP_DIR/gitlab-runner-repository.sh"

sudo apt-get install -y \
  "gitlab-runner=$RUNNER_VERSION" \
  "gitlab-runner-helper-images=$RUNNER_HELPER_VERSION" \
  dbus-user-session podman uidmap
sudo apt-mark hold gitlab-runner gitlab-runner-helper-images

RUNNER_UID="$(id -u "$RUNNER_USER")"

# Rootless Podman needs subordinate IDs that do not overlap existing ranges.
if ! grep -q "^${RUNNER_USER}:" /etc/subuid || \
   ! grep -q "^${RUNNER_USER}:" /etc/subgid; then
  SUBID_START="$(
    awk -F: '
      BEGIN { next_id = 100000 }
      NF >= 3 {
        range_end = $2 + $3
        if (range_end > next_id) {
          next_id = range_end
        }
      }
      END { print next_id }
    ' /etc/subuid /etc/subgid
  )"
  SUBID_END="$((SUBID_START + 65535))"

  echo "Assigning subordinate IDs $SUBID_START-$SUBID_END to $RUNNER_USER."

  if ! grep -q "^${RUNNER_USER}:" /etc/subuid; then
    sudo usermod --add-subuids "$SUBID_START-$SUBID_END" "$RUNNER_USER"
  fi

  if ! grep -q "^${RUNNER_USER}:" /etc/subgid; then
    sudo usermod --add-subgids "$SUBID_START-$SUBID_END" "$RUNNER_USER"
  fi
fi

# Linger keeps the Runner user's services active without a login session. Start
# its user manager now as well; linger otherwise guarantees it only after boot.
sudo loginctl enable-linger "$RUNNER_USER"
sudo systemctl start "user@${RUNNER_UID}.service"

RUNNER_RUNTIME_DIR="/run/user/$RUNNER_UID"
RUNNER_BUS="$RUNNER_RUNTIME_DIR/bus"

# The user manager can report active just before its bus socket appears. Use
# sudo because another user's /run/user/<uid> directory is intentionally 0700.
for _ in {1..20}; do
  if sudo test -S "$RUNNER_BUS"; then
    break
  fi
  sleep 0.25
done

# A manager started before dbus-user-session was ready must reload its units.
# Restart only when necessary so rerunning the installer does not disrupt jobs.
if ! sudo test -S "$RUNNER_BUS"; then
  echo "Restarting the $RUNNER_USER systemd user manager to create its bus."
  sudo systemctl restart "user@${RUNNER_UID}.service"

  for _ in {1..20}; do
    if sudo test -S "$RUNNER_BUS"; then
      break
    fi
    sleep 0.25
  done
fi

if ! sudo test -S "$RUNNER_BUS"; then
  echo "The systemd user bus was not created at $RUNNER_BUS." >&2
  exit 1
fi

sudo -u "$RUNNER_USER" \
  env XDG_RUNTIME_DIR="$RUNNER_RUNTIME_DIR" \
  DBUS_SESSION_BUS_ADDRESS="unix:path=$RUNNER_BUS" \
  systemctl --user enable --now podman.socket

PODMAN_SOCKET="$RUNNER_RUNTIME_DIR/podman/podman.sock"

# Confirm both the socket file and the Podman-compatible API are operational.
if ! sudo -u "$RUNNER_USER" test -S "$PODMAN_SOCKET"; then
  echo "Podman socket was not created at $PODMAN_SOCKET." >&2
  exit 1
fi

if [[ "$(
  cd /tmp
  sudo -u "$RUNNER_USER" \
    curl --fail --silent --show-error \
    --unix-socket "$PODMAN_SOCKET" \
    http://localhost/_ping
)" != "OK" ]]; then
  echo "Podman did not respond through $PODMAN_SOCKET." >&2
  exit 1
fi

# Leave the operator with the UI and registration steps that require a token.
echo
echo "Installation complete."
echo "GitLab status:"
sudo gitlab-ctl status
echo
echo "Next steps:"
echo "1. Open $GITLAB_URL and sign in as root."
echo "2. Read the temporary password with:"
echo "   sudo grep 'Password:' /etc/gitlab/initial_root_password"
echo "3. Create a Runner authentication token in GitLab."
echo "4. Register it with:"
echo "   GITLAB_URL='$GITLAB_URL' bash scripts/register_runner_ubuntu.sh"

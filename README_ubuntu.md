# Native Ubuntu Server Setup

This guide installs GitLab CE and GitLab Runner directly on Ubuntu Server.
Podman remains rootless and is used only to create isolated CI job containers.
This avoids nesting the Runner inside another rootless container.
See [README.md](README.md) for the cross-platform architecture overview.

## Architecture

```text
Ubuntu Server
├── GitLab CE 19.1.2 Linux package
├── GitLab Runner 19.1.1 Linux package
└── rootless Podman owned by gitlab-runner
    └── short-lived CI job containers
```

Use Ubuntu 24.04 on `amd64` or `arm64`. GitLab publishes native Linux packages
for both architectures. The commands below describe a fresh lab; they do not
migrate data from the macOS container installation.

## 1. Clone the repository

Check whether Git is already available:

```console
git --version
```

If that command is not found, install Git:

```console
sudo apt-get update --error-on=any
sudo apt-get install -y git
```

If APT cannot reach the Ubuntu repositories, follow the
[HTTPS repository workaround](#apt-cannot-reach-ubuntu-repositories), then
retry the commands above.

Clone this repository over HTTPS so the new server does not require a GitHub
SSH key:

```console
git clone https://github.com/jbarozet/gitlab-podman-lab.git
cd gitlab-podman-lab
```

All remaining commands assume the current directory is the repository root.

## 2. Choose the URLs

Use a resolvable DNS name when possible. A fixed LAN address also works for an
isolated test. Do not use `localhost`, because CI job containers must reach the
server through this address.

```console
export GITLAB_URL="http://gitlab.example.test"
export GITLAB_REGISTRY_URL="http://gitlab.example.test:5005"
```

For a server without DNS, use its IP address in both URLs. For example:

```console
export GITLAB_URL="http://192.168.64.2"
export GITLAB_REGISTRY_URL="http://192.168.64.2:5005"
```

Do not include a trailing slash in either URL.

## 3. Automated installation

On a fresh Ubuntu Server, the installer automates the steps documented in
sections 4.1 and 4.2: it adds the official GitLab repositories, installs and
holds the pinned GitLab CE and Runner packages, enables the registry, installs
Podman, and creates the Runner's rootless socket. Before its first APT update,
it changes official Ubuntu repository URLs from HTTP to HTTPS and preserves a
backup of the original source configuration.

Review [scripts/install_ubuntu.sh](scripts/install_ubuntu.sh), then run it from
the repository root after defining the URLs above:

```console
bash scripts/install_ubuntu.sh
```

The GitLab package can take a long time to configure. Run the installer inside
`tmux` when an SSH interruption is possible. The script is safe to rerun when
the pinned packages are already installed, but it does not upgrade across
GitLab versions or replace an existing registry URL.

After it succeeds, complete the [initial GitLab sign-in](#5-initial-gitlab-sign-in),
then continue at [Register the Runner](#6-register-the-runner). The manual steps
below document exactly what the script performs and remain the preferred
troubleshooting reference.

## 4. Manual Installation (if automation script not used)

### 4.1 Install the pinned GitLab CE package

Install the prerequisites and enable SSH:

```console
sudo apt-get update --error-on=any
sudo apt-get install -y ca-certificates curl openssh-server
sudo systemctl enable --now ssh
```

Add GitLab's CE repository, inspect the downloaded script if required by local
policy, and install the pinned server release:

```console
curl --location \
  "https://packages.gitlab.com/install/repositories/gitlab/gitlab-ce/script.deb.sh" \
  --output /tmp/gitlab-ce-repository.sh
less /tmp/gitlab-ce-repository.sh
sudo bash /tmp/gitlab-ce-repository.sh
sudo EXTERNAL_URL="$GITLAB_URL" apt-get install -y gitlab-ce=19.1.2-ce.0
sudo apt-mark hold gitlab-ce
```

Enable the lab registry by adding these lines to `/etc/gitlab/gitlab.rb`:

```ruby
gitlab_rails['registry_enabled'] = true
registry_external_url 'http://gitlab.example.test:5005'
```

Use the actual value of `GITLAB_REGISTRY_URL`, then apply the configuration:

```console
sudo editor /etc/gitlab/gitlab.rb
sudo gitlab-ctl reconfigure
sudo gitlab-ctl status
```

If UFW is enabled, allow only the trusted management subnet. Replace the
example subnet before running these commands:

```console
sudo ufw allow from 192.0.2.0/24 to any port 22 proto tcp
sudo ufw allow from 192.0.2.0/24 to any port 80 proto tcp
sudo ufw allow from 192.0.2.0/24 to any port 5005 proto tcp
```

### 4.2 Install the pinned native Runner and Podman

Add the official Runner repository and install the pinned release:

```console
curl --location \
  "https://packages.gitlab.com/install/repositories/runner/gitlab-runner/script.deb.sh" \
  --output /tmp/gitlab-runner-repository.sh
less /tmp/gitlab-runner-repository.sh
sudo bash /tmp/gitlab-runner-repository.sh
sudo apt-get install -y \
  gitlab-runner=19.1.1-1 \
  gitlab-runner-helper-images=19.1.1-1 \
  dbus-user-session podman uidmap
sudo apt-mark hold gitlab-runner gitlab-runner-helper-images
```

GitLab Runner requires the helper-images package at the exact same version.
Pinning both prevents APT from selecting a newer helper package that cannot
satisfy the Runner dependency. The `dbus-user-session` package provides the
systemd user bus needed to manage the rootless Podman socket without an
interactive login.

The package creates the dedicated `gitlab-runner` account. First check whether
the account has subordinate UID and GID ranges:

```console
RUNNER_UID="$(id -u gitlab-runner)"
grep '^gitlab-runner:' /etc/subuid /etc/subgid
```

The `grep` command must show subordinate UID and GID ranges for the account.
If it returns nothing on a fresh system, calculate the next unused range and
assign it to `gitlab-runner` before enabling linger:

```console
SUBID_START="$(
  awk -F: '
    BEGIN { next_id = 100000 }
    NF >= 3 {
      range_end = $2 + $3
      if (range_end > next_id) next_id = range_end
    }
    END { print next_id }
  ' /etc/subuid /etc/subgid
)"
SUBID_END="$((SUBID_START + 65535))"
sudo usermod \
  --add-subuids "$SUBID_START-$SUBID_END" \
  --add-subgids "$SUBID_START-$SUBID_END" \
  gitlab-runner
grep '^gitlab-runner:' /etc/subuid /etc/subgid
```

The installer performs this allocation automatically. Do not reuse a range
already assigned to another account.

Enable the rootless Podman socket and keep the Runner user's systemd manager
running after logout:

```console
sudo loginctl enable-linger gitlab-runner
sudo systemctl restart "user@${RUNNER_UID}.service"
sudo -u gitlab-runner \
  XDG_RUNTIME_DIR="/run/user/$RUNNER_UID" \
  DBUS_SESSION_BUS_ADDRESS="unix:path=/run/user/$RUNNER_UID/bus" \
  systemctl --user enable --now podman.socket
```

Verify the socket and Podman engine as the same account that runs jobs:

```console
(
  cd /tmp
  sudo -u gitlab-runner \
    XDG_RUNTIME_DIR="/run/user/$RUNNER_UID" \
    test -S "/run/user/$RUNNER_UID/podman/podman.sock"
  sudo -u gitlab-runner \
    XDG_RUNTIME_DIR="/run/user/$RUNNER_UID" \
    podman info
)
```

The subshell runs these checks from `/tmp`. Without it, `sudo` preserves the
current directory, and `gitlab-runner` may be unable to enter a repository
inside another user's home directory.

If the user bus is still unavailable, inspect
`systemctl status "user@${RUNNER_UID}.service"` and the system journal. Do not
replace the rootless socket with a world-writable socket.

## 5. Initial GitLab sign-in

On the Ubuntu machine, read the generated administrator password:

```console
sudo grep 'Password:' /etc/gitlab/initial_root_password
```

Open `GITLAB_URL` and sign in with:

- Username: `root`
- Password: the generated value shown by this command:

Replace the generated password immediately after signing in:

1. In the upper-right corner, select **Admin**.
2. In the left sidebar, select **Overview > Users**.
3. Find **Administrator** (username `root`) and select **Edit**.
4. In the **Password** section, enter and confirm a new password, then save the
   changes.

Update the root email address from the profile settings as well. GitLab
automatically removes the initial-password file after 24 hours. If that file no
longer exists, reset the root password interactively from the Ubuntu machine:

```console
sudo gitlab-rake "gitlab:password:reset[root]"
```

## 6. Register the Runner

In GitLab, open **Admin > CI/CD > Runners**, create an instance runner, enable
**Run untagged jobs**, and copy the authentication token beginning with
`glrt-`. From this repository, run:

```console
GITLAB_URL="$GITLAB_URL" bash scripts/register_runner_ubuntu.sh
```

The registration script securely prompts for the token. It configures the
Docker executor to use the rootless Podman socket directly, enables per-job
networks, and mounts only `/cache` into jobs. The socket itself must not be
included in the job `volumes` list.

Verify the native service and effective configuration:

```console
sudo systemctl status gitlab-runner
sudo gitlab-runner verify
sudo grep -nE '^[[:space:]]*(host|volumes)[[:space:]]*=' \
  /etc/gitlab-runner/config.toml
```

The configuration should contain a host under `/run/user/<uid>/podman/` and:

```toml
volumes = ["/cache"]
```

## 7. Run the smoke test

Follow [the smoke-test guide](smoke-test/README.md). A successful pipeline
confirms that the native Runner can pull the multi-architecture job image and
create a job container through rootless Podman.

## Operations

### APT cannot reach Ubuntu repositories

Ubuntu images can configure official repositories over HTTP. ARM64 normally
uses `ports.ubuntu.com`, while amd64 uses `archive.ubuntu.com` and
`security.ubuntu.com`. If HTTP port 80 times out, change these official Ubuntu
24.04 repository URLs to HTTPS:

```console
sudo install -d -m 0755 /var/backups/gitlab-podman-lab
sudo cp /etc/apt/sources.list.d/ubuntu.sources \
  /var/backups/gitlab-podman-lab/ubuntu.sources
sudo sed -i \
  -e 's|http://ports.ubuntu.com/ubuntu-ports|https://ports.ubuntu.com/ubuntu-ports|g' \
  -e 's|http://archive.ubuntu.com/ubuntu|https://archive.ubuntu.com/ubuntu|g' \
  -e 's|http://security.ubuntu.com/ubuntu|https://security.ubuntu.com/ubuntu|g' \
  /etc/apt/sources.list.d/ubuntu.sources
sudo apt-get update --error-on=any
```

If the HTTPS update also fails, fix the VM's network connection before running
the installer again. In UTM, the VM needs an enabled network adapter with
outbound access, such as **Shared Network**.

Only if HTTPS still fails because of broken IPv6 connectivity, retry APT with a
per-command IPv4 override:

```console
sudo apt-get \
  -o Acquire::ForceIPv4=true \
  update --error-on=any
```

If that override is required, run the installer with the equivalent opt-in
setting. Do not configure IPv4-only operation globally on a server whose IPv6
connectivity works.

```console
APT_FORCE_IPV4=1 bash scripts/install_ubuntu.sh
```

Use the native service tools instead of Compose:

```console
sudo gitlab-ctl status
sudo gitlab-ctl restart
sudo systemctl status gitlab-runner
sudo systemctl restart gitlab-runner
sudo journalctl -u gitlab-runner --follow
```

GitLab configuration, data, and logs live under `/etc/gitlab`,
`/var/opt/gitlab`, and `/var/log/gitlab`. Back them up before upgrades. Keep the
packages held until the required GitLab upgrade path has been reviewed:

```console
apt-mark showhold
```

## References

- [Install GitLab using the Linux package](https://docs.gitlab.com/install/package/)
- [Install GitLab Runner from the Linux repository](https://docs.gitlab.com/runner/install/linux-repository/)
- [Use Podman with the Docker executor](https://docs.gitlab.com/runner/executors/docker/#use-podman-to-run-docker-commands)
- [GitLab installation requirements](https://docs.gitlab.com/install/requirements/)

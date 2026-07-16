# Podman and Podman Compose Guide

This reusable guide covers installing Podman, configuring Podman Machine, running Compose projects, and optional Docker-compatible socket access.

## Contents

- [Overview](#overview)
- [Requirements](#requirements)
- [Install Podman](#install-podman)
- [Install `podman-compose`](#install-podman-compose)
- [Podman Compose notice](#podman-compose-notice)
- [Configure Podman Machine](#configure-podman-machine)
- [Run a Compose project](#run-a-compose-project)
- [Useful commands](#useful-commands)
- [Update a Compose project](#update-a-compose-project)
- [Reset an exposed GitLab Runner token](#reset-an-exposed-gitlab-runner-token)
- [Docker-compatible socket reference](#docker-compatible-socket-reference)

## Overview

[Podman](https://podman.io/) is a daemonless container engine with a Docker-compatible command-line experience. Podman runs containers directly on Linux. On macOS and Windows, it runs Linux containers in a lightweight virtual machine managed by `podman machine`.

## Requirements

- A host with Internet access.
- A recent Podman release.
- A Compose provider such as `podman-compose` when running Compose projects.

Check the installation with:

```console
podman --version
podman compose version
```

## Install Podman

Follow the [official Podman installation guide](https://podman.io/docs/installation) for current platform-specific instructions.

### macOS

Use the official Podman installer rather than Homebrew. Podman's installation guide recommends against Homebrew because it does not guarantee matched versions of Podman and its helper binaries (`krunkit`, `gvproxy`, and `vfkit`).

1. Download the CLI installer from the [Podman releases page](https://github.com/containers/podman/releases/latest). Choose `podman-installer-macos-<arch>.pkg`, or the universal build.
2. Run the `.pkg` installer.
3. Open a new terminal, then follow
   [Install `podman-compose`](#install-podman-compose).

Create the Linux VM and verify the installation:

```console
podman machine init --now
podman info
```

If Podman was previously installed with Homebrew, remove it first to avoid conflicting executables on `PATH`:

```console
brew uninstall --ignore-dependencies podman
brew uninstall krunkit   # If installed separately
```

### Windows

Install Podman with the Windows installer from the
[Podman releases page](https://github.com/containers/podman/releases), then
follow [Install `podman-compose`](#install-podman-compose).

Podman uses a WSL 2-backed machine by default. Initialize it and verify the installation:

```powershell
podman machine init --now
podman info
```

### Linux

Install Podman from the distribution repositories. Add `podman-compose` only
when the Linux host must run a Compose project; the native Ubuntu workflow in
this repository does not require it. For example:

```console
# Debian or Ubuntu
sudo apt-get update
sudo apt-get install podman uidmap

# Fedora
sudo dnf install podman
```

Linux does not normally require `podman machine`. For a rootless service on Ubuntu Server, enable the per-user API socket and keep it running after logout:

```console
systemctl --user enable --now podman.socket
sudo loginctl enable-linger "$USER"
test -S "/run/user/$(id -u)/podman/podman.sock"
```

Run rootless Podman as the same regular user each time; mixing `podman` and
`sudo podman` uses separate storage. Verify the installation with
`podman --version`. If Compose was installed, also check
`podman compose version`.

### Optional: Podman Desktop

[Podman Desktop](https://podman-desktop.io/) provides a graphical interface for managing containers, images, volumes, and Podman machines. It is optional; all commands in this guide work with the Podman CLI alone.

## Install `podman-compose`

`podman compose` (with a space) is a dispatcher included in Podman 4 and later.
It delegates Compose operations to an installed provider, such as
`docker compose`, `docker-compose`, or `podman-compose`. `podman-compose` is a
cross-platform Python provider that runs Compose files through Podman without
requiring Docker Desktop or the Docker daemon.

### macOS

Install `uv`, then install `podman-compose` in an isolated tool environment:

```console
brew install uv
uv tool install podman-compose
uv tool update-shell
```

Using Homebrew for `uv` does not replace the Podman installer or its helper
binaries. Alternatively, install `uv` with its
[official standalone installer](https://docs.astral.sh/uv/getting-started/installation/).
Open a new terminal, then verify:

```console
podman-compose --version
podman compose version
```

### Ubuntu

Ubuntu provides `podman-compose` in its package repository:

```console
sudo apt-get update
sudo apt-get install -y podman-compose
podman-compose --version
podman compose version
```

Ubuntu 24.04 packages `podman-compose` 1.0.6, which can lag behind the upstream
stable release. If a Compose project needs a newer provider, install it in an
isolated `uv` environment instead of modifying Ubuntu's system Python:

```console
curl -LsSf https://astral.sh/uv/install.sh | sh
uv tool install podman-compose
uv tool update-shell
```

Open a new login shell and use `command -v podman-compose` to confirm which
installation is selected. The native Ubuntu architecture in this repository
does not require Compose; these instructions are for other Compose projects.

### Windows

Install `uv` with WinGet, then install `podman-compose`:

```powershell
winget install --id=astral-sh.uv -e
uv tool install podman-compose
uv tool update-shell
```

Open a new PowerShell window and verify:

```powershell
podman-compose --version
podman compose version
```

If WinGet is unavailable, use the Windows command from the
[official `uv` installation guide](https://docs.astral.sh/uv/getting-started/installation/).

## Podman Compose notice

The notice below is informational and identifies the selected provider:

```text
>>>> Executing external compose provider "/path/to/provider". <<<<
```

If more than one provider is installed, select one for the current shell with:

```console
export PODMAN_COMPOSE_PROVIDER=podman-compose
```

## Configure Podman Machine

Podman Machine applies only to macOS and Windows. To set resources during initial setup, use:

```console
podman machine init --cpus 4 --memory 4096 --disk-size 40 --now
```

Choose values for the workload. The virtual disk stores container images and named volumes, so allow additional space for persistent application data.

To change an existing machine where the selected machine provider supports resource updates, stop it first:

```console
podman machine stop
podman machine set --cpus 4 --memory 4096
podman machine start
```

CPU, memory, and disk resizing support depends on the machine provider; disk size can only be increased. If the current provider does not support a requested change, recreate the machine with the desired `init` options. Removing a machine deletes its containers, images, and volumes, so back up required data first.

Inspect the machine and connection with:

```console
podman machine list
podman machine inspect
podman system connection list
podman info
```

Start and stop the VM with `podman machine start` and `podman machine stop`.

## Run a Compose project

From the directory containing `docker-compose.yml` or `compose.yml`:

```console
# macOS and Windows only; skip on Linux
podman machine start

podman compose config
podman compose up --build --detach
```

Use `podman compose up --build --detach` for the first deployment and after changing the image, dependencies, `Dockerfile`, or Compose configuration. Podman recognizes conventional Compose filenames, so they do not need to be renamed.

To stop and later restart the existing containers without rebuilding them:

```console
podman compose stop
podman compose start
```

## Update a Compose project

Update the project files using their normal source-control or release process, then pull images and recreate changed services:

```console
podman compose pull
podman compose up --build --detach
```

> **Warning:** `podman compose down --volumes` permanently deletes Compose-managed named volumes. Use it only when persistent application data should be removed.

## Reset an exposed GitLab Runner token

On macOS, this repository stores Runner configuration in the `gitlab-runner`
container's mounted configuration directory. If its `glrt-...` authentication
token is displayed, pasted into a message, committed, or otherwise exposed,
reset it from the container:

```console
podman exec gitlab-runner \
  gitlab-runner reset-token --name "Podman Runner"
```

The command uses the current token to request a replacement from GitLab and
updates the local `config.toml`. Do not share its output. Verify the replacement
without displaying the token:

```console
podman exec gitlab-runner gitlab-runner verify
```

On native Ubuntu, use the installed Runner directly:

```console
sudo gitlab-runner reset-token --name "Podman Ubuntu Runner"
sudo gitlab-runner verify
```

Avoid sharing the output of `gitlab-runner list`; current Runner releases can
include the complete authentication token. If resetting fails, delete the
Runner in the GitLab UI, create a replacement, and register it with the new
token. See GitLab's
[authentication token security guidance](https://docs.gitlab.com/ci/runners/configure_runners/#authentication-token-security).

## Docker-compatible socket reference

The Podman CLI does not require a conventional Docker socket. External Compose providers and other Docker-compatible tools may require one, depending on how they are invoked. First check the machine and connection on macOS or Windows:

```console
podman machine list
podman system connection list
podman info
```

Docker-compatible socket access is needed only when a host tool is hard-coded to use `/var/run/docker.sock`, or when a trusted container must control other containers.

> **Security warning:** Socket access grants control over the containers, images, volumes, and host paths available to the Podman engine. Expose or mount it only for trusted tools and containers. Never expose the API over an unauthenticated TCP connection.

### macOS

Podman Machine forwards its API socket to macOS. The forwarded path can change, so do not create a permanent link to the temporary path reported by `podman machine inspect`.

For tools that require `/var/run/docker.sock`, install the Podman helper and restart the machine:

```console
sudo podman-mac-helper install
podman machine stop
podman machine start
```

Verify it with:

```console
ls -l /var/run/docker.sock
curl --unix-socket /var/run/docker.sock http://localhost/_ping
```

The `curl` command should return `OK`. If Podman Desktop is installed, the same feature is available under **Settings > Docker Compatibility > Third-Party Docker Tool Compatibility**.

Applications that honor `DOCKER_HOST` can instead use the default Podman Machine socket directly. Adjust the path for non-default machine names or providers:

```console
export DOCKER_HOST="unix://${HOME}/.local/share/containers/podman/machine/podman.sock"
```

### Linux

Enable the rootless user socket and direct Docker-compatible tools to it:

```console
systemctl --user enable --now podman.socket
export DOCKER_HOST="unix://${XDG_RUNTIME_DIR}/podman/podman.sock"
```

For a rootful Podman service, use the system socket:

```console
sudo systemctl enable --now podman.socket
export DOCKER_HOST="unix:///run/podman/podman.sock"
```

Verify either configuration with `podman info` and, if the Docker CLI is installed, `docker info`.

In this repository's native Ubuntu workflow, the packaged `gitlab-runner`
service uses a socket owned by the `gitlab-runner` account. See
[README_ubuntu.md](../README_ubuntu.md) for the dedicated-user setup.
The `.env` socket setting applies only to the macOS Compose stack.

### Windows

Podman Machine exposes its API through a Windows named pipe. With Podman Desktop:

1. Open **Settings > Docker Compatibility**.
2. Enable Docker compatibility.
3. Select the Podman machine as the Docker CLI context.
4. Verify the connection with `podman info` and, if installed, `docker info`.

The conventional Docker-compatible named pipe is `npipe:////./pipe/docker_engine`.

### Give a container access to Podman

A container that must control the engine needs the Podman socket mounted at the path expected by its client. For a rootful engine, a Compose service can use:

```yaml
volumes:
  - /run/podman/podman.sock:/var/run/docker.sock
```

Rootless Podman uses `/run/user/<uid>/podman/podman.sock`. The container process
must have permission to read and write the mounted socket. The macOS Compose
stack maps its Podman Machine socket to `/var/run/docker.sock` inside the
containerized runner. Native Ubuntu Runner connects directly to its rootless
socket and does not mount that socket into CI job containers.

For more information, see the [`podman compose` documentation](https://docs.podman.io/en/stable/markdown/podman-compose.1.html), [`podman machine set` documentation](https://docs.podman.io/en/stable/markdown/podman-machine-set.1.html), Podman Desktop's [Docker compatibility documentation](https://podman-desktop.io/docs/migrating-from-docker/managing-docker-compatibility), and the [Podman service documentation](https://docs.podman.io/en/latest/markdown/podman-system-service.1.html).

## Useful commands

This section is the compact operations reference for the lab.

### Machine and connection

These commands apply to macOS and Windows:

```console
podman machine list
podman machine start
podman machine inspect
podman system connection list
podman info
podman machine stop
```

Rootless and rootful connections use separate container storage. Do not switch
a working lab between them unless recreating its containers and images is
intentional.

### Containers, images, networks, and storage

```console
# Containers
podman ps
podman ps --all
podman logs --follow gitlab
podman exec -it gitlab bash

# Images
podman images
podman image inspect <image:tag>
podman run --rm -it <image:tag> sh

# Networks
podman network ls
podman network inspect gitlabnet

# Storage usage
podman system df
```

### macOS Compose lifecycle

Prefer Compose over removing named lab containers individually:

```console
# Validate and start
podman compose config
podman compose up --detach

# Inspect and follow logs
podman compose ps
podman compose logs --follow
podman compose logs --follow <service-name>

# Preserve containers during a routine stop
podman compose stop
podman compose start

# Remove containers and the Compose network
podman compose down
```

Persistent GitLab files under `data/` survive `podman compose down`. Do not use
`podman compose down --volumes` when preserving data matters.

### Build and inspect the CI job image

```console
cd custom-image
./build.sh
podman run --rm nac-demo:latest terraform --version
```

See [custom-image/README.md](../custom-image/README.md) for native and
cross-platform builds and multi-architecture publishing.

### Verify Runner socket access

On macOS:

```console
podman machine ssh podman-machine-default \
  test -S /run/podman/podman.sock
podman exec gitlab-runner test -S /var/run/docker.sock
podman exec gitlab-runner \
  curl --fail --silent --show-error \
  --unix-socket /var/run/docker.sock \
  http://localhost/_ping
```

On native Ubuntu:

```console
RUNNER_UID="$(id -u gitlab-runner)"
sudo -u gitlab-runner \
  XDG_RUNTIME_DIR="/run/user/$RUNNER_UID" \
  test -S "/run/user/$RUNNER_UID/podman/podman.sock"
sudo gitlab-runner verify
sudo grep -nE '^[[:space:]]*(host|volumes)[[:space:]]*=' \
  /etc/gitlab-runner/config.toml
```

The Ubuntu Runner host must point to its rootless socket, and its job volumes
must be `["/cache"]`.

### Common failures

- If `podman compose` cannot find a provider on macOS, install
  `podman-compose` or enable Compose support in Podman Desktop, then run
  `podman compose version`.
- If a container name is already in use, inspect it with `podman ps --all`. For
  the macOS lab, prefer `podman compose down` before recreating the stack.
- If the Runner cannot pull an image, confirm registry authentication and that
  the image has a `linux/arm64` or `linux/amd64` manifest for the host. Check
  `podman logs gitlab-runner` on macOS or
  `sudo journalctl -u gitlab-runner` on Ubuntu.
- If GitLab is slow, confirm sufficient CPU, memory, and SSD-backed storage.
  The constrained 4-CPU and 8-GB configuration can start and respond slowly.

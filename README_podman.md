# Podman and Podman Compose Guide

This reusable guide covers installing Podman, configuring Podman Machine, running Compose projects, and optional Docker-compatible socket access.

## Contents

- [Overview](#overview)
- [Requirements](#requirements)
- [Install Podman](#install-podman)
- [How `podman compose` works](#how-podman-compose-works)
- [Configure Podman Machine](#configure-podman-machine)
- [Run a Compose project](#run-a-compose-project)
- [Useful commands](#useful-commands)
- [Update a Compose project](#update-a-compose-project)
- [Docker-compatible socket reference](#docker-compatible-socket-reference)

## Overview

[Podman](https://podman.io/) is a daemonless container engine with a Docker-compatible command-line experience. Podman runs containers directly on Linux. On macOS and Windows, it runs Linux containers in a lightweight virtual machine managed by `podman machine`.

## Requirements

- A host with Internet access.
- A recent Podman release.
- A Compose provider such as `podman-compose`.

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
3. Open a new terminal, then install `podman-compose`:

   ```console
   uv tool install podman-compose
   ```

Create the Linux VM and verify the installation:

```console
podman machine init --now
podman info
podman-compose --version
podman compose version
```

If Podman was previously installed with Homebrew, remove it first to avoid conflicting executables on `PATH`:

```console
brew uninstall --ignore-dependencies podman
brew uninstall krunkit   # If installed separately
```

### Windows

Install Podman with the Windows installer from the [Podman releases page](https://github.com/containers/podman/releases), then install `podman-compose`:

```powershell
uv tool install podman-compose
```

Podman uses a WSL 2-backed machine by default. Initialize it and verify the installation:

```powershell
podman machine init --now
podman info
podman-compose --version
podman compose version
```

### Linux

Install Podman and `podman-compose` from the distribution repositories. For example:

```console
# Debian or Ubuntu
sudo apt-get update
sudo apt-get install podman podman-compose

# Fedora
sudo dnf install podman podman-compose
```

Linux does not normally require `podman machine`. Verify the installation with `podman --version`, `podman-compose --version`, and `podman compose version`.

### Optional: Podman Desktop

[Podman Desktop](https://podman-desktop.io/) provides a graphical interface for managing containers, images, volumes, and Podman machines. It is optional; all commands in this guide work with the Podman CLI alone.

## How `podman compose` works

`podman compose` (with a space) is a dispatcher included in Podman 4 and later. It delegates Compose operations to an installed provider, such as `docker compose`, `docker-compose`, or `podman-compose`. Docker Desktop and the Docker daemon are not required when `podman-compose` is the provider.

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

## Useful commands

```console
# Show service status
podman compose ps

# Follow logs for all services
podman compose logs --follow

# Follow one service
podman compose logs --follow <service-name>

# Stop containers while preserving them
podman compose stop

# Start existing stopped containers
podman compose start

# Remove containers and the Compose network, preserving named volumes
podman compose down

# List containers, including stopped containers
podman ps --all

# Show Podman disk usage
podman system df
```

## Update a Compose project

Update the project files using their normal source-control or release process, then pull images and recreate changed services:

```console
podman compose pull
podman compose up --build --detach
```

> **Warning:** `podman compose down --volumes` permanently deletes Compose-managed named volumes. Use it only when persistent application data should be removed.

## Docker-compatible socket reference

Normal `podman` and `podman compose` commands do not require manual socket mapping. First check the machine and connection on macOS or Windows:

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

Rootless Podman uses `/run/user/<uid>/podman/podman.sock`. The container process must have permission to read and write the mounted socket.

For more information, see the [`podman compose` documentation](https://docs.podman.io/en/stable/markdown/podman-compose.1.html), [`podman machine set` documentation](https://docs.podman.io/en/stable/markdown/podman-machine-set.1.html), Podman Desktop's [Docker compatibility documentation](https://podman-desktop.io/docs/migrating-from-docker/managing-docker-compatibility), and the [Podman service documentation](https://docs.podman.io/en/latest/markdown/podman-system-service.1.html).

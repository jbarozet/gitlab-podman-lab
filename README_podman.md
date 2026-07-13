# Podman Setup Guide

This guide prepares Podman for the GitLab lab. It focuses on Apple Silicon macOS, while noting the main differences for Linux and Windows.

## Install Podman

Use the official installer from the [Podman installation page](https://podman.io/docs/installation). The `.pkg` installer is recommended on macOS; the Homebrew package is community-maintained and may ship mismatched helper versions.

Verify the CLI:

```console
podman --version
```

Podman runs Linux containers in a virtual machine on macOS and Windows. Linux hosts normally run Podman directly and can skip the `podman machine` commands.

## Install a Compose provider

`podman compose` is a wrapper around an external provider such as `podman-compose` or `docker-compose`. Install one provider before using this repository.

With `uv`:

```console
uv tool install podman-compose
```

Alternatively, Podman Desktop can install Compose support from **Settings > Docker Compatibility**.

Verify the provider:

```console
podman compose version
```

If multiple providers are installed, select one explicitly when needed:

```console
export PODMAN_COMPOSE_PROVIDER=podman-compose
```

## Configure Podman Machine

GitLab needs more resources than a default development VM. For a new machine:

```console
podman machine init --cpus 4 --memory 8192 --disk-size 50 --now
podman info
```

To resize an existing machine:

```console
podman machine stop
podman machine set --cpus 4 --memory 8192
podman machine start
```

Inspect the active machine and connection:

```console
podman machine list
podman machine inspect
podman system connection list
```

Disk size can only be increased. Removing a machine deletes its containers, images, and VM-managed volumes; back up anything important first. Bind-mounted data in this repository should also be backed up separately.

## Start a Compose project

From the directory containing `docker-compose.yml`:

```console
podman compose config
podman compose up --detach
podman compose ps
```

Common lifecycle commands:

```console
# Follow all service logs
podman compose logs --follow

# Stop and restart existing containers
podman compose stop
podman compose start

# Remove containers and the Compose network
podman compose down

# Show all containers and disk usage
podman ps --all
podman system df
```

Use `podman compose down --volumes` only when you intend to delete Compose-managed volumes. It does not delete this repository's `data/` bind mounts.

## Understand the runner socket

The runner uses GitLab's Docker executor, which talks to Podman's Docker-compatible API. In `docker-compose.yml`, the socket inside Podman Machine is mounted into the runner at the conventional Docker path:

```yaml
volumes:
  - /run/podman/podman.sock:/var/run/docker.sock
```

Confirm the source socket exists in the default VM (replace the machine name if yours differs):

```console
podman machine ssh podman-machine-default test -S /run/podman/podman.sock
```

Then confirm the mount inside the runner:

```console
podman exec gitlab-runner test -S /var/run/docker.sock
```

Do not mount the temporary macOS path reported by `podman machine inspect` into a container. That path exists on macOS, while the container and bind-mount source are resolved inside the Linux VM.

> [!WARNING]
> A container with socket access can create containers, modify images and volumes, and mount accessible host paths. Run only trusted CI projects and images.

## Optional host Docker compatibility

The lab itself does not require a host `/var/run/docker.sock`. Enable it only for macOS applications that insist on that path.

With Podman Desktop, open **Settings > Docker Compatibility** and enable **Third-Party Docker Tool Compatibility**. Verify the mapping with:

```console
ls -l /var/run/docker.sock
curl --unix-socket /var/run/docker.sock http://localhost/_ping
```

The request should return `OK`. Applications that accept `DOCKER_HOST` can instead use the socket shown by `podman system connection list`.

## Troubleshooting

### Compose provider is missing

If `podman compose version` reports that no provider is installed, install `podman-compose` or enable Compose support in Podman Desktop.

### GitLab is slow or returns 502

Check available VM resources with `podman info`, then follow startup with `podman logs --follow gitlab`. Initial startup can take several minutes.

### Runner cannot create job containers

Run both socket checks above, inspect `podman logs gitlab-runner`, and confirm that the runner configuration uses `unix:///var/run/docker.sock` and the `gitlabnet` network.

## References

- [Podman installation](https://podman.io/docs/installation)
- [`podman machine init`](https://docs.podman.io/en/stable/markdown/podman-machine-init.1.html)
- [`podman compose`](https://docs.podman.io/en/stable/markdown/podman-compose.1.html)
- [Podman Desktop Docker compatibility](https://podman-desktop.io/docs/migrating-from-docker/managing-docker-compatibility)

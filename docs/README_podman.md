# Podman Operations Reference

Use the root [Podman setup guide](../README_podman.md) for installation, Podman Machine resources, Compose configuration, and socket setup. This page is a compact command and troubleshooting reference for the lab.

## Machine and connection

These commands apply to macOS and Windows:

```console
podman machine list
podman machine start
podman machine inspect
podman system connection list
podman info
podman machine stop
```

Do not switch between rootless and rootful connections casually. They use separate container storage, so existing containers and images can appear to disappear.

## Containers, images, and networks

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

Prefer `podman compose` for this repository instead of removing named containers individually. Compose keeps service, network, and volume behavior aligned with `docker-compose.yml`.

## Compose lifecycle

```console
# Validate and start
podman compose config
podman compose up --detach

# Inspect and follow logs
podman compose ps
podman compose logs --follow

# Preserve containers during a routine stop
podman compose stop
podman compose start

# Remove containers and the Compose network
podman compose down
```

Persistent GitLab files live under `data/`. They survive `podman compose down`, but they contain sensitive configuration and repository data.

## Build the CI job image

The image workflow belongs to the separate [custom-image project](../custom-image/README.md):

```console
cd custom-image
./build.sh
podman run --rm nac-demo:latest terraform --version
```

The supplied `Containerfile` is arm64-specific because it downloads the Linux arm64 Terraform package.

## Socket model on macOS

Podman exposes different paths in different environments:

- The path from `podman machine inspect` is a temporary macOS-side API socket.
- `/run/podman/podman.sock` is the source used inside Podman Machine by this Compose stack.
- `/var/run/docker.sock` is the destination expected inside the runner container.

Check the complete path from engine to runner:

```console
podman machine ssh podman-machine-default test -S /run/podman/podman.sock
podman exec gitlab-runner test -S /var/run/docker.sock
```

Do not bind-mount a `/var/folders/...` macOS socket path into a Linux container. Enable Podman Desktop's Docker compatibility only when a host application needs `/var/run/docker.sock`; it is not required by the current Compose mount.

## Common failures

### `podman compose` cannot find a provider

Install `podman-compose` or enable Compose support in Podman Desktop, then run `podman compose version`.

### A container name is already in use

Inspect it with `podman ps --all`. If it belongs to this project, prefer `podman compose down` before recreating the stack.

### Runner cannot pull an image

Confirm the image name, registry authentication, and availability of a `linux/arm64` manifest. Check `podman logs gitlab-runner` for the exact pull error.

### GitLab is slow

Confirm that Podman Machine has at least 4 CPUs and 8 GB RAM. Follow the GitLab logs during initialization.

## Security

The mounted Podman socket gives the runner broad control of the container engine. Do not run untrusted pipelines. Never commit runner tokens, GitLab passwords, registry credentials, or the contents of `data/`.

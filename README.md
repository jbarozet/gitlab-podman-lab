# GitLab Podman Lab

Run a self-hosted GitLab server and GitLab Runner locally with Podman. The lab is optimized for Apple Silicon Macs and can be used for general CI/CD testing or Network as Code (NaC) demonstrations.

> [!WARNING]
> This repository is for local demonstrations only. It is not regularly patched or security-scanned. Do not expose it to untrusted networks or use it in production without a security review.

## Architecture

Podman Compose starts two containers on the `gitlabnet` network:

- **GitLab CE** stores repositories and runs the web interface.
- **GitLab Runner** uses Podman's Docker-compatible API to create a separate container for each CI job.

The default CI job image is configured in `register_runner.sh`. A project can override it with the `image` keyword in `.gitlab-ci.yml`. See [custom-image/README.md](custom-image/README.md) to build the supplied Terraform and Python image.

## Requirements

- macOS on Apple Silicon (`arm64`)
- Podman and a Compose provider
- `podman-mac-helper` configured for Docker-compatible socket access
- At least 4 CPUs and 8 GB RAM assigned to Podman Machine
- Internet access for the initial image downloads

The GitLab server uses the community-maintained `yrzr/gitlab-ce-arm64v8:latest` image because the upstream GitLab CE container is not published for arm64. Other host architectures require a compatible server image and may require further configuration changes.

Follow [README_podman.md](README_podman.md) to install and configure Podman.

## Quick start

### 1. Install the macOS socket helper

This lab requires Docker-compatible socket access for the external Compose provider and the GitLab Runner Docker executor. Install `podman-mac-helper` once, before starting Podman Machine:

```console
sudo podman-mac-helper install
```

The compatibility socket becomes active when Podman Machine starts in the next step.

### 2. Prepare Podman Machine

For a new machine:

```console
podman machine init --cpus 4 --memory 8192 --disk-size 50 --now
podman info
podman compose version
```

To resize an existing machine:

```console
podman machine stop
podman machine set --cpus 4 --memory 8192
podman machine start
```

Changing between rootless and rootful connections uses different Podman storage. Do not switch a working machine unless you intend to recreate its containers and images.

Verify the macOS compatibility socket and the socket inside Podman Machine after it starts:

```console
ls -l /var/run/docker.sock
curl --unix-socket /var/run/docker.sock http://localhost/_ping
podman machine ssh podman-machine-default test -S /run/podman/podman.sock
```

The `curl` command should return `OK`. The Compose configuration mounts the in-machine socket into the runner as `/var/run/docker.sock`.

> [!WARNING]
> Socket access gives the runner broad control over the Podman engine. Run only trusted CI projects and images.

See [Podman Desktop Docker compatibility](https://podman-desktop.io/docs/migrating-from-docker/managing-docker-compatibility) for the equivalent graphical setup and troubleshooting.

### 3. Start the lab

From the repository root:

```console
podman compose config
podman compose up --detach
podman compose ps
podman logs --follow gitlab
```

GitLab can take several minutes to initialize. A temporary `502` response normally means startup is still in progress.

Verify that the runner container can access Podman's API socket:

```console
podman exec gitlab-runner test -S /var/run/docker.sock
```

### 4. Sign in to GitLab

Read the generated initial password:

```console
podman exec -it gitlab grep 'Password:' /etc/gitlab/initial_root_password
```

Open <http://localhost:8088> and sign in as `root`. Change the password immediately. GitLab removes the initial-password file after the first container restart that occurs more than 24 hours after installation.

### 5. Register the runner

1. In GitLab, open **Admin > CI/CD > Runners**.
2. Select **Create instance runner**.
3. Add a tag such as `podman` and enable **Run untagged jobs**.
4. Create the runner and copy the authentication token beginning with `glrt-`.
5. Run `bash register_runner.sh` and enter the token at the hidden prompt. The token is never written to the script.

Confirm registration:

```console
podman exec -it gitlab-runner gitlab-runner list
```

## Run the smoke test

The [smoke-test project](smoke-test/README.md) verifies repository pushes, pipeline creation, runner assignment, Podman job execution, and the Git, Python, and Terraform tools in the default CI image.

Additional GitLab and runner behavior is explained in [docs/README_gitlab.md](docs/README_gitlab.md).

## Manage the lab

```console
# Stop containers without removing them
podman compose stop

# Restart the existing containers
podman compose start

# Remove containers and the Compose network
podman compose down
```

GitLab state is bind-mounted under `data/`, so `podman compose down` does not remove it. Back up or delete that directory deliberately; it contains repositories, configuration, credentials, and logs.

## Exposed ports

| Service | URL or port |
| --- | --- |
| GitLab HTTP | <http://localhost:8088> |
| GitLab HTTPS mapping | `localhost:8443` |
| GitLab SSH | `localhost:2222` |
| Container Registry | <http://localhost:5005> |

HTTPS is mapped but not configured with a trusted certificate in this demo. Use the HTTP URL unless you add TLS configuration.

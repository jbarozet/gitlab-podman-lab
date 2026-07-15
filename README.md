# GitLab Podman Lab

Run a self-hosted GitLab server and GitLab Runner with Podman on Apple Silicon macOS or Ubuntu Server. The lab can be used for general CI/CD testing or Network as Code (NaC) demonstrations.

> [!WARNING]
> This repository is for local demonstrations only. It is not regularly patched or security-scanned. Do not expose it to untrusted networks or use it in production without a security review.

## Architecture

Podman Compose starts two containers on the `gitlabnet` network:

- **GitLab CE** stores repositories and runs the web interface.
- **GitLab Runner** uses Podman's Docker-compatible API to create a separate container for each CI job.

The default CI job image is configured in `register_runner.sh`. A project can override it with the `image` keyword in `.gitlab-ci.yml`. See [custom-image/README.md](custom-image/README.md) to build the supplied Terraform and Python image.

## Requirements

- Apple Silicon macOS (`arm64`) or Ubuntu Server (`amd64` or `arm64`)
- Podman and a Compose provider
- Recommended: 8 vCPU, 16 GB RAM, and 80 GB SSD-backed storage
- Constrained lab minimum: 4 vCPU, 8 GB RAM, and 50 GB free disk space
- Internet access for the initial image downloads

GitLab's current single-node baseline is 8 vCPU and 16 GB RAM. The smaller configuration is suitable only for this low-traffic demonstration and can start or respond slowly.

The repository pins matching server and runner releases instead of using floating `latest` tags:

| Platform | GitLab CE | GitLab Runner |
| --- | --- | --- |
| Ubuntu Server amd64 | `gitlab/gitlab-ce:19.1.2-ce.0` | `gitlab/gitlab-runner:v19.1.1` |
| Apple Silicon or Ubuntu arm64 | `yrzr/gitlab-ce-arm64v8:18.9.0-ce.0` | `gitlab/gitlab-runner:v18.9.0` |

The arm64 server image is community-maintained and currently stops at GitLab 18.9.0 because the upstream GitLab CE container is not published for arm64. GitLab recommends keeping the server and runner on the same major and minor version; their patch numbers do not have to match.

The Compose service also reserves the 256 MB shared-memory size used by GitLab's official container examples.

Follow [README_podman.md](README_podman.md) to install and configure Podman.

## Quick start: Ubuntu Server

The commands below use rootless Podman. Run them as the regular user who will own and operate the lab; do not mix them with `sudo podman` commands.

### 1. Install Podman and enable its socket

```console
sudo apt-get update
sudo apt-get install -y podman podman-compose uidmap
systemctl --user enable --now podman.socket
sudo loginctl enable-linger "$USER"
podman info
podman compose version
```

Linger keeps the user service available after logout. Confirm the socket exists:

```console
test -S "/run/user/$(id -u)/podman/podman.sock"
```

### 2. Configure the Ubuntu host

Copy the example and edit `.env`:

```console
cp .env.example .env
id -u
```

For a fresh amd64 server, uncomment the Ubuntu GitLab and Runner image pair plus the three common settings. On arm64 Ubuntu, use the matched pair shown in the Apple Silicon section instead. Replace `gitlab.example.test` with the server's LAN IP address or resolvable DNS name, and replace `1000` in `PODMAN_SOCKET` if `id -u` prints a different value. Do not add a trailing slash to the URLs.

If UFW is active, permit only trusted management networks. For example, replace `192.0.2.0/24` with the actual administrator subnet:

```console
sudo ufw allow from 192.0.2.0/24 to any port 8088 proto tcp
sudo ufw allow from 192.0.2.0/24 to any port 2222 proto tcp
sudo ufw allow from 192.0.2.0/24 to any port 5005 proto tcp
```

Port `8443` is unnecessary until TLS is configured. This demonstration stack should not be exposed directly to the Internet.

Continue at [Start the lab](#start-the-lab).

## Quick start: Apple Silicon macOS

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

This is the constrained lab configuration. If the Mac has sufficient capacity, use 8 CPUs, 16 GB memory, and an 80 GB disk to match GitLab's normal single-node baseline.

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

Continue at [Start the lab](#start-the-lab).

## Start the lab

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

## Sign in to GitLab

Read the generated initial password:

```console
podman exec -it gitlab grep 'Password:' /etc/gitlab/initial_root_password
```

Open the configured `GITLAB_EXTERNAL_URL` (or <http://localhost:8088> on macOS) and sign in as `root`. Change the password immediately. GitLab removes the initial-password file after the first container restart that occurs more than 24 hours after installation.

## Register the runner

1. In GitLab, open **Admin > CI/CD > Runners**.
2. Select **Create instance runner**.
3. Add a tag such as `podman` and enable **Run untagged jobs**.
4. Create the runner and copy the authentication token beginning with `glrt-`.
5. Run `bash register_runner.sh`. The default fallback job image is the multi-architecture `docker.io/jbarozet/nac-demo:0.2.1`, so both arm64 and amd64 runners use the same tag. Publish that version first by following the custom-image guide. To use a locally built image instead:

   ```console
   (cd custom-image && ./build.sh)
   CUSTOM_IMAGE=nac-demo:latest bash register_runner.sh
   ```

   Enter the token at the hidden prompt. The token is never written to the script.

Confirm registration:

```console
podman exec -it gitlab-runner gitlab-runner list
```

The runner uses the `if-not-present` pull policy so a locally built image is usable. Keep this instance runner restricted to trusted projects; shared runners should use registry-hosted images and a stricter pull policy.

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

## Upgrade an existing installation

Never point existing GitLab data at an arbitrary newer image. Back up `data/`, identify the installed version, and follow GitLab's required upgrade stops. Check the current versions with:

```console
podman exec gitlab gitlab-rake gitlab:env:info
podman exec gitlab-runner gitlab-runner --version
```

An existing amd64 installation on GitLab 18.9 must stop at the latest GitLab 18.11 patch before moving to 19.1:

```text
18.9.x → 18.11.7 → 19.1.2
```

At the 18.11 stop, use `gitlab/gitlab-ce:18.11.7-ce.0` with `gitlab/gitlab-runner:v18.11.4`. Start GitLab, verify it, and wait for all background migrations to finish before changing `.env` to the pinned 19.1 images.

The community arm64 image does not provide the required 18.11 stop. Existing Apple Silicon data must remain on the matched 18.9 pair or be migrated to an official amd64 GitLab 18.9.0 installation before following the upgrade path. Fresh Ubuntu amd64 installations can start directly on the versions in `.env.example`.

## Exposed ports

| Service | URL or port |
| --- | --- |
| GitLab HTTP | `<host>:8088` |
| GitLab HTTPS mapping | `<host>:8443` |
| GitLab SSH | `<host>:2222` |
| Container Registry | `<host>:5005` |

On macOS, `<host>` is `localhost`. On Ubuntu, it is the IP address or DNS name configured in `.env`. HTTPS is mapped but not configured with a trusted certificate in this demo. Use the HTTP URL unless you add TLS configuration.

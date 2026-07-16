# Apple Silicon macOS Setup

This guide runs GitLab CE and GitLab Runner as containers in Podman Machine.
See [README.md](README.md) for the cross-platform architecture overview.

## Architecture

```text
macOS
└── Podman Machine
    ├── GitLab CE container
    ├── GitLab Runner container
    └── short-lived CI job containers
```

The Compose stack uses the `gitlabnet` network. The Runner controls Podman
through its Docker-compatible API socket and starts a separate container for
each CI job.

The pinned images are:

- `docker.io/yrzr/gitlab-ce-arm64v8:18.9.0-ce.0`
- `docker.io/gitlab/gitlab-runner:v18.9.0`

The GitLab server image is community-maintained because GitLab does not publish
its official server container for arm64. Keep this demonstration off untrusted
networks.

## Requirements

- Apple Silicon Mac
- Recent Podman installer from the official Podman releases
- A Compose provider
- Recommended: 8 CPUs, 16 GB RAM, and an 80 GB Podman Machine disk
- Constrained minimum: 4 CPUs, 8 GB RAM, and a 50 GB disk

See [README_podman.md](docs/README_podman.md) for detailed Podman installation and
machine-management guidance.

## 1. Install the socket helper

The Compose provider and containerized Runner need Docker-compatible socket
access. Install the helper before starting Podman Machine:

```console
sudo podman-mac-helper install
```

## 2. Prepare Podman Machine

For a new constrained machine:

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

Changing between rootless and rootful Podman connections uses different
storage. Do not switch a working machine unless recreating its containers and
images is intentional.

Verify the compatibility socket and Podman Machine socket:

```console
ls -l /var/run/docker.sock
curl --unix-socket /var/run/docker.sock http://localhost/_ping
podman machine ssh podman-machine-default \
  test -S /run/podman/podman.sock
```

The `curl` command should return `OK`.

## 3. Configure the stack

Copy the example settings:

```console
cp .env.example .env
```

The Compose defaults already select the pinned arm64 images. Uncomment values
in `.env` only when they need to be explicit or customized. The default URLs
are:

```dotenv
GITLAB_EXTERNAL_URL=http://localhost:8088
GITLAB_REGISTRY_URL=http://localhost:5005
PODMAN_SOCKET=/run/podman/podman.sock
```

## 4. Start GitLab and Runner

From the repository root:

```console
podman compose config
podman compose up --detach
podman compose ps
podman logs --follow gitlab
```

GitLab can take several minutes to initialize. A temporary `502` response
normally means startup is still in progress.

Verify the Runner container can access Podman:

```console
podman exec gitlab-runner test -S /var/run/docker.sock
podman exec gitlab-runner \
  curl --fail --silent --show-error \
  --unix-socket /var/run/docker.sock \
  http://localhost/_ping
```

## 5. Sign in

Read the generated administrator password:

```console
podman exec -it gitlab \
  grep 'Password:' /etc/gitlab/initial_root_password
```

Open <http://localhost:8088>, sign in as `root`, and change the password
immediately.

## 6. Register the Runner

In GitLab, open **Admin > CI/CD > Runners**, create an instance runner, enable
**Run untagged jobs**, and copy the authentication token beginning with
`glrt-`. Then run:

```console
bash scripts/register_runner_macos.sh
```

The script securely prompts for the token and uses
`docker.io/jbarozet/nac-demo:0.2.1` as the default multi-architecture job image.
To use a local build instead:

```console
(cd custom-image && ./build.sh)
CUSTOM_IMAGE=nac-demo:latest bash scripts/register_runner_macos.sh
```

Confirm registration without displaying the token:

```console
podman exec gitlab-runner gitlab-runner verify
```

Do not share `gitlab-runner list` output because it can include the complete
authentication token. See
[the token reset procedure](docs/README_podman.md#reset-an-exposed-gitlab-runner-token)
if a token is exposed.

## 7. Run the smoke test

Follow [smoke-test/README.md](smoke-test/README.md). The test validates the
repository push, pipeline, Runner, Podman job container, and installed tools.

## Operations

```console
# Stop while preserving containers and data
podman compose stop

# Restart existing containers
podman compose start

# Remove containers and the Compose network
podman compose down
```

Persistent GitLab state lives under `data/` and survives `podman compose down`.
Back up or remove it deliberately because it contains repositories,
configuration, credentials, and logs.

## Upgrade and migration

Do not point existing GitLab data at an arbitrary newer image. Existing 18.9.x
instances must follow required upgrade stops and complete background migrations
at each stop. Use
[the 18.9 arm64 maintenance runbook](docs/README_gitlab_18_9_arm64.md).

For a new long-lived Ubuntu installation, use the native architecture in
[README_ubuntu.md](README_ubuntu.md).

## Ports

| Service | Address |
| --- | --- |
| GitLab HTTP | `localhost:8088` |
| GitLab HTTPS mapping | `localhost:8443` |
| GitLab SSH | `localhost:2222` |
| Container Registry | `localhost:5005` |

HTTPS is mapped but does not have a trusted certificate by default.

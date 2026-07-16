# GitLab and Runner Reference

This document explains the GitLab-specific behavior behind the setup in the
repository root. Start with the main [README](../README.md) for installation
and startup.

## Deployment architectures

| Host | GitLab server | GitLab Runner | CI jobs |
| --- | --- | --- | --- |
| Apple Silicon macOS | Podman container | Podman container | Podman containers |
| Ubuntu Server 24.04 | Native GitLab CE package | Native Runner package | Rootless Podman containers |

## Platform roles

The macOS Compose stack runs two long-lived containers:

- `gitlab` hosts Git repositories, the web interface, CI coordinator, and
  container registry.
- `gitlab-runner` polls GitLab for jobs and asks Podman to create short-lived
  job containers.

```text
GitLab assigns a job
        |
        v
GitLab Runner container
        |
        | Docker-compatible API
        v
Podman socket ----> temporary CI job container
```

Ubuntu uses native GitLab CE and Runner packages instead. The native Runner
talks directly to a rootless Podman socket owned by the `gitlab-runner` account:

```text
Native GitLab assigns a job
        |
        v
Native GitLab Runner service
        |
        | Docker-compatible API
        v
Rootless Podman socket ----> temporary CI job container
```

See [Native Ubuntu Server Setup](../README_ubuntu.md) for that workflow.

Neither Runner environment contains Terraform or project dependencies. Those
tools belong in the job image, such as the image built in
[custom-image/](../custom-image/README.md).

## Server and runner versions

The repository pins:

- `docker.io/yrzr/gitlab-ce-arm64v8:18.9.0-ce.0` and
  `docker.io/gitlab/gitlab-runner:v18.9.0` on Apple Silicon. The server image
  is community-maintained, not official.
- GitLab CE package `19.1.2-ce.0`, Runner package `19.1.1-1`, and matching
  `gitlab-runner-helper-images=19.1.1-1` on Ubuntu Server. GitLab publishes
  these packages for amd64 and arm64.

The server and Runner stay on the same major and minor release for
compatibility. Patch versions can differ. Do not replace these pins with
floating `latest` versions. An uncontrolled server upgrade can require
intermediate database migrations, while an uncontrolled Runner upgrade can
create a compatibility mismatch.

The macOS GitLab service sets `shm_size: 256m`, matching GitLab's official
container installation examples.

## Upgrade path

Back up application data, configuration, and secrets before upgrading. For the
macOS container lab, preserve `data/`. For native Ubuntu, create a GitLab
application backup and separately protect `/etc/gitlab`, including
`gitlab.rb` and `gitlab-secrets.json`. A GitLab backup can only be restored to
the same GitLab version and edition.

Existing 18.9 installations moving to 19.1 must follow the required GitLab
18.11 stop:

```text
GitLab 18.9.x / Runner 18.9.x
             ↓
GitLab 18.11.7 / Runner 18.11.4
             ↓
GitLab 19.1.2 / Runner 19.1.1
```

At each stop, verify GitLab health and wait for background migrations to finish
before continuing. The community arm64 image has no 18.11 release, so existing
arm64 container data cannot follow this path in place. Use the
[18.9 arm64 maintenance runbook](README_gitlab_18_9_arm64.md) before changing
that instance.

Fresh Ubuntu installations can start directly on the pinned 19.1 packages.
See GitLab's
[upgrade path documentation](https://docs.gitlab.com/update/upgrade_paths/)
before changing versions.

## Job image selection

The platform registration script supplies `--docker-image`, which becomes the
fallback image in the runner configuration. A pipeline-level or job-level
`image` in `.gitlab-ci.yml` overrides it:

```yaml
image: docker.io/jbarozet/nac-demo:0.2.1

validate:
  script:
    - terraform version
```

The image must contain `sh` or `bash` and `grep`, in addition to the tools used
by the job.

## Internal and external URLs

Use the appropriate address for each context:

| Context | GitLab URL |
| --- | --- |
| macOS browser or host Git client | `GITLAB_EXTERNAL_URL` from `.env`, or `http://localhost:8088` |
| macOS Runner and job containers | `http://gitlab-server` |
| Ubuntu browser, Runner, and job containers | LAN IP or resolvable DNS name configured as `GITLAB_URL` |

Inside a container, `localhost` refers to that container. The macOS Compose
network resolves the dedicated `gitlab-server` alias. Ubuntu job containers use
the native server's LAN or DNS address instead.

## Initial administrator password

GitLab generates a temporary password for the administrator account. On macOS,
read it from the GitLab container:

```console
podman exec -it gitlab grep 'Password:' /etc/gitlab/initial_root_password
```

On Ubuntu, read it directly from the server:

```console
sudo grep 'Password:' /etc/gitlab/initial_root_password
```

Open the platform's configured GitLab URL and sign in with:

- Username: `root`
- Password: the generated value shown by the applicable command above

Replace the generated password immediately after signing in:

1. In the upper-right corner, select **Admin**.
2. In the left sidebar, select **Overview > Users**.
3. Find **Administrator** (username `root`) and select **Edit**.
4. In the **Password** section, enter and confirm a new password, then save the
   changes.

Update the root email address from the profile settings as well. GitLab removes
the initial-password file after 24 hours. If that file no longer exists, reset
the password interactively with the platform-specific command.

On macOS:

```console
podman exec -it gitlab gitlab-rake "gitlab:password:reset[root]"
```

On Ubuntu:

```console
sudo gitlab-rake "gitlab:password:reset[root]"
```

## Runner registration

Create an instance runner under **Admin > CI/CD > Runners**, enable **Run
untagged jobs** if examples do not declare tags, and copy the token beginning
with `glrt-`.

On macOS, run the container registration script and enter the token at its
hidden prompt:

```console
bash scripts/register_runner_macos.sh
podman exec gitlab-runner gitlab-runner verify
```

On Ubuntu, register the native service:

```console
GITLAB_URL="http://gitlab.example.test" \
  bash scripts/register_runner_ubuntu.sh
sudo gitlab-runner verify
```

The default fallback image is the already-published multi-architecture
`docker.io/jbarozet/nac-demo:0.2.1`, which contains Terraform 1.15.8. The
registration scripts use the `if-not-present` pull policy for this trusted lab.
Do not use that policy on a Runner shared with untrusted projects or users.

On macOS, `CUSTOM_IMAGE=nac-demo:latest` can select an image built in the same
Podman engine. Ubuntu's rootless image store belongs to `gitlab-runner`, not the
administrator who cloned this repository. Prefer a registry-hosted image on
Ubuntu unless the local image was built or loaded explicitly as
`gitlab-runner`.

Both scripts keep the token in memory instead of writing it to a tracked file.
Do not share `gitlab-runner list` output because it can contain the complete
authentication token. If a real token is displayed, committed, or shared,
follow the reset procedure in
[README_podman.md](README_podman.md#reset-an-exposed-gitlab-runner-token).
Deleting a token from the latest file does not remove it from Git history.

## Container registry

On macOS, the registry is enabled in `docker-compose.yml` and advertised
through `GITLAB_REGISTRY_URL` (`http://localhost:5005` by default). On Ubuntu,
set `registry_external_url` in `/etc/gitlab/gitlab.rb` as described in the
native setup guide. GitLab projects display repository-specific login and push
commands under **Deploy > Container Registry**.

For this local HTTP registry, clients may require an insecure-registry
configuration. Prefer a trusted TLS endpoint for any environment beyond this
isolated lab.

After changing GitLab configuration, apply it with:

```console
podman exec -it gitlab gitlab-ctl reconfigure
```

On Ubuntu, run `sudo gitlab-ctl reconfigure` directly on the host.

## Troubleshooting pipelines

### Pipeline remains pending

Check that:

1. The runner is online and assigned to the project.
2. **Run untagged jobs** is enabled, or the job's `tags` match the runner.
3. The runner can access its configured Podman socket.
4. The requested job image can be pulled for the host architecture
   (`linux/arm64` or `linux/amd64`).

Useful commands:

```console
podman logs gitlab-runner
podman exec gitlab-runner test -S /var/run/docker.sock
podman exec gitlab-runner \
  curl --fail --silent --show-error \
  --unix-socket /var/run/docker.sock \
  http://localhost/_ping
podman exec gitlab-runner gitlab-runner verify
```

For native Ubuntu:

```console
sudo systemctl status gitlab-runner
sudo gitlab-runner verify
sudo grep -nE '^[[:space:]]*(host|volumes)[[:space:]]*=' \
  /etc/gitlab-runner/config.toml
RUNNER_UID="$(id -u gitlab-runner)"
sudo -u gitlab-runner \
  curl --fail --silent --show-error \
  --unix-socket "/run/user/$RUNNER_UID/podman/podman.sock" \
  http://localhost/_ping
```

The Ubuntu `host` must point to `/run/user/<uid>/podman/podman.sock`, and
`volumes` must be `["/cache"]`. Do not expose the engine socket to job
containers.

### GitLab returns 502

GitLab is usually still starting. On macOS, follow
`podman logs --follow gitlab`. On Ubuntu, check `sudo gitlab-ctl status` and
`sudo gitlab-ctl tail`.

## YAML anchors in pipelines

The basic example uses a YAML anchor to reuse the Terraform initialization
command:

```yaml
.tf_init: &tf_init
  - terraform init

plan:
  before_script:
    - *tf_init
```

The leading dot makes `.tf_init` a hidden GitLab job template; `&tf_init`
defines the YAML anchor and `*tf_init` references it.

## References

- [GitLab Docker executor](https://docs.gitlab.com/runner/executors/docker/)
- [GitLab installation requirements](https://docs.gitlab.com/install/requirements/)
- [Back up GitLab](https://docs.gitlab.com/administration/backup_restore/backup_gitlab/)
- [GitLab Runner compatibility](https://docs.gitlab.com/runner/)
- [Run GitLab Runner in a container](https://docs.gitlab.com/runner/install/docker/)
- [Install GitLab in a container](https://docs.gitlab.com/install/docker/installation/)
- [Install GitLab using the Linux package](https://docs.gitlab.com/install/package/)
- [Install GitLab Runner on Linux](https://docs.gitlab.com/runner/install/linux-repository/)

# Repository Guidelines

## Architecture Invariants

This repository deliberately uses two different deployment models. Do not try
to make Ubuntu reuse the macOS Compose stack.

- Apple Silicon macOS runs GitLab CE and GitLab Runner as containers inside
  Podman Machine. CI jobs are additional Podman containers.
- Ubuntu Server 24.04 installs GitLab CE and GitLab Runner as native packages.
  Only CI jobs are containers, created through a rootless Podman socket owned by
  the `gitlab-runner` account.
- Both paths support the multi-architecture
  `docker.io/jbarozet/nac-demo:0.2.1` default CI image.
- The Podman engine socket is available to the Runner, but must never be mounted
  into CI job containers. Job volumes are exactly `["/cache"]` for this lab.

The pinned platform versions are:

| Platform | GitLab CE | GitLab Runner |
| --- | --- | --- |
| macOS | `docker.io/yrzr/gitlab-ce-arm64v8:18.9.0-ce.0` | `docker.io/gitlab/gitlab-runner:v18.9.0` |
| Ubuntu | `gitlab-ce=19.1.2-ce.0` | `gitlab-runner=19.1.1-1` |

Changing a GitLab server version is an upgrade operation, not a normal image or
package replacement. Preserve required upgrade stops and background migrations.

## Project Structure

- `README.md` is the architectural landing page.
- `README_macos.md` is the Apple Silicon container-lab procedure.
- `README_ubuntu.md` is the native Ubuntu procedure and troubleshooting guide.
- `docker-compose.yml` and `.env.example` are macOS-only.
- `scripts/register_runner_macos.sh` registers the containerized macOS Runner.
- `scripts/install_ubuntu.sh` installs and configures the native Ubuntu lab.
- `scripts/register_runner_ubuntu.sh` registers the native Runner against its
  rootless Podman socket.
- `custom-image/` builds and publishes the arm64/amd64 CI job image.
- `smoke-test/` is the end-to-end pipeline validation project.
- `docs/` contains supporting Podman, GitLab, and upgrade references.
- `data/` is generated runtime state and is never source code.

## Build, Test, and Development Commands

### macOS

- `podman compose config` validates and renders the Compose configuration.
- `podman compose up --detach` creates GitLab and Runner containers.
- `podman compose ps` checks state; `podman logs --follow gitlab` follows boot.
- `bash scripts/register_runner_macos.sh` registers the containerized Runner.
- `podman compose stop` preserves containers and data; `podman compose down`
  removes containers and the Compose network but preserves bind-mounted data.

The Compose network name is explicitly `gitlabnet`. The GitLab service has the
permanent `gitlab-server` alias used by Runner registration. Use fully qualified
container image names because fresh Podman installations may not define
unqualified-search registries.

### Ubuntu

- `GITLAB_URL=http://host GITLAB_REGISTRY_URL=http://host:5005 bash scripts/install_ubuntu.sh`
  installs the native lab.
- `GITLAB_URL=http://host bash scripts/register_runner_ubuntu.sh` registers the
  native Runner.
- `sudo gitlab-ctl status` checks GitLab services.
- `sudo systemctl status gitlab-runner` and `sudo gitlab-runner verify` check the
  Runner.
- `apt-mark showhold` confirms the server, Runner, and helper packages remain
  pinned.

`GITLAB_URL` must be reachable from CI job containers. Do not use `localhost`;
use DNS or the server's fixed address, and omit trailing slashes.

### CI image

- `cd custom-image && ./build.sh` builds for the host architecture.
- `cd custom-image && ARCH_OVERRIDE=amd64 ./build.sh` selects another target.
- `cd custom-image && VERSION=0.2.1 ./publish_dockerhub.sh` builds, tests,
  pushes, and publishes both architectures as one manifest.
- `podman manifest inspect IMAGE` takes a plain image name. Do not use a
  `docker://` prefix for local `manifest inspect`.

Cross-running amd64 Terraform on arm64/QEMU may require `GOGC=off` and
`CHECKPOINT_DISABLE=1`; these are emulation workarounds, not image defaults.

## Ubuntu Installer Requirements

Preserve these behaviors when changing `scripts/install_ubuntu.sh`:

- Convert official Ubuntu `ports`, `archive`, and `security` repository URLs
  from HTTP to HTTPS before APT access. Keep backups under
  `/var/backups/gitlab-podman-lab`, never inside `sources.list.d`.
- Run `apt-get update --error-on=any`; plain APT update can return success while
  ignoring unreachable repositories. `APT_FORCE_IPV4=1` is an opt-in fallback,
  not the default.
- Install and hold the exact Runner/helper pair. Runner `19.1.1-1` requires
  `gitlab-runner-helper-images=19.1.1-1`; allowing APT to choose a newer helper
  creates an unsatisfied dependency.
- Install `dbus-user-session`, `podman`, and `uidmap` explicitly.
- Give `gitlab-runner` non-overlapping subordinate UID and GID ranges when the
  package-created system account has none.
- Enable linger, start the user's systemd manager, and enable `podman.socket`
  through `/run/user/<uid>/bus`.
- `/run/user/<uid>` is mode `0700`. Bus and socket existence checks performed
  by the invoking administrator must use `sudo test -S`; an unprivileged
  `[[ -S ... ]]` produces a false negative.
- When running Podman commands as `gitlab-runner`, use an accessible working
  directory such as `/tmp`. `sudo` otherwise preserves a repository directory
  below another user's home and Podman fails to `chdir`.
- Verify the rootless Podman API through
  `/run/user/<uid>/podman/podman.sock` and require `/_ping` to return `OK`.

Ubuntu uses the native Runner service. A failure mentioning a missing
`gitlab-runner` container means the macOS registration script was used by
mistake.

## Runner Registration Requirements

- Registration uses authentication tokens beginning with `glrt-`; scripts must
  prompt without echo and unset the token on exit.
- macOS uses `http://gitlab-server`, Docker-compatible
  `unix:///var/run/docker.sock`, and network `gitlabnet`.
- Ubuntu uses the externally reachable `GITLAB_URL`, a dynamic socket path based
  on `id -u gitlab-runner`, and `FF_NETWORK_PER_BUILD=1`.
- Both registration scripts configure only `--docker-volumes /cache`. Adding
  `/var/run/docker.sock:/var/run/docker.sock` to job volumes causes permission
  and mountpoint failures and exposes the engine to jobs.
- Rootless images on Ubuntu belong to `gitlab-runner`; prefer registry-hosted
  multi-architecture job images over images built under an administrator's
  account.

## Coding Style & Naming Conventions

Use two-space indentation in YAML and Containerfile continuation blocks. Shell
scripts use an accurate shebang, `set -euo pipefail`, quoted expansions, and
uppercase names for configuration. Name operational scripts with lowercase,
action-oriented names. Add comments for non-obvious security, namespace,
systemd, or cross-architecture behavior. No repository-wide formatter exists.

Keep Markdown commands copyable and update all guides when ports, paths,
anchors, image tags, package versions, or script locations change. Root-level
setup guides are `README.md`, `README_macos.md`, and `README_ubuntu.md`; place
supporting material in `docs/`.

## Testing Guidelines

There is no automated test framework. Validate in proportion to the change:

- Run `bash -n` on every modified shell script and `shellcheck` when available.
- Run `git diff --check` before committing.
- Run `podman compose config` for macOS Compose or environment changes.
- On macOS, require the outer Runner container's Podman `/_ping` to return `OK`.
- On Ubuntu, require GitLab services running, a valid Runner, a rootless Podman
  socket, and Runner configuration with the rootless `host` plus
  `volumes = ["/cache"]`.
- Use `smoke-test/` to prove push, pipeline assignment, image pull, and job
  execution. It intentionally omits `image` so the registration default is
  tested.
- For CI image changes, inspect the recorded architecture and run Terraform,
  Python, and `nac-validate`. Verify the published manifest contains
  `linux/arm64` and `linux/amd64`.

The native Ubuntu design and multi-architecture CI image have been exercised on
both amd64 and arm64. Preserve both paths when changing packages or scripts.

## Commit & Pull Request Guidelines

Use short, imperative, lowercase subjects such as `update runner container
build`. Keep commits focused. Pull requests explain motivation and validation,
identify platform assumptions, and call out changes to data, ports, image tags,
package pins, socket paths, or registration. Include screenshots only for UI
changes.

## Security & Configuration Tips

This is a trusted demonstration lab, not a production design. Never commit or
publish Runner tokens, passwords, registry credentials, generated GitLab
configuration, files under `data/`, or native files from `/etc/gitlab` and
`/etc/gitlab-runner`. `gitlab-runner list` can print a complete authentication
token; use `verify` for safe status checks and reset any exposed token.

Podman socket access is privileged engine control. Run only trusted projects
and images. Avoid `podman compose down --volumes` unless deleting macOS lab
state is intentional. The generated GitLab root password is stored in
`/etc/gitlab/initial_root_password` for only 24 hours; change it immediately or
use `sudo gitlab-rake "gitlab:password:reset[root]"` after expiry.

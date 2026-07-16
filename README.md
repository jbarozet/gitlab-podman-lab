# GitLab Lab for macOS and Ubuntu

This repository provides a self-hosted GitLab lab for CI/CD and Network as Code
(NaC) demonstrations. It supports two deliberately different architectures,
chosen to fit each host rather than forcing the same deployment model
everywhere.

> [!WARNING]
> This repository is for trusted demonstrations. It is not regularly patched
> or security-scanned. Do not expose it to untrusted networks or treat it as a
> production design without a separate security and operations review.

## Deployment architectures

| Host | GitLab server | GitLab Runner | CI jobs |
| --- | --- | --- | --- |
| Apple Silicon macOS | Podman container | Podman container | Podman containers |
| Ubuntu Server 24.04 | Native GitLab CE package | Native Runner package | Rootless Podman containers |

### Apple Silicon macOS

Podman Machine provides the Linux environment needed by GitLab. Podman Compose
starts both long-lived services and the Runner creates a fresh container for
each job.

```text
macOS
└── Podman Machine
    ├── GitLab CE container
    ├── GitLab Runner container
    └── CI job containers
```

Use [README_macos.md](README_macos.md) for installation, registration,
operations, and upgrades.

### Ubuntu Server

GitLab CE and GitLab Runner use their official native Linux packages. The
Runner owns a rootless Podman socket and uses it only to create isolated CI job
containers. GitLab and Runner themselves are not containers.

```text
Ubuntu Server
├── Native GitLab CE service
├── Native GitLab Runner service
└── Rootless Podman
    └── CI job containers
```

This avoids nesting a Runner container inside rootless Podman and follows
GitLab's documented Podman executor model. Use
[README_ubuntu.md](README_ubuntu.md) for the complete setup.

## Shared principles

### Pin versions

The lab uses explicit server, Runner, and CI image versions instead of floating
`latest` tags:

| Platform | GitLab CE | GitLab Runner |
| --- | --- | --- |
| macOS | `docker.io/yrzr/gitlab-ce-arm64v8:18.9.0-ce.0` | `docker.io/gitlab/gitlab-runner:v18.9.0` |
| Ubuntu | Linux package `19.1.2-ce.0` | Linux package `19.1.1-1` |

The macOS server image is community-maintained. Ubuntu packages are official
and available for both amd64 and arm64. Review GitLab's required upgrade path
before changing any server version.

### Isolate CI jobs

Both architectures use the GitLab Runner Docker executor with Podman as the
container backend. Each job runs in the multi-architecture image configured by
the platform registration script. The default is:

```text
docker.io/jbarozet/nac-demo:0.2.1
```

Projects can override it with the `image` keyword in `.gitlab-ci.yml`.

### Optional custom CI image

The [custom-image/](custom-image/README.md) directory is not required to install
or run the GitLab lab. The default job image above is already published on
Docker Hub and can be pulled by either architecture.

That directory is a separate image-building project containing the
`Containerfile`, local build script, and multi-architecture publishing script.
Use it only when rebuilding, customizing, or publishing the Terraform and
Python container image used by CI jobs.

### Protect the Podman socket

Podman socket access grants broad control over the engine. Only the Runner
needs that access; the socket must not be mounted into CI job containers. Run
only trusted projects and images in this lab.

### Protect credentials and state

Never commit Runner tokens, GitLab passwords, registry credentials, generated
configuration, or runtime state under `data/`. Avoid sharing
`gitlab-runner list` output because it may include the complete authentication
token.

## Hardware guidance

GitLab's normal single-node baseline is 8 CPUs and 16 GB RAM. A constrained
4-CPU, 8-GB lab can work but may initialize and respond slowly. Prefer at least
80 GB of SSD-backed storage for a longer-lived installation.

## Validate the lab

After following the platform guide, use
[smoke-test/README.md](smoke-test/README.md) to validate repository pushes,
pipeline creation, Runner assignment, Podman job execution, and the tools in the
default CI image.

## Additional references

- [Podman and socket guide](docs/README_podman.md)
- [GitLab and Runner behavior](docs/README_gitlab.md)
- [Maintaining a GitLab 18.9.x arm64 instance](docs/README_gitlab_18_9_arm64.md)
- [GitLab Linux package installation](https://docs.gitlab.com/install/package/)
- [GitLab Runner with Podman](https://docs.gitlab.com/runner/executors/docker/#use-podman-to-run-docker-commands)

# GitLab and Runner Reference

This document explains the GitLab-specific behavior behind the setup in the repository root. Start with the main [README](../README.md) for installation and startup.

## Container roles

The Compose stack runs two long-lived containers:

- `gitlab` hosts Git repositories, the web interface, CI coordinator, and container registry.
- `gitlab-runner` polls GitLab for jobs and asks Podman to create short-lived job containers.

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

The runner container does not contain Terraform or project dependencies. Those tools belong in the job image, such as the image built in [custom-image/](../custom-image/README.md).

## Server and runner images

`docker-compose.yml` currently uses:

- `yrzr/gitlab-ce-arm64v8:latest` for GitLab CE on Apple Silicon. This is a community-maintained image, not an official GitLab image.
- `gitlab/gitlab-runner:latest` for the runner.

Floating `latest` tags are convenient for a lab but make upgrades unpredictable. Pin tested versions before using this setup for repeatable demonstrations, and back up `data/` before upgrading GitLab.

## Job image selection

`register_runner.sh` supplies `--docker-image`, which becomes the fallback image in the runner configuration. A pipeline-level or job-level `image` in `.gitlab-ci.yml` overrides it:

```yaml
image: quay.io/example/nac-demo:0.1.0

validate:
  script:
    - terraform version
```

The image must contain `sh` or `bash` and `grep`, in addition to the tools used by the job.

## Internal and external URLs

Use the appropriate address for each context:

| Context | GitLab URL |
| --- | --- |
| Browser or host Git client | `http://localhost:8088` |
| Runner and job containers | `http://gitlab` |

Inside a container, `localhost` refers to that container. The Compose network resolves the service hostname `gitlab`.

## Initial administrator password

Read the generated password with:

```console
podman exec -it gitlab grep 'Password:' /etc/gitlab/initial_root_password
```

Sign in as `root` at <http://localhost:8088> and change the password. GitLab deletes the file after the first restart that occurs more than 24 hours after installation.

## Runner registration

Create an instance runner under **Admin > CI/CD > Runners**, enable **Run untagged jobs** if examples do not declare tags, and copy the token beginning with `glrt-`.

Run the registration script and enter the token at its hidden prompt:

```console
bash register_runner.sh
podman exec -it gitlab-runner gitlab-runner list
```

The script keeps the token in memory instead of writing it to a tracked file. If a real token is ever committed or shared, rotate it in GitLab; deleting it from the latest file does not remove it from Git history.

## Container registry

The registry is enabled in `docker-compose.yml` and exposed at `http://localhost:5005`. GitLab projects display repository-specific login and push commands under **Deploy > Container Registry**.

For this local HTTP registry, clients may require an insecure-registry configuration. Prefer a trusted TLS endpoint for any environment beyond this isolated lab.

After changing GitLab configuration, apply it with:

```console
podman exec -it gitlab gitlab-ctl reconfigure
```

## Troubleshooting pipelines

### Pipeline remains pending

Check that:

1. The runner is online and assigned to the project.
2. **Run untagged jobs** is enabled, or the job's `tags` match the runner.
3. The runner can access `/var/run/docker.sock`.
4. The requested job image can be pulled for `linux/arm64`.

Useful commands:

```console
podman logs gitlab-runner
podman exec gitlab-runner test -S /var/run/docker.sock
podman exec -it gitlab-runner gitlab-runner verify
```

### GitLab returns 502

GitLab is usually still starting. Follow `podman logs --follow gitlab` and wait for the web services to become ready.

## YAML anchors in pipelines

The basic example uses a YAML anchor to reuse the Terraform initialization command:

```yaml
.tf_init: &tf_init
  - terraform init

plan:
  before_script:
    - *tf_init
```

The leading dot makes `.tf_init` a hidden GitLab job template; `&tf_init` defines the YAML anchor and `*tf_init` references it.

## References

- [GitLab Docker executor](https://docs.gitlab.com/runner/executors/docker/)
- [Run GitLab Runner in a container](https://docs.gitlab.com/runner/install/docker/)
- [Install GitLab in a container](https://docs.gitlab.com/install/docker/installation/)

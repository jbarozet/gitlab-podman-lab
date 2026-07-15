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

- `yrzr/gitlab-ce-arm64v8:18.9.0-ce.0` and `gitlab/gitlab-runner:v18.9.0` by default on Apple Silicon. The server image is community-maintained, not official.
- `gitlab/gitlab-ce:19.1.2-ce.0` and `gitlab/gitlab-runner:v19.1.1` through `.env` for a fresh amd64 Ubuntu Server.
- The pinned 18.9 pair on arm64 Ubuntu because the community server image does not currently publish a newer release.

The server and runner stay on the same major and minor release for compatibility. Patch versions can differ. Do not replace these pins with floating `latest` tags; an uncontrolled server upgrade can require intermediate database migrations, while an uncontrolled runner upgrade can create a server/runner mismatch.

The GitLab service sets `shm_size: 256m`, matching GitLab's official container installation examples.

## Upgrade path

Back up `data/` before upgrading GitLab. Existing amd64 installations on 18.9 must follow the required GitLab 18.11 stop:

```text
GitLab 18.9.x / Runner 18.9.x
             ↓
GitLab 18.11.7 / Runner 18.11.4
             ↓
GitLab 19.1.2 / Runner 19.1.1
```

At each stop, recreate the containers, verify GitLab health, and wait for background migrations to finish before continuing. The community arm64 image has no 18.11 release, so existing arm64 data cannot follow this path in place. Migrate it to an official amd64 GitLab 18.9.0 installation first, or keep the arm64 lab on its pinned matched versions.

Fresh amd64 installations with no existing `data/` can start directly on the pinned 19.1 pair. See GitLab's [upgrade path documentation](https://docs.gitlab.com/update/upgrade_paths/) before changing versions.

## Job image selection

`register_runner.sh` supplies `--docker-image`, which becomes the fallback image in the runner configuration. A pipeline-level or job-level `image` in `.gitlab-ci.yml` overrides it:

```yaml
image: docker.io/jbarozet/nac-demo:0.2.1

validate:
  script:
    - terraform version
```

The image must contain `sh` or `bash` and `grep`, in addition to the tools used by the job.

## Internal and external URLs

Use the appropriate address for each context:

| Context | GitLab URL |
| --- | --- |
| Browser or host Git client | `GITLAB_EXTERNAL_URL` from `.env`, or `http://localhost:8088` by default |
| Runner and job containers | `http://gitlab` |

Inside a container, `localhost` refers to that container. The Compose network resolves the service hostname `gitlab`.

## Initial administrator password

Read the generated password with:

```console
podman exec -it gitlab grep 'Password:' /etc/gitlab/initial_root_password
```

Sign in as `root` at the configured `GITLAB_EXTERNAL_URL` (or <http://localhost:8088> by default) and change the password. GitLab deletes the file after the first restart that occurs more than 24 hours after installation.

## Runner registration

Create an instance runner under **Admin > CI/CD > Runners**, enable **Run untagged jobs** if examples do not declare tags, and copy the token beginning with `glrt-`.

Run the registration script and enter the token at its hidden prompt:

```console
bash register_runner.sh
podman exec -it gitlab-runner gitlab-runner list
```

The default fallback job image is the multi-architecture `docker.io/jbarozet/nac-demo:0.2.1`, which contains Terraform 1.15.8. Publish that version before registering a runner. To use a host-native local build instead, set `CUSTOM_IMAGE=nac-demo:latest` when registering. The script configures `if-not-present` so the runner can use a local image. This pull policy is appropriate only for this trusted lab; do not share the instance runner with untrusted projects or users.

The script keeps the token in memory instead of writing it to a tracked file. If a real token is ever committed or shared, rotate it in GitLab; deleting it from the latest file does not remove it from Git history.

## Container registry

The registry is enabled in `docker-compose.yml` and advertised through `GITLAB_REGISTRY_URL` (`http://localhost:5005` by default). GitLab projects display repository-specific login and push commands under **Deploy > Container Registry**.

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
4. The requested job image can be pulled for the host architecture (`linux/arm64` or `linux/amd64`).

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
- [GitLab installation requirements](https://docs.gitlab.com/install/requirements/)
- [GitLab Runner compatibility](https://docs.gitlab.com/runner/)
- [Run GitLab Runner in a container](https://docs.gitlab.com/runner/install/docker/)
- [Install GitLab in a container](https://docs.gitlab.com/install/docker/installation/)

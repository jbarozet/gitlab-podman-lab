# GitLab Runner Job Image

This side project builds the Linux image used by the GitLab Runner's Docker executor. Each CI job runs in a fresh container; it does not run inside the runner container itself.

The image is based on `python:3.12-slim` and includes:

- Python 3.12 and `uv`
- Terraform, pinned by `TERRAFORM_VERSION` in `Containerfile`
- Git, cURL, `jq`, and `unzip`
- Python packages used by Network as Code workflows, including `nac-validate`

The current build targets Linux on arm64 for Apple Silicon.

## Build and verify

From this directory:

```console
./build.sh
podman image inspect nac-demo:latest
podman run --rm nac-demo:latest terraform --version
podman run --rm nac-demo:latest python --version
podman run --rm nac-demo:latest nac-validate --help
```

To override the Terraform version:

```console
podman build \
  --platform linux/arm64 \
  --build-arg TERRAFORM_VERSION=1.12.2 \
  --tag nac-demo:latest .
```

## Publish to a registry

Use immutable version tags for CI. Replace `<username>` and `0.1.0` in these examples.

### Quay

```console
podman login quay.io
podman tag nac-demo:latest quay.io/<username>/nac-demo:0.1.0
podman push quay.io/<username>/nac-demo:0.1.0
```

### Docker Hub

```console
podman login docker.io
podman tag nac-demo:latest docker.io/<username>/nac-demo:0.1.0
podman push docker.io/<username>/nac-demo:0.1.0
```

Do not place registry passwords or access tokens in scripts or committed files.

## Use the image in GitLab CI

Set a project-wide image in `.gitlab-ci.yml`:

```yaml
image: quay.io/<username>/nac-demo:0.1.0

validate:
  script:
    - terraform version
    - python --version
    - nac-validate --help
```

This value overrides the default image configured by `register_runner.sh`. To register the runner with a different fallback image, set `CUSTOM_IMAGE` for that invocation: `CUSTOM_IMAGE="quay.io/<username>/nac-demo:0.1.0" bash register_runner.sh`.

## Architecture notes

The `Containerfile` downloads the arm64 Terraform archive explicitly. To support amd64 or multiple platforms, parameterize the Terraform architecture and build each target separately. Do not claim multi-architecture support until both variants have been built and tested.

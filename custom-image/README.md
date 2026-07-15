# GitLab Runner Job Image

This side project builds the Linux image used by the GitLab Runner's Docker executor. Each CI job runs in a fresh container; it does not run inside the runner container itself.

The image is based on `python:3.12-slim` and includes:

- Python 3.12 and `uv`
- Terraform, pinned by `TERRAFORM_VERSION` in `Containerfile`
- Git, cURL, `jq`, and `unzip`
- Python packages used by Network as Code workflows, including `nac-validate`

The build script targets `linux/arm64` on Apple Silicon and arm64 Linux hosts, or `linux/amd64` on standard x86-64 Ubuntu hosts. The Docker Hub publishing script builds both variants and combines them under one multi-architecture tag.

## Build and verify

The local build workflow creates one Podman image for either `linux/arm64` or `linux/amd64`. Each invocation of `build.sh`:

1. Detects the host architecture unless `ARCH_OVERRIDE` is set.
2. Selects the matching base image and Terraform archive.
3. Builds the image from `Containerfile`.
4. Tags the result as `nac-demo:latest` unless `IMAGE_TAG` is set.

The script builds only one architecture at a time. It does not push the image or create a multi-architecture manifest; `publish_dockerhub.sh` handles that workflow.

### Build for the host architecture

From this directory:

```console
./build.sh
```

On Apple Silicon this builds `linux/arm64`. On a standard Intel or AMD Linux host it builds `linux/amd64`.

### Verify the local image

```console
podman image inspect nac-demo:latest
podman run --rm nac-demo:latest terraform --version
podman run --rm nac-demo:latest python --version
podman run --rm nac-demo:latest nac-validate --help
```

### Build for a different architecture

Set `ARCH_OVERRIDE` when the target must differ from the host. Set `IMAGE_TAG` to change the output tag:

```console
ARCH_OVERRIDE=amd64 IMAGE_TAG=nac-demo:amd64 ./build.sh
```

Cross-architecture builds require emulation. They are generally slower than builds for the host architecture.

### Override the Terraform version

Pass `TERRAFORM_VERSION` and the matching `TARGETARCH` directly to `podman build`:

```console
podman build \
  --platform linux/amd64 \
  --build-arg TERRAFORM_VERSION=1.15.8 \
  --build-arg TARGETARCH=amd64 \
  --tag nac-demo:latest .
```

## Publish a multi-architecture image to Docker Hub

The publishing workflow creates three tags:

- `<version>-arm64` for Apple Silicon and other arm64 hosts
- `<version>-amd64` for Intel and AMD hosts
- `<version>` as the multi-architecture tag used by CI

Image version `0.2.1` pins Terraform 1.15.8. The previously published `0.2.0` remains immutable and contains Terraform 1.12.2.

The sections below show each operation separately. This makes it easier to verify an architecture before anything is published. Run the commands from `custom-image/`.

### 1. Prepare Docker Hub

Create the `nac-demo` repository in Docker Hub and create a Docker Hub access token. Log in with your Docker Hub username and use the access token at the password prompt:

```console
podman login docker.io
```

Do not place the access token in a script or committed file.

### 2. Verify amd64 emulation

Confirm that the Podman Machine can execute amd64 containers on Apple Silicon:

```console
podman run --rm --platform linux/amd64 docker.io/library/alpine uname -m
```

The expected result is `x86_64`. An `exec format error` means x86-64 emulation is not available in the current Podman Machine.

### 3. Select the repository and version

Use an immutable version for CI. Change the repository if publishing from another Docker Hub account:

```console
export REPOSITORY=docker.io/jbarozet/nac-demo
export VERSION=0.2.1
```

### 4. Build both architectures

```console
ARCH_OVERRIDE=arm64 \
IMAGE_TAG="${REPOSITORY}:${VERSION}-arm64" \
./build.sh

ARCH_OVERRIDE=amd64 \
IMAGE_TAG="${REPOSITORY}:${VERSION}-amd64" \
./build.sh
```

The amd64 build runs through emulation on Apple Silicon and can be substantially slower than the arm64 build. For its build-time Terraform version check, the `Containerfile` disables Go garbage collection and Terraform's update check to avoid known QEMU user-mode crashes. Those environment settings are not persisted in the image.

### 5. Verify the image architectures

```console
podman image inspect \
  --format '{{.Os}}/{{.Architecture}}' \
  "${REPOSITORY}:${VERSION}-arm64"

podman image inspect \
  --format '{{.Os}}/{{.Architecture}}' \
  "${REPOSITORY}:${VERSION}-amd64"
```

The commands should return `linux/arm64` and `linux/amd64`, respectively.

### 6. Test both images

```console
podman run --rm \
  --platform linux/arm64 \
  "${REPOSITORY}:${VERSION}-arm64" \
  terraform --version

podman run --rm \
  --env CHECKPOINT_DISABLE=1 \
  --env GOGC=off \
  --platform linux/amd64 \
  "${REPOSITORY}:${VERSION}-amd64" \
  terraform --version
```

Both commands should report the Terraform version configured in `Containerfile`. `GOGC=off` and `CHECKPOINT_DISABLE=1` are needed only while running the amd64 Terraform binary through QEMU on an arm64 host. They avoid QEMU crashes in the Go garbage collector and Terraform update check, and are not stored in the image or required on a real amd64 server.

### 7. Push the architecture-specific images

```console
podman push "${REPOSITORY}:${VERSION}-arm64"
podman push "${REPOSITORY}:${VERSION}-amd64"
```

These tags are useful for inspection and troubleshooting. CI should normally use the multi-architecture tag created next.

### 8. Create and push the multi-architecture manifest

```console
podman manifest create "${REPOSITORY}:${VERSION}"

podman manifest add \
  "${REPOSITORY}:${VERSION}" \
  "docker://${REPOSITORY}:${VERSION}-arm64"

podman manifest add \
  "${REPOSITORY}:${VERSION}" \
  "docker://${REPOSITORY}:${VERSION}-amd64"

podman manifest push --all \
  "${REPOSITORY}:${VERSION}" \
  "docker://${REPOSITORY}:${VERSION}"
```

The `--all` option ensures that the architecture-specific images are pushed with the manifest list.

### 9. Verify the published manifest

```console
podman manifest inspect "${REPOSITORY}:${VERSION}"
```

Unlike `manifest add` and `manifest push`, `manifest inspect` expects the plain image name without a `docker://` transport prefix. The manifest should contain entries for `linux/arm64` and `linux/amd64`. Docker Hub and the runner automatically select the correct entry for the host.

### Automated publishing

`publish_dockerhub.sh` performs the same build, verification, test, push, and manifest steps automatically. The default repository is `docker.io/jbarozet/nac-demo`:

```console
VERSION=0.2.1 ./publish_dockerhub.sh
```

Override the destination for another Docker Hub account or repository:

```console
DOCKERHUB_REPOSITORY=docker.io/YOUR_DOCKERHUB_USERNAME/nac-demo \
VERSION=0.2.1 \
./publish_dockerhub.sh
```

The script performs the following operations:

1. Builds arm64 and amd64 images using `build.sh`.
2. Confirms the recorded architecture of each image.
3. Runs Terraform in both variants.
4. Pushes both architecture-specific tags.
5. Creates and pushes the multi-architecture manifest.

If the process fails before the manifest is pushed, fix the error and run the same command again. Version tags are replaced only when their corresponding push succeeds.

## Use the image in GitLab CI

Set a project-wide image in `.gitlab-ci.yml`:

```yaml
image: docker.io/YOUR_DOCKERHUB_USERNAME/nac-demo:0.2.1

validate:
  script:
    - terraform version
    - python --version
    - nac-validate --help
```

This value overrides the default image configured by `register_runner.sh`. From the repository root, register either architecture with the same multi-architecture fallback image:

```console
CUSTOM_IMAGE=docker.io/YOUR_DOCKERHUB_USERNAME/nac-demo:0.2.1 \
bash register_runner.sh
```

For this trusted local lab, the registration script uses the `if-not-present` pull policy. You can therefore build on the GitLab host and register `CUSTOM_IMAGE=nac-demo:latest` without publishing it. Do not use that pull policy on a runner shared by mutually untrusted users or projects.

## Architecture notes

The `Containerfile` uses `TARGETARCH` to download the matching Terraform archive. Each `build.sh` invocation creates one platform-specific image. `publish_dockerhub.sh` invokes it for both supported architectures and assembles their immutable tags into a manifest list.

#!/usr/bin/env bash

set -euo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
DOCKERHUB_REPOSITORY="${DOCKERHUB_REPOSITORY:-docker.io/jbarozet/nac-demo}"

if [[ -z "${VERSION:-}" ]]; then
  echo "VERSION is required, for example VERSION=0.2.1 $0" >&2
  exit 1
fi

if [[ ! "$VERSION" =~ ^[A-Za-z0-9_.-]+$ ]]; then
  echo "Invalid VERSION: use only letters, numbers, dots, underscores, and dashes." >&2
  exit 1
fi

if [[ "$DOCKERHUB_REPOSITORY" != docker.io/*/* ]]; then
  echo "DOCKERHUB_REPOSITORY must use docker.io/<username>/<repository>." >&2
  exit 1
fi

cd "$SCRIPT_DIR"

for arch in arm64 amd64; do
  tag="${DOCKERHUB_REPOSITORY}:${VERSION}-${arch}"
  echo "Building $tag"
  ARCH_OVERRIDE="$arch" IMAGE_TAG="$tag" ./build.sh
done

for arch in arm64 amd64; do
  tag="${DOCKERHUB_REPOSITORY}:${VERSION}-${arch}"
  platform="$(podman image inspect --format '{{.Os}}/{{.Architecture}}' "$tag")"

  if [[ "$platform" != "linux/$arch" ]]; then
    echo "Unexpected platform for $tag: $platform" >&2
    exit 1
  fi

  if [[ "$arch" == "amd64" && "$(uname -m)" =~ ^(arm64|aarch64)$ ]]; then
    podman run --rm \
      --env CHECKPOINT_DISABLE=1 \
      --env GOGC=off \
      --platform "linux/$arch" \
      "$tag" \
      terraform --version
  else
    podman run --rm --platform "linux/$arch" "$tag" terraform --version
  fi
done

for arch in arm64 amd64; do
  podman push "${DOCKERHUB_REPOSITORY}:${VERSION}-${arch}"
done

destination="${DOCKERHUB_REPOSITORY}:${VERSION}"
local_manifest="localhost/nac-demo-manifest:${VERSION}-$$"

podman manifest create "$local_manifest"
podman manifest add \
  "$local_manifest" \
  "docker://${DOCKERHUB_REPOSITORY}:${VERSION}-arm64"
podman manifest add \
  "$local_manifest" \
  "docker://${DOCKERHUB_REPOSITORY}:${VERSION}-amd64"
podman manifest push --all "$local_manifest" "docker://$destination"
podman manifest rm "$local_manifest"

echo "Published multi-architecture image: $destination"
echo "Verify with: podman manifest inspect $destination"

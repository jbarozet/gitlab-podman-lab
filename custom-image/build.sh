#!/usr/bin/env bash

set -euo pipefail

case "$(uname -m)" in
  arm64|aarch64)
    ARCH="arm64"
    ;;
  x86_64|amd64)
    ARCH="amd64"
    ;;
  *)
    echo "Unsupported host architecture: $(uname -m)" >&2
    exit 1
    ;;
esac

ARCH="${ARCH_OVERRIDE:-$ARCH}"
IMAGE_TAG="${IMAGE_TAG:-nac-demo:latest}"

if [[ "$ARCH" != "arm64" && "$ARCH" != "amd64" ]]; then
  echo "Unsupported target architecture: $ARCH" >&2
  exit 1
fi

podman build \
  --platform "linux/$ARCH" \
  --build-arg "TARGETARCH=$ARCH" \
  --tag "$IMAGE_TAG" \
  .

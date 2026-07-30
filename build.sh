#!/bin/sh
# Build and publish the image for both architectures.
#
# A plain `docker build` on an Apple Silicon Mac produces a linux/arm64 image
# only. Pushing that would replace the published amd64 image and break amd64
# deployments, so this always goes through buildx with an explicit platform
# list. buildx cannot --load a multi-platform result into the local daemon,
# which is why publishing and local builds are separate paths below.
#
# Normally you do not need to run this at all: .github/workflows/publish.yml
# does the same multi-arch push on every merge to master.
set -e

IMAGE=jimzucker/github-webhooks
PLATFORMS=linux/amd64,linux/arm64

case "$1" in
  --push)
    docker buildx build --platform "$PLATFORMS" -t "$IMAGE:latest" --push .
    echo "Pushed $IMAGE:latest for $PLATFORMS"
    ;;
  --local)
    # Single-arch, native to this machine, loaded into the local daemon.
    docker buildx build -t github-webhooks:latest --load .
    echo "Built github-webhooks:latest for local use (this architecture only)"
    ;;
  *)
    echo "usage: $0 --local | --push"
    echo "  --local  build for this machine and load into the local daemon"
    echo "  --push   build linux/amd64 + linux/arm64 and push to Docker Hub"
    echo "           (requires 'docker login')"
    exit 1
    ;;
esac

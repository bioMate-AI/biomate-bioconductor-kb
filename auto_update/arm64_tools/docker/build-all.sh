#!/bin/bash
# Build all ARM64 bioinformatics Docker images
# Usage: ./build-all.sh [--push]

set -e

REGISTRY="${DOCKER_REGISTRY:-biomate}"
TAG="${DOCKER_TAG:-arm64}"

echo "=== Building ARM64 Bioinformatics Docker Images ==="
echo "Registry: $REGISTRY"
echo "Tag: $TAG"
echo ""

cd "$(dirname "$0")"

# Build individual images
echo "=== Building samtools image ==="
docker build --platform linux/arm64 -t ${REGISTRY}/samtools:${TAG} -f Dockerfile.samtools .

echo ""
echo "=== Building mmseqs2 image ==="
docker build --platform linux/arm64 -t ${REGISTRY}/mmseqs2:${TAG} -f Dockerfile.mmseqs2 .

echo ""
echo "=== Building foldseek image ==="
docker build --platform linux/arm64 -t ${REGISTRY}/foldseek:${TAG} -f Dockerfile.foldseek .

echo ""
echo "=== Building seqkit image ==="
docker build --platform linux/arm64 -t ${REGISTRY}/seqkit:${TAG} -f Dockerfile.seqkit .

echo ""
echo "=== Building rush image ==="
docker build --platform linux/arm64 -t ${REGISTRY}/rush:${TAG} -f Dockerfile.rush .

echo ""
echo "=== Building combined biotools image ==="
docker build --platform linux/arm64 -t ${REGISTRY}/biotools:${TAG} -f Dockerfile.biotools .

echo ""
echo "=== All images built successfully ==="
docker images | grep "${REGISTRY}"

# Optional: push to registry
if [ "$1" == "--push" ]; then
    echo ""
    echo "=== Pushing images to registry ==="
    docker push ${REGISTRY}/samtools:${TAG}
    docker push ${REGISTRY}/mmseqs2:${TAG}
    docker push ${REGISTRY}/foldseek:${TAG}
    docker push ${REGISTRY}/seqkit:${TAG}
    docker push ${REGISTRY}/rush:${TAG}
    docker push ${REGISTRY}/biotools:${TAG}
    echo "=== Push complete ==="
fi

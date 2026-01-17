#!/bin/bash
# Build BioMate Interactive container for current architecture
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

ARCH=$(uname -m)
VERSION="${1:-latest}"

echo "=== Building BioMate Interactive Tools ==="
echo "Architecture: $ARCH"

if [ "$ARCH" = "aarch64" ] || [ "$ARCH" = "arm64" ]; then
    echo "Using ARM64 Dockerfile..."
    docker build -f Dockerfile.arm64 -t biomate/interactive:arm64 -t biomate/interactive:$VERSION .
elif [ "$ARCH" = "x86_64" ] || [ "$ARCH" = "amd64" ]; then
    echo "Using x86_64 Dockerfile..."
    docker build -f Dockerfile.x86 -t biomate/interactive:x86 -t biomate/interactive:$VERSION .
else
    echo "Unknown architecture: $ARCH"
    exit 1
fi

echo ""
echo "=== Build Complete ==="
docker images | grep "biomate/interactive"
echo ""
echo "Run with:"
echo "  docker run -p 8080:80 -v /your/data:/import biomate/interactive:$VERSION"

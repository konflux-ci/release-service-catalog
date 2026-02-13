#!/usr/bin/env bash
# generate-dockerfile-with-size.sh - Generate Dockerfile with random size
#
# USAGE:
#   ./generate-dockerfile-with-size.sh [min_mb] [max_mb] [output_file]
#
# ARGUMENTS:
#   min_mb      : Minimum image size in MB (default: 1000)
#   max_mb      : Maximum image size in MB (default: 5000)
#   output_file : Output Dockerfile path (default: ./Dockerfile)
#
# EXAMPLE:
#   # Generate 2GB image
#   ./generate-dockerfile-with-size.sh 2000 2000 Dockerfile
#
#   # Generate random 1-5GB image
#   ./generate-dockerfile-with-size.sh 1000 5000 Dockerfile

set -euo pipefail

MIN_SIZE_MB="${1:-1000}"
MAX_SIZE_MB="${2:-5000}"
OUTPUT_FILE="${3:-Dockerfile}"

# Generate random size between min and max
RANDOM_SIZE_MB=$((MIN_SIZE_MB + RANDOM % (MAX_SIZE_MB - MIN_SIZE_MB + 1)))

# Distribute size across multiple layers (more realistic)
# 70% in base layer, 15% in dependencies, 15% in app layer
BASE_LAYER_MB=$((RANDOM_SIZE_MB * 70 / 100))
DEPS_LAYER_MB=$((RANDOM_SIZE_MB * 15 / 100))
APP_LAYER_MB=$((RANDOM_SIZE_MB - BASE_LAYER_MB - DEPS_LAYER_MB))

cat > "${OUTPUT_FILE}" << EOF
# Auto-generated Dockerfile with target size: ${RANDOM_SIZE_MB} MB
# Distribution: Base=${BASE_LAYER_MB}MB, Deps=${DEPS_LAYER_MB}MB, App=${APP_LAYER_MB}MB
FROM registry.access.redhat.com/ubi9/ubi:latest

# Layer 1: Base layer with system packages (~${BASE_LAYER_MB} MB)
RUN dnf install -y \\
    python3 \\
    python3-pip \\
    git \\
    vim \\
    && dnf clean all \\
    && dd if=/dev/urandom of=/opt/base-data.bin bs=1M count=${BASE_LAYER_MB} 2>/dev/null

# Layer 2: Dependencies layer (~${DEPS_LAYER_MB} MB)
RUN mkdir -p /opt/deps \\
    && dd if=/dev/urandom of=/opt/deps/libs.bin bs=1M count=${DEPS_LAYER_MB} 2>/dev/null

# Layer 3: Application layer (~${APP_LAYER_MB} MB)
WORKDIR /app
COPY . /app/
RUN mkdir -p /app/data \\
    && dd if=/dev/urandom of=/app/data/assets.bin bs=1M count=${APP_LAYER_MB} 2>/dev/null \\
    && echo "Image size target: ${RANDOM_SIZE_MB} MB" > /app/size.txt

# Metadata
LABEL maintainer="release-team" \\
      target-size="${RANDOM_SIZE_MB}MB" \\
      base-layer="${BASE_LAYER_MB}MB" \\
      deps-layer="${DEPS_LAYER_MB}MB" \\
      app-layer="${APP_LAYER_MB}MB"

CMD ["/bin/bash", "-c", "cat /app/size.txt && tail -f /dev/null"]
EOF

echo "✅ Generated Dockerfile: ${OUTPUT_FILE}"
echo "   Target size: ${RANDOM_SIZE_MB} MB"
echo "   Distribution: Base=${BASE_LAYER_MB}MB, Deps=${DEPS_LAYER_MB}MB, App=${APP_LAYER_MB}MB"

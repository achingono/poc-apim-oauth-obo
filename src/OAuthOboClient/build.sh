#!/bin/bash
# Note: Before running this script, make sure it is executable:
#   chmod +x build.sh
set -e

# Build script for OAuth OBO Client Docker image

# Configuration
IMAGE_NAME="${IMAGE_NAME:-oauth-obo-client}"
IMAGE_TAG="${IMAGE_TAG:-latest}"
REGISTRY="${REGISTRY:-}"

# If registry is set, prepend it to the image name
if [ -n "$REGISTRY" ]; then
    FULL_IMAGE_NAME="$REGISTRY/$IMAGE_NAME:$IMAGE_TAG"
else
    FULL_IMAGE_NAME="$IMAGE_NAME:$IMAGE_TAG"
fi

echo "Building Docker image: $FULL_IMAGE_NAME"

# Build the Docker image
docker build -t "$FULL_IMAGE_NAME" .

echo "Docker image built successfully: $FULL_IMAGE_NAME"

# Optionally push the image if REGISTRY is set and PUSH is true
if [ -n "$REGISTRY" ] && [ "$PUSH" = "true" ]; then
    echo "Pushing Docker image to registry..."
    docker push "$FULL_IMAGE_NAME"
    echo "Docker image pushed successfully"
fi

echo "Build complete!"

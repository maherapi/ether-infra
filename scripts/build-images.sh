#!/bin/bash

# Build and Push Docker Images for Ethereum Infrastructure
# Builds all custom Docker images and pushes them to the local registry

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
ENV="${1:-local}"
REGISTRY_URL="${REGISTRY_URL:-localhost:5000}"
BUILD_PARALLEL="${BUILD_PARALLEL:-true}"
PUSH_IMAGES="${PUSH_IMAGES:-true}"
FORCE_REBUILD="${FORCE_REBUILD:-false}"

echo -e "${GREEN}=== Building Docker Images for Ethereum Infrastructure ===${NC}"
echo "Environment: $ENV"
echo "Registry: $REGISTRY_URL"
echo "Parallel builds: $BUILD_PARALLEL"
echo "Push images: $PUSH_IMAGES"
echo ""

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check Docker daemon
check_docker() {
    if ! command_exists docker; then
        echo -e "${RED}Docker is required but not installed${NC}"
        exit 1
    fi
    
    if ! docker info >/dev/null 2>&1; then
        echo -e "${RED}Docker daemon is not running${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✓ Docker is available${NC}"
}

# Function to check if image exists
image_exists() {
    local image="$1"
    docker image inspect "$image" >/dev/null 2>&1
}

# Function to build image
build_image() {
    local image_name="$1"
    local dockerfile_path="$2"
    local context_path="$3"
    local full_image="${REGISTRY_URL}/${image_name}"
    
    echo -e "${BLUE}Building image: $image_name${NC}"
    
    # Check if rebuild is needed
    if [ "$FORCE_REBUILD" != "true" ] && image_exists "$full_image"; then
        echo "Image $full_image already exists, skipping build"
        return 0
    fi
    
    # Build the image
    echo "Building $full_image from $dockerfile_path..."
    if docker build -t "$full_image" -f "$dockerfile_path" "$context_path"; then
        echo -e "${GREEN}✓ Successfully built $image_name${NC}"
        
        # Tag as latest
        docker tag "$full_image" "${REGISTRY_URL}/${image_name}:latest"
        
        return 0
    else
        echo -e "${RED}✗ Failed to build $image_name${NC}"
        return 1
    fi
}

# Function to push image
push_image() {
    local image_name="$1"
    local full_image="${REGISTRY_URL}/${image_name}"
    
    if [ "$PUSH_IMAGES" != "true" ]; then
        echo "Skipping push for $image_name (PUSH_IMAGES=false)"
        return 0
    fi
    
    echo -e "${BLUE}Pushing image: $image_name${NC}"
    
    if docker push "$full_image" && docker push "${full_image}:latest"; then
        echo -e "${GREEN}✓ Successfully pushed $image_name${NC}"
        return 0
    else
        echo -e "${RED}✗ Failed to push $image_name${NC}"
        return 1
    fi
}

# Function to build and push image
build_and_push() {
    local image_name="$1"
    local dockerfile_path="$2"
    local context_path="$3"
    
    if build_image "$image_name" "$dockerfile_path" "$context_path"; then
        if [ "$PUSH_IMAGES" = "true" ]; then
            push_image "$image_name"
        fi
        return 0
    else
        return 1
    fi
}

# Function to setup local registry (if needed)
setup_local_registry() {
    if [[ "$REGISTRY_URL" == "localhost:5000" ]] || [[ "$REGISTRY_URL" == "127.0.0.1:5000" ]]; then
        echo -e "${YELLOW}Setting up local registry...${NC}"
        
        # Check if registry is already running
        if curl -f http://$REGISTRY_URL/v2/ >/dev/null 2>&1; then
            echo "Local registry is already running"
            return 0
        fi
        
        # Start local registry if not running
        if ! docker ps | grep -q "registry:2"; then
            echo "Starting local Docker registry..."
            docker run -d -p 5000:5000 --restart=always --name registry registry:2 || true
            sleep 5
        fi
        
        # Verify registry is working
        if ! curl -f http://$REGISTRY_URL/v2/ >/dev/null 2>&1; then
            echo -e "${RED}Failed to start local registry${NC}"
            exit 1
        fi
        
        echo -e "${GREEN}✓ Local registry is ready at $REGISTRY_URL${NC}"
    fi
}

# Function to list images to build
list_images() {
    echo "Images to build:"
    echo "  • ethereum/geth - Optimized Geth client"
    echo "  • ethereum/snapshot-builder - Blockchain snapshot creation tool"
    echo "  • ethereum/delta-sync - Fast sync utility"
    echo ""
}

# Function to build all images sequentially
build_sequential() {
    local failed_builds=()
    
    # Build Geth client
    if ! build_and_push "ethereum/geth" "docker/clients/geth/Dockerfile" "."; then
        failed_builds+=("ethereum/geth")
    fi
    
    # Build snapshot builder
    if ! build_and_push "ethereum/snapshot-builder" "docker/snapshot-builder/Dockerfile" "."; then
        failed_builds+=("ethereum/snapshot-builder")
    fi
    
    # Build delta sync
    if ! build_and_push "ethereum/delta-sync" "docker/delta-sync/Dockerfile" "."; then
        failed_builds+=("ethereum/delta-sync")
    fi
    
    # Report results
    if [ ${#failed_builds[@]} -eq 0 ]; then
        echo -e "${GREEN}✓ All images built successfully${NC}"
        return 0
    else
        echo -e "${RED}✗ Failed to build: ${failed_builds[*]}${NC}"
        return 1
    fi
}

# Function to build all images in parallel
build_parallel() {
    echo -e "${YELLOW}Building images in parallel...${NC}"
    
    # Start builds in background
    (build_and_push "ethereum/geth" "docker/clients/geth/Dockerfile" "." && echo "GETH_SUCCESS" || echo "GETH_FAILED") &
    local geth_pid=$!
    
    (build_and_push "ethereum/snapshot-builder" "docker/snapshot-builder/Dockerfile" "." && echo "SNAPSHOT_SUCCESS" || echo "SNAPSHOT_FAILED") &
    local snapshot_pid=$!
    
    (build_and_push "ethereum/delta-sync" "docker/delta-sync/Dockerfile" "." && echo "DELTA_SUCCESS" || echo "DELTA_FAILED") &
    local delta_pid=$!
    
    # Wait for all builds to complete
    wait $geth_pid
    local geth_status=$?
    
    wait $snapshot_pid
    local snapshot_status=$?
    
    wait $delta_pid
    local delta_status=$?
    
    # Check results
    local failed_count=0
    
    if [ $geth_status -ne 0 ]; then
        echo -e "${RED}✗ Geth build failed${NC}"
        failed_count=$((failed_count + 1))
    fi
    
    if [ $snapshot_status -ne 0 ]; then
        echo -e "${RED}✗ Snapshot builder build failed${NC}"
        failed_count=$((failed_count + 1))
    fi
    
    if [ $delta_status -ne 0 ]; then
        echo -e "${RED}✗ Delta sync build failed${NC}"
        failed_count=$((failed_count + 1))
    fi
    
    if [ $failed_count -eq 0 ]; then
        echo -e "${GREEN}✓ All parallel builds completed successfully${NC}"
        return 0
    else
        echo -e "${RED}✗ $failed_count builds failed${NC}"
        return 1
    fi
}

# Function to cleanup old images
cleanup_images() {
    echo -e "${YELLOW}Cleaning up old images...${NC}"
    
    # Remove dangling images
    docker image prune -f >/dev/null 2>&1 || true
    
    # Remove old tagged images (keep last 3 versions)
    for image in "ethereum/geth" "ethereum/snapshot-builder" "ethereum/delta-sync"; do
        local old_images
        old_images=$(docker images "${REGISTRY_URL}/${image}" --format "table {{.Repository}}:{{.Tag}}" | grep -v "latest" | tail -n +4 || true)
        
        if [ -n "$old_images" ]; then
            echo "Removing old versions of $image..."
            echo "$old_images" | xargs docker rmi 2>/dev/null || true
        fi
    done
    
    echo -e "${GREEN}✓ Image cleanup completed${NC}"
}

# Function to verify images
verify_images() {
    echo -e "${YELLOW}Verifying built images...${NC}"
    
    local images=("ethereum/geth" "ethereum/snapshot-builder" "ethereum/delta-sync")
    local verification_failed=false
    
    for image in "${images[@]}"; do
        local full_image="${REGISTRY_URL}/${image}:latest"
        
        echo -n "Verifying $image... "
        
        if image_exists "$full_image"; then
            # Get image size
            local size
            size=$(docker images "$full_image" --format "{{.Size}}")
            echo -e "${GREEN}✓ ($size)${NC}"
        else
            echo -e "${RED}✗${NC}"
            verification_failed=true
        fi
    done
    
    if [ "$verification_failed" = "true" ]; then
        echo -e "${RED}✗ Image verification failed${NC}"
        return 1
    else
        echo -e "${GREEN}✓ All images verified successfully${NC}"
        return 0
    fi
}

# Function to show usage
show_usage() {
    echo "Usage: $0 [environment] [options]"
    echo ""
    echo "Environment:"
    echo "  local       Build for local development (default)"
    echo "  staging     Build for staging environment"
    echo "  production  Build for production environment"
    echo ""
    echo "Environment Variables:"
    echo "  REGISTRY_URL       Registry URL (default: localhost:5000)"
    echo "  BUILD_PARALLEL     Build images in parallel (default: true)"
    echo "  PUSH_IMAGES        Push images to registry (default: true)"
    echo "  FORCE_REBUILD      Force rebuild even if image exists (default: false)"
    echo ""
    echo "Examples:"
    echo "  $0                                    # Build for local with defaults"
    echo "  $0 staging                           # Build for staging"
    echo "  FORCE_REBUILD=true $0                # Force rebuild all images"
    echo "  BUILD_PARALLEL=false $0              # Build sequentially"
    echo "  PUSH_IMAGES=false $0                 # Build but don't push"
}

# Main function
main() {
    # Show usage if help requested
    if [[ "$1" == "-h" ]] || [[ "$1" == "--help" ]]; then
        show_usage
        exit 0
    fi
    
    # Check prerequisites
    check_docker
    
    # Setup local registry if needed
    setup_local_registry
    
    # List images to build
    list_images
    
    # Build images
    if [ "$BUILD_PARALLEL" = "true" ]; then
        build_parallel
    else
        build_sequential
    fi
    
    # Verify images
    verify_images
    
    # Cleanup old images
    cleanup_images
    
    echo ""
    echo -e "${GREEN}=== Image build process completed! ===${NC}"
    echo "Built images:"
    docker images | grep "$REGISTRY_URL/ethereum" | head -10
    
    echo ""
    echo "Next steps:"
    echo "1. Run 'make deploy-ethereum' to deploy the Ethereum infrastructure"
    echo "2. Run 'make validate' to verify the deployment"
}

# Run main function
main "$@"

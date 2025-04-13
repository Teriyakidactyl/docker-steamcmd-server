#!/bin/bash

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Docker SteamCMD Server Test Script${NC}"
echo "---------------------------------------"

# Define variables
IMAGE="ghcr.io/teriyakidactyl/docker-steamcmd-server:bookworm-20250407-slim-amd64"
CONTAINER_NAME="steamcmd-test-container"
CS_GO_SERVER_APPID="740" # Counter-Strike 2 Dedicated Server

# Check if Docker is installed
echo "Checking Docker installation..."
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Docker is not installed or not in PATH. Please install Docker first.${NC}"
    exit 1
fi
echo -e "${GREEN}Docker is installed.${NC}"

# Pull the image
echo "Pulling the Docker image..."
if ! docker pull $IMAGE; then
    echo -e "${RED}Failed to pull image: $IMAGE${NC}"
    exit 1
fi
echo -e "${GREEN}Image pulled successfully.${NC}"

# Stop and remove container if it already exists
echo "Cleaning up any existing test containers..."
docker rm -f $CONTAINER_NAME &> /dev/null

# Create test directories
echo "Creating test directories..."
TEST_DIR=$(mktemp -d)
mkdir -p $TEST_DIR/app
mkdir -p $TEST_DIR/world
echo -e "${GREEN}Test directories created at $TEST_DIR${NC}"

# Run the container with test command
echo "Running test container..."
docker run --name $CONTAINER_NAME \
    -v $TEST_DIR/app:/app \
    -v $TEST_DIR/world:/world \
    -e STEAM_SERVER_APPID=$CS_GO_SERVER_APPID \
    $IMAGE \
    bash -c "
        echo 'Testing SteamCMD functionality...' && \
        /opt/steamcmd/steamcmd.sh +login anonymous +app_info_print $CS_GO_SERVER_APPID +quit && \
        echo 'SteamCMD test completed.'
    "

# Check container exit code
EXIT_CODE=$?
if [ $EXIT_CODE -eq 0 ]; then
    echo -e "${GREEN}Container exited successfully with code $EXIT_CODE${NC}"
else
    echo -e "${RED}Container exited with error code $EXIT_CODE${NC}"
fi

# Display container logs
echo "Container logs:"
docker logs $CONTAINER_NAME

# Clean up
echo "Cleaning up test resources..."
docker rm -f $CONTAINER_NAME &> /dev/null
rm -rf $TEST_DIR
echo -e "${GREEN}Test resources cleaned up.${NC}"

# Final status
if [ $EXIT_CODE -eq 0 ]; then
    echo -e "${GREEN}Test completed successfully! The container has functioning SteamCMD capabilities.${NC}"
else 
    echo -e "${RED}Test failed! Check the logs for more details.${NC}"
fi

exit $EXIT_CODE
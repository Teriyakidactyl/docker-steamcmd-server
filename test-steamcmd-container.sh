#!/bin/bash
#
# test_steamcmd_container.sh
#
# Test script for verifying functionality of the docker-steamcmd-server base image.
# This script validates core functionality including SteamCMD operations, directory
# structure, environment variables, and utility scripts.
#
# Usage:
#   ./test_steamcmd_container.sh             # Test standard container
#   ./test_steamcmd_container.sh --wine      # Test Wine-enabled container
#
# Exit codes:
#   0 - All tests passed
#   1 - One or more tests failed
#
# Dependencies:
#   - Docker
#   - Internet connection (for pulling images)
#   - About 1GB free disk space

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

echo -e "${YELLOW}Docker SteamCMD Server Comprehensive Test Script${NC}"
echo "-----------------------------------------------"

# Define variables
BASE_IMAGE="ghcr.io/teriyakidactyl/docker-steamcmd-server"
IMAGE_TAG="bookworm-amd64"  # Using top-level tag instead of date tag
CONTAINER_NAME="steamcmd-test-container"
CS_GO_SERVER_APPID="740" # Counter-Strike 2 Dedicated Server

# Check image argument
if [ "$1" == "--wine" ]; then
    echo "Testing Wine-enabled image..."
    IMAGE_TAG="bookworm-wine-amd64"  # Use wine-specific tag
    WINE_ENABLED=true
else
    WINE_ENABLED=false
fi

IMAGE="${BASE_IMAGE}:${IMAGE_TAG}"

# Check if Docker is installed
echo "Checking Docker installation..."
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Docker is not installed or not in PATH. Please install Docker first.${NC}"
    exit 1
fi
echo -e "${GREEN}Docker is installed.${NC}"

# Pull the image
echo "Pulling the Docker image: ${IMAGE}..."
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
mkdir -p $TEST_DIR/world/Mods
echo -e "${GREEN}Test directories created at $TEST_DIR${NC}"

# Define test functions
run_test() {
    local test_name=$1
    local command=$2
    
    echo -e "\n${BLUE}Running test: ${test_name}${NC}"
    echo "Command: $command"
    
    docker run --rm --name $CONTAINER_NAME \
        -v $TEST_DIR/app:/app \
        -v $TEST_DIR/world:/world \
        -e STEAM_SERVER_APPID=$CS_GO_SERVER_APPID \
        $IMAGE \
        bash -c "$command" > $TEST_DIR/test_output.log 2>&1
    
    local EXIT_CODE=$?
    
    if [ $EXIT_CODE -eq 0 ]; then
        echo -e "${GREEN}✓ Test passed${NC}"
    else
        echo -e "${RED}✗ Test failed with exit code $EXIT_CODE${NC}"
        echo -e "${RED}Command output:${NC}"
        cat $TEST_DIR/test_output.log
    fi
    
    return $EXIT_CODE
}

# Array to track failed tests
FAILED_TESTS=()

# Test 1: Check container environment
echo -e "\n${YELLOW}====== Basic Environment Tests ======${NC}"

run_test "Directory Structure" "
    ls -la /opt/steamcmd && \
    ls -la /world && \
    ls -la /app && \
    ls -la /usr/local/bin && \
    ls -la /var/log && \
    echo 'Directory structure verified'
"
if [ $? -ne 0 ]; then FAILED_TESTS+=("Directory Structure"); fi

run_test "Environment Variables" "
    echo STEAMCMD_PATH: \$STEAMCMD_PATH && \
    echo STEAMCMD_PROFILE: \$STEAMCMD_PROFILE && \
    echo STEAM_LIBRARY: \$STEAM_LIBRARY && \
    echo WINEPREFIX: \$WINEPREFIX && \
    echo 'Environment variables verified'
"
if [ $? -ne 0 ]; then FAILED_TESTS+=("Environment Variables"); fi

# Test 2: SteamCMD functionality
echo -e "\n${YELLOW}====== SteamCMD Tests ======${NC}"

run_test "SteamCMD Basic" "
    /opt/steamcmd/steamcmd.sh +login anonymous +quit && \
    echo 'SteamCMD basic functionality verified'
"
if [ $? -ne 0 ]; then FAILED_TESTS+=("SteamCMD Basic"); fi

run_test "SteamCMD App Info" "
    /opt/steamcmd/steamcmd.sh +login anonymous +app_info_print $CS_GO_SERVER_APPID +quit && \
    echo 'SteamCMD app info functionality verified'
"
if [ $? -ne 0 ]; then FAILED_TESTS+=("SteamCMD App Info"); fi

run_test "SteamCMD Validation Script" "
    /usr/local/bin/validate-steamcmd.sh && \
    echo 'SteamCMD validation script verified'
"
if [ $? -ne 0 ]; then FAILED_TESTS+=("SteamCMD Validation Script"); fi

# Test 3: Wine functionality (only if this is a wine-enabled image)
echo -e "\n${YELLOW}====== Wine Tests ======${NC}"

if [ "$WINE_ENABLED" = true ]; then
    run_test "Wine Basic" "
        which wine && which wine64 && which wineboot && \
        echo 'Wine binaries verified'
    "
    if [ $? -ne 0 ]; then FAILED_TESTS+=("Wine Basic"); fi

    run_test "Wine Version" "
        wine --version && \
        echo 'Wine version verified'
    "
    if [ $? -ne 0 ]; then FAILED_TESTS+=("Wine Version"); fi

    run_test "Wine Prefix Setup" "
        [ -d \$WINEPREFIX ] || wine wineboot -i && \
        ls -la \$WINEPREFIX && \
        echo 'Wine prefix setup verified'
    "
    if [ $? -ne 0 ]; then FAILED_TESTS+=("Wine Prefix Setup"); fi
else
    echo -e "${BLUE}Skipping Wine tests for non-Wine image${NC}"
fi

# Test 4: Logging functions
echo -e "\n${YELLOW}====== Logging Tests ======${NC}"

run_test "Logging Functions" "
    source /usr/local/bin/logging_functions && \
    log 'Test log message' && \
    echo 'Logging functions verified'
"
if [ $? -ne 0 ]; then FAILED_TESTS+=("Logging Functions"); fi

# Test 5: Updates functions
echo -e "\n${YELLOW}====== Update Functions Tests ======${NC}"

run_test "Updates Functions" "
    source /usr/local/bin/update_functions && \
    echo 'Update functions loaded' && \
    type server_update >/dev/null && \
    type mod_updates >/dev/null && \
    echo 'Update functions verified'
"
if [ $? -ne 0 ]; then FAILED_TESTS+=("Updates Functions"); fi

# Test 6: Create a small test file for mod simulation
echo "Creating test mod file..."
echo "TestMod" > $TEST_DIR/world/Mods/testmod.pak

run_test "Mod Functions" "
    source /usr/local/bin/update_functions && \
    export WORLD_FILES=/world && \
    export SERVER_ALLOW_LIST='76561197960000000, 76561197960000001' && \
    export STEAM_ALLOW_LIST_PATH='/world/whitelist.txt' && \
    check_whitelist && \
    export SERVER_MOD_IDS='' && \
    mod_updates && \
    cat /world/Mods/modlist.txt && \
    echo 'Mod functions verified'
"
if [ $? -ne 0 ]; then FAILED_TESTS+=("Mod Functions"); fi

# Test 7: Check if up.sh script is functional
echo -e "\n${YELLOW}====== Startup Script Tests ======${NC}"

run_test "Up.sh Script Parsing" "
    cat /usr/local/bin/up.sh && \
    bash -n /usr/local/bin/up.sh && \
    echo 'Up.sh script syntax verified'
"
if [ $? -ne 0 ]; then FAILED_TESTS+=("Up.sh Script Parsing"); fi

# Display final test results
echo -e "\n${YELLOW}====== Test Results Summary ======${NC}"

if [ ${#FAILED_TESTS[@]} -eq 0 ]; then
    echo -e "${GREEN}All tests passed successfully!${NC}"
else
    echo -e "${RED}Failed tests (${#FAILED_TESTS[@]}):"
    for test in "${FAILED_TESTS[@]}"; do
        echo -e "  ✗ $test"
    done
    echo -e "${NC}"
fi

# Clean up
echo -e "\n${YELLOW}====== Cleaning Up ======${NC}"
echo "Removing test resources..."
rm -rf $TEST_DIR
echo -e "${GREEN}Test resources cleaned up.${NC}"

# Return status code based on test results
if [ ${#FAILED_TESTS[@]} -eq 0 ]; then
    echo -e "${GREEN}Test suite completed successfully!${NC}"
    exit 0
else
    echo -e "${RED}Test suite failed! See summary above for details.${NC}"
    exit 1
fi

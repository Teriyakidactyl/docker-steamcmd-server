#!/bin/bash
#
# test_steamcmd_container.sh
#
# Test script for verifying functionality of the docker-steamcmd-server base image.
# This script validates core functionality including SteamCMD operations, directory
# structure, environment variables, and utility scripts across multiple container tags.
#
# Usage:
#   ./test_steamcmd_container.sh             # Test all container tags
#   ./test_steamcmd_container.sh bookworm    # Test only tags containing "bookworm"
#   ./test_steamcmd_container.sh -d          # Test all container tags with debug output
#   ./test_steamcmd_container.sh bookworm -d # Test only tags containing "bookworm" with debug output
#   ./test_steamcmd_container.sh arm64       # Test only ARM64 tags (requires QEMU)
#
# Notes:
#   - ARM64 testing requires QEMU user-static emulation to be installed
#   - ARM64 images will automatically test box86/box64 if present
#
# Exit codes:
#   0 - All tests passed
#   1 - One or more tests failed
#
# Dependencies:
#   - Docker
#   - Internet connection (for pulling images)
#   - About 1GB free disk space per image tested
#
# Installation:
#   wget -O test_steamcmd_container.sh https://raw.githubusercontent.com/Teriyakidactyl/docker-steamcmd-server/dev/test_steamcmd_container.sh
#   chmod +x test_steamcmd_container.sh
#   ./test_steamcmd_container.sh

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Define variables
BASE_IMAGE="ghcr.io/teriyakidactyl/docker-steamcmd-server"
CONTAINER_NAME="steamcmd-test-container"
CS_GO_SERVER_APPID="740" # Counter-Strike 2 Dedicated Server
DEBUG_MODE=false

# Parse command line arguments
TAG_FILTER=""
for arg in "$@"; do
    if [ "$arg" = "-d" ] || [ "$arg" = "--debug" ]; then
        DEBUG_MODE=true
    else
        # If not a flag, treat as tag filter
        TAG_FILTER="$arg"
    fi
done

# Define the tags to test - use _dev suffix for dev branch
# Each tag will be tested in sequence
TAGS_TO_TEST=(
    # AMD64 Tags
    "bookworm_dev-amd64"
    "bookworm-wine_dev-amd64"
    "trixie_dev-amd64"
    "trixie-wine_dev-amd64"
    # ARM64 Tags
    "bookworm_dev-arm64"
    "bookworm-wine_dev-arm64"
    "trixie_dev-arm64"
    "trixie-wine_dev-arm64"
    # Add more tags as needed
)

# Create test directories
TEST_DIR=$(mktemp -d)
mkdir -p $TEST_DIR/app
mkdir -p $TEST_DIR/world
mkdir -p $TEST_DIR/world/Mods

# Global array to track failed tags
FAILED_TAGS=()

# Flag to track if QEMU is set up
QEMU_SETUP=false

# Function to setup QEMU for ARM64 emulation
setup_qemu_emulation() {
    echo -e "\n${YELLOW}====== Setting up QEMU for ARM64 emulation ======${NC}"
    
    # Check if QEMU is already set up
    if docker run --rm --privileged multiarch/qemu-user-static --reset -p yes > /dev/null 2>&1; then
        echo -e "${GREEN}✓ QEMU emulation handlers registered successfully${NC}"
        QEMU_SETUP=true
        return 0
    else
        echo -e "${RED}✗ Failed to set up QEMU emulation${NC}"
        echo -e "${YELLOW}You may need to install qemu-user-static and binfmt-support:${NC}"
        echo -e "  sudo apt-get update"
        echo -e "  sudo apt-get install -y qemu-user-static binfmt-support"
        return 1
    fi
}

# General test function
run_test() {
    local test_name=$1
    local command=$2
    local image=$3
    local platform_args=""
    
    # Check if image contains platform args (--platform linux/arm64)
    if [[ "$image" == *"--platform"* ]]; then
        # Extract platform arguments and image
        platform_args=$(echo "$image" | grep -o '\-\-platform [^ ]*')
        image=$(echo "$image" | sed "s/$platform_args //")
    fi
    
    echo -e "\n${BLUE}Running test: ${test_name}${NC}"
    
    # Run the command and capture output
    docker run --rm --name $CONTAINER_NAME \
        $platform_args \
        -v $TEST_DIR/app:/app \
        -v $TEST_DIR/world:/world \
        -e STEAM_SERVER_APPID=$CS_GO_SERVER_APPID \
        -e PATH=$PATH:/opt/wine-staging/bin \
        $image \
        bash -c "$command" > $TEST_DIR/test_output.log 2>&1
    
    local EXIT_CODE=$?
    
    # Display test result
    if [ $EXIT_CODE -eq 0 ]; then
        echo -e "${GREEN}✓ Test passed${NC}"
        # If debug mode is enabled, show the command output even for successful tests
        if [ "$DEBUG_MODE" = true ]; then
            echo -e "${YELLOW}Command output:${NC}"
            cat $TEST_DIR/test_output.log
        fi
    else
        echo -e "${RED}✗ Test failed with exit code $EXIT_CODE${NC}"
        echo -e "${RED}Command output:${NC}"
        cat $TEST_DIR/test_output.log
    fi
    
    return $EXIT_CODE
}

#
# Test Functions - Each one tests a specific aspect of the container
#

test_directories() {
    local image=$1
    echo -e "\n${YELLOW}====== Directory Structure Tests ======${NC}"
    
    run_test "Directory Structure" "
        ls -la /opt/steamcmd && \
        ls -la /world && \
        ls -la /app && \
        ls -la /usr/local/bin && \
        ls -la /var/log && \
        echo 'Directory structure verified'
    " "$image"
    
    return $?
}

test_environment_vars() {
    local image=$1
    echo -e "\n${YELLOW}====== Environment Variable Tests ======${NC}"
    
    run_test "Environment Variables" "
        echo STEAMCMD_PATH: \$STEAMCMD_PATH && \
        echo STEAMCMD_PROFILE: \$STEAMCMD_PROFILE && \
        echo STEAM_LIBRARY: \$STEAM_LIBRARY && \
        echo WINEPREFIX: \$WINEPREFIX && \
        echo 'Environment variables verified'
    " "$image"
    
    return $?
}

test_steamcmd_basic() {
    local image=$1
    echo -e "\n${YELLOW}====== SteamCMD Basic Tests ======${NC}"
    
    run_test "SteamCMD Basic" "
        /opt/steamcmd/steamcmd.sh +login anonymous +quit && \
        echo 'SteamCMD basic functionality verified'
    " "$image"
    
    return $?
}

test_steamcmd_app_info() {
    local image=$1
    echo -e "\n${YELLOW}====== SteamCMD App Info Tests ======${NC}"
    
    run_test "SteamCMD App Info" "
        /opt/steamcmd/steamcmd.sh +login anonymous +app_info_print $CS_GO_SERVER_APPID +quit && \
        echo 'SteamCMD app info functionality verified'
    " "$image"
    
    return $?
}

test_steamcmd_validation() {
    local image=$1
    echo -e "\n${YELLOW}====== SteamCMD Validation Script Tests ======${NC}"
    
    run_test "SteamCMD Validation Script" "
        /usr/local/bin/validate-steamcmd.sh && \
        echo 'SteamCMD validation script verified'
    " "$image"
    
    return $?
}

test_wine_basic() {
    local image=$1
    echo -e "\n${YELLOW}====== Wine Basic Tests ======${NC}"
    
    run_test "Wine Basic" "
        which wine && which wine64 && which wineboot && \
        echo 'Wine binaries verified'
    " "$image"
    
    return $?
}

test_wine_version() {
    local image=$1
    echo -e "\n${YELLOW}====== Wine Version Tests ======${NC}"
    
    run_test "Wine Version" "
        wine --version && \
        echo 'Wine version verified'
    " "$image"
    
    return $?
}

test_wine_prefix() {
    local image=$1
    echo -e "\n${YELLOW}====== Wine Prefix Tests ======${NC}"
    
    run_test "Wine Prefix Setup" "
        [ -d \$WINEPREFIX ] || wine wineboot -i && \
        ls -la \$WINEPREFIX && \
        echo 'Wine prefix setup verified'
    " "$image"
    
    return $?
}

test_logging_functions() {
    local image=$1
    echo -e "\n${YELLOW}====== Logging Functions Tests ======${NC}"
    
    run_test "Logging Functions" "
        source /usr/local/bin/logging_functions && \
        log 'Test log message' && \
        echo 'Logging functions verified'
    " "$image"
    
    return $?
}

test_update_functions() {
    local image=$1
    echo -e "\n${YELLOW}====== Update Functions Tests ======${NC}"
    
    run_test "Updates Functions" "
        source /usr/local/bin/update_functions && \
        echo 'Update functions loaded' && \
        type server_update >/dev/null && \
        type mod_updates >/dev/null && \
        echo 'Update functions verified'
    " "$image"
    
    return $?
}

test_mod_functions() {
    local image=$1
    echo -e "\n${YELLOW}====== Mod Functions Tests ======${NC}"
    
    # Create a test mod file
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
    " "$image"
    
    return $?
}

test_startup_script() {
    local image=$1
    echo -e "\n${YELLOW}====== Startup Script Tests ======${NC}"
    
    run_test "Up.sh Script Parsing" "
        cat /usr/local/bin/up.sh && \
        bash -n /usr/local/bin/up.sh && \
        echo 'Up.sh script syntax verified'
    " "$image"
    
    return $?
}

test_box86_box64() {
    local image=$1
    echo -e "\n${YELLOW}====== Box86/Box64 Tests ======${NC}"
    
    # Test box86 if present
    run_test "Box86 Version" "
        if command -v box86 &> /dev/null; then
            box86 --version && echo 'Box86 version verified'
        else
            echo 'Box86 not found, skipping test'
            exit 0
        fi
    " "$image"
    
    local box86_result=$?
    
    # Test box64 if present
    run_test "Box64 Version" "
        if command -v box64 &> /dev/null; then
            box64 --version && echo 'Box64 version verified'
        else
            echo 'Box64 not found, skipping test'
            exit 0
        fi
    " "$image"
    
    local box64_result=$?
    
    # Return success if at least one of them worked or was skipped gracefully
    [ $box86_result -eq 0 ] || [ $box64_result -eq 0 ]
    return $?
}

# Run tests on a container image
test_container() {
    local tag=$1
    local image="${BASE_IMAGE}:${tag}"
    local failed_tests=()
    local platform="linux/amd64"
    
    # Determine if this is an ARM64 image
    if [[ "$tag" == *"-arm64"* ]]; then
        platform="linux/arm64"
        
        # Check if QEMU is set up
        if [ "$QEMU_SETUP" = false ]; then
            echo -e "\n${YELLOW}====== ARM64 image detected but QEMU not set up ======${NC}"
            echo -e "${YELLOW}Attempting to set up QEMU emulation...${NC}"
            if ! setup_qemu_emulation; then
                echo -e "${RED}Skipping ARM64 image ${tag} due to missing QEMU emulation${NC}"
                FAILED_TAGS+=("$tag - Skipped: QEMU setup failed")
                return 1
            fi
        fi
    fi
    
    echo -e "\n${BOLD}${CYAN}====== Testing Container: ${image} (${platform}) ======${NC}"
    
    # Pull the image
    echo "Pulling the Docker image: ${image}..."
    if ! docker pull --platform ${platform} $image; then
        echo -e "${RED}Failed to pull image: $image${NC}"
        FAILED_TAGS+=("$tag - Failed to pull image")
        return 1
    fi
    echo -e "${GREEN}Image pulled successfully.${NC}"
    
    # Modify run_test function calls to include platform
    local original_run_test=run_test
    function run_test() {
        local test_name=$1
        local command=$2
        local img=$3
        
        $original_run_test "$test_name" "$command" "--platform ${platform} $img"
    }
    
    # Run the base tests that all containers should pass
    test_directories "$image" || failed_tests+=("Directory Structure")
    test_environment_vars "$image" || failed_tests+=("Environment Variables")
    test_steamcmd_basic "$image" || failed_tests+=("SteamCMD Basic")
    test_steamcmd_app_info "$image" || failed_tests+=("SteamCMD App Info")
    test_steamcmd_validation "$image" || failed_tests+=("SteamCMD Validation")
    test_logging_functions "$image" || failed_tests+=("Logging Functions")
    test_update_functions "$image" || failed_tests+=("Update Functions")
    test_mod_functions "$image" || failed_tests+=("Mod Functions")
    test_startup_script "$image" || failed_tests+=("Startup Script")
    
    # Run wine-specific tests only for wine-enabled images
    if [[ "$tag" == *"wine"* ]]; then
        echo -e "${BLUE}Detected Wine-enabled image, running Wine tests...${NC}"
        test_wine_basic "$image" || failed_tests+=("Wine Basic")
        test_wine_version "$image" || failed_tests+=("Wine Version")
        test_wine_prefix "$image" || failed_tests+=("Wine Prefix")
    else
        echo -e "${BLUE}Skipping Wine tests for non-Wine image${NC}"
    fi
    
    # Run box86/box64 tests only for ARM64 images
    if [[ "$platform" == "linux/arm64" ]]; then
        echo -e "${BLUE}Detected ARM64 image, running Box86/Box64 tests...${NC}"
        test_box86_box64 "$image" || failed_tests+=("Box86/Box64")
    fi
    
    # Restore original run_test function
    run_test=$original_run_test
    
    # Display test results for this container
    if [ ${#failed_tests[@]} -eq 0 ]; then
        echo -e "\n${GREEN}✓ All tests passed for ${tag}!${NC}"
    else
        echo -e "\n${RED}✗ Failed tests for ${tag}:"
        for test in "${failed_tests[@]}"; do
            echo -e "  - $test"
        done
        echo -e "${NC}"
        FAILED_TAGS+=("$tag - Failed tests: ${failed_tests[*]}")
    fi
}

#
# Main execution logic
#

echo -e "${YELLOW}Docker SteamCMD Server Multi-Container Test Script${NC}"
echo "-----------------------------------------------"
if [ "$DEBUG_MODE" = true ]; then
    echo -e "${BLUE}Debug mode enabled - Command output will be displayed for all tests${NC}"
fi

# Check if Docker is installed
echo "Checking Docker installation..."
if ! command -v docker &> /dev/null; then
    echo -e "${RED}Docker is not installed or not in PATH. Please install Docker first.${NC}"
    exit 1
fi
echo -e "${GREEN}Docker is installed.${NC}"

# Clean up any existing test containers
echo "Cleaning up any existing test containers..."
docker rm -f $CONTAINER_NAME &> /dev/null

# If a filter was provided, only test tags that match
if [ -n "$TAG_FILTER" ]; then
    echo -e "${BLUE}Filter provided: '$TAG_FILTER' - Only testing matching tags${NC}"
    FILTERED_TAGS=()
    for tag in "${TAGS_TO_TEST[@]}"; do
        if [[ "$tag" == *"$TAG_FILTER"* ]]; then
            FILTERED_TAGS+=("$tag")
        fi
    done
    TAGS_TO_TEST=("${FILTERED_TAGS[@]}")
    
    if [ ${#TAGS_TO_TEST[@]} -eq 0 ]; then
        echo -e "${RED}No tags matched the filter '$TAG_FILTER'${NC}"
        exit 1
    fi
fi

echo -e "${BLUE}Will test the following container tags:${NC}"
for tag in "${TAGS_TO_TEST[@]}"; do
    echo "  - $tag"
done

# Check if we need to set up QEMU for ARM64 testing
ARM64_NEEDED=false
for tag in "${TAGS_TO_TEST[@]}"; do
    if [[ "$tag" == *"-arm64"* ]]; then
        ARM64_NEEDED=true
        break
    fi
done

if [ "$ARM64_NEEDED" = true ]; then
    echo -e "${BLUE}ARM64 images detected, setting up QEMU emulation...${NC}"
    setup_qemu_emulation
    # If QEMU setup failed, we'll skip ARM64 images during testing
fi

# Test each container in the array
for tag in "${TAGS_TO_TEST[@]}"; do
    test_container "$tag"
done

# Display final test results
echo -e "\n${BOLD}${YELLOW}====== Final Test Results Summary ======${NC}"

if [ ${#FAILED_TAGS[@]} -eq 0 ]; then
    echo -e "${GREEN}All container tests passed successfully!${NC}"
else
    echo -e "${RED}Failed containers (${#FAILED_TAGS[@]}):"
    for tag in "${FAILED_TAGS[@]}"; do
        echo -e "  ✗ $tag"
    done
    echo -e "${NC}"
fi

# Clean up
echo -e "\n${YELLOW}====== Cleaning Up ======${NC}"
echo "Removing test resources..."
rm -rf $TEST_DIR
echo -e "${GREEN}Test resources cleaned up.${NC}"

# Return status code based on test results
if [ ${#FAILED_TAGS[@]} -eq 0 ]; then
    echo -e "${GREEN}Test suite completed successfully!${NC}"
    exit 0
else
    echo -e "${RED}Test suite failed! See summary above for details.${NC}"
    exit 1
fi

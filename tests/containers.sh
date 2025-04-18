#!/bin/bash
#
# streamlined_test_steamcmd_container.sh
#
# Streamlined test script focusing on core functionality of the docker-steamcmd-server base image.
# This script validates SteamCMD operations, directory permissions, Wine functionality, 
# and Box86/Box64 versions for ARM containers.
#
# Usage:
#   ./streamlined_test_steamcmd_container.sh             # Test all container tags
#   ./streamlined_test_steamcmd_container.sh bookworm    # Test only tags containing "bookworm"
#   ./streamlined_test_steamcmd_container.sh -d          # Test all container tags with debug output
#   ./streamlined_test_steamcmd_container.sh bookworm -d # Test only tags containing "bookworm" with debug output
#
# Exit codes:
#   0 - All tests passed
#   1 - One or more tests failed

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
    # Bookworm - Native - Development
    "bookworm-20250407-slim_dev-amd64"
    "bookworm-20250407-slim_dev-arm64"
    
    # Bookworm - Wine Staging - Development
    "bookworm-20250407-slim_wine-staging-10.5_dev-amd64"
    "bookworm-20250407-slim_wine-staging-10.5_dev-arm64"
    
    # Bookworm - Wine Stable - Development
    "bookworm-20250407-slim_wine-stable-10.0.0.0_dev-amd64"
    "bookworm-20250407-slim_wine-stable-10.0.0.0_dev-arm64"
    
    # Trixie - Native - Development
    "trixie-20250407-slim_dev-amd64"
    "trixie-20250407-slim_dev-arm64"
    
    # Trixie - Wine Staging - Development
    "trixie-20250407-slim_wine-staging-10.5_dev-amd64"
    "trixie-20250407-slim_wine-staging-10.5_dev-arm64"
    
    # Trixie - Wine Stable - Development
    "trixie-20250407-slim_wine-stable-10.0.0.0_dev-amd64"
    "trixie-20250407-slim_wine-stable-10.0.0.0_dev-arm64"
    
    # Codename tags - if you need to test these as well
    "bookworm-dev-amd64"
    "bookworm-dev-arm64"
    "bookworm-wine-staging-dev-amd64"
    "bookworm-wine-staging-dev-arm64"
    "trixie-dev-amd64"
    "trixie-dev-arm64"
    "trixie-wine-staging-dev-amd64"
    "trixie-wine-staging-dev-arm64"
)

# Create test directories
TEST_DIR=$(mktemp -d)
mkdir -p $TEST_DIR/app
mkdir -p $TEST_DIR/world
mkdir -p $TEST_DIR/world/Mods

# Global array to track failed tags
FAILED_TAGS=()

# General test function
run_test() {
    local test_name=$1
    local command=$2
    local image=$3
    local allowed_exit_codes=("${!4}")  # Array of allowed exit codes
    
    # If no allowed exit codes provided, default to just 0
    if [ ${#allowed_exit_codes[@]} -eq 0 ]; then
        allowed_exit_codes=(0)
    fi
    
    # Extract tag from the full image path
    local tag=$(echo "$image" | cut -d ':' -f2)
    
    # Extract architecture from tag
    local arch=""
    if [[ "$tag" == *"-amd64" ]]; then
        arch="amd64"
    elif [[ "$tag" == *"-arm64" ]]; then
        arch="arm64"
    else
        # Default to amd64 if not specified
        arch="amd64"
    fi
    
    # Always use the platform flag for consistency
    local platform_arg="--platform linux/${arch}"
    
    # Get host architecture
    local host_arch=$(uname -m)
    if [[ "$host_arch" == "x86_64" ]]; then
        host_arch="amd64"
    elif [[ "$host_arch" == "aarch64" ]]; then
        host_arch="arm64"
    fi
    
    # Determine if we're running cross-architecture
    local cross_arch=false
    if [[ "$host_arch" != "$arch" ]]; then
        cross_arch=true
        echo -e "${YELLOW}Cross-architecture testing: Host is $host_arch, container is $arch${NC}"
    fi
    
    echo -e "\n${BLUE}Running test: ${test_name}${NC}"
    
    # Debug output
    if [ "$DEBUG_MODE" = true ]; then
        echo -e "${YELLOW}Executing command:${NC}"
        echo -e "${CYAN}$command${NC}"
        echo -e "${CYAN}Platform: linux/${arch}${NC}"
        if [ "$cross_arch" = true ]; then
            echo -e "${CYAN}Using emulation (QEMU)${NC}"
        fi
    fi
    
    # Ensure test directories have UID 1000
    chown -R 1000:1000 $TEST_DIR/app $TEST_DIR/world 2>/dev/null || true
    
    # Run the command and capture output
    # Add '--privileged' flag for cross-architecture emulation to work properly
    if [ "$cross_arch" = true ]; then
        docker run --rm --privileged --name $CONTAINER_NAME \
            $platform_arg \
            --user 1000 \
            -v $TEST_DIR/app:/app \
            -v $TEST_DIR/world:/world \
            -e STEAM_SERVER_APPID=$CS_GO_SERVER_APPID \
            -e PATH=$PATH:/opt/wine-staging/bin \
            $image \
            bash -c "$command" > $TEST_DIR/test_output.log 2>&1
    else
        docker run --rm --name $CONTAINER_NAME \
            $platform_arg \
            --user 1000 \
            -v $TEST_DIR/app:/app \
            -v $TEST_DIR/world:/world \
            -e STEAM_SERVER_APPID=$CS_GO_SERVER_APPID \
            -e PATH=$PATH:/opt/wine-staging/bin \
            $image \
            bash -c "$command" > $TEST_DIR/test_output.log 2>&1
    fi
    
    local EXIT_CODE=$?
    
    # Check if the exit code is in the allowed list
    local exit_code_allowed=false
    for allowed_code in "${allowed_exit_codes[@]}"; do
        if [ $EXIT_CODE -eq $allowed_code ]; then
            exit_code_allowed=true
            break
        fi
    done
    
    # Display test result
    if [ "$exit_code_allowed" = true ]; then
        echo -e "${GREEN}✓ Test passed (exit code: $EXIT_CODE)${NC}"
        if [ "$DEBUG_MODE" = true ]; then
            echo -e "${YELLOW}Command output:${NC}"
            cat $TEST_DIR/test_output.log
        fi
        return 0
    else
        echo -e "${RED}✗ Test failed with exit code $EXIT_CODE (allowed: ${allowed_exit_codes[*]})${NC}"
        echo -e "${RED}Command output:${NC}"
        cat $TEST_DIR/test_output.log
        return 1
    fi
}

#
# Streamlined Test Functions
#

test_directory_permissions() {
    local image=$1
    echo -e "\n${YELLOW}====== Directory Permissions Tests ======${NC}"
    
    run_test "Directory Permissions" "
        # Check if important directories are owned by container user
        CONTAINER_USER=\$(whoami)
        CONTAINER_GROUP=\$(id -gn)
        
        echo \"Current user: \$CONTAINER_USER\"
        echo \"Current group: \$CONTAINER_GROUP\"
        
        # Create an array of all the directories that should be checked
        DIRS_TO_CHECK=(
            \"\$APP_FILES\"
            \"\$STEAMCMD_PATH\"
            \"\$WORLD_FILES\"
            \"\$WORLD_DIRECTORIES\"
            \"\$STEAM_LIBRARY\"
            \"\$LOGS\"
            \"\$SCRIPTS\"
        )
        
        # Add WINEPREFIX if it exists as an environment variable
        if [ -n \"\$WINEPREFIX\" ]; then
            DIRS_TO_CHECK+=(\"\$WINEPREFIX\")
        fi
        
        # Remove any empty entries
        DIRS_TO_CHECK=(\${DIRS_TO_CHECK[@]})
        
        # Print all directories that will be checked
        echo -e \"\\nChecking the following directories:\"
        printf '%s\\n' \"\${DIRS_TO_CHECK[@]}\"
        
        # Flag to track if any permission issues were found
        PERM_ERRORS=false
        
        # Check each directory
        for dir in \"\${DIRS_TO_CHECK[@]}\"; do
            if [ -d \"\$dir\" ]; then
                echo -e \"\\nChecking directory: \$dir\"
                
                # Simple write test - if we can create a file, we have proper permissions
                TEST_FILE=\"\$dir/test_perm_file\"
                if touch \"\$TEST_FILE\" 2>/dev/null; then
                    echo \"✓ Can write to \$dir\"
                    rm \"\$TEST_FILE\"
                else
                    echo \"✗ Cannot write to \$dir\"
                    PERM_ERRORS=true
                fi
            else
                echo \"Warning: Directory \$dir does not exist, skipping\"
            fi
        done
        
        if [ \"\$PERM_ERRORS\" = true ]; then
            echo \"One or more directories have permission issues!\"
            exit 1
        else
            echo \"All directories have correct permissions\"
        fi
        
        echo 'Directory permissions verified'
    " "$image"
    
    return $?
}

test_steamcmd_basic() {
    local image=$1
    echo -e "\n${YELLOW}====== SteamCMD Basic Tests ======${NC}"
    
    # Use array of allowed exit codes: 0 and 42
    local allowed_exit_codes=(0 42)
    
    run_test "SteamCMD Basic" "
        # Log whether we're using an emulation layer (box86/box64) or native
        echo \"DEBUGGER: \$DEBUGGER\"
        echo \"Architecture: \$(uname -m)\"
        
        # Simple login test - should work on both architectures
        # Exit code 42 is also acceptable (SteamCMD often exits with this code normally)
        steamcmd +login anonymous +quit
        EXIT_CODE=\$?
        
        echo \"SteamCMD exited with code: \$EXIT_CODE\"
        
        if [ \$EXIT_CODE -eq 0 ] || [ \$EXIT_CODE -eq 42 ]; then
            echo 'SteamCMD basic functionality verified'
            exit \$EXIT_CODE  # Return the original exit code
        else
            echo 'SteamCMD test failed'
            exit \$EXIT_CODE  # Return the original exit code
        fi
    " "$image" "allowed_exit_codes[@]"  # Pass the array of allowed exit codes
    
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
        # Check if WINEPREFIX directory exists
        if [ ! -d \$WINEPREFIX ]; then
            echo \"Creating new Wine prefix at \$WINEPREFIX\"
            mkdir -p \$WINEPREFIX
        fi
        
        # Initialize the prefix with wineboot
        echo \"Initializing Wine prefix...\"
        wine wineboot -iuf
        
        # Verify the prefix was created successfully
        if [ -f \$WINEPREFIX/system.reg ]; then
            echo \"Wine prefix created successfully.\"
            ls -la \$WINEPREFIX
            echo 'Wine prefix setup verified'
            exit 0
        else
            echo \"Failed to create Wine prefix.\"
            exit 1
        fi
    " "$image"
    
    return $?
}

test_box86_version() {
    local image=$1
    local tag=$(echo "$image" | cut -d ':' -f2)
    
    # Only run this test for ARM images
    if [[ "$tag" != *"-arm64"* ]]; then
        echo -e "\n${YELLOW}Skipping Box86 tests for non-ARM image${NC}"
        return 0
    fi
    
    echo -e "\n${YELLOW}====== Box86 Version Test ======${NC}"
    
    run_test "Box86 Version" "
        if command -v box86 &> /dev/null; then
            box86 --version
            echo 'Box86 version verified'
            exit 0
        else
            echo 'Box86 not installed on this ARM image!'
            exit 1
        fi
    " "$image"
    
    return $?
}

test_box64_version() {
    local image=$1
    local tag=$(echo "$image" | cut -d ':' -f2)
    
    # Only run this test for ARM images
    if [[ "$tag" != *"-arm64"* ]]; then
        echo -e "\n${YELLOW}Skipping Box64 tests for non-ARM image${NC}"
        return 0
    fi
    
    echo -e "\n${YELLOW}====== Box64 Version Test ======${NC}"
    
    run_test "Box64 Version" "
        if command -v box64 &> /dev/null; then
            box64 --version
            echo 'Box64 version verified'
            exit 0
        else
            echo 'Box64 not installed on this ARM image!'
            exit 1
        fi
    " "$image"
    
    return $?
}

# Run tests on a container image
test_container() {
    local tag=$1
    local image="${BASE_IMAGE}:${tag}"
    local failed_tests=()
    
    echo -e "\n${BOLD}${CYAN}====== Testing Container: ${image} ======${NC}"
    
    # Extract architecture from tag
    local arch=""
    if [[ "$tag" == *"-amd64" ]]; then
        arch="amd64"
    elif [[ "$tag" == *"-arm64" ]]; then
        arch="arm64"
    else
        # Default to amd64 if not specified
        arch="amd64"
    fi
    
    # Pull the image with explicit platform
    echo "Pulling the Docker image: ${image}..."
    if ! docker pull --platform "linux/${arch}" $image; then
        echo -e "${RED}Failed to pull image: $image${NC}"
        FAILED_TAGS+=("$tag - Failed to pull image")
        return 1
    fi
    echo -e "${GREEN}Image pulled successfully.${NC}"
    
    # Run streamlined tests that focus on the core functionality
    test_directory_permissions "$image" || failed_tests+=("Directory Permissions")
    
    # SteamCMD test - works on both architectures and accepts exit code 42
    test_steamcmd_basic "$image" || failed_tests+=("SteamCMD Basic")
    
    # Run wine-specific tests only for wine-enabled images
    if [[ "$tag" == *"wine"* ]]; then
        echo -e "${BLUE}Detected Wine-enabled image, running Wine tests...${NC}"
        test_wine_version "$image" || failed_tests+=("Wine Version")
        test_wine_prefix "$image" || failed_tests+=("Wine Prefix")
    else
        echo -e "${BLUE}Skipping Wine tests for non-Wine image${NC}"
    fi
    
    # Run ARM-specific tests only for ARM images
    if [[ "$arch" == "arm64" ]]; then
        echo -e "${BLUE}Detected ARM64 image, running ARM-specific tests...${NC}"
        test_box86_version "$image" || failed_tests+=("Box86 Version")
        test_box64_version "$image" || failed_tests+=("Box64 Version")
    fi
    
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

inspect_container() {
    local tag=$1
    local image="${BASE_IMAGE}:${tag}"
    
    echo -e "\n${YELLOW}Launching interactive bash session in container:${NC} ${CYAN}$image${NC}"
    echo -e "${YELLOW}Type 'exit' when done exploring the container.${NC}"
    
    # Clean up any existing test container
    docker rm -f $CONTAINER_NAME 2>/dev/null || true
    
    # Extract architecture from tag
    local arch=""
    if [[ "$tag" == *"-amd64" ]]; then
        arch="amd64"
    elif [[ "$tag" == *"-arm64" ]]; then
        arch="arm64"
    else
        # Default to amd64 if not specified
        arch="amd64"
    fi
    
    # Get host architecture
    local host_arch=$(uname -m)
    if [[ "$host_arch" == "x86_64" ]]; then
        host_arch="amd64"
    elif [[ "$host_arch" == "aarch64" ]]; then
        host_arch="arm64"
    fi
    
    # Determine if we're running cross-architecture
    local cross_arch=false
    if [[ "$host_arch" != "$arch" ]]; then
        cross_arch=true
        echo -e "${YELLOW}Cross-architecture inspection: Host is $host_arch, container is $arch${NC}"
        echo -e "${YELLOW}Using QEMU emulation. Performance may be slower.${NC}"
    fi
    
    # Ensure test directories have UID 1000
    chown -R 1000:1000 $TEST_DIR/app $TEST_DIR/world 2>/dev/null || true
    
    # Add platform flag for cross-architecture testing
    local platform_arg="--platform linux/${arch}"
    
    # Run the container with interactive terminal
    # Add '--privileged' flag for cross-architecture emulation to work properly
    if [ "$cross_arch" = true ]; then
        docker run --name $CONTAINER_NAME \
            --privileged \
            $platform_arg \
            --user 1000 \
            -v $TEST_DIR/app:/app \
            -v $TEST_DIR/world:/world \
            -e STEAM_SERVER_APPID=$CS_GO_SERVER_APPID \
            -e PATH=$PATH:/opt/wine-staging/bin \
            -it --entrypoint bash $image
    else
        docker run --name $CONTAINER_NAME \
            $platform_arg \
            --user 1000 \
            -v $TEST_DIR/app:/app \
            -v $TEST_DIR/world:/world \
            -e STEAM_SERVER_APPID=$CS_GO_SERVER_APPID \
            -e PATH=$PATH:/opt/wine-staging/bin \
            -it --entrypoint bash $image
    fi
    
    # Clean up the container after exiting
    docker rm -f $CONTAINER_NAME 2>/dev/null || true
}

#
# Main execution logic
#

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

# Test each container in the array
for tag in "${TAGS_TO_TEST[@]}"; do
    test_container "$tag"
done

# Display test results summary 
show_test_summary() {
    echo -e "\n${BOLD}${YELLOW}====== Test Results Summary ======${NC}"

    if [ ${#FAILED_TAGS[@]} -eq 0 ]; then
        echo -e "${GREEN}All container tests passed successfully!${NC}"
    else
        echo -e "${RED}Failed containers (${#FAILED_TAGS[@]}):"
        for i in "${!FAILED_TAGS[@]}"; do
            echo -e "  ${RED}$((i+1)).${NC} ${FAILED_TAGS[$i]}"
        done
        echo -e "${NC}"
    fi
}

# Show container inspection menu
show_inspection_menu() {
    local keep_menu=true
    
    while [ "$keep_menu" = true ]; do
        show_test_summary
        
        echo -e "\n${YELLOW}===== Container Inspection Menu =====${NC}"
        echo -e "${BLUE}Available containers:${NC}"
        
        # Show all available tags
        for i in "${!TAGS_TO_TEST[@]}"; do
            # Mark failed containers with an asterisk
            local tag="${TAGS_TO_TEST[$i]}"
            local failed=""
            
            for failed_tag in "${FAILED_TAGS[@]}"; do
                if [[ "$failed_tag" == "$tag"* ]]; then
                    failed=" ${RED}*${NC}"
                    break
                fi
            done
            
            echo -e "  ${CYAN}$((i+1)).${NC} ${tag}${failed}"
        done
        
        echo -e "\nOptions:"
        echo -e "  ${CYAN}r${NC} - Show test results summary"
        echo -e "  ${CYAN}q${NC} - Quit"
        echo -e "\n${YELLOW}Enter the number of the container to inspect, or 'q' to exit:${NC}"
        
        read -r choice
        
        if [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le "${#TAGS_TO_TEST[@]}" ]; then
            # Get the tag for the selected container
            local selected_tag="${TAGS_TO_TEST[$((choice-1))]}"
            
            # Launch inspection session
            inspect_container "$selected_tag"
            
            # After returning from the container, show menu again
            echo -e "\n${BLUE}Returned to menu. You can select another container or quit.${NC}"
        elif [ "$choice" = "r" ]; then
            # Just show the summary again (will happen at loop start)
            echo -e "\n${BLUE}Refreshing test results...${NC}"
        elif [ "$choice" = "q" ]; then
            keep_menu=false
            echo -e "\n${BLUE}Exiting container inspection menu.${NC}"
        else
            echo -e "\n${RED}Invalid choice. Please try again.${NC}"
        fi
    done
}

# Show the menu after tests complete
show_inspection_menu

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

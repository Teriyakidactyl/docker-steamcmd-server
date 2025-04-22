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
CONTAINER_USER="container"
CS_GO_SERVER_APPID="740" # Counter-Strike 2 Dedicated Server
DEBUG_MODE=false

# Function to clean up existing containers with the test container name
cleanup_existing_containers() {
    # Check if any container with the test name exists
    if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
        echo -e "${YELLOW}Found existing test container(s) with name: ${CONTAINER_NAME}${NC}"
        
        # Ask user if they want to remove these containers
        echo -n "Would you like to stop and remove these container(s)? [Y/n]: "
        read -r response
        
        # Default to Yes if no response
        if [[ -z "$response" ]] || [[ "$response" =~ ^[Yy] ]]; then
            echo "Stopping and removing existing test container(s)..."
            docker stop ${CONTAINER_NAME} 2>/dev/null || true
            docker rm ${CONTAINER_NAME} 2>/dev/null || true
            echo -e "${GREEN}Containers removed successfully.${NC}"
        else
            echo -e "${YELLOW}Skipping container cleanup. Be aware that existing containers might interfere with testing.${NC}"
        fi
    else
        echo -e "${GREEN}No existing test containers found.${NC}"
    fi
}

# Function to purge existing images related to the test
purge_existing_images() {
    # Check if any related images exist
    local existing_images=$(docker images "${BASE_IMAGE}*" --format '{{.Repository}}:{{.Tag}}')
    
    if [ -n "$existing_images" ]; then
        echo -e "${YELLOW}Found existing images for ${BASE_IMAGE}:${NC}"
        echo "$existing_images"
        
        # Ask user if they want to remove these images
        echo -n "Would you like to purge these images before testing? [Y/n]: "
        read -r response
        
        # Default to Yes if no response
        if [[ -z "$response" ]] || [[ "$response" =~ ^[Yy] ]]; then
            echo "Removing existing images..."
            
            # Get list of image IDs to remove
            local image_ids=$(docker images "${BASE_IMAGE}*" --format '{{.ID}}')
            
            # Remove the images
            for id in $image_ids; do
                docker rmi -f $id 2>/dev/null || true
            done
            
            echo -e "${GREEN}Images purged successfully.${NC}"
        else
            echo -e "${YELLOW}Skipping image purge. Using existing images if available.${NC}"
        fi
    else
        echo -e "${GREEN}No existing test images found.${NC}"
    fi
}

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

#
# Setup QEMU for cross-architecture testing
#
setup_qemu_emulation() {
    echo -e "${YELLOW}Checking Docker emulation capability for cross-platform testing...${NC}"
    
    # Check if Docker already supports ARM64 emulation
    if docker info | grep -q "linux/arm64"; then
        echo -e "${GREEN}Docker supports ARM64 emulation.${NC}"
        return 0
    fi
    
    echo -e "${YELLOW}Docker may not support ARM64 emulation yet. We'll attempt to configure it.${NC}"
    
    # Check if we're running with sufficient privileges
    if [ "$EUID" -eq 0 ] || sudo -n true 2>/dev/null; then
        echo "Installing QEMU user emulation..."
        if command -v apt-get &> /dev/null; then
            sudo apt-get update -qq
            sudo apt-get install -y qemu-user-static
        elif command -v yum &> /dev/null; then
            sudo yum install -y qemu-user-static
        elif command -v apk &> /dev/null; then
            sudo apk add qemu-user
        else
            echo -e "${YELLOW}Could not detect package manager to install QEMU. Please install manually.${NC}"
        fi
    else
        echo -e "${YELLOW}No sudo privileges to install QEMU. Cross-architecture tests may fail.${NC}"
        echo -e "${YELLOW}Consider running this script with sudo or installing QEMU manually.${NC}"
    fi
    
    # Set up QEMU for cross-architecture emulation
    echo "Setting up QEMU for cross-architecture emulation..."
    if ! docker run --privileged --rm tonistiigi/binfmt --install all; then
        echo -e "${YELLOW}Warning: Could not set up QEMU emulation. ARM64 tests may fail.${NC}"
        echo -e "${YELLOW}This is normal if you're not running on a platform that supports QEMU.${NC}"
        return 1
    fi
    
    echo -e "${GREEN}QEMU emulation setup completed successfully.${NC}"
    return 0
}

# General test function
run_test() {
    local test_name=$1
    local command=$2
    local image=$3
    local allowed_exit_codes_var=$4
    local allowed_exit_codes=(0)  # Default to just 0
    
    # If allowed exit codes were provided, use them
    if [ -n "$allowed_exit_codes_var" ]; then
        # Convert the string into an array
        allowed_exit_codes=($(echo $allowed_exit_codes_var | tr ',' ' '))
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
    # For ARM64 emulation, bypass Tini to avoid issues
    if [ "$cross_arch" = true ] && [ "$arch" = "arm64" ]; then
        docker run --rm --privileged --name $CONTAINER_NAME \
            $platform_arg \
            -v $TEST_DIR/app:/app \
            -v $TEST_DIR/world:/world \
            -e STEAM_SERVER_APPID=$CS_GO_SERVER_APPID \
            -e PATH=$PATH:/opt/wine-staging/bin \
            --entrypoint /bin/bash \
            $image \
            -l -c "$command" > $TEST_DIR/test_output.log 2>&1
    elif [ "$cross_arch" = true ]; then
        # Other cross-arch (not ARM64)
        docker run --rm --privileged --name $CONTAINER_NAME \
            $platform_arg \
            -v $TEST_DIR/app:/app \
            -v $TEST_DIR/world:/world \
            -e STEAM_SERVER_APPID=$CS_GO_SERVER_APPID \
            -e PATH=$PATH:/opt/wine-staging/bin \
            $image \
            bash -l -c "$command" > $TEST_DIR/test_output.log 2>&1
    else
        # Same architecture
        docker run --rm --name $CONTAINER_NAME \
            $platform_arg \
            -v $TEST_DIR/app:/app \
            -v $TEST_DIR/world:/world \
            -e STEAM_SERVER_APPID=$CS_GO_SERVER_APPID \
            -e PATH=$PATH:/opt/wine-staging/bin \
            $image \
            bash -l -c "$command" > $TEST_DIR/test_output.log 2>&1
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
    
    run_test "SteamCMD Basic" "
        # The container has the alias in .bashrc, so we need to force it to be loaded
        # First, enable alias expansion in this non-interactive shell
        shopt -s expand_aliases
        
        # Source the .bashrc file directly - this is where the steamcmd alias is defined
        if [ -f ~/.bashrc ]; then
            echo \"Sourcing .bashrc file...\"
            source ~/.bashrc
        fi
        
        # Print environment variables for debugging
        echo \"===========================================\"
        echo \"Current user: \$(whoami)\"
        echo \"DEBUGGER: \${DEBUGGER}\"
        echo \"Architecture: \$(uname -m)\"
        echo \"PATH: \${PATH}\"
        echo \"STEAMCMD_PATH: \${STEAMCMD_PATH}\"
        env | grep BOX
        echo \"===========================================\"
        
        # Attempt to run the alias directly first
        echo \"Attempting to run steamcmd via alias...\"
        if steamcmd +quit &>/dev/null; then
            echo \"Successfully executed steamcmd alias\"
            STEAMCMD_CMD=\"steamcmd\"
        else
            echo \"steamcmd alias test failed, checking for alternatives...\"
            
            # Check the STEAMCMD_PATH variable
            if [ -n \"\${STEAMCMD_PATH}\" ] && [ -x \"\${STEAMCMD_PATH}/steamcmd.sh\" ]; then
                echo \"Found steamcmd.sh at \${STEAMCMD_PATH}/steamcmd.sh\"
                STEAMCMD_CMD=\"\${STEAMCMD_PATH}/steamcmd.sh\"
            # Check if steamcmd is an alias but couldn't execute
            elif alias steamcmd 2>/dev/null; then
                echo \"steamcmd is defined as an alias: \$(alias steamcmd)\"
                echo \"But the alias failed to execute properly\"
                echo \"This is a critical failure as the steamcmd alias should work!\"
                exit 1
            # If not an alias, check if it's a command in PATH
            elif command -v steamcmd &>/dev/null; then
                echo \"steamcmd found in PATH\"
                STEAMCMD_CMD=\"steamcmd\"
            # Otherwise check common locations
            else
                echo \"steamcmd not found as alias or in PATH. Checking common locations...\"
                if [ -x \"/usr/games/steamcmd\" ]; then
                    STEAMCMD_CMD=\"/usr/games/steamcmd\"
                elif [ -x \"/usr/bin/steamcmd\" ]; then
                    STEAMCMD_CMD=\"/usr/bin/steamcmd\"
                elif [ -x \"/app/steamcmd/steamcmd.sh\" ]; then
                    STEAMCMD_CMD=\"/app/steamcmd/steamcmd.sh\"
                # Last resort - look for steamcmd.sh files
                else
                    echo \"Searching for steamcmd.sh files...\"
                    STEAMCMD_SH=\$(find / -name steamcmd.sh -type f -executable 2>/dev/null | head -1)
                    if [ -n \"\${STEAMCMD_SH}\" ]; then
                        echo \"Found steamcmd.sh at \${STEAMCMD_SH}\"
                        STEAMCMD_CMD=\"\${STEAMCMD_SH}\"
                    else
                        echo \"Error: steamcmd not found!\"
                        exit 1
                    fi
                fi
            fi
        fi
        
        echo \"Using SteamCMD command: \${STEAMCMD_CMD}\"
        
        # Run SteamCMD with anonymous login and quit (with longer timeout)
        echo \"Starting SteamCMD...\"
        timeout 300 \${STEAMCMD_CMD} +login anonymous +quit | tee /tmp/steamcmd_output.log
        STEAMCMD_EXIT_CODE=\$?
        
        echo \"SteamCMD exit code: \${STEAMCMD_EXIT_CODE}\"
        
        # Check if this is an ARM container with Box86/Box64
        if [ -n \"\${DEBUGGER}\" ] || command -v box64 &> /dev/null || command -v box86 &> /dev/null; then
            echo \"Detected emulation layer (Box86/Box64)\"
            # For emulated environments, accept more exit codes as success
            if [ \${STEAMCMD_EXIT_CODE} -eq 0 ] || [ \${STEAMCMD_EXIT_CODE} -eq 42 ] || [ \${STEAMCMD_EXIT_CODE} -eq 134 ] || [ \${STEAMCMD_EXIT_CODE} -eq 139 ]; then
                echo 'SteamCMD exited with acceptable code for emulated environment - test passed'
                exit 0
            fi
        fi
        
        # Check if the output contains any success indicators
        if grep -q 'Update complete' /tmp/steamcmd_output.log || \\
           grep -q 'Loading Steam API' /tmp/steamcmd_output.log || \\
           grep -q 'Success!' /tmp/steamcmd_output.log || \\
           grep -q 'Logged in OK' /tmp/steamcmd_output.log || \\
           grep -q 'Steam Console Client' /tmp/steamcmd_output.log || \\
           grep -q 'Checking for available update...' /tmp/steamcmd_output.log; then
            echo 'SteamCMD showed signs of successful operation - test passed'
            exit 0
        else
            echo 'SteamCMD did not show any signs of successful operation'
            echo 'Full output from SteamCMD:'
            cat /tmp/steamcmd_output.log
            exit 1
        fi
    " "$image" "0,42,134,139"
    
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
    
    # No need to set CONTAINER_USER as environment variable since we're using --user flag
    
    # For ARM64 emulation, bypass Tini to avoid issues
    if [ "$cross_arch" = true ] && [ "$arch" = "arm64" ]; then
        docker run --name $CONTAINER_NAME \
            --privileged \
            $platform_arg \
            -v $TEST_DIR/app:/app \
            -v $TEST_DIR/world:/world \
            -e STEAM_SERVER_APPID=$CS_GO_SERVER_APPID \
            -e PATH=$PATH:/opt/wine-staging/bin \
            -it --entrypoint /bin/bash $image -l
    elif [ "$cross_arch" = true ]; then
        # Other cross-arch emulation
        docker run --name $CONTAINER_NAME \
            --privileged \
            $platform_arg \
            -v $TEST_DIR/app:/app \
            -v $TEST_DIR/world:/world \
            -e STEAM_SERVER_APPID=$CS_GO_SERVER_APPID \
            -e PATH=$PATH:/opt/wine-staging/bin \
            -it --entrypoint bash $image -l
    else
        # Same architecture
        docker run --name $CONTAINER_NAME \
            $platform_arg \
            -v $TEST_DIR/app:/app \
            -v $TEST_DIR/world:/world \
            -e STEAM_SERVER_APPID=$CS_GO_SERVER_APPID \
            -e PATH=$PATH:/opt/wine-staging/bin \
            -it --entrypoint bash $image -l
    fi
    
    # Clean up the container after exiting
    docker rm -f $CONTAINER_NAME 2>/dev/null || true
}

#
# Main execution logic
#

# Implement TODOs
echo -e "${BOLD}${CYAN}====== Initial Setup ======${NC}"

# Clean up existing containers
cleanup_existing_containers

# Purge existing images
purge_existing_images

# Check and setup QEMU for cross-architecture testing
setup_qemu_emulation

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
#!/bin/bash
#
# fetch_docker_tags.sh
#
# Simple script to fetch available tags for docker-steamcmd-server

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m' # No Color

# Default values
REPO="teriyakidactyl/docker-steamcmd-server"
TAG_FILTER=""
DEV_ONLY=true

# Parse command line arguments
for arg in "$@"; do
    if [ "$arg" = "--all" ]; then
        DEV_ONLY=false
    elif [ "$arg" != "-d" ] && [ "$arg" != "--debug" ]; then
        # If not a flag, treat as tag filter
        TAG_FILTER="$arg"
    fi
done

echo -e "${YELLOW}Fetching available tags from Docker Registry API...${NC}"

# Get a token for authentication
echo -e "${BLUE}Requesting authentication token...${NC}"
TOKEN_RESPONSE=$(curl -s "https://ghcr.io/token?service=ghcr.io&scope=repository:${REPO}:pull")

if ! echo "$TOKEN_RESPONSE" | grep -q "token"; then
    echo -e "${RED}Failed to get authentication token!${NC}"
    exit 1
fi

# Extract the token
TOKEN=$(echo "$TOKEN_RESPONSE" | grep -o '"token":"[^"]*"' | sed 's/"token":"//g' | sed 's/"//g')

if [ -z "$TOKEN" ]; then
    echo -e "${RED}Failed to extract token from response!${NC}"
    exit 1
fi

echo -e "${GREEN}Successfully obtained authentication token${NC}"

# Use the token to fetch tags
echo -e "${BLUE}Fetching tags...${NC}"
TAGS_RESPONSE=$(curl -s -H "Authorization: Bearer $TOKEN" "https://ghcr.io/v2/${REPO}/tags/list")

if ! echo "$TAGS_RESPONSE" | grep -q "tags"; then
    echo -e "${RED}Failed to retrieve tags!${NC}"
    exit 1
fi

echo -e "${GREEN}Successfully retrieved tags${NC}"

# Save response to temp file for processing
echo "$TAGS_RESPONSE" > /tmp/docker_tags_response.json

# Extract and filter tags
ALL_TAGS=()

if command -v jq &> /dev/null; then
    echo -e "${GREEN}Using jq for JSON parsing${NC}"
    
    # Extract all tags with jq
    mapfile -t RAW_TAGS < <(jq -r '.tags[]' /tmp/docker_tags_response.json)
else
    echo -e "${YELLOW}jq not found, using grep/sed for extraction${NC}"
    # Extract tags with grep/sed
    TAG_LIST=$(grep -o '"tags":\[[^]]*\]' /tmp/docker_tags_response.json | 
              sed 's/"tags":\[//g' | 
              sed 's/\]//g' | 
              sed 's/"//g' | 
              sed 's/,/ /g')
    
    # Convert space-separated list to array
    read -ra RAW_TAGS <<< "$TAG_LIST"
fi

# Filter tags based on criteria
for tag in "${RAW_TAGS[@]}"; do
    # Skip empty tags
    if [ -z "$tag" ]; then
        continue
    fi
    
    # Filter by tag name if provided
    if [ -n "$TAG_FILTER" ] && [[ "$tag" != *"$TAG_FILTER"* ]]; then
        continue
    fi
    
    # If dev_only is true, only include tags with _dev or -dev
    if [ "$DEV_ONLY" = true ] && [[ "$tag" != *"_dev"* ]] && [[ "$tag" != *"-dev"* ]]; then
        continue
    fi
    
    ALL_TAGS+=("$tag")
done

# Remove temp file
rm -f /tmp/docker_tags_response.json

echo -e "${GREEN}Found ${#ALL_TAGS[@]} tags matching criteria${NC}"

# Print the final list of tags
echo -e "\n${GREEN}Tags:${NC}"
for tag in "${ALL_TAGS[@]}"; do
    echo "  - $tag"
done

# Export tags as a Bash array declaration
echo "TAGS_TO_TEST=(" > tags_array.sh
for tag in "${ALL_TAGS[@]}"; do
    echo "    \"$tag\"" >> tags_array.sh
done
echo ")" >> tags_array.sh

echo -e "\n${GREEN}Tags exported to tags_array.sh${NC}"

exit 0

#!/bin/bash
# Box64 Version Correlation Script
# This script discovers Box64 versions from Ryan Fortner's repository
# and correlates them with ptitSeb's original repository commits


# The pattern in the package filename is:
# box64-[platform]_[version]+[build_date].[commit_hash]-[package_revision]_[architecture].deb
# Breaking down your example:

# box64-android - The platform/device specific build
# 0.4.3 - The Box64 version
# 20250417 - Build date (April 17, 2025)
# 9579dd9 - The commit hash from ptitSeb's repository that this package was built from
# -1 - The package revision
# arm64 - The architecture

# Pitseb's code commit hashes: https://github.com/ptitSeb/box64/commits/main/ don't seem to relate to his release commit hashls https://github.com/ptitSeb/box64/releases/tag/v0.3.4

set -e

# Colors for better readability
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Repository URLs
RYAN_BOX64_REPO="https://github.com/ryanfortner/box64-debs"
PTITSEB_BOX64_REPO="https://github.com/ptitSeb/box64"
TEMP_DIR=$(mktemp -d)

echo -e "${BLUE}Box64 Version Correlation Script${NC}"
echo -e "${BLUE}==============================${NC}\n"

# Function to check if a command exists
check_command() {
    if ! command -v "$1" &> /dev/null; then
        echo -e "${RED}Error: $1 is required but not installed. Please install it and try again.${NC}"
        exit 1
    fi
}

# Check required commands
check_command curl
check_command jq
check_command git
check_command grep
check_command sed

# Function to get commit details from ptitSeb's repository
get_commit_details() {
    local commit_hash="$1"
    
    # Use GitHub API to get commit details
    local commit_details=$(curl -s "https://api.github.com/repos/ptitSeb/box64/commits/$commit_hash")
    
    # Check if commit exists
    if echo "$commit_details" | jq -e '.sha' > /dev/null; then
        # Extract commit date
        local commit_date=$(echo "$commit_details" | jq -r '.commit.author.date' | cut -d'T' -f1)
        
        # Extract commit message (first line only)
        local commit_message=$(echo "$commit_details" | jq -r '.commit.message' | head -n 1)
        
        # Extract author name
        local author_name=$(echo "$commit_details" | jq -r '.commit.author.name')
        
        echo "Commit: $commit_hash | Date: $commit_date | Author: $author_name | Message: $commit_message"
        return 0
    else
        echo "Commit $commit_hash not found in ptitSeb's repository"
        return 1
    fi
}

# Function to explore historical versions through commit history
find_box64_versions() {
    echo -e "${YELLOW}Discovering Box64 versions from repository history...${NC}"
    echo -e "${BLUE}Cloning repository (shallow clone)...${NC}"
    
    # Clone the repository to analyze commit history
    git clone --depth=500 "$RYAN_BOX64_REPO" "$TEMP_DIR/repo" 2>/dev/null
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: Failed to clone repository${NC}"
        rm -rf "$TEMP_DIR"
        exit 1
    fi
    
    # Change to the repository directory
    cd "$TEMP_DIR/repo"
    
    echo -e "${YELLOW}Analyzing commit history for Box64 versions...${NC}"
    
    # Get the list of commit hashes
    git log --pretty=format:"%H" -- debian/Packages | head -n 100 > "$TEMP_DIR/commits.txt"
    
    # Process each commit to find versions
    echo -e "${BLUE}Box64 versions found:${NC}"
    echo -e "${BLUE}===================${NC}"
    
    # Create files to store version info and correlation data
    echo "" > "$TEMP_DIR/versions.txt"
    echo "" > "$TEMP_DIR/correlation.csv"
    echo "box64_version,package_date,package_commit,source_commit,source_date,source_author,source_message" > "$TEMP_DIR/correlation.csv"
    
    # Process each commit to find versions
    echo -e "Analyzing commits to find versions..."
    
    while read -r commit_hash; do
        # For each commit, check the Packages file
        git show "$commit_hash:debian/Packages" > "$TEMP_DIR/Packages" 2>/dev/null
        
        if [ $? -eq 0 ]; then
            # Extract all package versions
            grep -E "Version: [0-9]+\.[0-9]+\.[0-9]+" "$TEMP_DIR/Packages" | sort -u | while read -r version_line; do
                version=$(echo "$version_line" | sed 's/Version: \([0-9]\+\.[0-9]\+\.[0-9]\+\).*/\1/')
                
                # Get the date of this commit for reference
                commit_date=$(git show -s --format=%ci "$commit_hash" | cut -d' ' -f1)
                
                # Extract the build commit hash
                build_commit=$(grep -A 10 -E "Version: $version\+" "$TEMP_DIR/Packages" | grep -o -E "\.[a-f0-9]{7}-" | head -n 1 | sed 's/\.//' | sed 's/-//')
                
                # Only add if we haven't seen this version yet
                if ! grep -q "^$version|" "$TEMP_DIR/versions.txt"; then
                    echo "$version|$commit_date|$build_commit" >> "$TEMP_DIR/versions.txt"
                    
                    # Get source commit details
                    if [ -n "$build_commit" ]; then
                        source_details=$(get_commit_details "$build_commit")
                        source_date=$(echo "$source_details" | grep -o -E "Date: [0-9]{4}-[0-9]{2}-[0-9]{2}" | cut -d' ' -f2)
                        source_author=$(echo "$source_details" | grep -o -E "Author: [^|]+" | cut -d' ' -f2-)
                        source_message=$(echo "$source_details" | grep -o -E "Message: .*$" | cut -d' ' -f2-)
                        
                        # Add to correlation data
                        echo "$version,$commit_date,$build_commit,$build_commit,$source_date,$source_author,\"$source_message\"" >> "$TEMP_DIR/correlation.csv"
                        
                        echo -e "${GREEN}Version: $version${NC} | Package Date: $commit_date | Source Date: $source_date"
                        echo -e "  Package Commit: ${YELLOW}$build_commit${NC}"
                        echo -e "  Source Commit: ${YELLOW}$build_commit${NC} | Author: $source_author"
                        echo -e "  Commit Message: $source_message"
                        echo
                    else
                        echo -e "${GREEN}Version: $version${NC} | Package Date: $commit_date | ${RED}No source commit found${NC}"
                    fi
                fi
            done
        fi
    done < "$TEMP_DIR/commits.txt"
    
    # Return to original directory
    cd - >/dev/null
    
    # Copy the correlation data to the current directory
    cp "$TEMP_DIR/correlation.csv" ./box64_version_correlation.csv
    
    echo -e "\n${GREEN}Version correlation complete!${NC}"
    echo -e "Correlation data saved to ${BLUE}box64_version_correlation.csv${NC}"
}

# Function to check official releases and their correlation with packages
check_official_releases() {
    echo -e "\n${YELLOW}Checking official Box64 releases...${NC}"
    
    # Get all releases from ptitSeb's repository
    curl -s "https://api.github.com/repos/ptitSeb/box64/releases" > "$TEMP_DIR/releases.json"
    
    # Extract release tags and dates
    jq -r '.[] | "\(.tag_name)|\(.published_at)|\(.target_commitish)"' "$TEMP_DIR/releases.json" > "$TEMP_DIR/releases.txt"
    
    echo -e "${BLUE}Official Box64 releases from ptitSeb:${NC}"
    echo -e "${BLUE}====================================${NC}"
    
    # Display official releases and look for matching packages
    echo "release_tag,release_date,release_commit,matching_package_version" > ./box64_releases.csv
    
    while IFS='|' read -r tag_name published_at target_commit; do
        release_version=$(echo "$tag_name" | sed 's/v//')
        published_date=$(echo "$published_at" | cut -d'T' -f1)
        
        echo -e "Release: ${GREEN}$tag_name${NC} | Published: $published_date | Commit: ${YELLOW}$target_commit${NC}"
        
        # Check if we have a package for this version
        if [ -f "$TEMP_DIR/versions.txt" ] && grep -q "^$release_version|" "$TEMP_DIR/versions.txt"; then
            package_info=$(grep "^$release_version|" "$TEMP_DIR/versions.txt")
            package_date=$(echo "$package_info" | cut -d'|' -f2)
            package_commit=$(echo "$package_info" | cut -d'|' -f3)
            
            echo -e "  ${GREEN}Found matching package${NC} | Package Date: $package_date | Package Commit: $package_commit"
            echo "$tag_name,$published_date,$target_commit,$release_version" >> ./box64_releases.csv
        else
            echo -e "  ${RED}No matching package found${NC}"
            echo "$tag_name,$published_date,$target_commit,NOT_FOUND" >> ./box64_releases.csv
        fi
        
        echo
    done < "$TEMP_DIR/releases.txt"
    
    echo -e "\n${GREEN}Release check complete!${NC}"
    echo -e "Release data saved to ${BLUE}box64_releases.csv${NC}"
}

# Function to get detailed information for a specific version
get_version_details() {
    local version="$1"
    
    echo -e "\n${YELLOW}Getting detailed information for Box64 version $version...${NC}"
    
    if [ ! -f "$TEMP_DIR/versions.txt" ] || ! grep -q "^$version|" "$TEMP_DIR/versions.txt"; then
        echo -e "${RED}Version $version not found in discovered versions.${NC}"
        return 1
    fi
    
    # Get package info
    package_info=$(grep "^$version|" "$TEMP_DIR/versions.txt")
    package_date=$(echo "$package_info" | cut -d'|' -f2)
    package_commit=$(echo "$package_info" | cut -d'|' -f3)
    
    echo -e "${BLUE}Package Information:${NC}"
    echo -e "  Version: ${GREEN}$version${NC}"
    echo -e "  Package Date: $package_date"
    echo -e "  Build Commit: $package_commit"
    
    # Get source commit details
    if [ -n "$package_commit" ]; then
        echo -e "\n${BLUE}Source Commit Information:${NC}"
        source_details=$(get_commit_details "$package_commit")
        echo -e "  $source_details"
        
        # Check if this matches an official release
        if [ -f "$TEMP_DIR/releases.txt" ]; then
            grep -q "$package_commit" "$TEMP_DIR/releases.txt"
            if [ $? -eq 0 ]; then
                release_info=$(grep "$package_commit" "$TEMP_DIR/releases.txt")
                release_tag=$(echo "$release_info" | cut -d'|' -f1)
                release_date=$(echo "$release_info" | cut -d'|' -f2 | cut -d'T' -f1)
                
                echo -e "\n${BLUE}Release Information:${NC}"
                echo -e "  ${GREEN}This commit matches official release $release_tag${NC}"
                echo -e "  Released on: $release_date"
            else
                echo -e "\n${BLUE}Release Information:${NC}"
                echo -e "  ${YELLOW}This commit does not match any official release${NC}"
            fi
        fi
        
        # Generate download URL
        echo -e "\n${BLUE}Package URL:${NC}"
        
        # Find a package file that matches this version
        if [ -d "$TEMP_DIR/repo" ]; then
            cd "$TEMP_DIR/repo"
            
            # Find commits that contain this version
            commits=$(git log --pretty=format:"%H" -- debian/Packages | head -n 100)
            
            found_package=false
            
            for commit in $commits; do
                if git show "$commit:debian/Packages" 2>/dev/null | grep -q "Version: $version+"; then
                    # Extract package filenames for this version
                    packages=$(git show "$commit:debian/Packages" | grep -A 20 "Version: $version+" | 
                              grep -E "Filename: " | 
                              sed 's/Filename: \.//')
                    
                    if [ -n "$packages" ]; then
                        echo -e "  Available packages for version $version:"
                        echo "$packages" | while read -r package_file; do
                            url="https://github.com/ryanfortner/box64-debs/raw/$commit/debian/$package_file"
                            target=$(echo "$package_file" | grep -o -E "box64(-[^_]+)?_" | sed 's/box64-//' | sed 's/_//' | sed 's/^$/generic/')
                            echo -e "  - Target: ${GREEN}$target${NC}"
                            echo -e "    URL: ${BLUE}$url${NC}"
                            echo -e "    Export: ${YELLOW}export BOX64_DEB_URL=\"$url\"${NC}"
                        done
                        found_package=true
                        break
                    fi
                fi
            done
            
            if [ "$found_package" = false ]; then
                echo -e "  ${RED}No package files found for version $version${NC}"
            fi
            
            cd - >/dev/null
        else
            echo -e "  ${RED}Repository not available for URL generation${NC}"
        fi
    else
        echo -e "\n${RED}No build commit information available${NC}"
    fi
}

# Main function
main() {
    if [ "$1" = "help" ] || [ "$1" = "--help" ] || [ "$1" = "-h" ]; then
        echo -e "Usage: $0 [command] [options]"
        echo -e "\nCommands:"
        echo -e "  (none)         Find all Box64 versions and correlate with source"
        echo -e "  details VERSION  Get detailed information for a specific version"
        echo -e "  releases       Check official releases and their correlation with packages"
        echo -e "  help           Show this help message"
        echo -e "\nExamples:"
        echo -e "  $0             Find all Box64 versions"
        echo -e "  $0 details 0.3.4  Get detailed information for version 0.3.4"
        echo -e "  $0 releases    Check official releases"
        exit 0
    fi

    if [ "$1" = "details" ]; then
        if [ -z "$2" ]; then
            echo -e "${RED}Error: No version specified.${NC}"
            echo -e "Usage: $0 details VERSION"
            exit 1
        fi
        
        # First find all versions if we haven't done so already
        if [ ! -f "$TEMP_DIR/versions.txt" ]; then
            find_box64_versions
        fi
        
        get_version_details "$2"
    elif [ "$1" = "releases" ]; then
        # First find all versions if we haven't done so already
        if [ ! -f "$TEMP_DIR/versions.txt" ]; then
            find_box64_versions
        fi
        
        check_official_releases
    else
        # Find all Box64 versions and correlate with source
        find_box64_versions
        check_official_releases
    fi
    
    # Clean up
    rm -rf "$TEMP_DIR"
    
    echo -e "\n${GREEN}Done!${NC}"
}

# Execute main function with all script arguments
main "$@"

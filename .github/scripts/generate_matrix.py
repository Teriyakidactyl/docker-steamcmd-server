#!/usr/bin/env python3
import json
import argparse
import datetime
import os
import re # Added for hash extraction
import sys # Added for printing warnings during preprocessing

# --- Configuration Section (Easy to Edit by User) ---
BASE_IMAGES = [
    "trixie-20250407-slim",
    "bookworm-20250407-slim",
]

COMPAT_LAYERS_DEFS = [
    {"id": "native", "type": "native"},
    {"id": "wine-staging-10.5", "type": "wine", "wine_branch": "staging", "wine_version": "10.5"},
    {"id": "wine-stable-10.0.0.0", "type": "wine", "wine_branch": "stable", "wine_version": "10.0.0.0"},
    {"id": "proton-9.27", "type": "proton", "proton_version": "9.27"},
    {"id": "proton-9.25", "type": "proton", "proton_version": "9.25"},
]

PLATFORM_DEFS = [
    {"name": "linux/amd64", "arch": "amd64"},
    {"name": "linux/arm64", "arch": "arm64"},
]

_EMULATOR_DEFS_CONFIG = [
    {
        "id": "box86",
        "version_default": "0.3.9",
        "deb_url_default": "https://github.com/ryanfortner/box86-debs/raw/2c23402be23090b484f3bc87da61e76a163a0dfc/debian/box86-generic-arm_0.3.9+20250308.d0aad67-1_armhf.deb"
    },
    {
        "id": "box64",
        "version_default": "0.3.5",
        "deb_url_default": "https://github.com/ryanfortner/box64-debs/raw/9e39e5a8ac7069f80757510d3f186c775334d9a9/debian/box64_0.3.5+20250425.3542c88-1_arm64.deb"
    }
]

# --- Preprocess EMULATOR_DEFS to include hash ---
def _extract_hash_from_filename(filename):
    # Looks for pattern like ".<hash>-" e.g., ".d0aad67-" from "....d0aad67-1_armhf.deb"
    # This captures a hex string of 7 or more characters.
    match = re.search(r'\.([0-9a-fA-F]{7,})-', filename)
    if match:
        return match.group(1)
    return None

EMULATOR_DEFS = [] # This will be the globally used, processed list
for config_def in _EMULATOR_DEFS_CONFIG:
    processed_def = config_def.copy()
    if "deb_url_default" in processed_def:
        filename = processed_def["deb_url_default"].split('/')[-1]
        hash_val = _extract_hash_from_filename(filename)
        if hash_val:
            processed_def["hash"] = hash_val
        else:
            print(f"Warning: Could not extract hash from filename '{filename}' for emulator '{processed_def['id']}'. Hash set to 'unknown'.", file=sys.stderr)
            processed_def["hash"] = "unknown"
    else:
        # Handle cases where an emulator definition might not have a deb_url_default
        processed_def["hash"] = "no_url"
    EMULATOR_DEFS.append(processed_def)
# EMULATOR_DEFS now contains the 'hash' key for each emulator.

BUILD_ARG_DEFAULTS = {
    "WINE_ID_DEFAULT": "debian",
    "WINE_TAG_SUFFIX_DEFAULT": "-1",
    # "PROTON_VERSION_DEFAULT": "9.26", # Removed as requested
}
# --- End Configuration Section ---

def _get_tag_codename_arch_specific_elements(debian_codename, compat_def, arch, current_emulator_defs):
    """
    Generates the core elements for the codename tag, including emulator details for arm64.
    Returns a list of strings.
    Example for amd64: ["trixie", "wine-staging-10.5"]
    Example for arm64: ["trixie", "wine-staging-10.5", "box64-0.3.5-3542c88"]
    """
    parts = [debian_codename]
    if compat_def["type"] != "native":
        parts.append(compat_def["id"]) # e.g., "wine-staging-10.5"

    if arch == "arm64":
        # Find box64 definition (assuming box64 is the primary one for tagging on arm64)
        box64_emu_def = next((e for e in current_emulator_defs if e["id"] == "box64"), None)
        if box64_emu_def:
            emu_hash = box64_emu_def.get("hash")
            # Ensure hash is valid and known before using it in the tag
            if emu_hash and emu_hash not in ["unknown", "no_url"]:
                emulator_tag_part = f"{box64_emu_def['id']}-{box64_emu_def['version_default']}-{emu_hash}"
                parts.append(emulator_tag_part)
            # else: Do not append emulator part if hash is unknown or missing to avoid malformed tags
    return parts

def generate_build_matrix(github_ref, registry_image_base):
    matrix_items = []
    build_date = datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
    is_dev_branch = not github_ref.endswith("/main")

    for base_image_name in BASE_IMAGES:
        debian_codename = base_image_name.split('-')[0]

        for compat_def in COMPAT_LAYERS_DEFS:
            for plat_def in PLATFORM_DEFS:
                arch = plat_def["arch"]
                
                item = {
                    "build_date": build_date,
                    "base_image_name": base_image_name,
                    "debian_codename": debian_codename,
                    "platform_name": plat_def["name"],
                    "architecture": arch,
                    "compat_layer_id": compat_def["id"],
                    "compat_layer_type": compat_def["type"],
                }

                item["wine_version_arg"] = compat_def.get("wine_version", "")
                item["wine_branch_arg"] = compat_def.get("wine_branch", "")
                # Use compat_def.get("proton_version", "") directly
                item["proton_version_arg"] = compat_def.get("proton_version", "") 
                item["wine_id_arg"] = BUILD_ARG_DEFAULTS["WINE_ID_DEFAULT"]
                item["wine_tag_suffix_arg"] = BUILD_ARG_DEFAULTS["WINE_TAG_SUFFIX_DEFAULT"]
                
                item["box86_version_arg"] = ""
                item["box86_deb_url_arg"] = ""
                item["box86_hash_arg"] = "" 
                item["box64_version_arg"] = ""
                item["box64_deb_url_arg"] = ""
                item["box64_hash_arg"] = "" 
                item["debugger_build_arg"] = ""

                app_cmd_prefix_parts = []

                if arch == "arm64":
                    for emu_def in EMULATOR_DEFS: 
                        if emu_def["id"] == "box86":
                            item["box86_version_arg"] = emu_def.get("version_default", "")
                            item["box86_deb_url_arg"] = emu_def.get("deb_url_default", "")
                            item["box86_hash_arg"] = emu_def.get("hash", "") 
                        elif emu_def["id"] == "box64":
                            item["box64_version_arg"] = emu_def.get("version_default", "")
                            item["box64_deb_url_arg"] = emu_def.get("deb_url_default", "")
                            item["box64_hash_arg"] = emu_def.get("hash", "") 
                    
                    item["debugger_build_arg"] = "box86"
                    app_cmd_prefix_parts.append("box64")

                if item["compat_layer_type"] == "wine":
                    item["compat_layer_build_arg"] = "wine"
                    app_cmd_prefix_parts.insert(0, "wine")
                elif item["compat_layer_type"] == "proton":
                    item["compat_layer_build_arg"] = "proton"
                    app_cmd_prefix_parts.insert(0, "proton")
                else: # native
                    item["compat_layer_build_arg"] = ""

                item["app_command_prefix_build_arg"] = " ".join(app_cmd_prefix_parts)

                # --- Tag Generation ---
                # 1. tag_versioned_arch
                tag_versioned_parts = [base_image_name]
                if compat_def["type"] != "native":
                    tag_versioned_parts.append(compat_def["id"])
                versioned_tag_with_arch = f"{'_'.join(tag_versioned_parts)}-{arch}"
                if is_dev_branch:
                    item["tag_versioned_arch"] = f"{versioned_tag_with_arch}_dev"
                else:
                    item["tag_versioned_arch"] = versioned_tag_with_arch

                # 2. tag_codename_arch
                tag_elements = _get_tag_codename_arch_specific_elements(debian_codename, compat_def, arch, EMULATOR_DEFS)
                codename_tag_stem = '-'.join(tag_elements)
                codename_tag_with_arch = f"{codename_tag_stem}-{arch}"
                
                if is_dev_branch:
                    item["tag_codename_arch"] = f"{codename_tag_with_arch}_dev"
                else:
                    item["tag_codename_arch"] = codename_tag_with_arch
                
                # 3. tag_latest_arch
                item["has_latest_tag_arch"] = (not is_dev_branch and compat_def["type"] == "native")
                item["tag_latest_arch"] = f"latest-{arch}" if item["has_latest_tag_arch"] else ""

                item["job_display_name"] = item["tag_codename_arch"]
                matrix_items.append(item)
    return {"include": matrix_items}

def generate_manifest_matrix(github_ref, registry_image_base):
    manifest_items = []
    is_dev_branch = not github_ref.endswith("/main")
    all_arches = [p["arch"] for p in PLATFORM_DEFS]

    for base_image_name in BASE_IMAGES:
        debian_codename = base_image_name.split('-')[0]
        for compat_def in COMPAT_LAYERS_DEFS:
            item = { "architectures": all_arches }

            # Versioned Tags (manifest source/target)
            tag_versioned_parts = [base_image_name]
            if compat_def["type"] != "native":
                tag_versioned_parts.append(compat_def["id"])
            versioned_tag_base = "_".join(tag_versioned_parts)
            if is_dev_branch:
                versioned_tag_base += "_dev"
            item["target_tag_versioned"] = f"{registry_image_base}:{versioned_tag_base}"
            item["source_images_versioned"] = []
            for plat_def in PLATFORM_DEFS: 
                arch = plat_def["arch"]
                src_tag_versioned_parts = [base_image_name]
                if compat_def["type"] != "native":
                    src_tag_versioned_parts.append(compat_def["id"])
                src_versioned_tag_with_arch = f"{'_'.join(src_tag_versioned_parts)}-{arch}"
                if is_dev_branch:
                    item["source_images_versioned"].append(f"{registry_image_base}:{src_versioned_tag_with_arch}_dev")
                else:
                    item["source_images_versioned"].append(f"{registry_image_base}:{src_versioned_tag_with_arch}")

            # Codename Tags (manifest source/target)
            target_tag_codename_parts = [debian_codename]
            if compat_def["type"] == "wine":
                target_tag_codename_parts.append(f"wine-{compat_def['wine_branch']}")
            elif compat_def["type"] == "proton":
                # Directly use proton_version from compat_def, assuming it exists for proton types
                pv = compat_def['proton_version'] 
                target_tag_codename_parts.append(f"proton-{pv}")
            
            codename_tag_base_for_target = "-".join(target_tag_codename_parts)
            if is_dev_branch:
                codename_tag_base_for_target += "_dev"
            item["target_tag_codename"] = f"{registry_image_base}:{codename_tag_base_for_target}"

            current_source_images_codename = []
            for plat_def in PLATFORM_DEFS:
                current_arch = plat_def["arch"]
                tag_elements = _get_tag_codename_arch_specific_elements(debian_codename, compat_def, current_arch, EMULATOR_DEFS)
                arch_specific_tag_name_stem = f"{'-'.join(tag_elements)}-{current_arch}"
                
                final_arch_specific_tag_name = arch_specific_tag_name_stem
                if is_dev_branch:
                    final_arch_specific_tag_name += "_dev"
                current_source_images_codename.append(f"{registry_image_base}:{final_arch_specific_tag_name}")
            item["source_images_codename"] = current_source_images_codename
            
            item["create_latest_tag"] = (not is_dev_branch and compat_def["type"] == "native")
            if item["create_latest_tag"]:
                item["target_tag_latest"] = f"{registry_image_base}:latest"
                item["source_images_latest"] = [f"{registry_image_base}:latest-{arch}" for arch in all_arches]
            else:
                item["target_tag_latest"] = ""
                item["source_images_latest"] = []

            manifest_items.append(item)
    return {"include": manifest_items}

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Generate matrix for GitHub Actions.")
    parser.add_argument("--job", choices=["build", "manifest"], required=True, help="Type of matrix to generate.")
    parser.add_argument("--github-ref", required=True, help="GitHub reference (e.g., refs/heads/main).")
    parser.add_argument("--registry-image-base", required=True, help="Base registry image path (e.g., ghcr.io/user/image).")
    parser.add_argument("--debug", action="store_true", help="Enable debug output")
    args = parser.parse_args()

    if args.debug:
        print(f"Running script with: job={args.job}, github-ref={args.github_ref}, registry-image-base={args.registry_image_base}", file=sys.stderr)
        print(f"Processed EMULATOR_DEFS: {json.dumps(EMULATOR_DEFS, indent=2)}", file=sys.stderr)
    
    try:
        if args.job == "build":
            matrix = generate_build_matrix(args.github_ref, args.registry_image_base)
        elif args.job == "manifest":
            matrix = generate_manifest_matrix(args.github_ref, args.registry_image_base)
        else:
            raise ValueError(f"Invalid job type: {args.job}")
        
        print(json.dumps(matrix))
    except Exception as e:
        import traceback
        print(f"Error generating matrix: {str(e)}", file=sys.stderr)
        traceback.print_exc(file=sys.stderr)
        exit(1)

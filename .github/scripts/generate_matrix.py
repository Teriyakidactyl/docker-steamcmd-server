#!/usr/bin/env python3

"""
Generates build and manifest matrices for GitHub Actions CI/CD pipelines.

This script defines configurations for Docker image builds, including:
- Base Debian images (e.g., Trixie, Bookworm).
- Compatibility layers (Native, Wine, Proton with specific versions).
- Emulators (Box86, Box64) for cross-architecture support, including hash-based versioning.
- Target platforms (e.g., linux/amd64, linux/arm64).

It produces JSON output suitable for GitHub Actions `strategy.matrix.include` directives
for two main types of jobs:
1.  **Build Jobs**: Compiling individual Docker images for each configured variant.
    This includes generating specific, descriptive tags for each image.
2.  **Manifest Jobs**: Creating Docker manifest lists that group multiple
    architecture-specific images under common multi-arch tags.

Tagging Philosophy:
All conceptual elements within a generated tag are separated by underscores ('_').
Internal structures within a single conceptual element (e.g., a version number
like "10.0.0.0" or a name with a date like "trixie-20250407-slim") can use hyphens ('-').
Example of a detailed arch-specific tag:
  trixie-20250407-slim_proton-9.27_box64-0.3.5-3542c88_box86-0.3.9-d0aad67_arm64
"""


import json
import argparse
import datetime
import os
import re
import sys

# TODO this script generates tags that will be used in multiarch.

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

def _extract_hash_from_filename(filename):
    match = re.search(r'\.([0-9a-fA-F]{7,})-', filename)
    if match:
        return match.group(1)
    return None

EMULATOR_DEFS = []
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
        processed_def["hash"] = "no_url"
    EMULATOR_DEFS.append(processed_def)

BUILD_ARG_DEFAULTS = {
    "WINE_ID_DEFAULT": "debian",
    "WINE_TAG_SUFFIX_DEFAULT": "-1",
}
# --- End Configuration Section ---

def _get_tag_codename_conceptual_elements(base_image_name, compat_def, arch, current_emulator_defs):
    """
    Returns a list of conceptual elements for the codename-style tag.
    Each element in the list is a string, which itself might contain hyphens.
    """
    elements = [base_image_name]
    if compat_def["type"] != "native":
        elements.append(compat_def["id"])

    if arch == "arm64":
        box64_emu_def = next((e for e in current_emulator_defs if e["id"] == "box64"), None)
        if box64_emu_def:
            emu_hash_64 = box64_emu_def.get("hash")
            if emu_hash_64 and emu_hash_64 not in ["unknown", "no_url"]:
                elements.append(f"{box64_emu_def['id']}-{box64_emu_def['version_default']}-{emu_hash_64}")
        
        box86_emu_def = next((e for e in current_emulator_defs if e["id"] == "box86"), None)
        if box86_emu_def:
            emu_hash_86 = box86_emu_def.get("hash")
            if emu_hash_86 and emu_hash_86 not in ["unknown", "no_url"]:
                elements.append(f"{box86_emu_def['id']}-{box86_emu_def['version_default']}-{emu_hash_86}")
    return elements

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

                # --- Tag Generation (all conceptual elements separated by _) ---
                
                # 1. tag_versioned_arch: base_image_name[_compat_id]_arch
                versioned_elements_stem = [base_image_name]
                if compat_def["type"] != "native":
                    versioned_elements_stem.append(compat_def["id"])
                versioned_tag_value = '_'.join(versioned_elements_stem + [arch])
                item["tag_versioned_arch"] = f"{versioned_tag_value}_dev" if is_dev_branch else versioned_tag_value

                # 2. tag_codename_arch: base_image_name[_compat_id][_box64-info][_box86-info]_arch
                codename_elements = _get_tag_codename_conceptual_elements(base_image_name, compat_def, arch, EMULATOR_DEFS)
                codename_tag_value = '_'.join(codename_elements + [arch])
                item["tag_codename_arch"] = f"{codename_tag_value}_dev" if is_dev_branch else codename_tag_value
                
                # 3. tag_latest_arch: latest_debian_codename_arch
                item["has_latest_tag_arch"] = (not is_dev_branch and compat_def["type"] == "native")
                if item["has_latest_tag_arch"]:
                    latest_elements = ["latest", debian_codename, arch]
                    item["tag_latest_arch"] = '_'.join(latest_elements)
                else:
                    item["tag_latest_arch"] = ""

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

            # --- Versioned Tags ---
            # Target: base_image_name[_compat_id]
            target_versioned_elements = [base_image_name]
            if compat_def["type"] != "native":
                target_versioned_elements.append(compat_def["id"])
            target_versioned_base = '_'.join(target_versioned_elements)
            if is_dev_branch:
                target_versioned_base += "_dev"
            item["target_tag_versioned"] = f"{registry_image_base}:{target_versioned_base}"

            # Sources: base_image_name[_compat_id]_arch
            current_source_images_versioned = []
            for arch_val in all_arches:
                source_versioned_elements_stem = [base_image_name]
                if compat_def["type"] != "native":
                    source_versioned_elements_stem.append(compat_def["id"])
                source_versioned_tag_value = '_'.join(source_versioned_elements_stem + [arch_val])
                if is_dev_branch:
                    source_versioned_tag_value += "_dev"
                current_source_images_versioned.append(f"{registry_image_base}:{source_versioned_tag_value}")
            item["source_images_versioned"] = current_source_images_versioned

            # --- Codename Tags ---
            # Target: debian_codename[_compat-type-branch/version]
            target_codename_elements = [debian_codename]
            if compat_def["type"] == "wine":
                target_codename_elements.append(f"wine-{compat_def['wine_branch']}") # e.g., wine-staging
            elif compat_def["type"] == "proton":
                target_codename_elements.append(f"proton-{compat_def['proton_version']}") # e.g., proton-9.27
            target_codename_base = '_'.join(target_codename_elements)
            if is_dev_branch:
                target_codename_base += "_dev"
            item["target_tag_codename"] = f"{registry_image_base}:{target_codename_base}"
            
            # Sources: base_image_name[_compat_id][_box64-info][_box86-info]_arch
            current_source_images_codename = []
            for arch_val in all_arches:
                codename_elements_for_source = _get_tag_codename_conceptual_elements(base_image_name, compat_def, arch_val, EMULATOR_DEFS)
                source_codename_tag_value = '_'.join(codename_elements_for_source + [arch_val])
                if is_dev_branch:
                    source_codename_tag_value += "_dev"
                current_source_images_codename.append(f"{registry_image_base}:{source_codename_tag_value}")
            item["source_images_codename"] = current_source_images_codename
            
            # --- Latest Tags ---
            item["create_latest_tag"] = (not is_dev_branch and compat_def["type"] == "native")
            if item["create_latest_tag"]:
                # Target: latest_debian_codename
                item["target_tag_latest"] = f"{registry_image_base}:{'_'.join(['latest', debian_codename])}" 
                # Sources: latest_debian_codename_arch
                item["source_images_latest"] = [f"{registry_image_base}:{'_'.join(['latest', debian_codename, arch_val])}" for arch_val in all_arches]
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

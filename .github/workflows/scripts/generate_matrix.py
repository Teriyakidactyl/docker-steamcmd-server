#!/usr/bin/env python3
import json
import argparse
import datetime
import os

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

# Default versions for build arguments if not specified by a compat_layer_def
# These correspond to the old global ENV vars in the YAML
BUILD_ARG_DEFAULTS = {
    "WINE_ID_DEFAULT": "debian",
    "WINE_TAG_SUFFIX_DEFAULT": "-1",
    "PROTON_VERSION_DEFAULT": "9.26", # Default if compat_def type is proton but no version
    "BOX86_VERSION_DEFAULT": "0.3.9",
    "BOX86_DEB_URL_DEFAULT": "https://github.com/ryanfortner/box86-debs/raw/2c23402be23090b484f3bc87da61e76a163a0dfc/debian/box86-generic-arm_0.3.9+20250308.d0aad67-1_armhf.deb",
    "BOX64_VERSION_DEFAULT": "0.3.5",
    "BOX64_DEB_URL_DEFAULT": "https://github.com/ryanfortner/box64-debs/raw/9e39e5a8ac7069f80757510d3f186c775334d9a9/debian/box64_0.3.5+20250425.3542c88-1_arm64.deb",
}
# --- End Configuration Section ---

def generate_build_matrix(github_ref, registry_image_base):
    matrix_items = []
    build_date = datetime.datetime.now(datetime.timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')
    is_dev_branch = not github_ref.endswith("/main") # GITHUB_REF is like 'refs/heads/main' or 'refs/pull/123/merge'

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

                # --- Build Args & Specific Configs ---
                item["wine_version_arg"] = compat_def.get("wine_version", "")
                item["wine_branch_arg"] = compat_def.get("wine_branch", "")
                item["proton_version_arg"] = compat_def.get("proton_version", BUILD_ARG_DEFAULTS["PROTON_VERSION_DEFAULT"])

                item["wine_id_arg"] = BUILD_ARG_DEFAULTS["WINE_ID_DEFAULT"]
                item["wine_tag_suffix_arg"] = BUILD_ARG_DEFAULTS["WINE_TAG_SUFFIX_DEFAULT"]
                item["box86_version_arg"] = BUILD_ARG_DEFAULTS["BOX86_VERSION_DEFAULT"]
                item["box86_deb_url_arg"] = BUILD_ARG_DEFAULTS["BOX86_DEB_URL_DEFAULT"]
                item["box64_version_arg"] = BUILD_ARG_DEFAULTS["BOX64_VERSION_DEFAULT"]
                item["box64_deb_url_arg"] = BUILD_ARG_DEFAULTS["BOX64_DEB_URL_DEFAULT"]

                if item["compat_layer_type"] == "wine":
                    item["compat_layer_build_arg"] = "wine"
                elif item["compat_layer_type"] == "proton":
                    item["compat_layer_build_arg"] = "proton"
                else: # native
                    item["compat_layer_build_arg"] = ""

                item["debugger_build_arg"] = ""
                app_cmd_prefix_parts = []
                if arch == "arm64":
                    item["debugger_build_arg"] = "box86" # For debugging x86 apps on arm64
                    app_cmd_prefix_parts.append("box64") # For running x86_64 apps

                if item["compat_layer_type"] == "wine":
                    app_cmd_prefix_parts.insert(0, "wine")
                elif item["compat_layer_type"] == "proton":
                    app_cmd_prefix_parts.insert(0, "proton")
                item["app_command_prefix_build_arg"] = " ".join(app_cmd_prefix_parts)

                # --- Tag Generation ---
                tag_versioned_parts = [base_image_name]
                if compat_def["type"] != "native":
                    tag_versioned_parts.append(compat_def["id"])
                versioned_tag_base = "_".join(tag_versioned_parts)
                if is_dev_branch:
                    versioned_tag_base += "_dev"
                item["tag_versioned_arch"] = f"{versioned_tag_base}-{arch}"

                tag_codename_parts = [debian_codename]
                if compat_def["type"] == "wine":
                    tag_codename_parts.append(f"wine-{compat_def['wine_branch']}")
                elif compat_def["type"] == "proton":
                    pv = compat_def['proton_version']
                    tag_codename_parts.append(f"proton-{pv}")
                codename_tag_base = "-".join(tag_codename_parts)
                if is_dev_branch:
                    codename_tag_base += "_dev"
                item["tag_codename_arch"] = f"{codename_tag_base}-{arch}"

                item["has_latest_tag_arch"] = (not is_dev_branch and compat_def["type"] == "native")
                item["tag_latest_arch"] = f"latest-{arch}" if item["has_latest_tag_arch"] else ""

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

            tag_versioned_parts = [base_image_name]
            if compat_def["type"] != "native":
                tag_versioned_parts.append(compat_def["id"])
            versioned_tag_base = "_".join(tag_versioned_parts)
            if is_dev_branch:
                versioned_tag_base += "_dev"
            item["target_tag_versioned"] = f"{registry_image_base}:{versioned_tag_base}"
            item["source_images_versioned"] = [f"{registry_image_base}:{versioned_tag_base}-{arch}" for arch in all_arches]

            tag_codename_parts = [debian_codename]
            if compat_def["type"] == "wine":
                tag_codename_parts.append(f"wine-{compat_def['wine_branch']}")
            elif compat_def["type"] == "proton":
                pv = compat_def['proton_version']
                tag_codename_parts.append(f"proton-{pv}")
            codename_tag_base = "-".join(tag_codename_parts)
            if is_dev_branch:
                codename_tag_base += "_dev"
            item["target_tag_codename"] = f"{registry_image_base}:{codename_tag_base}"
            item["source_images_codename"] = [f"{registry_image_base}:{codename_tag_base}-{arch}" for arch in all_arches]

            item["create_latest_tag"] = (not is_dev_branch and compat_def["type"] == "native")
            if item["create_latest_tag"]:
                item["target_tag_latest"] = f"{registry_image_base}:latest"
                item["source_images_latest"] = [f"{registry_image_base}:latest-{arch}" for arch in all_arches]
            else: # Ensure keys exist even if false
                item["target_tag_latest"] = ""
                item["source_images_latest"] = []


            manifest_items.append(item)
    return {"include": manifest_items}

if __name__ == "__main__":
    parser = argparse.ArgumentParser(description="Generate matrix for GitHub Actions.")
    parser.add_argument("--job", choices=["build", "manifest"], required=True, help="Type of matrix to generate.")
    parser.add_argument("--github-ref", required=True, help="GitHub reference (e.g., refs/heads/main).")
    parser.add_argument("--registry-image-base", required=True, help="Base registry image path (e.g., ghcr.io/user/image).")
    args = parser.parse_args()

    if args.job == "build":
        matrix = generate_build_matrix(args.github_ref, args.registry_image_base)
    elif args.job == "manifest":
        matrix = generate_manifest_matrix(args.github_ref, args.registry_image_base)
    else:
        # Should not happen due to choices in argparse
        raise ValueError(f"Invalid job type: {args.job}")

    print(json.dumps(matrix, indent=2))
#!/usr/bin/env python3

import argparse
import datetime
import json
import re
import sys

BASE_IMAGES = [
    "trixie-20260421-slim",
    "bookworm-20260421-slim",
]

COMPAT_LAYERS = [
    {"id": "native", "type": "native", "architectures": ["amd64", "arm64"]},
    {
        # WineHQ discontinued Bookworm binaries after 11.10.
        "id": "wine-staging",
        "type": "wine",
        "wine_branch": "staging",
        "wine_versions": {"trixie": "11.19", "bookworm": "11.10"},
        "architectures": ["amd64", "arm64"],
    },
    {"id": "wine-stable-11.0.0.0", "type": "wine", "wine_branch": "stable", "wine_version": "11.0.0.0", "architectures": ["amd64", "arm64"]},
    {"id": "proton-11.7", "type": "proton", "proton_version": "11.7", "architectures": ["amd64"]},
    {"id": "proton-10.34", "type": "proton", "proton_version": "10.34", "architectures": ["amd64"]},
]

PLATFORMS = {
    "amd64": "linux/amd64",
    "arm64": "linux/arm64",
}

EMULATORS = {
    "box86": {
        "version": "0.3.9",
        "url": "https://github.com/ryanfortner/box86-debs/raw/e8c2c790274f37f642fa66b39712767d5770b5dc/debian/box86-generic-arm_0.3.9+20260927.7dec081-1_armhf.deb",
    },
    "box64": {
        "version": "0.4.5",
        "url": "https://github.com/ryanfortner/box64-debs/raw/0afc90842ada83a9b60d1d7114a9044ae2a3dd07/debian/box64_0.4.5+20261001.f5ffcd0-1_arm64.deb",
    },
}

WINE_ID = "debian"
WINE_TAG_SUFFIX = "-1"


def extract_hash(url: str) -> str:
    filename = url.rsplit("/", 1)[-1]
    match = re.search(r"\.([0-9a-fA-F]{7,})-", filename)
    return match.group(1) if match else "unknown"


def branch_suffix(github_ref: str) -> str:
    return "_dev" if github_ref.endswith("/dev") else ""


def wine_version_for_base(base_image: str, compat: dict) -> str:
    if compat["type"] != "wine":
        return ""
    versions = compat.get("wine_versions")
    if versions:
        codename = base_image.split("-", 1)[0]
        return versions[codename]
    return compat.get("wine_version", "")


def compat_id_for_base(base_image: str, compat: dict) -> str:
    if compat["type"] == "wine":
        return f"wine-{compat['wine_branch']}-{wine_version_for_base(base_image, compat)}"
    return compat["id"]


def compat_alias(compat: dict) -> str:
    if compat["type"] == "native":
        return ""
    if compat["type"] == "wine":
        return f"wine-{compat['wine_branch']}"
    return f"proton-{compat['proton_version']}"


def build_stem(base_image: str, compat: dict) -> str:
    parts = [base_image]
    if compat["type"] != "native":
        parts.append(compat_id_for_base(base_image, compat))
    return "_".join(parts)


def detailed_stem(base_image: str, compat: dict, arch: str) -> str:
    parts = [build_stem(base_image, compat)]
    if arch == "arm64":
        for name in ("box64", "box86"):
            emu = EMULATORS[name]
            hash_value = extract_hash(emu["url"])
            parts.append(f"{name}-{emu['version']}-{hash_value}")
    return "_".join(parts)


def apply_suffix_and_arch(stem: str, suffix: str, arch: str) -> str:
    return f"{stem}{suffix}_{arch}"


def generate_build_matrix(github_ref: str, registry_image_base: str) -> dict:
    del registry_image_base
    suffix = branch_suffix(github_ref)
    build_date = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    items = []

    for base_image in BASE_IMAGES:
        codename = base_image.split("-", 1)[0]
        for compat in COMPAT_LAYERS:
            for arch in compat["architectures"]:
                alias = compat_alias(compat)
                versioned_stem = build_stem(base_image, compat)
                detailed = detailed_stem(base_image, compat, arch)
                codename_stem = codename if not alias else f"{codename}_{alias}"

                item = {
                    "build_date": build_date,
                    "base_image_name": base_image,
                    "debian_codename": codename,
                    "platform_name": PLATFORMS[arch],
                    "architecture": arch,
                    "compat_layer_id": compat_id_for_base(base_image, compat),
                    "compat_layer_type": compat["type"],
                    "compat_layer_build_arg": "" if compat["type"] == "native" else compat["type"],
                    "wine_version_arg": wine_version_for_base(base_image, compat),
                    "wine_branch_arg": compat.get("wine_branch", ""),
                    "wine_id_arg": WINE_ID,
                    "wine_tag_suffix_arg": WINE_TAG_SUFFIX,
                    "wine_install_i386_arg": "false",
                    "proton_version_arg": compat.get("proton_version", ""),
                    "proton_install_i386_arg": "false",
                    "box86_version_arg": EMULATORS["box86"]["version"] if arch == "arm64" else "",
                    "box64_version_arg": EMULATORS["box64"]["version"] if arch == "arm64" else "",
                    "box86_deb_url_arg": EMULATORS["box86"]["url"] if arch == "arm64" else "",
                    "box64_deb_url_arg": EMULATORS["box64"]["url"] if arch == "arm64" else "",
                    "tag_versioned_arch": apply_suffix_and_arch(versioned_stem, suffix, arch),
                    "tag_detailed_arch": apply_suffix_and_arch(detailed, suffix, arch),
                    "tag_codename_arch": apply_suffix_and_arch(codename_stem, suffix, arch),
                }
                item["has_latest_tag_arch"] = compat["type"] == "native" and not suffix
                item["tag_latest_arch"] = f"latest_{codename}_{arch}" if item["has_latest_tag_arch"] else ""
                item["job_display_name"] = item["tag_detailed_arch"]
                items.append(item)

    return {"include": items}


def generate_manifest_matrix(github_ref: str, registry_image_base: str) -> dict:
    suffix = branch_suffix(github_ref)
    items = []

    for base_image in BASE_IMAGES:
        codename = base_image.split("-", 1)[0]
        for compat in COMPAT_LAYERS:
            alias = compat_alias(compat)
            versioned_stem = build_stem(base_image, compat)
            codename_stem = codename if not alias else f"{codename}_{alias}"
            architectures = compat["architectures"]

            target_versioned = f"{registry_image_base}:{versioned_stem}{suffix}"
            target_codename = f"{registry_image_base}:{codename_stem}{suffix}"
            versioned_sources = [
                f"{registry_image_base}:{apply_suffix_and_arch(versioned_stem, suffix, arch)}"
                for arch in architectures
            ]
            codename_sources = [
                f"{registry_image_base}:{apply_suffix_and_arch(codename_stem, suffix, arch)}"
                for arch in architectures
            ]

            create_latest = compat["type"] == "native" and not suffix
            items.append({
                "architectures": architectures,
                "target_tag_versioned": target_versioned,
                "source_images_versioned": versioned_sources,
                "target_tag_codename": target_codename,
                "source_images_codename": codename_sources,
                "create_latest_tag": create_latest,
                "target_tag_latest": f"{registry_image_base}:latest_{codename}" if create_latest else "",
                "source_images_latest": [
                    f"{registry_image_base}:latest_{codename}_{arch}" for arch in architectures
                ] if create_latest else [],
            })

    return {"include": items}


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--job", choices=["build", "manifest"], required=True)
    parser.add_argument("--github-ref", required=True)
    parser.add_argument("--registry-image-base", required=True)
    parser.add_argument("--debug", action="store_true")
    args = parser.parse_args()

    matrix = (
        generate_build_matrix(args.github_ref, args.registry_image_base)
        if args.job == "build"
        else generate_manifest_matrix(args.github_ref, args.registry_image_base)
    )

    if args.debug:
        print(json.dumps(matrix, indent=2), file=sys.stderr)
    print(json.dumps(matrix))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())

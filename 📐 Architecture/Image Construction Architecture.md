---
uid: YKT023
form:
  path: 'https://github.com/Teriyakidactyl/Repo-Manager/blob/main/a.%20Document%20Design/a.%20Assemblies/b.%20Forms/b.%20Architecture%20Document/README.md'
  version: '1.0'
description: >-
  Governs SteamCMD base-image construction, dependency installation,
  compatibility variants, filesystem ownership, and build evolution.
quadrant: Reference
outline:
  topology: tree
  axis: image construction responsibility
  numbering: hierarchical-decimal
writing-style:
  formality: professional
  tone: clinical/detached
  mode: declarative
  density: compressed/dense
  abstraction: mixed
  redundancy: zero
  signposting: entry-headers only
  register: technical
---

# 📖 Image Construction Architecture

## 1. Scope

Governs the root `Dockerfile`, its installers, and image-construction boundaries. Runtime behavior and the downstream configuration interface remain governed by their existing contracts.

## 2. Drivers

Image construction prioritizes compatibility correctness, minimal runtime dependencies, non-root execution, and persistent-state safety.

Build efficiency is desirable but must not compromise these properties. Supported variants represent intentional compatibility commitments, not every possible dependency combination.

## 3. Architecture

### 3.1 Installation

Installers execute within the target Debian environment because they modify native dependencies, system configuration, executable paths, and lifecycle hooks. Copying their apparent binary outputs alone is not equivalent.

Architecture-specific components precede compatibility layers, followed by SteamCMD.

Installation and cleanup currently share one `RUN`, preventing deleted temporary artifacts from remaining in earlier image layers. This is a useful property, not a requirement to retain that exact Dockerfile structure.

### 3.2 Compatibility

CPU emulation and Windows compatibility are separate responsibilities.

ARM64 uses Box86/Box64; SteamCMD uses Box64's Box32 mode. Wine requires architecture-aware package extraction, including i386 PE components for modern WoW64. Proton is limited to supported amd64 configurations.

The build matrix explicitly selects supported combinations. Dependency versions and platform restrictions must not be generalized without verifying compatibility.

### 3.3 Ownership and persistence

Runtime machinery and hooks are root-owned; game processes run unprivileged.

Image-owned tools remain separate from persistent application state under `/app` and world state under `/world`. Startup hooks establish persistent-state topology because mounted volumes can hide build-time filesystem contents.

### 3.4 Build identity

Build identity records source revision, build time, platform, and compatibility variant.

Changing metadata alone does not semantically require reinstalling unchanged dependencies. Cache optimization may exploit this distinction while preserving correct invalidation when functional inputs change.

## 4. Realization

- `Dockerfile` — construction, installation ordering, permissions, cleanup.
- `installers/` — dependency installation and runtime integration.
- `.github/scripts/generate_matrix.py` — supported variants and tags.
- `.github/workflows/docker-build.yml` — build and publication gates.
- `tests/` — executable contract verification.

## 5. Verification

Changes must preserve supported builds, native and compatibility smoke tests, ARM64 execution, runtime ownership, hooks, and persistent-state behavior.

Construction changes must additionally verify runtime dependencies, image size, and applicable cache invalidation. Existing tests do not establish all these properties automatically.

## 6. Evolution

Construction may be reorganized, including additional layers or stages, when equivalent behavior and dependency completeness are demonstrated.

Do not treat the current single-`RUN` arrangement as permanent architecture. Equally, do not replace it solely for caching convenience without demonstrating that its cleanup, security, and compatibility properties survive.

Architectural changes update this document alongside their implementation.

---
uid: D8S4QW
description: >-
  Routes authors of docker-steamcmd-server derivative images to current
  authoring procedures for application contracts, configuration projection,
  persistence, and lifecycle validation.
---

# SteamCMD derivative authoring

Use this directory when creating or revising a dedicated-server image that
inherits from `docker-steamcmd-server`. The root
[`README.md`](../README.md) remains the runtime/base contract; documents here
own reusable derivative-authoring procedures rather than base implementation.

## Authoring guides

- [🛠️ Author a SteamCMD Derivative Container](./1.%20%F0%9F%9B%A0%EF%B8%8F%20Author%20a%20SteamCMD%20Derivative%20Container.md)
  — build a derivative around the shared runtime, expose a sourced container
  configuration API, reconcile native configuration idempotently, persist
  application/world state, and validate first-start plus recreation behavior.

## Working notes

[`TODO.md`](TODO.md) predates this authoring surface and remains a working
note, not current authoring authority. Promote durable guidance from it into an
appropriate controlled document before relying on it as a rule.

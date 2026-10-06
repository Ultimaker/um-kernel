---
name: build-test-and-deployment
description: Build, test, and deployment verification commands detected for this repository, with Freshness Before Evidence rules.
trigger: always_on
---
# Build, Test & Deployment Verification

1. **Build Commands (detected)**:
   - `./build_for_ultimaker.sh`
   - Builds must complete cleanly (no new warnings) before PR creation.
   - **Container Rebuilds & Compilation Mandate**: When changing frontend or backend code in Docker or compiled environments, executing container rebuilds or asset compilation (`docker compose build <service>` / `npm run build`) is strictly required before visual or functional verification.
2. **Package Registry Authentication**:
   - Obtain `GITHUB_TOKEN` (scope `read:packages`) for private `@ultimaker` packages via the keyring-first chain in `scripts/get_github_token.sh` — source it (`. scripts/get_github_token.sh`) instead of hand-exporting: (a) an existing env var wins, (b) else the system keyring (Linux: `secret-tool lookup service github user "$USER"`), (c) else a gitignored `.env`/`.env.local` fallback with a warning. Store it once per machine, user-specific — never a hardcoded username: `echo -n "<PAT>" | secret-tool store --label="$USER-github-token" service github user "$USER"`. Never write tokens to disk, logs, or git.
3. **Artifact Isolation**:
   - Keep generated build outputs, intermediate binaries, and logs out of git. Ensure `.env` and `.env.local` files remain strictly gitignored.
4. **Firmware Docker Container Testing Mandate**:
   - Firmware repositories (`opinicus`, `okuda`, `jedi-build`, `jedi-cookbook`, `stardust-embedded`, `ultimoco`, `fdm_materials`) target ARM embedded Linux devices. Unit and integration tests MUST be executed inside official Docker build containers (`./build_for_ultimaker.sh` or `docker run ...` with container mounts) and NEVER directly on host x86 development environments.
   - All tests must pass cleanly inside Docker before committing or opening pull requests.
5. **Freshness Before Evidence**:
   - Rebuild binaries/packages/containers before treating a behavioral observation as evidence. An observation is only valid if the artifacts observed were compiled from the current source state. An unverified stale build is a false observation.
6. **Git Submodules**:
   - This repository uses submodules (`linux`). Run `git submodule update --init` after checkout.
   - NEVER commit changes inside submodule trees from this repository; submodule pointer bumps require their own reviewed change.


## Semantic Release & Version Tagging

1. **SemVer Version Tagging**:
   - Releases MUST follow Semantic Versioning (`MAJOR.MINOR.PATCH`).
   - Tags MUST be created on main branch commits after PR integration.
2. **Automated Changelog Generation**:
   - Changelogs are generated directly from Pull Request titles. Ensure PR titles follow the `[EMB-370] <Descriptive Title>` standard.
3. **Version Synchronization**:
   - Keep the version number synchronized across the manifests this repository actually carries: DEBIAN `changelog` / `control`. A release that bumps one and not the others ships a lie about itself.

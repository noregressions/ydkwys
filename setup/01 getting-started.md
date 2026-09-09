---
id: setup-getting-started
oneliner: "Clone the repository, then pick one of three routes: local tools, a locally built container image, or the published image."
track: core
---

# Getting Started

Setup is two steps: clone the repository, then make the tools available by one of three routes.

```text
1. clone the repository                      everyone
2. pick one route:
   A  install the tools on your host         full control, slowest setup
   B  build the workshop image locally       one Docker build, no large pull
   C  pull the published workshop image      one Docker pull, fastest setup
```

Routes B and C give an identical shell; they differ only in where the image comes from. All three end at the same check, `./scripts/tools-check.sh` exiting 0.

## Step 1: Clone the Repository

Required for every route: the manual, the scenario sources, and the scripts all live in the repository, and routes B and C mount and build from it.

```command
git clone https://github.com/noregressions/ydkwys.git
cd ydkwys
```

To update an existing checkout:

```command
git pull
```

Run every command in this manual from the repository root.

## Step 2, Route A: Install Tools Locally

### A1. Check Tool Prerequisites

```command
./scripts/tools-check.sh
```

This utility inspects installed binaries against the minimum required versions and outputs installation links for missing dependencies. It makes no system modifications.

### A2. Install Missing Prerequisites

Install missing packages using the system package manager, or refer to [`setup/INSTALL.md`](./INSTALL.md) for OS-specific commands (macOS Homebrew, Debian/Ubuntu APT).

Re-run validation:

```command
./scripts/tools-check.sh
```

### A3. Build the Scenario Targets

```command
./scripts/build-all.sh
```

This script:
1. Pulls the required container base images (`eclipse-temurin:21-jre-jammy`, `payara/server-web:7.2026.7`).
2. Builds the Maven, npm, and Python targets across scenarios S01–S05.
3. Builds the container image targets.
4. Initializes the local vulnerability databases for Grype, Trivy, and Syft.

Every phase is independent: a failure is recorded and the run continues. This is the slowest step of this route — it performs every download the workshop needs — so run it on a good network. `./scripts/build-all.sh --help` lists the available options; see [`setup/04 BUILDING.md`](./04%20BUILDING.md) for the phase breakdown and [`setup/BUILD-MANUAL.md`](./BUILD-MANUAL.md) for the equivalent commands run by hand.

## Step 2, Route B: Build the Container Image Locally

Requirements: Docker Desktop, or Docker Engine on Linux, with at least 20 GB free disk space.

Build the tools/base image and the workshop code image:

```command
./container/build.sh
```

Add `--base` to force a rebuild of the tools/base image, which refreshes the scanner vulnerability databases. Then start a shell in the image you just built:

```command
WORKSHOP_IMAGE=shipping-workshop:latest ./container/run.sh
```

Validate the environment inside the container:

```command
./scripts/tools-check.sh
```

## Step 2, Route C: Pull the Published Container Image

Requirements: Docker Desktop, or Docker Engine on Linux, with at least 20 GB free disk space.

The first run pulls the published image `noregressions/ydnwys-workshop:0.0.1` (about 2.4 GB) and drops you into a shell:

```command
./container/run.sh
```

Validate the environment inside the container:

```command
./scripts/tools-check.sh
```

## Container Notes (Routes B and C)

The image provides the preinstalled tools, precompiled scenario targets, and pre-cached vulnerability databases that route A builds locally.

- The container accesses the host Docker daemon via a mounted Unix socket (`/var/run/docker.sock`). Images built by scenarios S01 and S02 are registered directly with the host daemon and publish ports to `localhost`.
- Scenario servers in S03, S04, and S05 bind within the container network namespace. Issue `curl` verification requests from within the container shell.
- Authentication tokens can be forwarded by exporting `SNYK_TOKEN` and `NVD_API_KEY` before executing `./container/run.sh`.

## Verification Criteria

Setup is complete when:

```text
Route A     tools-check.sh   exits 0
            build-all.sh     reports 0 failed
Routes B/C  tools-check.sh   exits 0   inside the container shell
```

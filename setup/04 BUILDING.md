---
id: setup-building
oneliner: "What build-all.sh does: base image pulls, scenario compilation, and scanner vulnerability database initialization."
track: core
---

# Building the Scenario Targets

Reference for `./scripts/build-all.sh`, the build step of the host route in
[`setup/01 getting-started.md`](./01%20getting-started.md). It pulls the base
container images, compiles every scenario target, and initializes the local
scanner vulnerability databases. The container routes ship all of this already
built inside the image.

## Automated Execution

```command
./scripts/build-all.sh
```

This command executes the following operations without starting persistent background services:
1. Pulls required base container images.
2. Builds all five scenario targets (S01–S05).
3. Compiles S01 and S02 container images.
4. Initializes local vulnerability databases for Grype, Trivy, and Syft.

To include baseline runs for investigations T01–T08:

```command
./scripts/build-all.sh --with-investigations
```

Additional CLI options:

```command
./scripts/build-all.sh --list     # List configured build phases
./scripts/build-all.sh --quick    # Build scenarios only; skip container pulls and DB downloads
./scripts/build-all.sh --help     # Display CLI option summary
```

The script evaluates each phase independently and returns a non-zero exit status if any step fails.

## What Each Phase Builds

| Step | Target Resource | Direct CLI Command |
|---|---|---|
| Container Base Images | `eclipse-temurin:21-jre-jammy`, `payara/server-web:7.2026.7` | `docker pull eclipse-temurin:21-jre-jammy && docker pull payara/server-web:7.2026.7` |
| Maven Scenarios (S01, S02, S04) | Plugins and dependencies in `~/.m2/repository` | `./scripts/build.sh` within each scenario directory |
| npm Scenario (S05) | Node packages and lifecycle script validation | `scenarios/S05-node-prepack/scripts/build.sh` |
| Python Scenario (S03) | Virtual environment and package dependencies | `scenarios/S03-python-pep517/scripts/build.sh` |
| Grype Database | Local vulnerability database cache | `grype db update && grype db status` |
| Trivy Database | Local vulnerability database cache | `trivy fs --scanners vuln --no-progress scenarios/S01-spring-node` |
| Syft Cache | Asset index and binary dependencies | `syft scenarios/S01-spring-node -o table >/dev/null` |

For step-by-step manual execution procedures, see [`setup/BUILD-MANUAL.md`](./BUILD-MANUAL.md).

## Manual Configuration Requirements

### 1. Snyk CLI Authentication (T01)

```command
snyk auth
```

### 2. OWASP Dependency-Check NVD Cache (T06)

Populate the local NVD dataset using an exported `NVD_API_KEY`:

```command
cd investigations/T06-owasp-dependency-check-s04
./scripts/baseline-s04.sh
./scripts/run-dependency-check-s04.sh
cd ../..
```

Data is persisted in `~/.cache/kcdc-dependency-check/<version>`. If `NVD_API_KEY` is not set, the harness executes against Dependency-Check version 12.2.2.

## Verification

Verify completion with the following checks:

```command
./scripts/tools-check.sh
./scripts/build-all.sh
docker image inspect eclipse-temurin:21-jre-jammy >/dev/null && \
docker image inspect payara/server-web:7.2026.7 >/dev/null && \
echo "Workshop base images ready"
```

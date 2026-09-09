---
id: setup-tools
oneliner: "Tool prerequisites, minimum version specifications, automated verification, and container engine compatibility."
track: core
---

# Tool Prerequisites

Verify the local environment against the required tool specifications:

```command
./scripts/tools-check.sh
```

The script evaluates installed binaries against the minimum version thresholds and outputs install documentation for any missing tools. Non-zero exit status indicates a missing or outdated prerequisite.

To display installation URLs for all tools:

```command
./scripts/tools-check.sh --urls
```

## Environment Specifications

| Tool | Requirement | Source / Packaging |
|---|---|---|
| Bash | 4+ or macOS system Bash | System |
| Git | 2.30+ | System package manager |
| JDK | 21+ | OpenJDK / Temurin / Zulu |
| Maven | 3.9+ | Apache Maven |
| Node.js | 20+ | Node.js |
| npm | 10+ | Bundled with Node.js |
| Python | 3.11+ | Python.org / system package manager |
| pip / venv | Compatible with Python | Bundled with Python |
| Docker | Current Docker Desktop or Docker Engine | Docker Engine 24+ |
| jq | 1.6+ | System package manager |
| Syft | 1.0+ | Anchore |
| Snyk CLI | Current | npm (`snyk`) |
| Trivy | 0.50+ | Aqua Security |
| Grype | 0.75+ | Anchore |
| pip-audit | 2.7+ | PyPA (`pipx install pip-audit`) |
| cosign | 3.0+ | Sigstore (S07 signing and attestation) |
| GuardDog | 3.0+ | Datadog (`pipx install guarddog`, T08) |
| Docker Scout | Current | Bundled with Docker Desktop / Docker plugin |
| curl | System standard | System |
| zip / unzip / tar | System standard | System |
| coreutils (grep, find, sort, diff, tee) | System standard | System |

Note: `npm audit` is provided by npm; `jar` and `javap` are provided by the JDK; `pip` is provided by Python. Maven plugins (CycloneDX, Shade, Spring Boot, frontend/esbuild, OWASP Dependency-Check) and mvnpm artifacts are resolved automatically during build executions. SBOM+ (S08) is not yet on Maven Central; the scenario installs a vendored copy from `scenarios/S08-extended-sbom/plugin-repo/` when it cannot be fetched.

## Installation Commands (macOS / Homebrew)

```command
brew install openjdk@21 maven node python jq syft grype trivy osv-scanner cosign pipx
pipx install pip-audit
pipx install guarddog
npm install -g snyk
```

Install Docker Desktop for the Docker daemon and Docker Scout CLI integration.

For Debian/Ubuntu APT commands, manual installation procedures, and version verification tests, see [`setup/INSTALL.md`](./INSTALL.md).

For the baseline versions used when capturing scenario results, see [`setup/VERSIONS.md`](./VERSIONS.md).

## Container Engine Compatibility (Podman)

Docker is the target container engine invoked by scenario build scripts. Podman can execute basic build and run steps for S01 and S02 when using a Docker alias or socket emulation, with the following technical constraints:

- **T02 (Docker Scout):** Requires Docker Scout CLI and Docker daemon integration; not supported under standalone Podman.
- **T03 (Trivy):** Uses the `docker:` image target source.
- **T04 (Grype):** Uses the `docker:` image target source.

Refer to [`setup/INSTALL.md`](./INSTALL.md) for Podman socket and configuration requirements.

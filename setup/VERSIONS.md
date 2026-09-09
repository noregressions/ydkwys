---
id: setup-versions
oneliner: "Baseline authoring environment, pinned repository dependencies, dynamic scanner versions, and vulnerability database drift."
track: reference
---

# Verified Baseline Versions

The scenario outputs and benchmark data in this repository were generated against the following environment baseline:

| Tool | Verified Version |
|---|---|
| Bash | 3.2.57(1) (macOS system Bash) |
| Git | 2.50.1 (Apple Git-155) |
| JDK | 25.0.2 Temurin (`25.0.2+10-LTS`) |
| Maven | 3.9.16 |
| Node.js | 26.4.0 |
| npm | 12.0.1 |
| Python | 3.14.6 |
| pip | 26.1.2 |
| Docker | 29.7.2 client and engine (Docker Desktop 4.87.0) |
| Docker Compose | 5.4.0 |
| Docker Scout | 1.24.0 |
| jq | 1.7.1-apple |
| Syft | 1.51.0 |
| Snyk CLI | 1.1305.2 |
| Trivy | 0.74.0 |
| Grype | 0.115.0 (DB schema 6) |
| pip-audit | 2.10.1 |
| curl | 8.7.1 (LibreSSL 3.3.6) |
| zip / unzip | Zip 3.0 / UnZip 6.00 |
| tar | bsdtar 3.5.3 (libarchive 3.7.4) |
| grep | BSD grep 2.6.0-FreeBSD |

Note: The build configurations set `maven.compiler.release` to 21, ensuring bytecode consistency across JDK 21 and newer compiler releases.

## Pinned Repository Components

These dependencies and plugins are pinned in POM and configuration files and resolved at build time:

| Component | Version | Target Module |
|---|---|---|
| Spring Boot | 3.5.12 | S01 |
| Maven Shade Plugin | 3.6.2 | S01 |
| CycloneDX Maven Plugin | 2.9.3 | S01 |
| SBOM+ Maven Plugin | 1.0.0 (vendored) | S08 |
| esbuild Maven Plugin | 2.0.0 | S02 |
| Jakarta EE API | 11.0.0 | S02 |
| maven-plugin-tools | 3.15.1 | S04 tooling |

## Dynamic Runtime Scanner Configurations

- **OWASP Dependency-Check (T06):** Selects version `13.0.0` when `NVD_API_KEY` is present, and falls back to `12.2.2` when unauthenticated to avoid API update restrictions. See `investigations/T06-owasp-dependency-check-s04/scripts/common.sh`.
- **Grype:** Embeds an internal version of Syft (Grype 0.115.0 bundles Syft v1.46.0). Differences between Grype package inventories and standalone Syft 1.51.0 inventories reflect version differences in the embedded cataloger.

## Vulnerability Database Drift

Vulnerability matchers (Trivy, Grype, Snyk, Dependency-Check) query vulnerability feeds that receive continuous updates. Exact finding counts recorded in traces reflect database state at capture time. Structural assertions (such as whether a component is detected or omitted across boundaries) remain constant.

Check local database update timestamps:

```command
trivy --version
```

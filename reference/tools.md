---
id: reference-tools
oneliner: "Taxonomy of supply chain tooling categorized by evidence boundary, data inputs, and boundary limitations."
track: reference
---

# Tooling and Evidence Boundaries Reference

Technical categorization of analysis, build, and scanning tooling based on observed supply chain boundaries and evidence inputs.

```text
Evidence Evaluation Model:
1. Target boundary observed
2. Evidence sources available at that boundary
3. Systematic visibility limitations
```

## 1. Resolvers (Declared Model -> Resolved Graph)

- **Apache Maven:** Resolves declared Java dependencies into concrete versions, generating `dependency:tree` and effective POM models.
  - *Evidence boundary:* Declared project dependency graph and configured build plugins.
  - *Visibility limitation:* Does not record transitive dependencies inside plugin execution realms as application dependencies (S04).
- **npm:** Resolves Node.js package trees, generating `package-lock.json`.
  - *Evidence boundary:* Declared package manifest and locked dependency tree.
  - *Visibility limitation:* Executes lifecycle scripts (`prepack`, `postinstall`) that can generate or modify artifacts without altering the dependency graph (S05).
- **pip:** Resolves Python packages according to PEP 517 build-backend specifications.
  - *Evidence boundary:* Source distributions and requirement manifests.
  - *Visibility limitation:* Delegates artifact generation to arbitrary build backend code during package installation (S03).

## 2. Inventory / SBOM Generators

- **Syft (Anchore):** Generates Software Bills of Materials (CycloneDX / SPDX) from static file inspection of archives, directories, and container images.
  - *Evidence boundary:* Physical artifact metadata (`pom.properties`, package manifests, file paths).
  - *Visibility limitation:* Misses shaded/relocated bytecode when Maven metadata is omitted, and does not reconstruct individual package boundaries from bundled JavaScript (S01).
- **CycloneDX Maven Plugin:** Generates CycloneDX SBOMs from Maven's in-memory project object model.
  - *Evidence boundary:* Maven resolver data.
  - *Visibility limitation:* Omits code introduced dynamically via build plugin executions or compiler source generation (S04).
- **SBOM+ Maven Plugin (`dev.noregressions:sbom-plus-maven-plugin`):** Generates a CycloneDX SBOM from the project graph plus every plugin's dependency graph and imported BOMs, with a companion scan report recording `origin` and the `broughtInBy` path per row.
  - *Evidence boundary:* Maven resolver data, extended to build tooling (marked `excluded`) and BOM imports (`?type=pom`).
  - *Visibility limitation:* Still a resolver-level claim: names the plugin that generated code, not the generated code; resolves from repositories, so uninstalled sibling modules land in `unresolved` (S08).

## 3. Vulnerability Scanners

- **Grype (Anchore):** Matches package inventories against vulnerability feeds using an embedded cataloger.
  - *Evidence boundary:* Artifact metadata and container filesystem layers.
  - *Visibility limitation:* Bound to the package extraction fidelity of its embedded Syft engine (T04).
- **Trivy (Aqua Security):** Scans filesystems, Git repositories, and container images against Aqua vulnerability databases.
  - *Evidence boundary:* Manifest files, lockfiles, and container image layers.
  - *Visibility limitation:* Produces diverging vulnerability inventories depending on whether target is inspected as source, JAR artifact, JS bundle, or container (T03).
- **Docker Scout:** Evaluates finalized container image layers.
  - *Evidence boundary:* Container filesystem and OS package manager databases.
  - *Visibility limitation:* Blind to upstream source transformations and build-time plugin execution (T02).
- **npm audit:** Evaluates `package-lock.json` dependency metadata against npm security advisories.
  - *Evidence boundary:* Static metadata graph.
  - *Visibility limitation:* Does not inspect unpacked tarball bytecode or verify runtime execution behavior (T07).
- **pip-audit:** Evaluates installed Python environments against PyPA advisory feeds.
  - *Evidence boundary:* Installed distribution metadata in `site-packages`.
  - *Visibility limitation:* Blind to transient build backend execution that executed during installation (T05).
- **OWASP Dependency-Check:** Matches file hashes and extracted metadata against NVD CPE configurations.
  - *Evidence boundary:* Archive contents and manifest strings.
  - *Visibility limitation:* Subject to CPE dictionary mapping accuracy; cannot detect components lacking standard metadata headers (T06).
- **Snyk:** Commercial SCA platform analyzing dependencies across manifests and binary hashes.
  - *Evidence boundary:* Dependency graphs, package hashes, and proprietary vulnerability databases.
  - *Visibility limitation:* Cannot identify components when build transformations omit both coordinate metadata and recognizable bytecode signatures (T01).

## 4. Vulnerability and Intelligence Datasets

- **CVE.org (CNAs):** Primary vulnerability disclosure registry published by authorized Numbering Authorities.
- **NVD (NIST):** Enriches CVE records with CVSS vectors and structured CPE match criteria.
- **CISA KEV:** Authoritative catalogue of actively exploited vulnerabilities in the wild.
- **OSV (Open Source Vulnerabilities):** Distributed vulnerability database keyed by ecosystem package coordinates.
- **deps.dev (Google):** Free package-coordinate index aggregating advisories, licences, dependents and Scorecard results. No account required; web UI and API.
- **Sonatype OSS Index:** Formerly a free package-coordinate index, used by earlier editions of Part 4. As of 2026-09-08 the site redirects to Sonatype's commercial guide and the API returns 401 unauthenticated. Recorded here because Part 4 uses its disappearance as evidence, not because it is still usable.

## 5. Maintenance and Lifecycle Assessment

- **OpenSSF Scorecard:** Automated repository analysis evaluating software development hygiene and CI/CD security controls.
- **OpenEoX (OASIS):** Open standard specification for exchanging machine-readable lifecycle, EOL, and end-of-support data.
- **Dependency-Track (OWASP):** Continuous component analysis platform evaluating SBOMs against vulnerability intelligence.

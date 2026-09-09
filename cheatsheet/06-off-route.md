---
id: cheatsheet-off-route
oneliner: "Reference investigations T02-T07: one tool each, same questions, same artefacts. Not on the route."
track: reference
---

# Off the Route — Reference Investigations

One tool each, asking the same questions of the same artefacts. Nothing
here is needed to follow the workshop; all of it is runnable afterwards.

---

## T02 — Docker Scout: what does the final container know? (S01, S02)

Question: once the image is built, what identity can Scout recover from it, and what history is already gone?
Needs: Docker Desktop with Scout, `docker login`, `jq`. S01 and S02 images are rebuilt by the baselines.

```command
cd investigations/T02-docker-scout
```

Confirm Scout is available and the CLI is authenticated.
```command
docker scout version
```

#### S01 image

Rebuild the S01 image via the scenario's image-trace and record its digest and labels. Writes results/s01/baseline/.
```command
./scripts/baseline-s01.sh
```
```output
registry.example.com/checkout-service:release-123
sha256:<digest>
179 packages        (Syft, second witness)
837 executables
```

Run quickview, sbom --format list, cves (filtered to the tracked components) and recommendations against local://<image>. Writes results/s01/scout/.
```command
./scripts/run-scout-s01.sh
```
```output
237 packages indexed
base image: eclipse-temurin:21-jre-jammy
provenance obtained from attestation
policy: FAILED (3/7)
health score: D (44%)

commons-codec      1.17.1
commons-codec      1.18.0
jackson-databind   2.19.4
normalizer         1.0.0
lodash 4.17.21     (not identified)

jackson-databind 2.19.4
    2 HIGH
    3 MEDIUM
```
Provenance shows the repo URL and source commit. Syft saw 179 packages, Scout 237, same image.

Print the Scout summary, tracked identities and tracked CVEs, then ten interpretation questions.
```command
./scripts/compare-s01.sh
```

#### S02 image

Rebuild the Payara image and record its digest and labels. Writes results/s02/baseline/.
```command
./scripts/baseline-s02.sh
```

Same four Scout views on local://payara-mvnpm-trace-lab:local, filtered to commons-lang3, lodash-es, jakarta and payara. Writes results/s02/scout/.
```command
./scripts/run-scout-s02.sh
```
```output
655 packages indexed
base image: payara/server-web:7.2026.7
provenance obtained from attestation

commons-lang3 3.18.0
many Jakarta APIs
many Payara/GlassFish modules
lodash-es 4.17.21     (not identified)

No vulnerable packages detected
No recommendations
```
Jakarta is back in the inventory, but as Payara's packages, not the WAR's.

Print the S02 answers and a fixed interpretation block.
```command
./scripts/compare-s02.sh
```

Assert six claims: the three Java tracked components seen, lodash not recovered, provenance obtained, commons-lang3 seen.
```command
./scripts/proof-check.sh
```
```output
T02 Docker Scout proof check
============================
PASS  S01 Scout identifies commons-codec
PASS  S01 Scout identifies jackson-databind
PASS  S01 Scout identifies normalizer
PASS  S01 Scout does not recover bundled lodash
PASS  S01 Scout obtains provenance attestation
PASS  S02 Scout identifies commons-lang3

Passed: 6
Failed: 0
```

Takeaway: a container is a different evidence boundary. Moving later adds runtime and OS software but does not recover identity lost by bundling. Same artefact boundary ≠ same inventory across scanners.

---

## T03 — Trivy across S01 boundaries

Question: does the vulnerability answer change when the same software is observed as a POM, a JAR, a bundle, or an image?
Needs: Trivy, `jq`, Docker, `zip`, Maven, npm. Trivy mode matters: `fs` for models and dist, `rootfs` for staged JARs, `image --image-src docker` for the image.

```command
cd investigations/T03-trivy-s01
```

Build S01 clean, create the metadata-stripped normalizer, build the image, capture Maven/npm/jar/Syft ground truth. Writes results/s01/baseline/.
```command
./scripts/baseline-s01.sh
```
```output
normalizer -> commons-codec 1.17.1
service    -> jackson-databind 2.19.4, normalizer 1.0.0 -> commons-codec 1.18.0 (version managed from 1.17.1)
checkout-trace-frontend@1.0.0 -> lodash@4.17.21
```

trivy fs on the two POMs, package-lock and frontend/dist, plus trivy image on the container. Writes results/s01/trivy/<label>.*
```command
./scripts/run-trivy-nonarchives-s01.sh
```

Stage each JAR (shaded, stripped, Boot) in an isolated dir and scan with trivy rootfs. Same output layout.
```command
./scripts/run-trivy-archives-s01.sh
```

Or run all eight probes in one pass.
```command
./scripts/run-trivy-s01.sh
```

Per boundary, the tracked identities Trivy reported:

```text
normalizer POM             commons-codec 1.17.1
service POM                jackson-databind 2.19.4 (5 CVEs: 2 HIGH, 3 MEDIUM); codec 1.18.0 NOT seen from this POM alone
package-lock               lodash 4.17.21 (3 CVEs, e.g. CVE-2026-4800)
shaded normalizer JAR      commons-codec 1.17.1
stripped normalizer JAR    normalizer 1.0.0 only; commons-codec GONE
service JAR                codec 1.17.1, codec 1.18.0, jackson-databind 2.19.4, normalizer 1.0.0
frontend/dist              Number of language-specific files num=0; nothing
container image            codec 1.17.1, codec 1.18.0, jackson-databind 2.19.4; OS Ubuntu 22.04, 143 OS packages; no lodash
```

Print ground truth, then tracked identity and tracked CVEs for all eight boundaries, then ten questions.
```command
./scripts/compare-s01.sh
```

Assert 19 claims against results/, including "Trivy loses codec identity after Maven metadata removal".
```command
./scripts/proof-check.sh
```
```output
T03 Trivy proof check
=====================
PASS  ...
Passed: 19
Failed: 0
```

Takeaway: a CVE scanner is downstream of identification. Break the chain at package identity and the CVE disappears while the code stays. Using the wrong scan mode is a false negative before matching even starts.

---

## T04 — Grype: inventory versus matching (S02)

Question: does Grype give a different answer when it discovers the Payara image itself versus consuming an SBOM of that image?
Needs: Grype, Syft, Docker, `jq`, `diff`. Grype refuses a stale DB (max age 5 days); `common.sh` sets `GRYPE_DB_VALIDATE_AGE=false`.

```command
cd investigations/T04-grype-s02
```

Build S02, capture Maven app tree, plugin realm, WAR contents, build the image, and write Syft JSON + CycloneDX inventories of it. Writes results/s02/baseline/.
```command
./scripts/baseline-s02.sh
```
```output
payara-mvnpm-trace-lab:local
589 packages / 825 executables      (Syft JSON)
6014 components                     (CycloneDX)
commons-lang3 3.18.0   seen
lodash-es 4.17.21      not identified
```

Grype three ways over one image (docker:, sbom:<syft json>, sbom:<cyclonedx>) plus two direct PURL controls. Writes results/s02/grype/.
```command
./scripts/run-grype-s02.sh
```
```output
direct image     169 unique vulnerability matches
Syft JSON        169 unique vulnerability matches
CycloneDX        169 unique vulnerability matches

nimbus-jose-jwt 10.0.1   GHSA-xwmg-2g98-w7v9   Medium
jline-remote-telnet      GHSA-2r2c-cx56-8933   High
jackson-core 2.15.2      GHSA-r7wm-3cxj-wff9   High

pkg:maven/org.apache.commons/commons-lang3@3.18.0   no vulnerability matches
pkg:maven/org.mvnpm/lodash-es@4.17.21               no vulnerability matches
```
No tracked match anywhere. The PURL controls show the silence is a database fact for commons-lang3 and an identity loss plus database fact for lodash-es.

Print counts and the exact diffs of the three match sets side by side.
```command
./scripts/compare-s02.sh
```
```output
direct image vs Syft JSON    no differences
direct image vs CycloneDX    no differences
Syft JSON vs CycloneDX       no differences
```

Assert 20 claims: inventory counts, 169 x3, identical sets, empty PURL controls, the two named GHSA findings.
```command
./scripts/proof-check.sh
```
```output
T04 Grype proof check
=====================
PASS  Direct image scan has 169 unique vulnerability matches
PASS  Direct image and Syft JSON match sets are identical
PASS  lodash-es PURL control has no vulnerability match
...
Passed: 20
Failed: 0
```

Takeaway: representation does not change the answer; inventory does. An SBOM-driven scan can agree perfectly with a direct scan and still miss software whose identity vanished earlier. The database, and its freshness, is part of the result.

---

## T05 — pip-audit: identity, matching, and execution (S03)

Question: can a Python audit see that a PEP 517 backend ran, and can the audit itself run that backend?
Needs: pip-audit, Python 3.11+, `jq`, `tar`, `unzip`.

```command
cd investigations/T05-pip-audit-s03
```

Build S03 in a fresh venv and capture requirements, metadata, sdist listing, backend declaration, installed files and the generated marker. Writes results/s03/baseline/.
```command
./scripts/baseline-s03.sh
```
```output
Successfully installed: reportkit-1.0.0 tracehook-demo-1.0.0
tracehook_demo/__init__.py        (installed, absent from sdist)
tracehook_demo/build-hook.json    (installed, absent from sdist)
```

Build a local PEP 503 index, then run five audits: requirements (resolved), --no-deps, --no-deps --disable-pip, installed site-packages, CycloneDX. Writes results/s03/pip-audit/.
```command
./scripts/run-pip-audit-s03.sh
```
```output
requirements audit          Dry run: would have audited 2 packages
                            reportkit, tracehook-demo
                            Dependency not found on PyPI and could not be audited
--no-deps                   reportkit, tracehook-demo      (still both, on pip-audit 2.10.1)
--no-deps --disable-pip     reportkit                      (transitive gone)
installed environment       pip 26.1.2, reportkit 1.0.0, tracehook-demo 1.0.0
                            pip 26.1.2  PYSEC-2026-3721 / CVE-2026-13346  fixed in 26.2
CycloneDX output            pip 26.1.2 only; reportkit and tracehook-demo absent
```

Controlled experiment: rebuild the sdist with a backend that writes a marker on import, then audit it. Proves the audit executes packaging code.
```command
./scripts/run-pep517-exec-probe.sh
```
```output
INFO:pip_audit._audit:Dry run: would have audited 2 packages
No known vulnerabilities found

PEP 517 execution marker:
tracehook_backend imported during pip-audit dependency resolution
```

Print ground truth, resolution signals, the marker, all four dependency lists and the CycloneDX grep, then nine questions.
```command
./scripts/compare-s03.sh
```

Assert 21 claims against results/.
```command
./scripts/proof-check.sh
```
```output
T05 pip-audit proof check
=========================
PASS  pip-audit dependency collection executes PEP 517 backend code
PASS  --no-deps --disable-pip excludes transitive tracehook-demo
PASS  Installed-environment audit finds PYSEC-2026-3721
...
Passed: 21
Failed: 0
```

Takeaway: package identity ≠ vulnerability coverage ≠ build history. With resolution enabled, the audit is itself an active supply-chain operation, not a static read.

---

## T06 — OWASP Dependency-Check: which dependency universe? (S04)

Question: at which boundary can Dependency-Check still identify the plugin and payload that generated S04's hidden route?
Needs: Maven, `jq`, `javap`, and an NVD API key. First run downloads about 380,000 NVD records and is slow; the cache lives in `~/.cache/kcdc-dependency-check/<version>`.

```command
cd investigations/T06-owasp-dependency-check-s04
```

Without a key the harness falls back to Dependency-Check 12.2.2; with one it uses 13.0.0.
```command
export NVD_API_KEY='your-key-here'
```

Capture Maven app tree, plugin resolution, plugin realm, generated files, JAR entries and javap strings, and copy the plugin/payload JARs as controls. Writes results/s04/baseline/ and results/s04/controls/.
```command
./scripts/baseline-s04.sh
```
```output
dev.noregressions.trace:maven-plugin-hidden-content:jar:1.0.0          (app tree: only this)
dev.noregressions.trace:trace-injector-maven-plugin:jar:1.0.0          (plugin resolution)
dev.noregressions.trace:trace-route-payload:jar:1.0.0                  (plugin resolution)
dev/noregressions/trace/s04/generated/GeneratedTraceRoute.class        (in JAR)
```

Four probes, one engine and one NVD snapshot: default Maven scan, plugin-aware scan (-Dodc.plugins.scan=true), final JAR directory, plugin+payload JAR controls. Writes results/s04/dependency-check/<label>/.
```command
./scripts/run-dependency-check-s04.sh
```
```output
NVD API key: supplied via NVD_API_KEY environment variable

default-maven             Dependencies: 0     Vulnerability records: 0    tracked components: (none)
plugin-aware-maven        Dependencies: 167   Vulnerability records: 78   tracked components: trace-injector-maven-plugin, trace-route-payload
final-jar                 Dependencies: 1     Vulnerability records: 0    tracked components: maven-plugin-hidden-content only
plugin-payload-controls   Dependencies: 2     Vulnerability records: 0    tracked components: both identified
```
The 78 records are build tooling: commons-beanutils 1.7.0, commons-compress 1.20, guava 16.0.1, maven-core 3.2.5, jetty 9.4.46, velocity 1.7 and others. Neither tracked component itself has a match.

Re-print ground truth, the four probe summaries, diffs between adjacent probes, and eight questions.
```command
./scripts/compare-s04.sh
```

Assert 27 claims. Note: it pins the exact counts 167 and 78, which drift with Maven version and NVD snapshot.
```command
./scripts/proof-check.sh
```
```output
T06 Dependency-Check proof check
================================
PASS  ...
Passed: 27
Failed: 0
```

Takeaway: application graph ≠ build-tool graph ≠ plugin realm ≠ final artefact identity. Scan build tooling where its package identity still exists; the shipped JAR cannot give it back.

---

## T07 — npm audit: metadata versus bytes (S05)

Question: when prepack generates the shipped code and the generator disappears, what can `npm audit` still see?
Needs: Node 20+, npm, `tar`. Network for the registry advisory endpoint and the lodash control.

```command
cd investigations/T07-npm-audit-s05
```

Clean and build S05, then capture source files, pack log, tarball listing, the unpacked tarball, installed files and the evidence JSON. Writes results/s05/baseline/.
```command
./scripts/baseline-s05.sh
```
```output
npm notice run trace-route-package@1.0.0 prepack
generated dist/index.js for /hidden/prepack-info
package/dist/index.js
package/package.json
package/dist/prepack-evidence.json          (no scripts/generate-dist.js, no build-input/)
```

Eight audits: application, --package-lock-only, source pkg with/without lockfile, published pkg with/without lockfile, provenance-string grep, public lodash control. Writes results/s05/npm-audit/<probe>/.
```command
./scripts/run-npm-audit-s05.sh
```
```output
application                     dependencyTotal=1  vulnerabilityRecords=0  exit=0
application-lock-only           dependencyTotal=1  vulnerabilityRecords=0  exit=0
source-package                  npm error code ENOLOCK  (This command requires an existing lockfile.)
source-package-no-lock          dependencyTotal=0  vulnerabilityRecords=0
published-package               npm error code ENOLOCK
published-package-no-lock       dependencyTotal=0  vulnerabilityRecords=0

scripts/generate-dist.js     not found
npm-prepack-generated        not found
prepack-evidence.json        not found
/hidden/prepack-info         not found

public-vulnerable-control       lodash  severity: high  direct  range: <=4.17.23   vulnerabilityRecords=1
```
The lodash control proves the advisory path works, so the clean S05 results are real.

Print ground truth beside each probe's exit and summary, FOUND / not found per provenance string, and eight questions.
```command
./scripts/compare-s05.sh
```

Assert 33 claims: prepack ran, tarball contents, each probe's exit and counts, lodash record, no provenance string in any output.
```command
./scripts/proof-check.sh
```
```output
T07 npm audit proof check
========================
PASS  npm prepack executed
PASS  published tarball excludes generator implementation
PASS  lodash control returns one vulnerability record
PASS  npm audit output omits provenance string: /hidden/prepack-info
...
Passed: 33
Failed: 0
```

Takeaway: `npm audit` is vulnerability analysis over dependency metadata. Source and published packages look identical to it, and a clean result says nothing about how the shipped bytes were produced.

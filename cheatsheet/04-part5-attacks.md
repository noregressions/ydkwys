---
id: cheatsheet-part5
oneliner: "Part 5 in run order: GuardDog against the S05/S03 packages and their malicious variants, then reverse provenance on S01."
track: reference
---

# Part 5 — Someone Is Counting on That

---

## T08 — GuardDog: reading code, not metadata (S05, S03, malicious variants)

**Proving:** What a code-reading scanner recovers, and the boundary it still cannot cross: what packaging chose to include.

Question: when a scanner reads the code, does a clean result mean safe, or only that nothing detectable was in the bytes it was handed?
Needs: `pipx install guarddog` (3.2.0, Python 3.11), `tar`. Every command passes `--no-sandbox`; that lowers isolation, not detection. S05 and S03 built. No Java ecosystem, so S04 is out of scope.

```command
cd investigations/T08-guarddog
```

Calibration: write a deliberately malicious npm package (never installed) and scan it, so a later 0.0 means "nothing matched", not "nothing ran". Writes results/control/.
```command
./scripts/positive-control.sh
```
```output
execution-risk: found 1 indicator
│ * threat.process.spawn
│   Detects download-and-execute patterns: fetching a remote file then executing it
│   at index.js:3
Assessment:  High risk  (8.2/10)
```

Scan the S05 published tarball. The prepack generator was excluded by files:["dist"], so there is no mechanism to judge. Writes results/s05/.
```command
./scripts/scan-s05.sh
```
```output
package/dist/index.js
package/package.json
package/dist/prepack-evidence.json

No risks found in trace-route-package-1.0.0.tgz
Assessment:  No risks detected  (0.0/10)
```

Scan the S03 sdist. The PEP 517 backend does ship and is benign; every rule ran and returned empty. Writes results/s03/ including scan.json.
```command
./scripts/scan-s03.sh
```
```output
tracehook_demo-1.0.0/pyproject.toml
tracehook_demo-1.0.0/tracehook_backend.py

No risks found in tracehook_demo-1.0.0.tar.gz
Assessment:  No risks detected  (0.0/10)
```

Build both malicious S05 variants (payload aimed at an unresolvable .invalid host), then scan A's tarball, A's source, and B's tarball. Writes results/malicious/.
```command
./scripts/scan-malicious.sh
```
```output
== Case A — published tarball (payload was in the un-shipped generator) ==
No risks found in CASE-A-generator-payload.tgz
Assessment:  No risks detected  (0.0/10)

== Case A — SOURCE (the generator is present here) ==
│ * threat.process.spawn   at scripts/generate-dist.js:9
Assessment:  High risk  (8.2/10)

== Case B — published tarball (payload rode into the shipped dist) ==
│ * threat.process.spawn   at package/dist/index.js:4
Assessment:  High risk  (8.2/10)
```
Payload in the generator hits the publisher and the tarball scan misses it. Payload in the generated output hits the consumer and the tarball scan catches it.

Assert ten claims against results/: the two clean scans, tarball contents, control fired, A-tarball clean, A-source and B-tarball caught.
```command
./scripts/proof-check.sh
```
```output
T08 GuardDog proof check
========================
PASS  S05 published tarball scans clean
PASS  S05 tarball excludes the generator itself
PASS  S03 sdist DOES carry the executable build backend
PASS  positive control is flagged High risk
PASS  case A published tarball is clean (generator payload not shipped)
PASS  case A source is caught (generator present)
PASS  case B published tarball is caught (payload rode into shipped dist)
...
Passed: 10
Failed: 0
```

Takeaway: reading code beats reading metadata, and a clean score still is not a safety proof. "No risk detected" covers absent evidence, benign evidence, and an attack in the half you did not scan. Only the artefact contents tell you which.

---

## S07 — Reverse provenance on S01: from anonymous image to signed attestation

**Proving:** From a finished image to a verifiable origin, one layer at a time. Only layer 4 survives an adversary.

Reuses S01's source in a throwaway copy under `work/s01`. Does not modify S01.
Needs: Docker, Maven, Java 21, `syft`, `cosign`, `curl`. Starts a local `registry:2` on port 5000 if none is running.

```command
cd scenarios/S07-provenance-s01
```

Copy S01, build it exactly as shipped, then try to trace the image back to a commit and fail.
```command
./scripts/build-baseline.sh
```
```output
-- Which commit produced this? (git.properties in the JAR) --
   MISSING — the JAR names no commit
-- Which repo/commit built this image? (OCI labels) --
   {"org.opencontainers.image.version":"22.04"}
-- What is inside? (an SBOM travelling with the image) --
   NONE
-- Can we prove the image is what we think? (a signature) --
   NONE — only a mutable tag names it
```
The only label is inherited from the Ubuntu base image.

Rebuild with four provenance layers: git.properties, OCI labels, digest-keyed SBOM, cosign signature + attestation.
```command
./scripts/add-provenance.sh
```
Four layers, printed in sequence. Commit ids, times and digests will differ.

Layer 1, `git.properties` recovered from the JAR (git-commit-id-maven-plugin):
```text
git.branch=master
git.commit.id.abbrev=<abbrev>
git.remote.origin.url=https://github.com/herodevs/kcdc2026workshop.git
```

Layer 2, OCI labels from `docker image inspect` (Dockerfile LABELs from build args):
```json
{
    "org.opencontainers.image.revision": "<full sha>",
    "org.opencontainers.image.source": "https://github.com/herodevs/kcdc2026workshop.git",
    "org.opencontainers.image.version": "1.0.0"
}
```

Layer 3, image pushed to the local registry to obtain a digest, then Syft SBOM of that digest:
```text
Image digest: sha256:<digest>
SBOM components: ~5040
```

Layer 4, `cosign sign` and `cosign attest` on the digest, then verified with the public key only:
```text
  - The cosign claims were validated
  - The signatures were verified against the specified public key

signature:   VERIFIED
attestation: VERIFIED (the SBOM travels bound to the digest)
```

Outputs in `results/`: `image-digest.txt`, `checkout-service.cdx.json`, `cosign.key`, `cosign.pub`. Committed examples in `evidence/`.

Assert the baseline has no provenance and the provenance image has all four layers, signature included.
```command
./scripts/proof-check.sh
```
```output
PASS  baseline image has NO revision label
PASS  JAR carries git.properties with a commit id
PASS  prov image has a revision label
PASS  prov image has a source label
PASS  SBOM lists the jackson-databind tracked component
PASS  image signature verifies
PASS  SBOM attestation verifies

Passed: 7
Failed: 0
```

No clean script. work/ and results/ are gitignored and rebuilt each run. Remove the local registry:
```command
docker rm -f s07-registry
```

Layers 1 to 3 are claims. Layer 4 is the first one an outsider can verify.

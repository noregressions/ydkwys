---
id: t02-docker-scout
oneliner: "Treats the finished container as the evidence source, and asks what the shipped image can still explain about its own contents."
track: reference
---

# T02 — Docker Scout: What Does the Final Container Know?

## The question

Use Docker Scout as a final-container evidence source for the workshop scenarios that produce container images.

Coverage:

```text
S01  Spring + Node
S02  Payara + mvnpm
```

The investigation asks:

> Once dependency resolution, plugin execution, shading, bundling, packaging and container assembly are complete, what software identity can Docker Scout recover from the final image, and what history has already been lost?

## The instrument

The tested Scout views are:

```text
docker scout quickview
docker scout sbom --format list
docker scout cves
docker scout recommendations
```

All scans use:

```text
local://IMAGE
```

so Scout analyses the exact locally built scenario image.

Syft scans the same images as a second witness, so scanner-to-scanner
disagreement at the same boundary is part of the evidence.

---

# Probe 1 — S01 final image (Spring + Node)

## Ground truth

Important component states:

```text
jackson-databind 2.19.4
    ordinary Maven dependency
    shipped as intact nested JAR

commons-codec 1.18.0
    service-selected Maven dependency
    shipped as intact nested JAR

commons-codec 1.17.1
    dependency of normalizer
    shaded and relocated
    Maven package identity metadata survives

normalizer 1.0.0
    custom application library

lodash 4.17.21
    npm dependency
    bundled by Vite into browser JavaScript
    npm package boundary disappears
```

## Question

Which of these tracked identities can Docker Scout recover from the finished
`checkout-service` image, and what evidence does it add beyond the package
inventory?

## Expectation

Ground truth: the four Java tracked components ship inside the image with their Maven
identity evidence intact — including the shaded codec 1.17.1, whose package
metadata survives relocation. A final-image scan should therefore recover all
four. lodash's npm package boundary was destroyed by Vite before the image was
assembled, and nothing at the container boundary re-creates that evidence, so
lodash should stay invisible. The image should also expose a deployed software
universe — base image, JRE, OS packages — that no application-level dependency
model describes.

## Run

```command
./scripts/baseline-s01.sh
./scripts/run-scout-s01.sh
./scripts/compare-s01.sh
```

## Observed

The rebuilt image was:

```output
registry.example.com/checkout-service:release-123
sha256:7d3b4c23011efff02feddce24a181f921f5d9a46fb9b8a72c940d316fe7dae3c
```

The Docker build exported an attestation manifest.

Syft, scanning the same final image, catalogued:

```text
179 packages
837 executables
```

and identified:

```text
commons-codec      1.17.1
commons-codec      1.18.0
jackson-databind   2.19.4
normalizer         1.0.0
```

Docker Scout reported:

```text
237 packages indexed
base image: eclipse-temurin:21-jre-jammy
provenance obtained from attestation
policy: FAILED (3/7)
health score: D (44%)
```

Scout identified the same four Java tracked components:

```text
commons-codec      1.17.1
commons-codec      1.18.0
jackson-databind   2.19.4
normalizer         1.0.0
```

Scout did not identify:

```text
lodash 4.17.21
```

The tracked CVE view reported five vulnerabilities, all on:

```text
jackson-databind 2.19.4
    2 HIGH
    3 MEDIUM
```

Scout's provenance view linked the image to:

```text
https://github.com/noregressions/kcdc2026workshop.git
commit c8c745d5a7d4e8b83813965de87b7ac167d75db9
```

The base-image recommendation view said the current:

```text
eclipse-temurin:21-jre-jammy
```

was up to date. It also suggested Java 25 and Java 26 tags as alternative major-runtime upgrades, each with one fewer vulnerability in the base-image comparison.

## Verdict

**Four Java tracked components: identified. lodash 4.17.21: identity lost** — both as
expected.

```text
Maven/npm model             → application dependency identity before transformation
Syft final image            → 179 packages
Docker Scout final image    → 237 packages
```

Both final-image scanners recover the two codec versions, Jackson and normalizer.

Neither recovers lodash after Vite bundling destroys the npm package boundary.

Moving the scanner later expands the deployed software universe, but does not guarantee recovery of identities destroyed earlier.

---

# Probe 2 — S02 final image (Payara + mvnpm)

## Ground truth

Important component states:

```text
commons-lang3 3.18.0
    ordinary application dependency
    shipped intact in WAR

Jakarta EE Web API 11.0.0
    Maven provided dependency
    present in application model
    absent from WAR

lodash-es 4.17.21
    Maven plugin dependency
    present in esbuild ClassRealm
    source-map evidence proves code entered browser bundle
    package identity lost after bundling

Payara server
    supplies its own Jakarta/API/runtime package universe
```

## Question

Which of these tracked identities can Docker Scout recover from the finished
Payara image — and when a package family reappears at this boundary, whose
software is it?

## Expectation

Ground truth: commons-lang3 ships intact in the WAR, so it should be
identified. The Jakarta EE Web API is a `provided` dependency — absent from
the WAR — but Payara supplies its own Jakarta universe, so Jakarta-named
packages should *reappear* at this boundary for a reason unrelated to the
application's build. lodash-es lost its npm package identity at bundling, so
it should stay invisible. The Payara server should also inflate the package
inventory well beyond S01's.

## Run

```command
./scripts/baseline-s02.sh
./scripts/run-scout-s02.sh
./scripts/compare-s02.sh
```

## Observed

The rebuilt image was:

```output
payara-mvnpm-trace-lab:local
sha256:9ad9bb4ab46971e6639855c48b7769864c437cf43ab7e786595613895f40a98c
```

The Docker build exported an attestation manifest.

Syft catalogued:

```text
589 packages
825 executables
```

It identified:

```text
commons-lang3 3.18.0
payara-mvnpm-trace-lab 1.0.0
many Jakarta API packages supplied by Payara
```

It did not identify:

```text
lodash-es 4.17.21
```

Docker Scout reported:

```text
655 packages indexed
base image: payara/server-web:7.2026.7
provenance obtained from attestation
policy: FAILED (3/7)
health score: D (44%)
```

Scout identified:

```text
commons-lang3 3.18.0
many Jakarta APIs
many Payara/GlassFish modules
payara-mvnpm-trace-lab 1.0.0
```

Scout did not identify:

```text
lodash-es 4.17.21
```

The filtered CVE probe used package-name patterns for:

```text
commons-lang3
lodash-es
payara
jakarta
```

Those patterns matched a large set of Payara/Jakarta-named packages. Scout reported:

```text
No vulnerable packages detected
```

for that filtered set.

Scout's provenance view linked the image to:

```text
https://github.com/noregressions/kcdc2026workshop.git
commit c8c745d5a7d4e8b83813965de87b7ac167d75db9
```

Scout reported:

```text
No recommendations
```

for the `payara/server-web:7.2026.7` base image.

## Verdict

**commons-lang3 3.18.0: identified. Jakarta APIs: present again — but as
Payara's packages, not the WAR's. lodash-es 4.17.21: identity lost** — all as
expected.

The Jakarta APIs demonstrate an important boundary change:

```text
Maven application model
    → Jakarta APIs present as provided dependencies

WAR
    → Jakarta APIs absent

Payara container image
    → Jakarta APIs present again
       because the server supplies them
```

The container scan proves that Jakarta software is deployed with the application.

It does **not** prove that the application's Maven-provided Jakarta artefacts were packaged in the WAR.

For lodash-es:

```text
Maven plugin ClassRealm    → YES
source map                 → YES, code contributed
WAR package identity       → NO
Syft final image           → NO
Docker Scout final image   → NO
```

Once esbuild bundled the code, neither final-image scanner reconstructed the npm identity.

---

# Scorecard

What the final-image scans established, tracked component by tracked component — `seen` means the
package identity was recovered from the image; `—` means it was not. Every `—`
in this table is code that shipped in the image anyway.

| Tracked component | Scenario | Docker Scout (final image) |
| --- | --- | --- |
| jackson-databind 2.19.4 | S01 | seen |
| commons-codec 1.18.0 | S01 | seen |
| commons-codec 1.17.1 (shaded) | S01 | seen |
| normalizer 1.0.0 | S01 | seen |
| lodash 4.17.21 | S01 | — |
| commons-lang3 3.18.0 | S02 | seen |
| Jakarta EE Web API 11.0.0 | S02 | seen — as Payara-supplied Jakarta packages, not the WAR's |
| payara-mvnpm-trace-lab 1.0.0 | S02 | seen |
| lodash-es 4.17.21 | S02 | — |

The two scanners' views of the same images also differ:

| Observation | S01 | S02 |
| --- | ---: | ---: |
| Syft final-image packages | 179 | 589 |
| Docker Scout packages | 237 | 655 |
| Scout provenance attestation | yes | yes |
| Scout base image | `eclipse-temurin:21-jre-jammy` | `payara/server-web:7.2026.7` |
| Ordinary app dependency recovered | yes | yes |
| Shaded Java dependency recovered | yes | n/a |
| Bundled npm identity recovered | no | no |
| Runtime/base-image universe exposed | yes | yes |
| Scout recommendations | Java 25/26 alternatives | none |

The package counts differ between Syft and Scout even when both observe the same image.

Therefore:

```text
same artefact boundary
    !=
same software inventory
```

Scanner implementation, cataloguers and package-identification rules still matter.

---

# Findings

## 1. A container image is a different evidence boundary from the application package

The final container includes:

```text
application software
runtime/server software
JDK/JRE software
OS packages
```

An application POM, npm lockfile, WAR or executable JAR does not describe that complete deployed universe.

## 2. Moving later in the supply chain can add software

S02 shows this directly:

```text
Jakarta provided dependency
    present in Maven model
    absent from WAR
    present again in final deployment through Payara
```

The same package family can disappear at one boundary and reappear at another for a different reason.

## 3. Moving later does not necessarily recover lost identity

Both scenarios contain npm code that loses package identity during bundling:

```text
S01  lodash
S02  lodash-es
```

Neither Syft nor Docker Scout reconstructed those npm package identities from the final container.

## 4. Different scanners can disagree at the same boundary

Observed package counts:

```text
S01
    Syft         179
    Docker Scout 237

S02
    Syft         589
    Docker Scout 655
```

The final image is the same, but the inventory is not.

## 5. Docker Scout adds evidence beyond package inventory

Observed Scout evidence includes:

```text
base-image identification
vulnerability intelligence
policy evaluation
health score
base-image recommendations
build provenance attestation
repository and source commit
```

These are useful deployed-image facts, but they do not reconstruct every earlier build transformation.

## 6. Provenance and package discovery are separate evidence channels

Scout obtained provenance attestations linking both images to the repository and commit.

That provenance existed separately from ordinary image labels and separately from Scout's package catalogue.

A provenance claim about where an image was built does not itself imply complete knowledge of every dependency or transformation used during the build.

---

# Final verdict

Docker Scout is valuable precisely because it observes a boundary the source dependency tools do not:

```text
the final deployed container
```

That gives it visibility into the runtime, server, JDK and OS software universe and allows it to attach vulnerability, policy, recommendation and provenance information.

But T02 also confirms two limits:

```text
a later scan cannot be assumed to recover identity destroyed earlier

and

two scanners looking at the same final image need not produce the same inventory
```

The practical rule is:

> Choose the evidence source for the question you are asking. A container scanner tells you about the deployed container; it does not replace dependency, build-time, transformation or publication evidence collected earlier in the supply chain.

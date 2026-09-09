---
id: t04-grype-s02
oneliner: "Separates how Grype constructs a software inventory from how it matches vulnerabilities against that inventory."
track: reference
---

# T04 — Grype / S02

## The question

Use Grype against S02 to separate:

```text
software inventory construction
```

from:

```text
vulnerability matching
```

The central question is:

> Does Grype produce a different vulnerability answer when it discovers the Payara image itself versus when it consumes an SBOM generated from that same image?

## The instrument

The observed run used:

```text
Grype 0.115.0
Syft 1.46.0
Grype DB schema 6.1.9
Grype DB built 2026-08-22T06:14:16Z
DB status: valid
```

Every run used the same final image and the same Grype vulnerability database.

The database state is itself part of the instrument. The first attempted run
failed because the local Grype database was too old:

```text
Status: invalid
the vulnerability database was built 2 weeks ago
(max allowed age is 5 days)
```

After refreshing the database, the successful run reported:

```text
Schema: v6.1.9
Built: 2026-08-22T06:14:16Z
Status: valid
```

Vulnerability database state is part of the evidence: a stale or invalid
database can prevent the vulnerability experiment from running at all.

---

# Ground truth

Every expectation below is derived from this section: what S02 actually
contains, established independently of the tool under investigation.

## Fixture

S02 has three deliberately different kinds of software evidence.

### Application dependencies

The Maven application model contains:

```text
jakarta.platform:jakarta.jakartaee-web-api:11.0.0   provided
org.apache.commons:commons-lang3:3.18.0             compile
```

### Maven plugin dependencies

The `esbuild-maven-plugin` runs during `generate-resources`.

Its Maven plugin realm contains:

```text
io.mvnpm:esbuild-maven-plugin:2.0.0
org.mvnpm:lodash-es:4.17.21
```

The plugin realm also contains its own larger transitive toolchain, including:

```text
commons-codec 1.19.0
commons-lang3 3.18.0
jackson-databind 2.20.1
jackson-core 2.20.1
```

### WAR contents

The built WAR contains:

```text
WEB-INF/lib/commons-lang3-3.18.0.jar
assets/app.js
assets/app.js.map
```

It does not physically package the provided Jakarta EE API dependency.

It does not contain a `lodash-es` package boundary.

## Run

```command
./scripts/baseline-s02.sh
```

## Observed

The final image is:

```output
payara-mvnpm-trace-lab:local
```

Observed image digest:

```text
sha256:9deab630f88089a2254668ed55569a73f0317a0d1d226832ed1134436a48aeaa
```

Syft catalogued:

```text
589 packages
825 executables
5,424 locations
```

The Syft image inventory identifies:

```text
commons-lang3 3.18.0
payara-mvnpm-trace-lab 1.0.0
many Jakarta API/runtime components supplied by Payara
```

It does not identify:

```text
lodash-es 4.17.21
```

The generated CycloneDX document contained:

```text
6014 components
```

This number is not treated as equivalent to the Syft package count. The CycloneDX document represents more than the 589-package catalogue.

## What this pins down

S02 separates four boundaries:

```text
application dependency model
Maven plugin realm
WAR contents
final deployed container
```

They contain different software universes. The probes below test what Grype's
vulnerability answer looks like over the last of them — and whether the *way*
that boundary is represented to Grype changes the answer.

---

# Running the probes

The probes are driven by one harness script:

```command
./scripts/run-grype-s02.sh
```

Grype was run three ways:

```text
1. docker:payara-mvnpm-trace-lab:local

2. sbom:results/s02/baseline/image.syft.json

3. sbom:results/s02/baseline/image.cdx.json
```

The experiment also used two direct PURL controls:

```text
pkg:maven/org.apache.commons/commons-lang3@3.18.0
pkg:maven/org.mvnpm/lodash-es@4.17.21
```

---

# Probe 1 — direct image scan

## Question

What does Grype report when it discovers the final image itself?

## Expectation

Ground truth: the image is the application WAR deployed onto a Payara runtime
over an Ubuntu base — Syft catalogued 589 packages, most of them runtime and
OS software the application never declared. The vulnerability answer should
therefore be dominated by runtime and OS packages, not by the tracked components; and
`lodash-es` cannot be matched at all, because its identity is absent from the
image inventory.

## Observed

Grype reported:

```output
169 unique vulnerability matches
```

The findings include both operating-system and Java-runtime packages.

Examples from the final image include:

```text
nimbus-jose-jwt 10.0.1
    GHSA-xwmg-2g98-w7v9
    Medium
    fixed in 10.0.2

jline-remote-telnet 3.30.15
    GHSA-2r2c-cx56-8933
    High
    fixed in 4.2.1

jline-remote-telnet 3.30.15
    GHSA-47qp-hqvx-6r3f
    High
    fixed in 4.2.1

jackson-core 2.15.2
    GHSA-r7wm-3cxj-wff9
    High
    fixed in 2.18.8

jackson-core 2.15.2
    GHSA-72hv-8253-57qq
    Medium
    fixed in 2.18.6
```

There were also many Ubuntu package findings.

No vulnerability match against the tracked components was reported for:

```text
commons-lang3
lodash-es
Payara-named tracked-component pattern
Jakarta-named tracked-component pattern
```

## Verdict

**Runtime and OS packages dominate; no tracked match**, as expected. The
deployed runtime/base-image software universe, not merely the application WAR,
dominates the final-image vulnerability answer.

The harness did not expose a direct Grype package-catalogue count, so this investigation does not claim one.

---

# Probe 2 — Syft JSON input

## Question

Does Grype produce the same answer when it consumes a Syft JSON SBOM instead
of discovering the image itself?

## Expectation

Ground truth: the Syft JSON was generated from the same image, by the same
Syft, describing the same 589-package catalogue. If Grype's own discovery and
Syft's catalogue see the same package universe, the match set should be
identical to Probe 1's.

## Observed

Grype emitted:

```output
document has schema version 16.1.10,
but parser has older schema version 16.1.5
```

Despite that compatibility warning, Grype again produced:

```text
169 unique vulnerability matches
```

## Verdict

**Same match count**, as expected — despite a schema-version warning the
expectation had no way to predict. For this image and these tool versions, the
Syft schema-version warning did not change the resulting vulnerability match
set.

---

# Probe 3 — CycloneDX input

## Question

Does a different SBOM *format* — with a very different raw component count —
change the vulnerability answer?

## Expectation

Ground truth: the CycloneDX document was generated from the same image but
contains 6014 components against the Syft JSON's 589 package artifacts. If
those extra components are representation detail rather than additional
matchable package identities, the match set should again be unchanged; if
Grype matches against them, the answer should grow.

## Observed

Grype consumed the CycloneDX SBOM generated from the same image and again produced:

```output
169 unique vulnerability matches
```

## Verdict

**Same match count**, as expected. The CycloneDX document contains 6014
components rather than the Syft JSON's 589 package artifacts; in this run,
that difference did not produce a different vulnerability answer. Those raw
document counts should therefore not be interpreted as equivalent package
counts.

---

# Probe 4 — exact match-set comparison

## Question

The counts agree — but are the three match *sets* actually identical?

## Expectation

Probes 1–3 each produced 169 matches. Equal counts can still hide differing
contents; if the three representations genuinely describe the same matchable
inventory, a set comparison should show no differences in any direction.

## Run

```command
./scripts/compare-s02.sh
```

## Observed

The final comparison showed:

```output
direct image     169 unique vulnerability matches
Syft JSON        169 unique vulnerability matches
CycloneDX        169 unique vulnerability matches
```

and:

```text
direct image vs Syft JSON
    no differences

direct image vs CycloneDX
    no differences

Syft JSON vs CycloneDX
    no differences
```

## Verdict

**Identical match sets**, as expected. For this S02 image:

```text
Grype direct discovery
        =
Grype over Syft JSON
        =
Grype over CycloneDX
```

with respect to the vulnerability match set.

The inventory representation did not change Grype's vulnerability answer.

---

# Probe 5 — commons-lang3 control

## Question

commons-lang3 produced no vulnerability match anywhere — is that because the
scanner lost its identity, or because there is genuinely no match to find?

## Expectation

Ground truth: `commons-lang3 3.18.0` is in the final image inventory, so its
identity survived. A direct PURL control removes discovery from the experiment
entirely: it asks the vulnerability database about the exact package identity.
If the database has no entry for that version, the control should also come
back empty — proving the silent scans were a database fact, not an identity
loss.

## Observed

The final image inventory contains:

```output
commons-lang3 3.18.0
```

The direct PURL control produced:

```text
no vulnerability matches
```

The image/SBOM scans likewise produced no vulnerability match against the tracked components for commons-lang3.

## Verdict

**commons-lang3 3.18.0: identified; no match exists.** Grype identifies the
package in the final image inventory, so the inventory is doing its job: the
observed Grype vulnerability database simply produced no match for that
package/version.

---

# Probe 6 — lodash-es control

## Question

lodash-es demonstrably participated in the build — can any final-image scan,
or even a direct database query, say anything about it?

## Expectation

Ground truth: `org.mvnpm:lodash-es:4.17.21` is proven in the
`esbuild-maven-plugin` ClassRealm, but the WAR carries only the generated
bundle — no package boundary — and the image inventory does not identify it.
The scans therefore cannot match it. The PURL control then asks the remaining
question: does the database even hold a match for this identity, i.e. could a
"scanner knows the vulnerability but discovery lost the package" story be told
here at all?

## Observed

Maven plugin evidence proves:

```output
org.mvnpm:lodash-es:4.17.21
```

was included in the `esbuild-maven-plugin` ClassRealm during the build.

The final WAR contains the generated browser bundle, but no `lodash-es` package boundary.

The final image Syft inventory does not identify lodash-es.

The direct PURL control also produced:

```text
no vulnerability matches
```

## Verdict

**lodash-es 4.17.21: identity lost before the image — and no database match
either.** For this run, lodash-es cannot demonstrate:

```text
Grype knows the vulnerability
but package discovery loses the package
```

because the direct PURL control produced no vulnerability match.

What it does demonstrate is:

```text
build participation
    !=
final-image package identity
```

Grype cannot vulnerability-match a final-image package identity that is not present in the supplied inventory.

---

# Probe 7 — provided dependencies and runtime supply

## Question

Where does the Jakarta software in the final image actually come from?

## Expectation

Ground truth: the application declares `jakarta.jakartaee-web-api 11.0.0` at
`provided` scope, and the WAR does not package it. Yet the image is a Payara
runtime, which ships its own Jakarta implementation. The scan should therefore
show Jakarta components that never passed through the application's dependency
graph at all.

## Observed

The application Maven model declares:

```output
jakarta.jakartaee-web-api 11.0.0
    scope: provided
```

The WAR does not package that API dependency.

The final image nevertheless contains many Jakarta components, including:

```text
jakarta.servlet-api 6.1.0
jakarta.ws.rs-api 4.0.0
jakarta.persistence-api 3.2.0
jakarta.validation-api 3.1.1
...
```

Those components are supplied by the Payara runtime image.

## Verdict

**Jakarta components: present, but supplied by the runtime**, as expected. The
container vulnerability scan answers:

```text
what software is deployed together?
```

It does not tell us that all software found in the image came from the application dependency graph or WAR.

---

# Scorecard

What survived into the final-image inventory, tracked component by tracked component — `seen` means
the package identity was established there; `—` means it was not. No tracked component
produced a vulnerability match in any of the three Grype runs: for
commons-lang3 because the database holds no match for that version (Probe 5),
for lodash-es because its identity never reached the image (Probe 6), and for
the Jakarta tracked component because the WAR never packaged it — the image's Jakarta
software is the runtime's own (Probe 7).

| Tracked component | final-image inventory | vulnerability match |
| --- | --- | --- |
| commons-lang3 3.18.0 | seen | — |
| lodash-es 4.17.21 | — | — |
| jakarta.jakartaee-web-api 11.0.0 (provided) | — | — |
| payara-mvnpm-trace-lab 1.0.0 | seen | — |

And across the three inventory representations of that same boundary, the
answer did not move:

```text
direct image     169 unique vulnerability matches
Syft JSON        169 unique vulnerability matches
CycloneDX        169 unique vulnerability matches
```

---

# Findings

## 1. Grype can consume different inventory representations without changing the answer

In this experiment:

```text
direct image
Syft JSON
CycloneDX
```

all produced exactly:

```text
169 unique vulnerability matches
```

with no match-set differences.

This means the SBOM representation was not the source of vulnerability-answer variation here.

## 2. Inventory still determines what can be vulnerability-matched

The equality of the three Grype results does not mean the inventory is complete.

All three views ultimately describe the same final-image software boundary.

They all omit `lodash-es` identity after its build-time contribution has been bundled away.

## 3. A container vulnerability scan includes software the application did not package

The application WAR contains commons-lang3 and generated browser assets.

The final container also contains:

```text
Ubuntu OS packages
Payara/GlassFish runtime libraries
Jakarta APIs
server-side Jackson
JLine
Nimbus JOSE JWT
...
```

Those packages materially change the deployed vulnerability surface.

## 4. Build-time software can disappear before final-image vulnerability scanning

`lodash-es 4.17.21` is proven in the Maven plugin realm.

Its package identity does not survive into the WAR or final image inventory.

Therefore:

```text
software participated in producing the artefact
```

does not imply:

```text
final-image vulnerability scanner can identify that software
```

## 5. The vulnerability database is itself part of the result

The initial run could not proceed because the DB was invalid due to age.

After updating it, the scan succeeded.

A CVE scan therefore depends on at least:

```text
inventory evidence
package identity
version identity
vulnerability database content
database freshness/validity
matching rules
```

---

# Final verdict

T04 demonstrates that changing the *representation* of a good final-image inventory does not necessarily change the vulnerability answer.

For this image:

```text
direct image discovery
        =
Syft JSON
        =
CycloneDX
```

at the Grype vulnerability-match layer.

But all three still inherit the same supply-chain limitation:

> They can only vulnerability-match software identities that survived into, or can be reconstructed from, the final-image evidence.

The practical rule is:

> An SBOM-driven CVE scan can be perfectly consistent with a direct image scan and still miss software that disappeared as an identifiable package at an earlier build boundary.

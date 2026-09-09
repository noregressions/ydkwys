---
id: t01-snyk-beyond-sbom
oneliner: "What a commercial SCA tool knows beyond an SBOM, which transformations stay invisible even to it, and a cross-scenario matrix of both."
track: instructor-demo
---

# T01 — Snyk Beyond the SBOM

## The question

> What does a commercial SCA tool know that an ordinary SBOM does not, and which supply-chain transformations remain invisible even to it?

This investigation reuses five completed trace labs:

- S01 — Spring + Node
- S02 — Payara + mvnpm
- S03 — Python + PEP 517
- S04 — Maven plugin hidden-content
- S05 — Node + npm prepack

and compares several evidence types:

- source declarations
- package-manager dependency models
- build-tool execution evidence
- generated artefacts
- SBOMs
- Snyk project scans
- Snyk artefact/unmanaged scans
- runtime evidence

## The instrument

The observed runs used Snyk CLI 1.1305.2, authenticated, exercised in every
mode the labs support:

- project scans against Maven, npm and pip dependency models
- `--include-provenance` enrichment of those scans
- CycloneDX SBOM output
- unmanaged scans of built artefacts (JARs, WARs, tarballs), packed and
  unpacked

The headline result, stated up front:

**better package identity ≠ complete supply-chain history**

Snyk often provides richer identity, vulnerability and dependency-path information than a basic SBOM. But it does not reconstruct every build realm, lifecycle action, code-generation step, bundling transformation, or publication-time mutation after those facts have disappeared from the dependency model. The probes below establish both halves of that sentence, scenario by scenario.

## Running the probes

Each scenario's probes are driven by a baseline/run/compare script triplet,
run from `investigations/T01-snyk-beyond-sbom` with the scenario labs built:

```command
./scripts/baseline.sh && ./scripts/run-snyk.sh && ./scripts/compare.sh          # S04
./scripts/baseline-s01.sh && ./scripts/run-snyk-s01.sh && ./scripts/compare-s01.sh
./scripts/baseline-s02.sh && ./scripts/run-snyk-s02.sh && ./scripts/compare-s02.sh
./scripts/baseline-s03.sh && ./scripts/run-snyk-s03.sh && ./scripts/compare-s03.sh
./scripts/baseline-s05.sh && ./scripts/run-snyk-s05.sh && ./scripts/compare-s05.sh
```

The scripts expect the scenarios at `../../scenarios/`; override with, for
example, `S04_DIR=/path/to/S04-maven-plugin-hidden-content ./scripts/baseline.sh`.
Requirements beyond the scenarios themselves: Maven 3.9+, JDK 21+, an
authenticated Snyk CLI, `jq`, and Syft for the baseline scanner comparisons.
`./scripts/proof-check.sh` reruns the investigation and asserts the observed
evidence boundaries.

---

# S01 — Spring + Node

## Ground truth

The lab contains four component states:

- `jackson-databind 2.19.4`
  - ordinary Maven dependency
  - physically shipped as intact nested JAR
- `commons-codec 1.17.1`
  - dependency of normalizer
  - shaded and relocated into normalizer
  - Maven package metadata survives
- `commons-codec 1.18.0`
  - selected by service dependency management
  - physically shipped as intact nested JAR
- `lodash 4.17.21`
  - npm dependency
  - bundled by Vite into generated browser JavaScript
  - package boundary disappears

Maven resolves:

```text
normalizer
    → commons-codec 1.17.1

service
    → normalizer
        → commons-codec 1.18.0
    → jackson-databind 2.19.4
```

The final Spring Boot JAR physically contains:

```text
BOOT-INF/lib/jackson-databind-2.19.4.jar
BOOT-INF/lib/normalizer-1.0.0.jar
BOOT-INF/lib/commons-codec-1.18.0.jar
```

The normalizer JAR also contains relocated `commons-codec 1.17.1` bytecode.

Syft can identify `commons-codec 1.17.1` inside the shaded normalizer while its Maven metadata survives. Removing only:

```text
META-INF/maven/commons-codec/commons-codec/
```

makes that identity disappear from Syft while leaving the relocated bytecode unchanged.

## Probe — Maven project scan

### Question

Does Snyk's Maven project view know both codec versions, in their module
contexts?

### Expectation

Ground truth: the reactor resolves codec 1.17.1 for normalizer and codec
1.18.0 for the service. A scan that reads the Maven reactor model should
reproduce both — but reading the model proves nothing about what physically
ships.

### Observed

Snyk's Maven aggregate view identifies both codec versions in their respective module contexts:

```output
normalizer
    → commons-codec 1.17.1

service
    → normalizer
        → commons-codec 1.18.0
    → jackson-databind 2.19.4
```

### Verdict

**Both codec versions: identified**, as expected, from the Maven reactor
model. This does **not** prove that Snyk independently reconstructed the
physical fact that both versions' code ship in the final application — the
model was the evidence, not the artefact.

## Probe — provenance enrichment

### Question

Does `--include-provenance` broaden what Snyk knows, or only strengthen it?

### Expectation

Ground truth still holds two facts outside the dependency model — the shaded
codec bytecode and the bundled lodash. If provenance mode reconstructs
history, new components should appear; if it only enriches, the component set
should be unchanged with stronger identities.

### Observed

`--include-provenance` preserves the same component set.

For external Maven artefacts it adds checksum-qualified PURLs such as:

```output
pkg:maven/commons-codec/commons-codec@1.17.1?checksum=sha1:...
pkg:maven/commons-codec/commons-codec@1.18.0?checksum=sha1:...
pkg:maven/com.fasterxml.jackson.core/jackson-databind@2.19.4?checksum=sha1:...
```

The root reactor POM gains:

```text
?type=pom
```

### Verdict

**Component set: unchanged. Identities: strengthened.**

> Snyk provenance strengthens the identity of software already present in its dependency model. It does not broaden the dependency model.

## Probe — npm project, then the bundled output

### Question

Snyk sees lodash in the npm project. Does any Snyk view still see it after
Vite bundles the frontend?

### Expectation

Ground truth: Vite inlines the lodash code into generated browser JavaScript
and the npm package boundary disappears. The npm project scan should identify
lodash; the bundle should offer Snyk no package boundary to anchor on.

### Observed

From the npm project Snyk identifies:

```output
lodash 4.17.21
```

and reports vulnerability information for it.

After Vite bundling, scanning `frontend/dist` produces:

```text
No supported files found
```

### Verdict

**lodash 4.17.21: identified in the npm project; lost in the bundle.** The
correct interpretation is not *Snyk inspected the bundle and failed to
recognise lodash* but *the deployable bundle no longer presents a supported
npm project boundary*. No tested artefact-oriented Snyk view recovered
`lodash 4.17.21` from the shipped browser bundle.

## Probe — unmanaged JAR scans

### Question

Without a project model, can Snyk recover package identities from the built
artefacts alone?

### Expectation

Ground truth: the shaded normalizer still carries the codec's Maven metadata
— Syft identifies codec 1.17.1 from it — and the Spring Boot JAR nests three
intact library JARs. If Snyk's unmanaged scanning reads the same evidence as
Syft, the shaded codec should be identified while the metadata survives, and
the intact nested JARs should be identified once they are reachable.

### Observed

Direct unmanaged scans of both:

```output
normalizer-1.0.0.jar
normalizer-no-codec-metadata.jar
```

produce an `unknown` custom JAR.

Unlike Syft, Snyk unmanaged scanning did not identify shaded `commons-codec 1.17.1` from the surviving Maven metadata.

Scanning the complete Spring Boot JAR also produced one unknown custom JAR.

After unpacking the Spring Boot JAR, recursive unmanaged scanning identifies intact nested libraries such as:

```text
commons-codec 1.18.0
jackson-databind 2.19.4
```

while the custom shaded normalizer remains unknown.

### Verdict

**Shaded codec 1.17.1: not identified — even with its Maven metadata intact,
where Syft succeeds. Intact nested libraries: identified after unpacking.
Custom JARs: unknown.** Identity recovery from artefacts depends on the
package boundary surviving intact, and different tools read different
evidence from the same bytes.

## What S01 pins down

- known from model + shipped intact
  - recoverable from Maven model
  - recoverable again when intact nested package boundary survives
- known from model + transformed
  - visible before transformation
  - may become unrecoverable afterwards
- known from npm model + bundled
  - visible before bundling
  - package identity can disappear from deployable output

---

# S02 — Payara + mvnpm

## Ground truth

The application has:

- `commons-lang3 3.18.0`
  - ordinary application dependency
  - physically shipped in WEB-INF/lib
- Jakarta EE Web API 11.0.0
  - Maven provided dependency
  - present in application dependency model
  - absent from WAR
- `lodash-es 4.17.21`
  - dependency of esbuild Maven plugin
  - present in actual Maven plugin ClassRealm
  - contributes source modules to generated browser bundle
  - absent from application dependency graph

The generated source map proves `lodash-es` source modules contributed to the browser bundle.

## Probe — Maven project scan

### Question

Does the application-graph scan see software that entered through the Maven
plugin realm?

### Expectation

Ground truth: `lodash-es` lives in the esbuild plugin's ClassRealm, not in
the application dependency graph. A scan that reads the application graph
should report commons-lang3 and the Jakarta provided dependencies — and
should have no path to lodash-es.

### Observed

Snyk's Maven project scan identifies the application dependency graph, including:

- Jakarta provided dependencies
- `commons-lang3 3.18.0`

It does not identify:

```output
lodash-es 4.17.21
```

### Verdict

**commons-lang3: identified. Jakarta provided dependencies: identified.
lodash-es: not identified** — as expected, because that package exists in the
Maven plugin realm rather than the application dependency graph. The plugin
realm is simply not part of the evidence this scan reads.

## Probe — provenance enrichment

### Question

Does provenance mode turn model identity into physical-inclusion evidence?

### Expectation

Ground truth: the Jakarta provided dependencies are in the model but never
ship in the WAR. If provenance enrichment were inclusion proof, they should
be treated differently from the shipped dependencies. If it is identity
enrichment only, everything in the model gets enriched alike.

### Observed

Normal `snyk test` JSON emitted no PURLs.

With `--include-provenance`, Snyk added PURLs for the same Maven dependency set:

```output
root
    → ?type=war

dependencies
    → ?checksum=sha1:...
```

The CycloneDX comparison showed the same component set before and after provenance enrichment.

Critically, Snyk checksum-qualified Jakarta `provided` dependencies even though they never physically ship in the WAR.

### Verdict

**Provenance: identity enrichment of the existing model, applied even to
dependencies that never ship.** Therefore:

**provenance identity ≠ physical inclusion proof**

## Probe — artefact scans

### Question

Can the WAR itself tell Snyk what the model could not?

### Expectation

Ground truth: commons-lang3 ships intact in WEB-INF/lib; the lodash-es
contribution survives only as generated bundle content with no npm boundary.
Expect the intact library to be recoverable once reachable, and the bundled
contribution not to be.

### Observed

Direct unmanaged scan of the whole WAR:

```output
unknown custom WAR
```

After unpacking the WAR, Snyk identifies preserved `commons-lang3 3.18.0`.

It does not reconstruct `lodash-es 4.17.21` from the generated browser bundle.

### Verdict

**commons-lang3: identified after unpacking. lodash-es: not identified at any
boundary.** The artefact restores nothing that the transformation already
removed.

## What S02 pins down

- modelled but not shipped — Jakarta provided APIs
- modelled and shipped intact — commons-lang3
- not modelled by the application but code ships — lodash-es

Snyk's project/provenance model handles the first two well, but the Maven plugin-domain contribution remains invisible.

---

# S03 — Python + PEP 517

## Ground truth

The application declares:

```text
reportkit==1.0.0
```

The `reportkit` wheel metadata declares:

```text
Requires-Dist: tracehook-demo==1.0.0
```

`tracehook-demo` is supplied as an sdist containing:

```text
pyproject.toml
tracehook_backend.py
```

Its PEP 517 configuration declares:

```text
build-backend = "tracehook_backend"
backend-path = ["."]
```

The original sdist does not contain:

```text
tracehook_demo/__init__.py
tracehook_demo/build-hook.json
```

During `pip install`, pip builds a wheel and executes:

```text
tracehook_backend.build_wheel()
```

The generated wheel contains both runtime files.

The installed marker records:

```text
event       = pep517-build-backend-executed
generatedBy = tracehook_backend.build_wheel
```

and the generated content affects runtime behaviour.

## Probe — pip dependency graph

### Question

Can Snyk reconstruct the installed dependency graph, including the transitive
package that arrived as an sdist?

### Expectation

Ground truth: the application declares only `reportkit`, but the installed
environment contains `tracehook-demo` because reportkit's wheel metadata
requires it. A scan anchored on the installed environment should recover the
full edge, going beyond the literal `requirements.txt`.

### Observed

Snyk reconstructs the full installed dependency graph:

```output
S03-python-pep517
    → reportkit 1.0.0
        → tracehook-demo 1.0.0
```

Its CycloneDX SBOM preserves:

```text
application
    → reportkit
        → tracehook-demo
```

### Verdict

**reportkit and tracehook-demo: identified**, including the transitive edge
the source declaration never states. Snyk's graph is genuinely richer than
the literal declaration here.

## Probe — build execution history

### Question

Does anything in the Snyk output represent the PEP 517 backend execution that
manufactured the installed files?

### Expectation

Ground truth: `tracehook_backend.build_wheel()` executed during install and
generated runtime content, and the installed marker records that event. If
Snyk models package identity rather than build execution, none of that should
surface.

### Observed

The actual Snyk outputs contain no evidence for:

```output
tracehook_backend
build_wheel
build-hook.json
pep517-build-backend-executed
```

### Verdict

**PEP 517 execution history: not represented.** Snyk can reconstruct package
dependency identity without reconstructing the executable build history that
produced the installed files.

## Probe — package artefact boundaries

### Question

Which of the physical Python artefacts can Snyk scan as a project on its own?

### Expectation

Ground truth offers three physical artefacts — the unpacked sdist, the
unpacked generated wheel, and the installed site-packages directory. Whether
any of them forms a supported project boundary on its own is exactly what
this probe asks.

### Observed

In the tested modes, Snyk Open Source did not treat any of these as a supported project on their own:

- unpacked tracehook sdist
- unpacked generated wheel
- installed site-packages directory

The successful scan is anchored on the application `requirements.txt` plus the installed Python environment.

### Verdict

**Standalone Python artefacts: not scannable in the tested modes.** The
working evidence boundary is the application manifest plus the installed
environment, not the intermediate artefacts.

## What S03 pins down

**dependency graph knowledge ≠ build execution history**

---

# S04 — Maven plugin hidden-content

## Ground truth

The application has no ordinary third-party runtime dependencies.

During the build:

```text
trace-injector-maven-plugin
    → trace-route-payload
```

exist in the Maven plugin resolution domain and actual plugin ClassRealm.

The plugin generates:

```text
GeneratedTraceRoute.class
META-INF/services/dev.noregressions.trace.s04.TraceRoute
META-INF/trace-lab/plugin-injection.properties
```

The resulting application exposes:

```text
/hidden/build-info
```

even though that route did not exist in checked-in application source.

## Baseline views

What the non-Snyk instruments already said, framing the expectations below:

Maven application dependency tree:

**application only**

Maven CycloneDX:

**0 dependency components**

Syft final-JAR scan:

**application archive only**

## Probe — Maven project scan

### Question

Does Snyk see further into the plugin realm than the baseline views did?

### Expectation

Ground truth: the plugin and its payload exist only in the plugin resolution
domain and ClassRealm. Every baseline view that read the application graph
reported the application only. If Snyk reads the same application graph, it
should report the same.

### Observed

Normal Snyk Maven analysis identifies:

**application only**

It does not identify:

```output
trace-injector-maven-plugin
trace-route-payload
```

### Verdict

**Plugin and payload: not identified** — the application dependency graph is
the evidence read, and they are not in it.

## Probe — provenance enrichment

### Question

Does provenance mode discover what the plain scan could not?

### Expectation

From the S01 and S02 probes: provenance strengthens known identities and does
not broaden the model. Expect the root application identity enriched and
nothing discovered.

### Observed

`--include-provenance` adds a Maven PURL to the known root application artefact.

It does not discover the plugin or payload.

In Snyk's CycloneDX output, provenance produced no substantive component-set change beyond run-specific metadata.

### Verdict

**Root identity: enriched. Plugin and payload: still not identified** —
consistent with provenance being enrichment, not reconstruction.

## Probe — unmanaged JAR scan

### Question

Does the final artefact expose the plugin-generated content to Snyk?

### Expectation

Ground truth: the generated class, service registration and properties file
are in the JAR, but they carry no package identity — they are custom
application bytes. Expect the artefact to be scannable only as an unknown
custom JAR.

### Observed

Snyk reports the final custom JAR as:

```output
unknown
```

### Verdict

**Final JAR: unknown custom artefact.** The scan exposes uncertainty but does
not reconstruct the plugin/payload relationship or build history.

## What S04 pins down

- Maven dependency tree — application only
- Maven plugin resolver — plugin + payload
- Maven plugin ClassRealm — plugin + payload
- Maven CycloneDX — no dependency components
- Snyk Maven — application only
- Snyk + provenance — same known application identity, enriched
- Snyk unmanaged JAR — unknown custom JAR
- runtime — plugin-generated behaviour executes

The build-tool dependency realm is a distinct evidence source.

---

# S05 — Node + npm prepack

## Ground truth

The application depends on:

```text
trace-route-package 1.0.0
```

The package source declares:

```json
{
  "main": "dist/index.js",
  "files": ["dist"],
  "scripts": {
    "prepack": "node scripts/generate-dist.js"
  }
}
```

The source contains:

```text
build-input/route.json
scripts/generate-dist.js
```

The clean build removes any old `dist/`, then `npm pack` records:

```text
trace-route-package@1.0.0 prepack
node scripts/generate-dist.js
generated dist/index.js
generated dist/prepack-evidence.json
```

The resulting tarball contains only:

```text
package.json
dist/index.js
dist/prepack-evidence.json
```

It does **not** contain:

```text
scripts/generate-dist.js
build-input/route.json
```

The installed package preserves the same publication boundary.

Runtime imports the generated `dist/index.js`.

## An awkward publication state

The published `package.json` still declares:

```text
prepack = node scripts/generate-dist.js
```

but the referenced file:

```text
scripts/generate-dist.js
```

is absent from the published package.

Therefore the published package contains a lifecycle declaration but not the executable source that previously satisfied it.

That declaration alone does not prove the lifecycle hook executed; the `npm pack` log provides that proof.

## Probe — npm application scan

### Question

Does Snyk identify the traced package from the application's npm model?

### Expectation

Ground truth: the application depends on `trace-route-package 1.0.0` and the
package boundary (its `package.json`) survives publication and install.
Expect the identity recovered.

### Observed

Snyk identifies:

```output
node-prepack-trace-lab 1.0.0
    → trace-route-package 1.0.0
```

The Snyk CycloneDX SBOM preserves the same relationship.

### Verdict

**trace-route-package 1.0.0: identified**, as expected — the npm package
boundary is intact at every stage of this scenario.

## Probe — package-boundary scans

### Question

Which physical states of the package can Snyk scan on their own?

### Expectation

Ground truth: source, published tarball and installed copy all retain a
`package.json`. If that file is what anchors an npm project scan, all three
should be independently scannable — in contrast to S03's Python artefacts.

### Observed

Snyk can independently scan:

- source trace-route-package
- unpacked published tarball
- installed trace-route-package

because each retains `package.json`.

All scans succeed.

### Verdict

**All three package states: scannable**, as expected. The npm package
boundary is unusually durable evidence — which makes the next probe's absence
all the more instructive.

## Probe — publication history

### Question

Does any Snyk output represent the `prepack` execution that manufactured the
published files?

### Expectation

Ground truth: `prepack` ran during `npm pack`, generated `dist/`, and the
published package even retains the (now-unsatisfiable) lifecycle declaration.
If Snyk's views model package identity rather than publication history, none
of that should surface — even when scanning the source package where the
generator physically exists.

### Observed

The real Snyk outputs contain no evidence for:

```output
scripts/generate-dist.js
npm-prepack-generated
prepack-evidence.json
/hidden/prepack-info
```

Textual matches for `prepack` are only incidental occurrences in project/path names such as:

```text
node-prepack-trace-lab
```

They are not lifecycle-script evidence.

Even when scanning the source package, where the lifecycle declaration and generator physically exist, the Snyk Open Source result does not expose the `prepack` action as supply-chain execution evidence.

### Verdict

**prepack publication history: not represented** at any tested boundary,
including the one where the generator source is physically present.

## What S05 pins down

**npm package identity ≠ npm publication history**

Snyk knows what package is present, but the tested dependency views do not explain how npm manufactured the files that package published.

---

# Scorecard

Tracked component by tracked component, what a tested Snyk view established at each boundary.
`seen` means a tested Snyk view established the identity or fact at that
boundary; `—` means none did; `n/a` marks boundaries where ground truth says
there was nothing to find (not shipped, or no standalone artefact tested).
Every `—` is code that shipped, or an execution that really happened, anyway.

| Scenario | Tracked component / fact | Dependency-model boundary | Artefact boundary |
| --- | --- | --- | --- |
| S01 | jackson-databind 2.19.4 | seen | seen (after unpack) |
| S01 | commons-codec 1.17.1 (shaded) | seen | — |
| S01 | commons-codec 1.18.0 | seen | seen (after unpack) |
| S01 | lodash 4.17.21 (bundled) | seen | — |
| S02 | commons-lang3 3.18.0 | seen | seen (after unpack) |
| S02 | Jakarta provided APIs | seen | n/a — never shipped |
| S02 | lodash-es 4.17.21 (plugin realm) | — | — |
| S03 | reportkit → tracehook-demo | seen | n/a — no standalone artefact scan supported |
| S03 | PEP 517 backend execution | — | — |
| S04 | trace-injector plugin + payload | — | — |
| S05 | trace-route-package 1.0.0 | seen | seen (package.json survives) |
| S05 | prepack publication history | — | — |

The full capability matrix behind those verdicts:

| Evidence / capability | S01 | S02 | S03 | S04 | S05 |
| --- | --- | --- | --- | --- | --- |
| Normal dependency model | Java + npm identities visible before transformation | App Maven deps visible | Python transitive package recovered | Plugin/payload absent | npm package recovered |
| Snyk SBOM | Same project identities | Same app Maven identities | Preserves Python transitive edge | Plugin/payload absent | Preserves npm dependency edge |
| Provenance enrichment | Same Maven set + checksum PURLs | Same Maven set + checksum PURLs | not applicable in tested Python mode | Root identity enriched only | not used |
| Build-time dependency realm | not reconstructed from final artefact | `lodash-es` plugin realm missed | PEP 517 backend execution not represented | plugin + payload missed | lifecycle execution not represented |
| Generated/bundled content lineage | lodash not recovered after bundle | lodash-es not recovered after bundle | generated Python files not tied to backend | generated route not tied to plugin | generated dist not tied to prepack |
| Intact package artefact recovery | nested JARs recoverable after unpack | commons JAR recoverable after unpack | project anchored to manifest + environment | custom JAR unknown | package.json remains enough for npm project scan |
| Transformed custom artefact recovery | shaded normalizer unknown to Snyk unmanaged | n/a | n/a | custom application JAR unknown | n/a |
| Evidence outside Snyk still required | shade metadata / physical JAR / bundling evidence | Maven plugin ClassRealm + source map | pip build log + sdist/backend + generated marker | Maven plugin resolver/ClassRealm | npm pack log + generator + generated evidence |

---

# Findings

## 1. Snyk can know more than a literal source declaration

Examples:

```text
requirements.txt
    reportkit only

Snyk
    reportkit → tracehook-demo
```

and:

```text
npm application
    → trace-route-package
```

Snyk dependency analysis reconstructs dependency relationships rather than merely echoing top-level declarations.

## 2. Snyk can provide materially richer security intelligence than a basic inventory

The investigation observed Snyk adding:

- dependency paths
- vulnerability intelligence
- fix guidance
- PURLs
- checksum-qualified Maven identities in provenance mode

## 3. Provenance enrichment is not provenance reconstruction

For the Maven cases, `--include-provenance` → stronger identities for known Maven artefacts.

It did not discover:

- Maven plugin-realm packages
- code-generation history
- bundling history
- lifecycle execution

Therefore:

**provenance enrichment ≠ supply-chain history reconstruction**

## 4. Package-manager models and shipped artefacts answer different questions

A model may include something not shipped:

*Jakarta provided dependencies*

A shipped artefact may contain something absent from the application model:

*lodash-es code introduced through a Maven plugin*

A transformed artefact may contain code whose package identity has become difficult or impossible for the tested scanner to recover:

- bundled lodash
- shaded custom JAR contents

## 5. Build systems have dependency and execution domains outside the application dependency graph

Observed examples:

- Maven plugin ClassRealm
- PEP 517 build backend
- npm prepack lifecycle

These domains can execute code and materially change the resulting application without becoming ordinary runtime dependency edges.

## 6. Generated content does not carry its own history automatically

Observed examples:

- Vite browser bundle
- PEP 517 generated Python files
- Maven-plugin-generated Java/service metadata
- npm-prepack-generated dist files

A scanner observing only the final output may identify some surviving package boundaries. You cannot assume it reconstructs the process that created those bytes.

## 7. Evidence must be collected at the boundary where the fact still exists

For these labs:

- Maven application graph — ordinary application dependency resolution
- Maven plugin ClassRealm — build-plugin dependencies
- npm/package-lock — Node package identity before bundling
- pip build log + sdist — PEP 517 build execution
- npm pack log — publication lifecycle execution
- final artefact scan — software whose package boundaries survive strongly enough

No single one of these views is the complete supply-chain record.

---

# Final verdict

The strongest T01 conclusion is that software supply-chain evidence is **boundary-specific**, not that Snyk is deficient.

Snyk is good at the dependency models and package identities it supports, and can enrich those identities with useful security and provenance information.

But once a build or publication transformation crosses out of that model:

- plugin execution
- shading
- bundling
- PEP 517 build hooks
- npm lifecycle scripts
- generated code

you cannot assume the missing history remains recoverable later from the final artefact.

The practical rule is:

> Capture supply-chain evidence when the transformation happens. Do not rely on a later scanner to reconstruct facts that the build has already discarded.

---
id: s08-extended-sbom
oneliner: "Two SBOMs from the same POMs: the standard CycloneDX plugin describes what ships, SBOM+ also records the build tooling and BOM imports that shaped it, and marks them so a consumer can tell the two apart."
track: core
---

# S08 — Extended SBOM: What Built This, Not Just What Ships

Every SBOM so far in this workshop was generated from one of two places: the
resolver's view of the **application dependency graph** (the CycloneDX Maven
plugin in S01 and S04) or the **bytes of the final artefact** (Syft in S01,
S04, S07). S04 showed the gap between them: a Maven plugin and its transitive
payload generated runtime code, and the Maven-model SBOM listed **zero
components**, because plugins are not application dependencies.

This lab asks whether a Maven-model SBOM *has* to stop there. It runs a second
generator, [SBOM+](https://noregressions.github.io/sbom-plus-maven-plugin/),
against the same POMs, with no changes to them, and compares.

The tracked components are S04's and S01's, unchanged:

- `trace-injector-maven-plugin` and `trace-route-payload` — S04's build-time
  software that never appears in `dependency:tree`.
- `maven-shade-plugin` — the S01 tooling that relocated `commons-codec`.
- `spring-boot-dependencies` — the BOM import that decided S01's versions.
- `jackson-databind` and `commons-codec` — the S01 control and shading legs.

The pattern is:

**Why → Approach → Run → Observed output → Establish**

## The two generators

Both are ordinary Maven plugins run as bare goals from the command line, so
neither scenario's `pom.xml` is touched.

| | Standard | Extended |
|---|---|---|
| Plugin | `org.cyclonedx:cyclonedx-maven-plugin:2.9.3` | `dev.noregressions:sbom-plus-maven-plugin:1.0.0` |
| Goal | `makeBom` / `makeAggregateBom` | `scan` / `scan-aggregate` |
| Reads | the resolved **project** dependency graph | the project graph **and** every plugin's dependency graph **and** imported BOMs |
| Writes | one CycloneDX 1.6 document | a CycloneDX 1.5 document **plus** a scan report with `origin` and `broughtInBy` for every row |

SBOM+ classifies every row it resolves by which pass found it:

```text
MAIN_BUILD      the application dependency graph       -> CycloneDX scope required / optional
BUILD_TOOLING   a plugin, or a plugin's dependency      -> CycloneDX scope excluded
BOM             an imported dependency-management POM   -> CycloneDX scope excluded, purl ?type=pom
```

The scope mapping is the important design choice. Build tooling **is listed**
but is marked `excluded`, CycloneDX's word for "part of the record, not part
of the delivered artefact". A consumer that only cares about what ships can
filter on `scope`. A consumer asking "what software participated in producing
this" has the answer in the same file.

## Requirements

- S04 built (`scenarios/S04-maven-plugin-hidden-content/scripts/build.sh`)
- S01 checked out; it does not need to be built
- JDK 21+, Maven 3.9+, `jq`


---

# 1. S04: a build with an empty dependency graph

## Why

S04 is the sharpest possible test. Its application POM declares **no
dependencies** and one build plugin. Everything interesting about the build
lives in the plugin realm, which is exactly the domain the standard SBOM does
not model.

## Run

```command
cd scenarios/S08-extended-sbom
./scripts/scan-s04.sh
```

The script runs, in S04's own scenario-local repository:

```command
mvn -Dmaven.repo.local=.maven-repo org.cyclonedx:cyclonedx-maven-plugin:2.9.3:makeBom -DoutputFormat=json
mvn -Dmaven.repo.local=.maven-repo dev.noregressions:sbom-plus-maven-plugin:1.0.0:scan
```

## Observed output

```output
===== S04: what each SBOM says =====
standard : 0 components    specVersion=1.6
extended : 171 components  excluded=171  specVersion=1.5
SBOM+ report: 194 rows across 1 module(s)  BUILD_TOOLING=194  unresolved=0

-- The S04 tracked components --
standard SBOM:
   (absent)
extended SBOM:
   trace-injector-maven-plugin  1.0.0  excluded  pkg:maven/dev.noregressions.trace/trace-injector-maven-plugin@1.0.0?type=maven-plugin
   trace-route-payload          1.0.0  excluded  pkg:maven/dev.noregressions.trace/trace-route-payload@1.0.0
SBOM+ report (origin, scope, path):
   maven-plugin-hidden-content  BUILD_TOOLING  plugin             dev.noregressions.trace:trace-injector-maven-plugin:1.0.0  (declared directly)
   maven-plugin-hidden-content  BUILD_TOOLING  plugin-transitive  dev.noregressions.trace:trace-route-payload:1.0.0          via trace-injector-maven-plugin
```

The rest of the 194 rows are Maven's own lifecycle plugins and their
dependencies: `maven-compiler-plugin 3.14.1` and the `asm 9.8` it compiles
with, `maven-jar-plugin`, `maven-surefire-plugin`, `plexus-archiver`, and so
on. The full list is in `results/s04/plus.report.json`.

## Establish

Same POM, same local repository, same moment. The standard SBOM is a
truthful, empty statement about the application graph. The extended SBOM
records the two components S04 spent fourteen steps proving were causally
responsible for `/hidden/build-info`, and it records **how** the payload got
there: `via trace-injector-maven-plugin`, the same path S04's step 4 had to
recover by hand with `dependency:resolve-plugins`.

Notice that every one of the 171 components is `excluded`. That is correct.
None of them ship in the JAR. What ships is *generated code*, and neither
SBOM can name generated code as a component, because it has no coordinates.
SBOM+ names the **cause**; it still cannot name the **effect**. Only the
byte-level evidence in S04 steps 8 and 9 does that.

---

# 2. S01: a real reactor with a BOM and a shading plugin

## Why

S04 is a constructed extreme. S01 is an ordinary Spring Boot multi-module
build, so the question becomes: on a normal project, what does the extended
view add, and where does it disagree with the standard one?

## Run

```command
./scripts/scan-s01.sh
```

This runs `makeAggregateBom` and `scan-aggregate` from S01's root POM, so
both generators cover the whole reactor (`normalizer` and `service`; the
frontend is an npm build outside Maven's model).

## Observed output

On a fresh checkout that has been packaged but not installed:

```output
[WARNING] SBOM+ scan: 1 dependency could not be resolved for dev.noregressions.trace:service
[WARNING]   - dev.noregressions.trace:normalizer:1.0.0 (compile) - Could not find artifact ... in central

===== S01: what each SBOM says =====
standard : 38 components   (no scope)=2  required=36  specVersion=1.6
extended : 265 components  excluded=230  required=35  specVersion=1.5
SBOM+ report: 642 rows across 3 module(s)  BOM=1  BUILD_TOOLING=569  MAIN_BUILD=72  unresolved=1
```

The tracked components:

```text
standard SBOM:
   commons-codec     1.17.1  required
   commons-codec     1.18.0  required
   jackson-databind  2.19.4  required
   normalizer        1.0.0   -
extended SBOM:
   commons-codec             1.11    excluded
   commons-codec             1.17.1  required
   commons-codec             1.19.0  excluded
   jackson-databind          2.19.4  required
   maven-shade-plugin        3.6.0   excluded
   maven-shade-plugin        3.6.2   excluded  ...?type=maven-plugin
   spring-boot-dependencies  3.5.12  excluded  ...?type=pom
```

And the report rows that explain them:

```text
normalizer  BUILD_TOOLING  plugin             maven-shade-plugin:3.6.2       (declared directly)
normalizer  BUILD_TOOLING  plugin-transitive  commons-codec:1.11             via maven-site-plugin > doxia-core > httpclient
normalizer  BUILD_TOOLING  plugin-transitive  commons-codec:1.19.0           via maven-jar-plugin > plexus-archiver > commons-compress
normalizer  MAIN_BUILD     compile            commons-codec:1.17.1           (declared directly)
service     BUILD_TOOLING  plugin-transitive  jackson-databind:2.19.4        via spring-boot-maven-plugin > spring-boot-buildpack-platform
service     BUILD_TOOLING  plugin-transitive  commons-codec:1.17.1           via spring-boot-maven-plugin > spring-boot-buildpack-platform > commons-compress
service     BUILD_TOOLING  plugin-transitive  maven-shade-plugin:3.6.0       via spring-boot-maven-plugin
service     MAIN_BUILD     compile            jackson-databind:2.19.4        (declared directly)
(root)      BOM            import             spring-boot-dependencies:3.5.12
```

## Establish

Four things are visible here that no earlier S01 step could show from a
single document.

**The shading plugin is on the record.** `maven-shade-plugin 3.6.2` is the
tool that relocated `commons-codec` into `com.acme.internal.codec` and made
S01's shading leg so hard to identify from the bytes. The standard SBOM does
not know it exists. The extended SBOM lists it as `excluded`, with the
`?type=maven-plugin` qualifier, so a reader of the SBOM knows a relocation
tool was in the build without opening the POM.

**The BOM that chose the versions is on the record.** `spring-boot-dependencies
3.5.12` appears as a component with `?type=pom`. S01's control leg established
that `jackson-databind 2.19.4` was *selected by dependency management*, not
declared. This is the artefact that did the selecting, and Part 4 flagged this
exact Spring Boot line as past its open-source support date.

**The same coordinate can be two different things.** `jackson-databind 2.19.4`
is `MAIN_BUILD compile` in `service` (it ships) **and** `BUILD_TOOLING` via
`spring-boot-maven-plugin > spring-boot-buildpack-platform` (it ran in the
build and did not ship). One CycloneDX component, marked `required`, two rows
in the report. Without `origin`, a scanner finding against jackson-databind in
the build tooling would be indistinguishable from one in the application.
`commons-codec` shows the same effect three times over: `1.17.1` ships; `1.11`
and `1.19.0` are pulled in by the site and jar plugins and do not.

**The two generators disagree, and the disagreement is informative.** The
standard SBOM lists `commons-codec 1.18.0`; the extended one, on a fresh
checkout, does not. Look at the warning. SBOM+ declares
`requiresDependencyResolution = NONE` and resolves every module's graph
itself, from *repositories*. On a checkout that has been packaged but never
`install`ed, `service`'s dependency on its sibling `normalizer` cannot be
resolved from any repository, so `normalizer` and everything under it,
including the BOM-managed `commons-codec 1.18.0`, is missing, and the report
says so in `unresolved`. The CycloneDX plugin runs inside the reactor with
Maven's own resolution and sees the sibling directly. Neither is wrong; they
have different evidence boundaries, and the extended one writes its boundary
down.

## Go deeper: close the gap and re-scan

```command
(cd ../S01-spring-node && mvn -q install -DskipTests) && ./scripts/scan-s01.sh
```

```output
extended : 267 components  excluded=230  required=37  specVersion=1.5
SBOM+ report: 644 rows across 3 module(s)  BOM=1  BUILD_TOOLING=569  MAIN_BUILD=74  unresolved=0
...
service   MAIN_BUILD  compile  commons-codec:1.18.0    via normalizer
service   MAIN_BUILD  compile  normalizer:1.0.0        (declared directly)
-- Components only one of them lists --
   only in standard : dev.noregressions.trace:service:1.0.0
   only in extended : 230 (build tooling and the BOM import)
   in both          : 37
```

With `normalizer` installed, the two `required` sets agree exactly. The only
component left that appears in one and not the other is `service` itself,
which the standard aggregate lists as a component and SBOM+ treats as the
document's subject. Everything else the extended SBOM adds, all 230
components, is build tooling and the BOM.

---

# 3. What kind of evidence is this?

Both documents are **claims from the resolver**, not observations of bytes.
Place them on the workshop's boundary map:

```text
declared model     ->  resolved graph      ->  build execution   ->  artefact bytes  ->  runtime
                       standard SBOM           extended SBOM         Syft (S01/S04)     javap, curl
                       (what will ship)        (+ what will run       (what did ship)
                                                during the build)
```

The extended SBOM moves one boundary to the right: it covers software that
*executes during the build* and can therefore change what ships. It does not
cross into the artefact. S04's `GeneratedTraceRoute.class` is in the JAR and
in no SBOM here, because it was never a coordinate. S07's Syft SBOM, taken
from the image digest, is the document that describes bytes; this one
describes intent and process.

A consumer holding the extended SBOM can ask questions the standard one
cannot answer:

```text
Was a bytecode-rewriting tool in this build?          yes: maven-shade-plugin 3.6.2
Which POM chose these versions?                       spring-boot-dependencies 3.5.12
Did jackson-databind run at build time as well?       yes, via spring-boot-buildpack-platform
Which plugin brought in this unexplained artefact?    trace-route-payload via trace-injector-maven-plugin
Is anything in this record known to be missing?       the unresolved list
```

---

# What this lab establishes

1. **A Maven-model SBOM is not obliged to stop at the application graph.**
   The same resolver that produces an empty SBOM for S04 can, asked
   differently, produce 171 components of build tooling from the same POM.

2. **Listing build tooling and marking it `excluded` are both necessary.**
   Listing it makes S04's plugin and payload visible in the SBOM for the first
   time. Marking it `excluded` keeps a shipped-components consumer honest: none
   of it is in the JAR.

3. **`origin` disambiguates coordinates that appear for two reasons.**
   `jackson-databind 2.19.4` ships *and* runs in the build. Only the report's
   per-row origin tells them apart.

4. **The BOM that selected the versions is itself a supply-chain input**, and
   the extended SBOM records it as a `?type=pom` component.

5. **Different evidence boundaries produce different SBOMs from the same POM.**
   The reactor-aware standard plugin sees a sibling module the
   repository-resolving SBOM+ cannot until it is installed. The extended
   report writes that gap into `unresolved` rather than silently omitting it.

6. **Neither document describes bytes.** Generated code, relocated classes and
   the contents of the final JAR remain the province of artefact-level tools.
   The extended SBOM names what *caused* those bytes; S04 and S07 show how to
   inspect and attest to the bytes themselves.

---

# Run

```command
cd scenarios/S08-extended-sbom
./scripts/scan-s04.sh        # S04: 0 components versus 171 build-tooling components
./scripts/scan-s01.sh        # S01: the shade plugin, the BOM, and the sibling-module gap
./scripts/proof-check.sh     # assert the claims above still hold
./scripts/clean.sh           # remove results/
```

`scripts/seed-plugin.sh [local-repo]` makes SBOM+ resolvable up front,
for offline machines and the workshop container. Outputs land in `results/`;
`evidence/` holds the captured summaries this lesson quotes.

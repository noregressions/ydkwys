---
id: workshop-02-identification
oneliner: "The hands-on route through S01, S04, S08, S05, S03 and S02, and the T01 scanner test: six ways a component stops being identifiable, one evidence source that recovers some of it, and the table that results."
track: core
status: draft
---

# Part 2 — Can We Identify What We Ship?

This is the longest hands-on stretch of the workshop by a distance, and
everything after it refers back to what you find here.

Seven stops, four ecosystems, one question. Each lab declares a component you
can name, builds with the real toolchain, and then asks what is left of that
component's identity at the far end. The full walkthrough for each lab
follows this chapter; what is below is the route — the commands to run, what
you should see, and what it proves.

If you fall behind, keep moving. Every lab has captured output in its lesson,
and the point of each is visible in one command.

## Step 1 — Build transformations (S01)

Lab: *S01 — Spring + Node*.

Three tracked components in one Spring Boot application, chosen because they fail
differently.

```command
cd scenarios/S01-spring-node
./scripts/build.sh
```

**The control — `jackson-databind`.** An ordinary dependency, resolved
ordinarily, packaged ordinarily.

```command
mvn -pl service dependency:tree -Dincludes=com.fasterxml.jackson.core:jackson-databind
syft service/target/service-1.0.0.jar | grep -i jackson
```

The resolver says `jackson-databind:2.19.4`. Syft, reading the packaged JAR,
says `jackson-databind:2.19.4`. Both boundaries agree. This is what working
looks like, and it is worth seeing before we break it.

**Shading and metadata — `commons-codec`.** The normalizer module shades
`commons-codec` and relocates its bytecode into an application namespace.

```command
syft normalizer/target/normalizer-1.0.0.jar
./scripts/strip-codec-metadata.sh
```

Before stripping, Syft finds `commons-codec:1.17.1`. The script then removes
the `META-INF/maven/...` entries from the shaded JAR — **and touches no
bytecode at all**. Scan again: `commons-codec` is gone. The code that
computes the hashes is still running. Only the paperwork left.

**Bundling — `lodash`.** The frontend imports lodash; Vite bundles it.

```command
npm --prefix frontend ls lodash
grep -oE "__lodash_hash_undefined__|4\.17\.21" frontend/dist/assets/*.js | sort | uniq -c
syft frontend/dist
```

npm declares `lodash@4.17.21`. Grep finds lodash's own sentinel strings and
its version number sitting in the shipped bundle. Syft reports
`No packages discovered`. Nothing was hidden on purpose here — this is what
every JavaScript build in production does by default.

**What this proves:** static scanners identify components from embedded
package metadata, not from code. Where a build omits, strips or dissolves
that metadata, presence and identifiability come apart — and two of the three
cases above are ordinary, sanctioned build behaviour.

## Step 2 — Plugin execution realms (S04)

Lab: *S04 — Maven plugin hidden content*.

S01 broke identity for dependencies you declared. S04 asks a harder question:
what about code you never declared at all?

```command
cd scenarios/S04-maven-plugin-hidden-content
./scripts/build.sh
mvn -Dmaven.repo.local="$PWD/.maven-repo" dependency:tree
```

The dependency tree contains exactly one thing: the project itself. No
dependencies. By the usual reading, there is nothing here to audit.

```command
./scripts/run.sh
curl -sS http://localhost:8082/hidden/build-info | jq
unzip -l target/maven-plugin-hidden-content-1.0.0.jar | grep -E 'Generated|services'
./scripts/stop.sh
```

The application serves an endpoint that no source file in the project
defines. `trace-injector-maven-plugin` generated it during the build, from a
payload dependency the plugin brought with it.

**What this proves:** a dependency resolver reports the *application's*
dependency graph. Plugins execute in their own ClassRealms with their own
transitive dependencies, and that graph is not in the report — even though
its code ends up in your artefact.

## Step 3 — An SBOM that does see it (S08)

Lab: *S08 — Extended SBOM*.

S04 ends on a genuinely uncomfortable note: the code is in the artefact and no
inventory names it. Before accepting that as inevitable, it is worth asking
whether the inventory was the wrong *kind*, rather than simply wrong.

Point two SBOM generators at the same POMs and compare.

```command
cd scenarios/S08-extended-sbom
./scripts/seed-plugin.sh    # offline machines only: puts SBOM+ in ~/.m2
./scripts/scan-s04.sh
```

The standard CycloneDX Maven plugin, run against S04, produces an SBOM with
**zero components** — which is a truthful answer to the question it was asked.
It describes the application dependency graph, and that graph is empty.

[SBOM+](https://noregressions.github.io/sbom-plus-maven-plugin/) asks a
different question: not *what ships* but *what built this*. Against the same
POM it returns 171 components, every one marked `excluded`, including the two
you went looking for:

```text
trace-injector-maven-plugin  1.0.0  excluded  plugin
trace-route-payload          1.0.0  excluded  plugin-transitive
                                              via trace-injector-maven-plugin
```

Then do the same across S01, where there is a real dependency graph to
compare against rather than an empty one:

```command
./scripts/scan-s01.sh
```

Standard: 38 components. Extended: 265, of which 230 are `excluded` build
tooling — `maven-shade-plugin` among them, which is the thing that destroyed
`commons-codec`'s identity in Step 1. The tool that broke the inventory is
itself absent from the inventory, unless you ask a generator that looks at the
build.

**What this proves, and it is the first good news in the workshop:** the gap in
S04 is a gap in the *evidence source*, not a law of physics. The information
existed at build time. Nothing had been recording it. That distinction — the
data was never captured, versus the data cannot be captured — is what Part 6
is built on.

Note the discipline in the output, too: the extended SBOM marks build-time
components as `excluded` rather than mixing them in with shipped ones. An
inventory that cannot tell you which boundary each component came from has
traded one problem for another.

One wrinkle you will hit, and it recurs in Part 6: on a checkout that has been
packaged but not installed, SBOM+ cannot resolve S01's sibling `normalizer`
module and says so. `(cd ../S01-spring-node && mvn -q install -DskipTests)`
then re-run, and the two `required` sets agree exactly. Worth seeing, because
"the tool could not resolve it" and "the component is not there" print very
differently and mean completely different things.

## Step 4 — Package lifecycle hooks (S05)

Lab: *S05 — Node prepack*.

Same mechanism, different ecosystem — which matters, because it means this is
not a Maven problem.

```command
cd scenarios/S05-node-prepack
./scripts/build.sh
tar -tzf npm-repo/trace-route-package-1.0.0.tgz
./scripts/run.sh
curl -sS http://localhost:8083/hidden/prepack-info | jq
./scripts/stop.sh
```

The build log shows npm running `prepack`, which runs `generate-dist.js`. The
tarball contains a `dist/` directory that exists in no commit of the source
repository. Anyone reading the repo sees one thing; anyone installing the
package gets another.

**What this proves:** packaging hooks run before the distributable exists, so
the published artefact can differ from the published source by design, with
no warning to either side.

## Step 5 — Python build backends (S03)

Lab: *S03 — Python PEP 517*.

```command
cd scenarios/S03-python-pep517
./scripts/build.sh
tar -tzf python-repo/tracehook_demo-1.0.0.tar.gz
ls .venv/lib/python*/site-packages/tracehook_demo/
./scripts/run.sh
curl -sS http://localhost:8081/trace | jq
./scripts/stop.sh
```

The source distribution contains two files: `pyproject.toml` and
`tracehook_backend.py`. No package. During `pip install`, the build backend
runs and constructs the importable package that ends up in `site-packages`.

**What this proves:** in ecosystems with pluggable build backends, the sdist
is not the software — it is a program that produces the software, on the
installing machine.

## Step 6 — All of it at once, in Jakarta EE (S02)

Lab: *S02 — Payara + mvnpm*.

Each lab so far isolated one mechanism, which is how you prove a mechanism and
not how software actually arrives. S02 is the realistic case: a Jakarta EE
application, packaged as a WAR, deployed to Payara, with front-end
dependencies delivered through **mvnpm** — npm packages republished as Maven
artefacts — that reach the browser bundle only by way of a plugin execution
realm.

```command
cd scenarios/S02-payara-mvnpm
./scripts/build.sh
```

Two tracked components, chosen to fail differently again. `commons-lang3` is an ordinary
Maven dependency and behaves ordinarily:

```command
mvn dependency:tree -Dincludes=org.apache.commons:commons-lang3
```
```output
\- org.apache.commons:commons-lang3:jar:3.18.0:compile
```

`lodash-es` arrives through mvnpm, and the hunt for it is the lab:

Not a project dependency. The tree says nothing.
```command
mvn dependency:tree -Dincludes=org.mvnpm:lodash-es
```

Ask about the esbuild plugin instead: the plugin is listed, its own dependencies still are not.
```command
mvn dependency:resolve-plugins -DincludeArtifactIds=esbuild-maven-plugin
```

Only at debug level, in the plugin's class realm, does it finally appear.
```command
mvn -X generate-resources 2>&1 | grep 'org.mvnpm:lodash-es'
```
```output
[DEBUG] org.mvnpm:lodash-es:jar:4.17.21:runtime
```

Then confirm it reached the browser: the esbuild source map lists every
`lodash-es` module bundled into `app.js`. The code ships. The identity was
only ever visible in `-X` output that nobody reads and no scanner parses.

Follow the rest of the lab through the WAR, the exploded deployment and the
container image, noting where each tracked component stops being identifiable. The WAR
boundary deserves particular attention — `WEB-INF/lib` looks like a tidy,
complete inventory, and it is complete only about the things that got there by
being declared.

**What this proves:** the mechanisms are not exotic and they compose. A single
ordinary enterprise application can lose component identity at packaging, at
plugin execution, and at the registry-translation boundary between npm and
Maven — three times, for three different reasons, in one build.

This lab is also the target for two of the reference investigations: T04
points Grype at it and T02 points Docker Scout at it, if you want to see what
different tools make of the same WAR later.

## Step 7 — Can a commercial scanner recover it? (T01)

Investigation: *T01 — Snyk beyond the SBOM*.

By now the obvious objection is that these are toy failures and a serious
commercial tool would do better. S04 is the fair test: we know exactly what
is in that artefact, and the evidence for it was never written down.

Snyk is pointed at the S04 project across five views — Maven test, test with
provenance, CycloneDX SBOM, SBOM with provenance, and an unmanaged JAR scan.
None of them recovers the plugin or its payload.

**What this proves, and it is the load-bearing finding of Part 2:**

```text
Analysis cannot reconstruct evidence that the build never produced.
```

This is not a criticism of Snyk. No scanner reading that artefact can
identify a component whose coordinates and signatures were never written
into it. The fix is not a better scanner; it is an additional evidence
source, captured at build time, at the boundary where the information still
exists. Part 6 is about capturing it.

## The evidence boundary table

This table is the output of Part 2, and Parts 3 to 6 keep referring to it.
Every inventory you will ever read was produced by one of these rows.

| Evidence source | What it can see | What it structurally cannot |
|---|---|---|
| Manifest / POM | What you declared | Anything resolved, generated or transformed later |
| Resolver | The resolved application graph | Plugin realms, build backends, lifecycle hooks |
| SBOM | Whatever its producer inspected | Everything outside that producer's evidence domain |
| Artefact scanner | Archives, files, embedded metadata | Shaded or relocated code whose metadata is gone |
| Image scanner | Layers, OS packages, installed files | How any of it was built, and from what source |
| Build-aware SBOM (S08) | Plugins, backends, BOM imports, and their paths | Anything the build did not resolve through Maven at all |

Read left to right and the columns look like coverage. Read the third column
on its own and you have the attack surface the rest of the workshop is about.

Note the last row carefully. It is the only evidence source in Part 2 that
recovered ground the others lost, and it did so not by analysing harder but by
being present at a boundary where the information still existed. That is the
whole of the good news, and the whole of Part 6.

## You should now be able to

- Point at the exact boundary where each tracked component stopped being identifiable,
  across four ecosystems, and say why in each case.
- Explain why an empty dependency tree is not evidence of an empty artefact.
- Distinguish a gap that is inherent from a gap that is merely unrecorded —
  S08 is the difference, and Part 6 is what you do about it.
- Say what a scanner would have needed, and when, to catch what it missed.

**Next:** every inventory you have produced so far is incomplete in a way you
can now name. Part 3 lays vulnerability data over the top of it and asks what
a finding — or a clean report — is actually worth.

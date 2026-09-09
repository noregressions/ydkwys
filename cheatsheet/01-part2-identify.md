---
id: cheatsheet-part2
oneliner: "Part 2 in run order: S01, S04, S08, S05, S03, S02, T01 — every command and the output it should produce."
track: reference
---

# Part 2 — Can We Identify What We Ship?

---

## S01 — Spring + Node: shading, bundling, metadata stripping

**Proving:** Three tracked components, three fates: one survives, one dies when only its metadata is deleted, one is dissolved by the bundler.

Tracking: `jackson-databind` (control), `commons-codec` (shaded and relocated), `lodash` (bundled by Vite).
Needs: JDK 21, Maven 3.9+, Node 20+. Full trace also needs `jq`, `syft`, `zip`, Docker.

Work from the scenario directory.
```command
cd scenarios/S01-spring-node
```

Remove all build output.
```command
./scripts/clean.sh
```

npm install + Vite build of the frontend, then mvn package for normalizer and service.
```command
./scripts/build.sh
```

Prints a `Cleaned:` list, then `Built:` with `frontend/dist/`, `normalizer/target/normalizer-1.0.0.jar`, `service/target/service-1.0.0.jar`.

#### Declared versions

Ask Maven which jackson-databind version the service resolved.
```command
mvn -pl service -am dependency:tree \
  -Dincludes=com.fasterxml.jackson.core:jackson-databind
```
```output
[INFO] \- com.fasterxml.jackson.core:jackson-databind:jar:2.19.4:compile
```

Ask Maven which commons-codec version the normalizer resolved, before shading.
```command
mvn -pl normalizer dependency:tree \
  -Dincludes=commons-codec:commons-codec
```
```output
[INFO] \- commons-codec:commons-codec:jar:1.17.1:compile
```

Ask npm which lodash version the frontend resolved.
```command
(cd frontend && npm ls lodash)
```
```output
checkout-trace-frontend@1.0.0
└── lodash@4.17.21
```

#### Jackson in the JAR (control)

Confirm the resolved Jackson jar is physically inside the Spring Boot JAR, name and version intact.
```command
unzip -l service/target/service-1.0.0.jar | grep jackson-databind
```
```output
1679441  ...   BOOT-INF/lib/jackson-databind-2.19.4.jar
```

#### commons-codec after shading

Show commons-codec classes now live under the relocated package name.
```command
unzip -l normalizer/target/normalizer-1.0.0.jar | grep \
  'com/acme/internal/codec' | head
```

Show the original package path is gone from the shaded JAR.
```command
unzip -l normalizer/target/normalizer-1.0.0.jar | grep \
  'org/apache/commons/codec' | head
```
First shows relocated classes (`com/acme/internal/codec/BinaryDecoder.class` ...). Second prints nothing.

Read the Maven metadata the shade plugin kept; this is the only remaining identity clue.
```command
unzip -p normalizer/target/normalizer-1.0.0.jar \
  META-INF/maven/commons-codec/commons-codec/pom.properties
```
```output
artifactId=commons-codec
groupId=commons-codec
version=1.17.1
```

Scan the shaded JAR; Syft finds commons-codec because that metadata is still present.
```command
syft normalizer/target/normalizer-1.0.0.jar
```
```output
NAME           VERSION  TYPE
commons-codec  1.17.1   java-archive
normalizer     1.0.0    java-archive
```

#### Strip the metadata, scan again

Copy the shaded JAR minus META-INF/maven/commons-codec; bytecode untouched. Prints before/after scans.
```command
./scripts/strip-codec-metadata.sh
```

Scan the stripped copy to show what the scanner was actually relying on.
```command
syft trace-output/normalizer-no-codec-metadata.jar
```
```output
normalizer                    1.0.0    java-archive
normalizer-no-codec-metadata  UNKNOWN  java-archive
```
commons-codec has vanished from the scan. Bytecode untouched. Software presence ≠ software identifiability.

#### lodash in the bundle

List what Vite produced: one minified bundle, no package structure.
```command
find frontend/dist -maxdepth 2 -type f -print
```

Scan the bundle; there is no package metadata for Syft to read.
```command
syft frontend/dist
```
```output
frontend/dist/index.html
frontend/dist/assets/index-<hash>.js
frontend/dist/assets/index-<hash>.css
frontend/dist/.vite/manifest.json

No packages discovered
```

#### Whole Spring Boot JAR

Confirm the frontend bundle was copied into the service JAR as static resources.
```command
unzip -l service/target/service-1.0.0.jar | grep \
  'BOOT-INF/classes/static/'
```

Confirm the shaded normalizer JAR is nested inside the service JAR.
```command
unzip -l service/target/service-1.0.0.jar | grep \
  'normalizer-1.0.0.jar'
```

Scan the finished application JAR to see the full identifiable inventory.
```command
syft service/target/service-1.0.0.jar
```
34 packages. Relevant rows:
```text
commons-codec     1.17.1   java-archive
commons-codec     1.18.0   java-archive
jackson-databind  2.19.4   java-archive
normalizer        1.0.0    java-archive
service           1.0.0    java-archive
```
No lodash. Two commons-codec versions.

Explain the second commons-codec: Spring Boot's BOM manages the version up to 1.18.0 for the service.
```command
mvn -pl service -am dependency:tree \
  -Dincludes=commons-codec:commons-codec -Dverbose
```
```output
[INFO] \- dev.noregressions.trace:normalizer:jar:1.0.0:compile
[INFO]    \- commons-codec:commons-codec:jar:1.18.0:compile (version managed from 1.17.1)
```
Dependency graph ≠ complete physical inventory.

#### SBOMs: Maven model vs artefact

Generate CycloneDX SBOMs from the Maven dependency model for every module.
```command
mvn -pl service -am \
  org.cyclonedx:cyclonedx-maven-plugin:2.9.3:makeBom \
  -DoutputFormat=json
```

Print the tracked rows from the normalizer and service BOMs side by side.
```command
./scripts/compare-sboms.sh
```
```output
=== normalizer BOM ===
commons-codec	1.17.1	pkg:maven/commons-codec/commons-codec@1.17.1?type=jar

=== service BOM ===
jackson-databind	2.19.4	...
normalizer	1.0.0	...
commons-codec	1.18.0	...
```

Generate a second CycloneDX SBOM, this time from the finished JAR's bytes rather than the POM.
```command
mkdir -p trace-output
syft service/target/service-1.0.0.jar -o \
  cyclonedx-json=trace-output/service-syft.cdx.json
```

Compare the Maven-model SBOM with the artefact-derived SBOM for the same service.
```command
./scripts/compare-service-sboms.sh
```
```output
=== Maven-generated service SBOM ===
commons-codec	1.18.0
jackson-databind	2.19.4
normalizer	1.0.0

=== Syft-generated service SBOM ===
commons-codec	1.17.1
commons-codec	1.18.0
jackson-databind	2.19.4
normalizer	1.0.0
```
Same format, different inventory. Where the SBOM is generated matters.

#### Container image

Build the Docker image, record its digest, and scan the whole image (app + JRE + OS packages).
```command
./scripts/image-trace.sh
```
Builds `registry.example.com/checkout-service:release-123`, writes `trace-output/image.cdx.json`.
```text
Packages      179
Executables   837

commons-codec     1.17.1
commons-codec     1.18.0
jackson-databind  2.19.4
normalizer        1.0.0
```
JAR scan 34 packages, image scan 179. Still no lodash. Application SBOM ≠ container SBOM.

#### Optional

Run the service locally and hit its trace endpoint to prove the shaded codec is executing.
```command
java -jar service/target/service-1.0.0.jar
curl 'http://localhost:8080/api/trace?value=Hello%20Supply%20Chain'
```

Replay every evidence step non-interactively; writes files into trace-output/.
```command
./scripts/trace.sh
```

Re-run the lab and assert every outcome above still holds.
```command
./scripts/proof-check.sh    # flags: --quick, --skip-build, \
  --skip-runtime, --skip-image
```

Remove build output; keeps frontend/package-lock.json.
```command
./scripts/clean.sh
```

---

## S04 — Maven plugin hidden content: empty dependency graph, injected route

**Proving:** An empty dependency tree and a running endpoint that no source file defines.

Tracked components: `trace-injector-maven-plugin` and its payload `trace-route-payload`. Neither is an application dependency.
Needs: JDK 21+, Maven 3.9+, `curl`, `unzip`. `jq` and Syft optional. All `mvn` calls use the scenario-local repo `.maven-repo`.

```command
cd scenarios/S04-maven-plugin-hidden-content
```

Remove target/, tooling output and evidence; keeps the local Maven repo.
```command
./scripts/clean.sh
```

Build the plugin and payload into .maven-repo, then build the app with the plugin running.
```command
./scripts/build.sh
```
```output
[INFO] --- trace-injector:1.0.0:inject-route (inject-build-route) @ maven-plugin-hidden-content ---
[INFO] Injected route: /hidden/build-info
[INFO] Compiling 3 source files with javac [debug release 21] to target/classes
[INFO] BUILD SUCCESS
```
Three source files compiled, only two exist in `src/`.

#### Three Maven domains

The application dependency graph: the plugin and payload are not in it.
```command
mvn -Dmaven.repo.local="$PWD/.maven-repo" dependency:tree
```
```output
[INFO] dev.noregressions.trace:maven-plugin-hidden-content:jar:1.0.0
```
Nothing beneath it. Empty graph.

The plugin dependency graph: here the plugin and its transitive payload appear.
```command
mvn -Dmaven.repo.local="$PWD/.maven-repo" \
  dependency:resolve-plugins \
  -DincludeArtifactIds=trace-injector-maven-plugin
```
```output
[INFO]    dev.noregressions.trace:trace-injector-maven-plugin:maven-plugin:1.0.0:runtime
[INFO]       dev.noregressions.trace:trace-injector-maven-plugin:jar:1.0.0
[INFO]       dev.noregressions.trace:trace-route-payload:jar:1.0.0
```

The plugin execution realm: debug output proves both jars were loaded to run the mojo.
```command
mvn -Dmaven.repo.local="$PWD/.maven-repo" -X generate-sources 2>&1 \
  | grep -E 'trace-injector|trace-route-payload'
```
```output
[DEBUG] Created new class realm plugin>dev.noregressions.trace:trace-injector-maven-plugin:1.0.0
[DEBUG]   Included: dev.noregressions.trace:trace-injector-maven-plugin:jar:1.0.0
[DEBUG]   Included: dev.noregressions.trace:trace-route-payload:jar:1.0.0
```

#### Generated content

List the Java source and resources the plugin wrote into target/ during the build.
```command
find target/generated-sources target/generated-resources -type f \
  -print
```
```output
target/generated-sources/trace-injector/dev/noregressions/trace/s04/generated/GeneratedTraceRoute.java
target/generated-resources/trace-injector/META-INF/trace-lab/plugin-injection.properties
target/generated-resources/trace-injector/META-INF/services/dev.noregressions.trace.s04.TraceRoute
```

Read the marker the plugin left naming itself, its payload and the injected route.
```command
cat \
  target/generated-resources/trace-injector/META-INF/trace-lab/plugin-injection.properties
```
```output
plugin=trace-injector-maven-plugin
payload=trace-route-payload
route=/hidden/build-info
```

#### In the JAR

Confirm the generated class, ServiceLoader entry and marker were packaged into the final JAR.
```command
unzip -l target/maven-plugin-hidden-content-1.0.0.jar | grep -E \
  'GeneratedTraceRoute|META-INF/services|plugin-injection'
```
```output
META-INF/trace-lab/plugin-injection.properties
META-INF/services/dev.noregressions.trace.s04.TraceRoute
dev/noregressions/trace/s04/generated/GeneratedTraceRoute.class
```

Disassemble the shipped class to prove the route string is in the bytecode.
```command
javap -classpath target/maven-plugin-hidden-content-1.0.0.jar -c \
  -p dev.noregressions.trace.s04.generated.GeneratedTraceRoute
```
```output
  public java.lang.String path();
       0: ldc           #7                  // String /hidden/build-info
```

#### Scanners see none of it

Scan the JAR; only the application itself is identified.
```command
syft target/maven-plugin-hidden-content-1.0.0.jar
```
```output
NAME                         VERSION  TYPE
maven-plugin-hidden-content  1.0.0    java-archive
```

Generate the standard CycloneDX SBOM from the Maven model; it is empty.
```command
mvn -Dmaven.repo.local="$PWD/.maven-repo" \
  org.cyclonedx:cyclonedx-maven-plugin:2.9.3:makeBom \
  -DoutputFormat=json
```
```output
[INFO] CycloneDX: Creating BOM version 1.6 with 0 component(s)
```

#### Runtime

Start the app detached on port 8082.
```command
./scripts/run.sh
```

Control endpoint defined in src/: proves the app is up.
```command
curl -sS http://localhost:8082/health | jq
```

Endpoint that exists only because the plugin injected it at build time.
```command
curl -sS http://localhost:8082/hidden/build-info | jq
```
Health returns `{"application": "maven-plugin-hidden-content", "status": "UP"}`. Build-info returns:
```json
{
  "message": "This runtime endpoint came from a transitive Maven plugin dependency.",
  "origin": "trace-route-payload",
  "introducedBy": "trace-injector-maven-plugin",
  "route": "/hidden/build-info"
}
```

Stop the app using the saved PID.
```command
./scripts/stop.sh
```

Replay the dependency-domain and generated-content steps non-interactively.
```command
./scripts/trace-plugin.sh
```

Re-run the lab and assert every outcome above still holds.
```command
./scripts/proof-check.sh
```

Remove build output; keeps .maven-repo. Add rm -rf .maven-repo for a cold resolution run.
```command
./scripts/clean.sh
```

---

## S08 — Extended SBOM: what built this, not just what ships

**Proving:** The same POM, two generators: 0 components against 171. The gap in S04 was unrecorded, not unrecordable.

Runs the standard CycloneDX plugin and SBOM+ against the S04 and S01 POMs.
Needs: S04 built, S01 checked out, JDK 21+, Maven 3.9+, `jq`.

```command
cd scenarios/S08-extended-sbom
```

Optional, offline machines: install the SBOM+ plugin into ~/.m2 so the scans resolve without network.
```command
./scripts/seed-plugin.sh
```

Run both generators on the S04 POM and print what each says about the plugin and payload.
```command
./scripts/scan-s04.sh
```
```output
===== S04: what each SBOM says =====
standard : 0 components    specVersion=1.6
extended : 171 components  excluded=171  specVersion=1.5
SBOM+ report: 194 rows across 1 module(s)  BUILD_TOOLING=194  unresolved=0

-- The S04 tracked components --
standard SBOM:
   (absent)
extended SBOM:
   trace-injector-maven-plugin  1.0.0  excluded  ...?type=maven-plugin
   trace-route-payload          1.0.0  excluded
SBOM+ report (origin, scope, path):
   ...  BUILD_TOOLING  plugin             trace-injector-maven-plugin:1.0.0  (declared directly)
   ...  BUILD_TOOLING  plugin-transitive  trace-route-payload:1.0.0          via trace-injector-maven-plugin
```
Standard SBOM is empty and correct. Extended names the plugin and payload as build tooling, marked `excluded`.

Run both generators across the whole S01 reactor (makeAggregateBom vs scan-aggregate).
```command
./scripts/scan-s01.sh
```
On a checkout that is packaged but not installed:
```text
[WARNING] SBOM+ scan: 1 dependency could not be resolved for dev.noregressions.trace:service

===== S01: what each SBOM says =====
standard : 38 components   (no scope)=2  required=36  specVersion=1.6
extended : 265 components  excluded=230  required=35  specVersion=1.5
SBOM+ report: 642 rows across 3 module(s)  BOM=1  BUILD_TOOLING=569  MAIN_BUILD=72  unresolved=1
```
Extended SBOM adds `maven-shade-plugin 3.6.2` (excluded), `spring-boot-dependencies 3.5.12` (excluded, `?type=pom`), and shows `jackson-databind 2.19.4` twice: once as `MAIN_BUILD compile`, once as `BUILD_TOOLING` via `spring-boot-maven-plugin`.

Install S01 into the local repo so SBOM+ can resolve the sibling normalizer module, then re-scan.
```command
(cd ../S01-spring-node && mvn -q install -DskipTests) && \
  ./scripts/scan-s01.sh
```
```output
extended : 267 components  excluded=230  required=37  specVersion=1.5
SBOM+ report: 644 rows across 3 module(s)  ...  MAIN_BUILD=74  unresolved=0
   only in standard : dev.noregressions.trace:service:1.0.0
   only in extended : 230 (build tooling and the BOM import)
   in both          : 37
```
With `normalizer` installed, the two `required` sets agree exactly.

Outputs in `results/s04/` and `results/s01/`: `standard.cdx.json`, `plus.cdx.json`, `plus.report.json`.

Re-run both scans silently and assert the 13 claims above still hold.
```command
./scripts/proof-check.sh    # 13 PASS lines, then Passed: 13 / \
  Failed: 0
```

Remove results/.
```command
./scripts/clean.sh          # S08 results removed.
```

The extended SBOM moves one boundary to the right: it covers software that executes during the build. Neither SBOM describes bytes; S04 and S07 do that.

---

## S05 — npm prepack: the package generates itself while packing

**Proving:** The published tarball contains files that exist in no commit. Not a Maven problem.

Tracked component: `trace-route-package`, whose `prepack` script writes `dist/` before the tarball is made.
Needs: Node 20+, npm, `curl`, `tar`. `jq` and Syft optional. No external npm packages.

```command
cd scenarios/S05-node-prepack
```

Remove node_modules, the packed tarball, generated dist/ and evidence.
```command
./scripts/clean.sh
```

npm pack the package (running its prepack hook), then npm install the app from that tarball.
```command
./scripts/build.sh
```
```output
npm notice run trace-route-package@1.0.0 prepack
npm notice run node scripts/generate-dist.js
generated dist/index.js for /hidden/prepack-info
generated dist/prepack-evidence.json
npm notice Tarball Contents
npm notice 435B dist/index.js
npm notice 334B dist/prepack-evidence.json
npm notice 300B package.json
npm notice total files: 3

added 1 package
└── trace-route-package@1.0.0
```
Tarball lands in `npm-repo/trace-route-package-1.0.0.tgz`. Logs in `trace-output/`.

#### Source vs tarball vs installed

List the package source after packing: generator script, its input, and the dist/ it produced.
```command
find packages/trace-route-package -maxdepth 3 -type f -print | sort
```
```output
packages/trace-route-package/build-input/route.json
packages/trace-route-package/dist/index.js
packages/trace-route-package/dist/prepack-evidence.json
packages/trace-route-package/package.json
packages/trace-route-package/scripts/generate-dist.js
```

List the tarball: only dist/ and package.json shipped.
```command
tar -tzf npm-repo/trace-route-package-1.0.0.tgz
```
```output
package/dist/index.js
package/package.json
package/dist/prepack-evidence.json
```
The generator script and its input are not in the tarball. Only its output is.

Read the provenance marker the prepack script wrote into the tarball.
```command
tar -xOzf npm-repo/trace-route-package-1.0.0.tgz \
  package/dist/prepack-evidence.json | jq
```
```json
{
  "event": "npm-prepack-generated",
  "package": "trace-route-package",
  "version": "1.0.0",
  "generatedBy": "npm lifecycle prepack -> scripts/generate-dist.js",
  "route": "/hidden/prepack-info"
}
```

Confirm the installed copy has the same three files.
```command
find node_modules/trace-route-package -maxdepth 3 -type f -print | \
  sort
```

Confirm the marker survived install unchanged.
```command
cat node_modules/trace-route-package/dist/prepack-evidence.json | jq
```

npm's own view of the installed tree: one dependency, correctly identified.
```command
npm ls --all
```

#### Evidence views

Generate npm's CycloneDX SBOM and list its components.
```command
npm sbom --sbom-format cyclonedx > trace-output/npm-sbom.json
jq -r '.components[]? | [.name, .version] | @tsv' \
  trace-output/npm-sbom.json
```
```output
trace-route-package	1.0.0
```

Scan only the installed package directory; Syft has no project context here.
```command
syft node_modules/trace-route-package
```
```output
No packages discovered
```

Scan the whole project; with package.json and the lockfile present Syft identifies both packages.
```command
syft dir:.
```
```output
NAME                     VERSION  TYPE
node-prepack-trace-lab   1.0.0    npm
trace-route-package      1.0.0    npm
```
Same package, 0 or 2 results depending on scan context.

#### Runtime

Start the Node app detached on port 8083.
```command
./scripts/run.sh
```
```output
Runtime started as PID <pid>
Open:   http://localhost:8083/
Health: http://localhost:8083/health
Trace:  http://localhost:8083/hidden/prepack-info
```

Route served by the prepack-generated dist/index.js.
```command
curl -sS http://localhost:8083/hidden/prepack-info | jq
```

Control endpoint defined in the app's own source.
```command
curl -sS http://localhost:8083/health | jq
```

Stop the app using the saved PID.
```command
./scripts/stop.sh
```

Re-run the lab and assert every outcome above still holds.
```command
./scripts/proof-check.sh
```

Stop the app if running, then remove all generated and installed state.
```command
./scripts/clean.sh
```
Prepack-info returns the same JSON as `prepack-evidence.json`. Health returns `{"application": "node-prepack-trace-lab", "status": "UP"}`.

Related: `malicious-variant/` (used by investigation T08) builds two tarballs. Case A hides the payload in the prepack script that never ships. Case B writes the payload into the shipped `dist/index.js`.

---

## S03 — Python PEP 517: the build backend writes the package

**Proving:** The sdist is not the software. It is a program that builds the software on your machine.

Tracked components: `reportkit` (direct) → `tracehook-demo` (transitive sdist with its own build backend).
Needs: Python 3.11+, `curl`, `tar`, `unzip`. `jq` optional. Fixtures are local, no PyPI access needed.

```command
cd scenarios/S03-python-pep517
```

Remove the venv and previous evidence so the install below is a fresh one.
```command
./scripts/clean.sh
```

The only thing the application declares.
```command
cat requirements.txt
```
```output
reportkit==1.0.0
```

Read the direct package's metadata to find its transitive requirement.
```command
unzip -p python-repo/reportkit-1.0.0-py3-none-any.whl \
  reportkit-1.0.0.dist-info/METADATA
```
```output
Name: reportkit
Version: 1.0.0
Requires-Dist: tracehook-demo==1.0.0
```

List the transitive source distribution: two files, no package code.
```command
tar -tzf python-repo/tracehook_demo-1.0.0.tar.gz
```
```output
tracehook_demo-1.0.0/pyproject.toml
tracehook_demo-1.0.0/tracehook_backend.py
```
No `__init__.py`, no `build-hook.json`. The sdist has no package code.

Read the build-system declaration: the sdist names its own local module as the PEP 517 backend.
```command
tar -xOzf python-repo/tracehook_demo-1.0.0.tar.gz \
  tracehook_demo-1.0.0/pyproject.toml
```
```toml
[build-system]
requires = []
build-backend = "tracehook_backend"
backend-path = ["."]
```

#### Install and watch the backend run

Create .venv and pip install from the local repo; pip runs the backend to build the wheel.
```command
./scripts/build.sh
```
```output
  Building wheel for tracehook-demo (pyproject.toml): finished with status 'done'
Successfully built tracehook-demo
Successfully installed reportkit-1.0.0 tracehook-demo-1.0.0
```
Full log in `trace-output/pip-install.log`.

Compare the one-line requirements file with what actually got installed.
```command
.venv/bin/python -m pip freeze
```
```output
reportkit==1.0.0
tracehook-demo==1.0.0
```

Look for the two files that were not in the sdist; they now exist in site-packages.
```command
find .venv \( -path '*site-packages/tracehook_demo/__init__.py' -o \
  -path '*site-packages/tracehook_demo/build-hook.json' \) -print
```
```output
.venv/lib/python3.x/site-packages/tracehook_demo/__init__.py
.venv/lib/python3.x/site-packages/tracehook_demo/build-hook.json
```
Both files exist now. Neither was in the sdist.

Read the marker the backend wrote while building the wheel.
```command
find .venv -path '*site-packages/tracehook_demo/build-hook.json' \
  -exec cat {} \;
```
```json
{
  "event": "pep517-build-backend-executed",
  "generatedBy": "tracehook_backend.build_wheel",
  "package": "tracehook-demo",
  "version": "1.0.0"
}
```

#### Runtime

Import the direct dependency and show it returns the backend-generated content.
```command
.venv/bin/python -c \
  'import reportkit; print(reportkit.runtime_trace())'
```
Prints the same dict, `'event': 'pep517-build-backend-executed'`.

Start the small HTTP app detached on port 8081.
```command
./scripts/run.sh
```
```output
Runtime started as PID <pid>
Open:  http://localhost:8081/
Trace: http://localhost:8081/trace
```

Fetch the trace endpoint; the generated content is now runtime behaviour.
```command
curl -sS http://localhost:8081/trace | jq
```
Same JSON as `build-hook.json` above.

Stop the app using the saved PID.
```command
./scripts/stop.sh
```

Replay the declaration, sdist, backend and installed-marker steps non-interactively.
```command
./scripts/trace-python.sh
```

Re-run the lab and assert every outcome above still holds.
```command
./scripts/proof-check.sh       # flags: --quick, --skip-build, \
  --skip-runtime
```

Stop the app if running, then remove .venv/ and trace-output/.
```command
./scripts/clean.sh
```

---

## S02 — Payara + mvnpm: plugin-realm dependency reaches the browser

**Proving:** One ordinary enterprise build losing component identity three times: packaging, plugin realm, registry translation.

Tracked components: `commons-lang3` (ordinary), `lodash-es` (mvnpm, plugin realm only), `jakarta.jakartaee-web-api` (`provided`), the container's own software.
Needs: JDK 21+, Maven, Docker. Syft and `jq` for the SBOM steps.

```command
cd scenarios/S02-payara-mvnpm
```

Start from nothing: drop previous evidence and Maven output.
```command
rm -rf trace-output && mvn clean
```

mvn clean package: esbuild bundles lodash-es into assets/app.js, then the WAR is assembled.
```command
./scripts/build.sh
```

Confirm the WAR exists and the generated browser bundle was produced.
```command
ls -lh target/payara-mvnpm-trace-lab-1.0.0.war
find target/generated-web -maxdepth 2 -type f -print
```
```output
target/generated-web/assets/app.js.map
target/generated-web/assets/app.js
```

#### Three Maven dependency domains

Ordinary application dependency: appears in the project tree as expected.
```command
mvn dependency:tree -Dincludes=org.apache.commons:commons-lang3
```
```output
[INFO] \- org.apache.commons:commons-lang3:jar:3.18.0:compile
```

lodash-es is a plugin dependency, not a project dependency, so the project tree shows nothing.
```command
mvn dependency:tree -Dincludes=org.mvnpm:lodash-es
```
Nothing under the project. `BUILD SUCCESS` only.

Ask Maven what it resolved for the esbuild plugin; the plugin's own extra dependencies are still not listed.
```command
mvn dependency:resolve-plugins \
  -DincludeArtifactIds=esbuild-maven-plugin
```
Lists `io.mvnpm:esbuild-maven-plugin:maven-plugin:2.0.0` and its jars. lodash-es is still not listed.

Debug-level Maven output shows the real plugin class realm, where lodash-es finally appears.
```command
mvn -X generate-resources 2>&1 | grep 'org.mvnpm:lodash-es'
```
```output
[DEBUG]    org.mvnpm:lodash-es:jar:4.17.21:runtime
[DEBUG]   Included: org.mvnpm:lodash-es:jar:4.17.21
```
Only the plugin execution realm shows it.

#### lodash-es is in the bundle but not identifiable

The source map lists every lodash-es module esbuild pulled into app.js.
```command
jq -r '.sources[]' target/generated-web/assets/app.js.map | grep \
  'lodash'
```
32 lines like `../../../../node_modules/lodash-es/_freeGlobal.js`.

Scan the generated bundle as an artefact; no package metadata survives bundling.
```command
syft target/generated-web
```
```output
No packages discovered
```

#### WAR boundary

Show both tracked components physically inside the WAR: the jar under WEB-INF/lib and the bundle under assets/.
```command
unzip -l target/payara-mvnpm-trace-lab-1.0.0.war | grep -E \
  'WEB-INF/lib/commons-lang3|assets/app\.js'
```
```output
702952  ...   WEB-INF/lib/commons-lang3-3.18.0.jar
 44987  ...   assets/app.js.map
  8110  ...   assets/app.js
```

Scan the WAR; only the Java jar is identifiable, the bundled JS is not.
```command
syft target/payara-mvnpm-trace-lab-1.0.0.war
```
```output
commons-lang3             3.18.0   java-archive
payara-mvnpm-trace-lab    1.0.0    java-archive
```

Show the WAR deliberately omits the Jakarta EE API jar (provided by the server).
```command
unzip -l target/payara-mvnpm-trace-lab-1.0.0.war | grep \
  'WEB-INF/lib/'
```

Confirm the API is declared with provided scope, which is why it is absent from the WAR.
```command
mvn dependency:tree \
  -Dincludes=jakarta.platform:jakarta.jakartaee-web-api
```
First lists only `commons-lang3-3.18.0.jar`. Second shows `jakarta.jakartaee-web-api:jar:11.0.0:provided`.

#### Two CycloneDX SBOMs

Generate a CycloneDX SBOM from the Maven model and pull out the three tracked components.
```command
mvn org.cyclonedx:cyclonedx-maven-plugin:2.9.3:makeBom \
  -DoutputFormat=json
jq -r '.components[] | [.name, .version, (.scope // "-")] | @tsv' \
  target/bom.json \
  | grep -E 'commons-lang3|jakarta.jakartaee-web-api|lodash-es'
```
```output
jakarta.jakartaee-web-api    11.0.0    required
commons-lang3                3.18.0    required
```
27 components. `provided` became `required`. lodash-es absent.

Generate a CycloneDX SBOM from the WAR's bytes and pull out the same tracked components.
```command
mkdir -p trace-output
syft target/payara-mvnpm-trace-lab-1.0.0.war -o \
  cyclonedx-json=trace-output/war-syft.cdx.json
jq -r '.components[] | [.name, .version, (.scope // "-")] | @tsv' \
  trace-output/war-syft.cdx.json \
  | grep -E 'commons-lang3|jakarta|lodash-es|payara-mvnpm'
```
```output
commons-lang3            3.18.0    -
payara-mvnpm-trace-lab   1.0.0     -
```
The Jakarta API disappears and lodash-es never appears. Maven `provided` ≠ CycloneDX `required` ≠ physical presence.

#### Runtime and container

Build the Payara image with the WAR and start it detached on port 8080.
```command
./scripts/run.sh
```

Call the deployed app to prove commons-lang3 is executing inside Payara.
```command
curl -sS \
  'http://localhost:8080/trace/api/info?name=runtime%20trace' | jq
```
```json
{
  "message": "Hello Runtime trace",
  "application": "payara-mvnpm-trace-lab",
  "javaLibrary": "commons-lang3",
  "server": "Payara"
}
```

Scan the whole container image: Payara, the JDK and OS packages join the inventory.
```command
syft payara-mvnpm-trace-lab:local
```
589 packages, 825 executables. Includes `commons-lang3 3.18.0`, `payara-api 7.2026.7`, `zulu21-jre 21.0.11-3 deb`. Still no lodash-es.

Remove the running Payara container.
```command
./scripts/stop.sh
```

Replay the dependency-domain and WAR evidence steps non-interactively.
```command
./scripts/trace-mvnpm.sh
```

Build the image and write its Syft CycloneDX SBOM to trace-output/image.cdx.json.
```command
./scripts/image-trace.sh
```

Re-run the lab and assert every outcome above still holds.
```command
./scripts/proof-check.sh    # flags: --quick, --skip-build, \
  --skip-runtime, --skip-image
```

Remove target/ and trace-output/.
```command
./scripts/clean.sh
```

---

## T01 — Snyk beyond the SBOM

**Proving:** A commercial scanner against S04 ground truth. Analysis cannot reconstruct evidence the build never produced.

Question: what does a commercial SCA tool know that an SBOM does not, and which transformations stay invisible even to it?
Needs: Maven 3.9+, JDK 21+, `jq`, Syft, and an authenticated Snyk CLI. S01 to S05 built.

```command
cd investigations/T01-snyk-beyond-sbom
```

Log in once; every run snyk script should start by recording `snyk --version`.
```command
snyk auth
```

#### S04, the live demo

Capture Maven's dependency tree, plugin resolution, plugin ClassRealm, CycloneDX and a Syft JAR scan. Writes results/baseline/.
```command
./scripts/baseline.sh
```
```output
Maven application dependency tree:  application only
Maven CycloneDX:                    0 dependency components
Syft final-JAR scan:                application archive only
Included: dev.noregressions.trace:trace-injector-maven-plugin:jar:1.0.0
Included: dev.noregressions.trace:trace-route-payload:jar:1.0.0
```

Five Snyk views: Maven test, test + --include-provenance, CycloneDX SBOM, SBOM + provenance, unmanaged JAR. Writes results/snyk/.
```command
./scripts/run-snyk.sh
```
Snyk Maven test identifies the application only. The plugin and payload are absent. Provenance adds a PURL to the root artefact and nothing else. The unmanaged JAR scan reports:
```text
unknown
```

Grep every baseline and Snyk file for the plugin, payload and app names, then print the five discussion prompts.
```command
./scripts/compare.sh
```
```output
Interpretation questions:
  1. Does normal Snyk Maven analysis expose plugin or payload?
  2. Does Snyk's SBOM expose either?
  3. Does --include-provenance change the visible evidence?
  4. Can unmanaged JAR analysis identify anything useful?
  5. Which S04 ground-truth facts remain visible only in Maven's plugin domain?
```

#### S01, S02, S03, S05 reference runs

S01: Maven reactor, npm, bundle, and unmanaged JAR views. Also builds an isolated Maven repo for provenance mode.
```command
./scripts/baseline-s01.sh && ./scripts/run-snyk-s01.sh && \
  ./scripts/compare-s01.sh
```

S02: Maven test with/without provenance, CycloneDX, unmanaged WAR, unpacked WAR.
```command
./scripts/baseline-s02.sh && ./scripts/run-snyk-s02.sh && \
  ./scripts/compare-s02.sh
```

S03: pip test, pip CycloneDX, then project discovery on the sdist, wheel and site-packages.
```command
./scripts/baseline-s03.sh && ./scripts/run-snyk-s03.sh && \
  ./scripts/compare-s03.sh
```

S05: npm test, npm CycloneDX, then project scans of source, unpacked tarball and installed package.
```command
./scripts/baseline-s05.sh && ./scripts/run-snyk-s05.sh && \
  ./scripts/compare-s05.sh
```

What each shows:

- **S01.** Maven scan finds `commons-codec 1.17.1` under normalizer and `1.18.0` plus `jackson-databind 2.19.4` under service. `--include-provenance` keeps the same set and adds `?checksum=sha1:...` to each PURL. npm scan finds `lodash 4.17.21`; scanning `frontend/dist` returns `No supported files found`. Unmanaged scans of the shaded JAR, stripped JAR and Boot JAR all return `unknown`. After unpacking, Snyk recovers `commons-codec 1.18.0` and `jackson-databind 2.19.4` but never the shaded 1.17.1, even with its Maven metadata intact where Syft succeeds.
- **S02.** Maven scan finds `commons-lang3 3.18.0` and the Jakarta `provided` dependencies, not `lodash-es`. Provenance mode checksum-qualifies the Jakarta artefacts even though they never ship in the WAR. Whole WAR is `unknown custom WAR`. Unpacked WAR recovers commons-lang3; lodash-es is not identified at any boundary.
- **S03.** pip graph shows `reportkit 1.0.0 → tracehook-demo 1.0.0`, an edge `requirements.txt` never states. No Snyk output mentions `tracehook_backend`, `build_wheel` or `pep517-build-backend-executed`. The sdist, wheel and site-packages are not supported projects on their own.
- **S05.** npm scan shows `node-prepack-trace-lab 1.0.0 → trace-route-package 1.0.0`. Source, unpacked tarball and installed package all scan because each has `package.json`. No output mentions `generate-dist.js`, `npm-prepack-generated` or `/hidden/prepack-info`.

Assert 34 claims against the results/ tree written by the five triplets above.
```command
./scripts/proof-check.sh
```

Remove the whole results/ tree. Prints: T01 results removed.
```command
./scripts/clean.sh
```
```output
T01 proof check
===============
PASS  S01 Maven normalizer resolves codec 1.17.1
PASS  S01 bundled frontend has no supported Snyk project
PASS  S03 Snyk recovers transitive tracehook-demo
PASS  S04 Snyk Maven scan omits plugin payload
PASS  S05 Snyk dependency result omits generator
...
Passed: 34
Failed: 0
```

Takeaway: better package identity ≠ complete supply-chain history. Capture evidence when the transformation happens; a later scanner cannot reconstruct what the build discarded.

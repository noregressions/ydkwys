---
id: t09-three-scanners-s01
oneliner: "Three vulnerability scanners, one project, the same seven boundaries: they agree almost everywhere, and the three places they don't are three different kinds of failure."
track: core
---

# T09 — Three Scanners, One Target

Captured 2026-09-08 with grype 0.118.0, trivy 0.74.0 and osv-scanner 2.3.8
(v2 CLI). Counts drift as databases update; the identity findings should not.

## The question

Every other investigation in this workshop asks one tool what it can see.
This one asks three tools the same question at the same moment and reads the
difference.

> Point Grype, Trivy and OSV-Scanner at the same six boundaries of the same
> project. Where do they agree, where do they disagree, and is the
> disagreement about what they can *analyse* or about what they can *look
> up*?

That distinction is the whole investigation. A tool can miss a component
because it could not identify it, or it can identify it
perfectly and still report nothing, because the database it joins against has
no record. Those two failures look identical in a dashboard and have
completely different remedies.

## The instruments

Three free CLI scanners, no account required, (deliberately chosen to differ) :

| Tool | Identity method | Advisory source |
|---|---|---|
| **Grype** | Syft's cataloguers — file and archive inspection | Grype's own aggregated DB (NVD, GHSA, distro feeds) |
| **Trivy** | Its own analysers, per target type | Trivy DB (NVD, GHSA, distro feeds, vendor sources) |
| **OSV-Scanner** | Lockfiles and package manifests, PURL-first | osv.dev only |

Grype and Trivy overlap heavily in method and diverge in data. OSV-Scanner
diverges in both: it is PURL-native, has no CPE matching, and queries a single
open database. Three tools, two different kinds of difference.

Record the exact versions, they change weekly:

```text
captured:     2026-09-08T19:18:44Z
grype:        0.118.0  (build 2026-08-27)
trivy:        0.74.0
osv-scanner:  2.3.8    (v2 CLI form)
```

## The target

S01, because its component states are already known independently of any scanner

```text
jackson-databind 2.19.4   ordinary Maven dependency, shipped intact
commons-codec 1.18.0      service-selected, shipped intact
commons-codec 1.17.1      shaded into normalizer and relocated;
                          Maven identity metadata still present
lodash 4.17.21            bundled by Vite; npm package boundary gone
normalizer 1.0.0          local application library
```

Plus one controlled variant: `normalizer-no-codec-metadata.jar` removes only
`META-INF/maven/commons-codec/commons-codec/*` and changes **no bytecode**.

Any tool whose answer differs between the two JARs is reading metadata. Any
tool whose answer is unchanged is either reading code or ignoring both.

## The boundaries

The same seven targets, for every tool:

| Boundary | What it represents |
|---|---|
| `service-pom` | The resolver's model, before anything is built |
| `frontend-lock` | The npm lockfile, likewise |
| `normalizer-jar` | Shaded archive, identity metadata intact |
| `normalizer-stripped-jar` | Same bytecode, identity metadata removed |
| `service-jar` | The Spring Boot fat JAR that actually ships |
| `frontend-dist` | The built browser bundle |
| `container-image` | The final image, which should be the superset |

Each tool gets whatever invocation makes it work on that target — `fs` vs
`rootfs` vs `image`, staged directories for bare JARs. 

## Run

```command
cd investigations/T09-three-scanners-s01
./scripts/capture.sh             # preflight, then all three stages in order
```

Or the stages individually, if one of them needs re-running:

```command
./scripts/baseline-s01.sh        # build S01, strip the variant, record ground truth
./scripts/run-scanners-s01.sh    # all three tools, all seven boundaries
./scripts/compare-s01.sh         # the matrix — this is what gets pasted below
```

Any tool that is not installed is skipped with a note.

`./scripts/proof-check.sh` asserts the structural claims afterwards, and `./scripts/clean.sh` removes `results/`.

---

All three tools, independently, report vulnerabilities against
`lodash@4.17.21`:

```text
grype   GHSA-f23m-r3pf-42rh  GHSA-r5fr-rjxr-66jc  GHSA-xxjr-mmjv-4gpg
osv     GHSA-f23m-r3pf-42rh  GHSA-r5fr-rjxr-66jc  GHSA-xxjr-mmjv-4gpg
trivy   CVE-2025-13465       CVE-2026-2950        CVE-2026-4800
```

After alias resolution that is **two distinct defects**, agreed by all three:
a prototype pollution issue in `_.unset` / `_.omit` (the first and third IDs in
each row are aliases of one another) and a code injection issue via
`_.template`.


---

# Probe 1 — the control

## Question

Do all three tools name `jackson-databind` where it is present as an ordinary,
untransformed dependency?

## Expectation

Yes, everywhere it appears. If a tool misses the control, the probe is
misconfigured and nothing downstream of it can be trusted.

## Observed

```output
jackson-databind
  boundary                    grype  trivy    osv
  service-pom                     .    YES    YES
  frontend-lock                   .      .      .
  normalizer-jar                  .      .      .
  normalizer-stripped-jar         .      .      .
  service-jar                   YES    YES      .
  frontend-dist                   .      .      .
  container-image               YES    YES    YES

  YES = named   . = scanned, nothing named   - = probe did not run
```

## Verdict

The control holds: every tool names `jackson-databind` somewhere, so no probe
is misconfigured and the rest of the matrix can be read.

It is worth noticing *where* each one names it, because the three columns are
already different. Trivy names it at the source manifest and everywhere
downstream. Grype names it only once it is a physical JAR — reading
`service/pom.xml`, grype has nothing to say, because `jackson-databind` is
never declared there; it arrives through the Spring Boot BOM. OSV names it at
the manifest and in the image but not in the fat JAR, which it has no analyser
for.

Three tools, three different ideas of which artefacts are worth reading. None
of them is wrong. If you run one, you have chosen one of these shapes without
knowing..

---

# Probe 2 — the metadata differential

## Question

`normalizer-jar` and `normalizer-stripped-jar` contain identical relocated
`commons-codec` bytecode. Only `META-INF/maven/...` differs. Which tools
change their answer?

## Expectation

A prediction, to be tested rather than assumed: tools that identify Java
components from embedded Maven metadata should name `commons-codec` in the
intact JAR and lose it in the stripped one. A tool that names it in neither
was never reading the archive that way. A tool that names it in **both** would
be genuinely interesting — it would mean identity was recovered from something
other than the metadata.

## Observed

```output
commons-codec
  boundary                    grype  trivy    osv
  normalizer-jar                YES    YES      .
  normalizer-stripped-jar         .      .      .
```

## Verdict

Unambiguous, and the sharpest result in the investigation.

| Tool | Intact JAR | Stripped JAR | Reading |
|---|---|---|---|
| grype | names it | loses it | **metadata** |
| trivy | names it | loses it | **metadata** |
| osv-scanner | never named it | never named it | neither — no Java-archive analyser |

The two tools that could see `commons-codec` both stopped seeing it when
`META-INF/maven/commons-codec/commons-codec/` was deleted. **No bytecode
changed.** The relocated codec classes are byte-for-byte identical in both
JARs, and the code still executes in the running application.

So the answer to "can a scanner find a shaded dependency" is: only while the
metadata survives the build. Both tools are matching on embedded package
metadata, and metadata is the thing a build transformation is most likely to
discard — for perfectly ordinary reasons, with no attacker involved.

OSV-Scanner's row is a different fact and not a worse one: it declines to
analyse a bare JAR at all. It is a lockfile-and-manifest scanner. It ran, it
catalogued nothing, and it said so.

---

# Probe 3 — same package, different answers

## Question

Where two tools both identify the same package at the same version, do they
report the same vulnerabilities?

## Expectation

Not entirely. Identity is the joint they share; the advisory database is not.
Divergence here cannot be explained by analysis capability — both tools
extracted the same identity — so whatever differs is upstream, in the data.
This is the probe that separates "the scanner missed it" from "the record did
not exist in that database".

## Observed

Raw counts first:

```output
  boundary                    grype  trivy    osv
  service-pom                     0      5      0
  frontend-lock                   3      3      3
  normalizer-jar                  0      0      0
  normalizer-stripped-jar         0      0      0
  service-jar                     5      5      -
  frontend-dist                   0      0      0
  container-image                 5      5      5
```

At `service-jar`, the two tools that ran both reported five. They do not share
a single identifier:

```text
trivy    CVE-2026-54512  CVE-2026-54513  CVE-2026-54514  CVE-2026-54515  CVE-2026-59888
grype    GHSA-3pjw-73gf-8qr5  GHSA-5jmj-h7xm-6q6v  GHSA-hgj6-7826-r7m5
         GHSA-j3rv-43j4-c7qm  GHSA-rmj7-2vxq-3g9f
```

Resolving aliases — grype publishes `relatedVulnerabilities`, osv-scanner
publishes `aliases` — collapses that into the truth:

```text
  service-jar        5 distinct defects; 5 reported by both
  container-image    5 distinct defects; 5 reported by all three
  frontend-lock      2 distinct defects; 2 reported by all three
  service-pom        5 distinct defects; 0 reported by all three
```

## Verdict

Two findings here, and the first one nearly hid the second.

**The identifier scheme is not the data.** Ten IDs at `service-jar` looked
like ten findings and two disagreeing tools. They are five defects, and the
tools agree completely. Trivy reports CVE identifiers; grype and OSV report
GHSA identifiers for the same records. Any comparison that counts identifiers
— including the first version of this investigation's own comparison script —
manufactures a disagreement out of a naming convention. Note also
`frontend-lock`: three IDs, two defects, because two of the lodash GHSAs are
aliases of each other. **A count of findings is not a count of defects**, and
no dashboard in common use makes that distinction.

**The one real disagreement is at the source manifest**, and it is a genuine
three-way split on the same file:

- **Trivy: 5.** It resolves the Spring Boot BOM, gets `jackson-databind`
  at 2.19.4, and matches.
- **Grype: 0.** It never names `jackson-databind` at that boundary at all
  (probe 1). Nothing to match, so nothing found.
- **OSV-Scanner: 0 — and this is the interesting one.** It *did* name the
  package. It just had no version for it:

```text
com.fasterxml.jackson.core:jackson-databind        Maven
org.springframework.boot:spring-boot-starter-test  Maven
org.springframework.boot:spring-boot-starter-web   Maven
```

The version column is empty, because `service/pom.xml` declares the dependency
without one — the version is managed by the BOM. From the container image, the
same tool reports `jackson-databind 2.19.4` and finds all five.

**Identity without a version is not identity.** It is a name, and a name
cannot be joined against a version range. This is a third failure mode,
distinct from the two the investigation was built to show: not "the tool could
not identify it", and not "the database had no record", but "the tool
identified it and had nothing to join on". On a dashboard it renders exactly
like the other two: green.

---

# Probe 4 — the bundle and the image

## Question

Two boundaries where Part 2 already told us the answer: does any tool name
`lodash` in `frontend-dist`, where it is present as code but not as a package?
And is `container-image` the superset of everything below it?

## Expectation

`frontend-dist`: no tool should name it. The npm package boundary was
dissolved by the bundler; there is no manifest, no metadata, nothing to match
— only minified code that happens to be lodash. If a tool *does* name it,
find out how, because that is a capability the others lack.

`container-image`: it should contain at least what `service-jar` contains.
Whether it does depends on how each tool treats an application archive inside
an image layer, which is not the same question as how it treats that archive
on disk.

## Observed

```output
lodash
  boundary                    grype  trivy    osv
  service-pom                     .      .      .
  frontend-lock                 YES    YES    YES
  service-jar                     .      .      .
  frontend-dist                   .      .      .
  container-image                 .      .      .

container-image (all four tracked components)
  jackson-databind              YES    YES    YES
  commons-codec                 YES    YES    YES
  normalizer                    YES    YES    YES
  lodash                          .      .      .
```

## Verdict

**The bundle behaved exactly as Part 2 predicted, for all three tools.**
`lodash` is named in `frontend-lock`, where it is a declared npm package, by
every tool. It is named by nobody in `frontend-dist`, where it is present as
executing code inside a Vite bundle. Nothing was hidden and nobody was
attacked; a standard front-end build dissolved the package boundary, and with
it every tool's ability to say the component is there.

**The image is a superset of the Java boundaries and a subset of the whole
truth.** All three tools name all three Java tracked components in the image, including
OSV-Scanner, which could not read the fat JAR on disk but reads the image
happily. That is a useful practical point: the image is the single most
productive target of the seven, and scanning it is the cheapest way to get all
three tools agreeing.

It is also where `lodash` disappears for good. The bundled JavaScript is in
that image. Nothing reports it. If the image is the only thing you scan — and
for most organisations it is — the front-end half of the application is
outside your inventory entirely.

---

# What this investigation establishes

1. **On identity.** Grype and Trivy both read embedded package metadata, and
   both lose a component the moment a build discards it — proven by two JARs
   with identical bytecode and one deleted directory. OSV-Scanner reads
   lockfiles and manifests and declines bare archives entirely. Every tool
   named every tracked component that still carried metadata, and no tool named `lodash`
   once the bundler had dissolved its package boundary. On identity, the three
   tools differ in *which artefacts they will read*, not in how well they read
   them.

2. **On data.** Where two tools identified the same component at the same
   version, they agreed on the defects — every time. Ten identifiers at
   `service-jar` and five at `container-image` resolved to five defects with no
   genuine disagreement. The apparent divergence was Trivy naming records by
   CVE while Grype and OSV name them by GHSA.

3. **On the difference between the two.** The only real disagreement was at
   the source manifest, and all three tools failed there for *different*
   reasons: Trivy succeeded, Grype never identified the component, and
   OSV-Scanner identified it with no version and so had nothing to join
   against. Three green-looking outcomes, three unrelated causes, one file.
   You cannot see that with one tool, and you cannot see it from a count.

The structural claim the workshop makes, and which these results support:

```text
Agreement between scanners is weak evidence. Disagreement is information:
it tells you whether the gap is in the analysis or in the database, and
those have different fixes.
```

With one amendment this run earned. There is a third thing the gap can be:
**the identity was extracted but was incomplete**. A name without a version
matches nothing, reports clean, and is indistinguishable from safety unless
you look at what the tool actually catalogued rather than what it found.

---

# Re-running this

```command
./scripts/capture.sh          # all three stages
./scripts/proof-check.sh      # 13 PASS / 0 FAIL at capture time
```

A single tool can be re-run without redoing the others:

```command
./scripts/run-scanners-s01.sh grype
./scripts/compare-s01.sh
```

Vulnerability counts drift as databases update, so the capture date is
recorded beside them at the top of this chapter. The identity findings — who
could name what, at which boundary — should be stable. If they are not, that
is itself the finding, and `proof-check.sh` is what tells you.

## Three bugs this investigation found in itself

Worth recording, because each one produced a plausible, publishable, wrong
result, and each is a mistake anyone comparing scanners will make:

1. **Grype's JSON has no package catalogue.** It reports `matches` only. The
   first version of this comparison derived identity from it, and Grype
   appeared unable to name anything it had not also found a vulnerability for
   — a claim about an output format, presented as a capability gap. Identity
   now comes from a second `cyclonedx-json` pass.

2. **The tools disagree about how to write a Maven name.** Grype prints
   `jackson-databind`; Trivy and OSV-Scanner print
   `com.fasterxml.jackson.core:jackson-databind`. An anchored string match
   scored `commons-codec` (whose groupId and artifactId are identical) as
   found and `jackson-databind` as missing, in the same file. The comparison
   now matches on the artifact segment.

3. **Comparing identifiers is not comparing findings.** See probe 3. Alias
   resolution turned ten disagreements into zero.

All three inflated the apparent difference between the tools. That is the
direction this kind of error runs in, and it is worth being suspicious of any
scanner comparison — including a vendor's — that does not say how it matched
names and resolved aliases.

---
id: workshop-03-vulnerabilities
oneliner: "The pipeline between software and a finding, every arrow of it a failure point, walked through one real CVE record that kept changing its answers for six years."
track: core
status: draft
---

# Part 3 — What Does a CVE Finding Actually Mean?

Part 2 left you with incomplete inventories. Part 3 asks what happens when
vulnerability data is laid over the top of them — because a scanner finding
is not an observation about your software. It is the end of a long chain of
translations, each performed by different people at different times for
different reasons.

## The pipeline

```text
software -> identity -> package/product mapping -> CVE record
   -> affected versions -> scanner matching -> finding
```

Every arrow is a place the chain can break, and each breaks in its own way:

- **software → identity.** The whole of Part 2. If the artefact carries no
  coordinates, nothing downstream has anything to match on.
- **identity → mapping.** Your PURL says `pkg:maven/...`; the CVE says
  `cpe:2.3:a:apache:tomcat`. Somebody has to decide those are the same thing.
- **mapping → record.** A human writes the record, under time pressure,
  usually with partial knowledge of who else is affected.
- **record → affected versions.** Someone enumerates version ranges. What
  they leave out is invisible: an omitted range does not look like an
  omission, it looks like *not vulnerable*.
- **affected versions → matching.** The scanner joins your extracted
  identity against those ranges. Exact string matching, mostly.
- **matching → finding.** And then someone reads the finding and believes
  it means "this software is vulnerable", when what it means is "these two
  strings joined today".

## The case: Ghostcat (CVE-2020-1938)

Investigation: *T10 — CVE-2020-1938 / Tomcat*. The chapter follows this one.

One real record — the Tomcat AJP flaw, affecting 8.5.0 to 8.5.50 — read end
to end as evidence, from four public APIs. You need `curl` and `jq`; there is
no build and no Docker. On conference wifi, skip the `curl` lines and run the
`jq` against the captured responses in the investigation's `evidence/`
directory. Every observed output in the lesson came from exactly those
captures.

```command
cd investigations/T10-cve-tomcat-85
jq -r '.containers.cna.metrics' evidence/cve-org.json
```

Work the nine steps in the lesson. They take you through the CNA's own
record, what NVD added on top, what a CPE actually is, who else ended up in
the record, the record's own changelog, KEV, and two CVEs that handle
end-of-life branches in opposite ways.

### What you will find

1. **One defect, three severities.** Apache's CNA record calls it
   "Important". NVD scores it 7.5 under CVSS v2 and 9.8 CRITICAL under v3.1.
   All three are live in the ecosystem simultaneously, and your dashboard
   shows whichever one its data source picked.

2. **CPE matching is a breakable string join.** A scanner raises this finding
   only if it extracted vendor `apache`, product `tomcat`, and a version that
   falls in `>= 8.5.0, < 8.5.51`. Rename the artefact, repackage it, embed it,
   or build it yourself, and the join silently fails.

3. **Embedders arrive late.** Of the record's 38 CPE entries, 20 are Oracle
   products that embed Tomcat. They were added **26 months** after initial
   publication. For over two years, a scanner reading NVD had no basis to
   flag those products — not because they were safe, but because nobody had
   written them down yet.

4. **KEV dates are catalogue dates.** CISA catalogued Ghostcat as known
   exploited in March 2022. Public exploit code existed in February 2020.
   The catalogue records when the catalogue learned, not when the exploitation
   started.

5. **EOL branches are handled inconsistently, in both directions.**
   CVE-2020-1938 omits the end-of-life Tomcat 6.x line from its structured
   ranges entirely. CVE-2025-24813 does the opposite: it names EOL 8.5 in
   prose and then applies an unbounded range (`* < 9.0.99`) that sweeps it
   in. Two records, two conventions, one scanner trying to read both.

The conclusion the investigation is built to earn:

```text
A CVE is not a point-in-time fact.
It is a versioned record of an event that keeps evolving.
```

Ghostcat's record has been edited 57 times. A scan you ran in 2021 and the
same scan today are querying different data about the same unchanged
software. Neither result is wrong. Only one of them is current, and the
report does not tell you which.

## The same question, live, on your own project

Investigation: *T09 — Three Scanners, One Target*.

Ghostcat shows the record failing. T09 shows the consequence, on S01, with
three tools running at once:

```command
cd investigations/T09-three-scanners-s01
./scripts/baseline-s01.sh
./scripts/run-scanners-s01.sh
./scripts/compare-s01.sh
```

Grype, Trivy and OSV-Scanner are pointed at the same seven boundaries of the
same build. The comparison separates two failures that look identical on a
dashboard:

- **The tool could not identify the component.** The Part 2 failure. Fixed by
  a different evidence source, not a different scanner.
- **The tool identified it perfectly and found nothing** — because the
  database it queries has no record. Fixed by querying more than one.

The sharpest instrument in it is a pair of JARs with identical bytecode where
only `META-INF/maven/...` differs. Any tool whose answer changes between them
is reading metadata; any tool whose answer does not is reading something else.

The captured run is in the chapter that follows, and its headline is not the
one the lab was designed to produce. Where two tools identified the same
component at the same version, they agreed on the defects every time — the
apparent disagreements were one tool naming records by CVE and another by
GHSA. The single real split was at the source manifest, where all three tools
came back differently for three unrelated reasons, one of which was a tool
that identified the component correctly but with **no version**, and therefore
had nothing to match against.

A name without a version reports clean and looks exactly like safety.

## The research note that follows

Three chapters continue this part. They are the written-up findings of an
investigation into how vulnerability data propagates — or fails to — across
projects, forks and databases.

| Chapter | The question it answers |
|---|---|
| *A CVE Is Not a Software Genealogy System* | Why a CVE record does not propagate a vulnerability, and what does |
| *How Scanners Behave When the Data Is Incomplete* | Three classes of scanner, and how EOL degrades all three |
| *Empirical Comparison — Tomcat and Node.js Across the Public Databases* | Five Tomcat CVEs and one Node CVE across Snyk, GitHub and OSV |

Primary sources for all of it are in the *Vulnerability Data Sources*
appendix; every claim can be checked at source.

## You should now be able to

- Trace a finding backwards to the exact vendor, product and version strings
  it was joined on.
- Explain why a repackaged, renamed or self-built component can be vulnerable
  and clean at the same time.
- Say what a scan result is evidence *of*, and what date that evidence has.

**Next:** so far the failures have been about incomplete data. Part 4 is
about the case where the data is complete, correct, and still tells you
nothing useful — because nobody upstream is looking any more.

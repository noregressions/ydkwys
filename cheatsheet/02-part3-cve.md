---
id: cheatsheet-part3
oneliner: "Part 3 in run order: the Ghostcat record and the three-scanner comparison."
track: reference
---

# Part 3 — What Does a CVE Finding Actually Mean?

---

## T10 — CVE-2020-1938 "Ghostcat": anatomy of an evolving record

**Proving:** One record, four APIs, six years of edits. Offline-safe: run the jq against evidence/.

Question: what had to be true for a scanner to produce a finding from this record, and was that the same in 2020, 2022 and 2026?
Needs: `curl`, `jq`. `NVD_API_KEY` optional, raises rate limits only. No build, no Docker. Offline: skip the `curl` lines and run the `jq` lines against the captured files in `evidence/` (captured 2026-08-24).

```command
cd investigations/T10-cve-tomcat-85
```

Refresh all four captures at once (cve.org, NVD record, NVD history, NVD record for CVE-2025-24813). Prints the capture date to put in evidence/CAPTURED.md.
```command
./scripts/fetch-evidence.sh
```

#### The CNA record

Fetch what Apache, the CNA, actually claimed; everything downstream derives from this.
```command
curl -sS https://cveawg.mitre.org/api/cve/CVE-2020-1938 -o \
  evidence/cve-org.json
```

Who published it and when it was last touched.
```command
jq -r \
  '.cveMetadata | {datePublished, dateUpdated, assignerShortName}' \
  evidence/cve-org.json
```

Which branches the CNA lists as affected.
```command
jq -r \
  '.containers.cna.affected[] | .versions[] | [.version, .status] | @tsv' \
  evidence/cve-org.json
```
```output
"datePublished": "2020-02-24T21:19:18.000Z"
"dateUpdated":   "2025-10-21T23:35:50.835Z"
"assignerShortName": "apache"

Apache Tomcat 9.0.0.M1 to 9.0.0.30    affected
8.5.0 to 8.5.50                       affected
7.0.0 to 7.0.99                       affected
```
Three branches. No Tomcat 6.x, no embedding products. Apache rated it Important.

#### What NVD added

Fetch NVD's enrichment of the same CVE: severity, CWE, CPE configurations.
```command
curl -sS \
  "https://services.nvd.nist.gov/rest/json/cves/2.0?cveId=CVE-2020-1938" \
  -o evidence/nvd.json
```

NVD's own dates and analysis status.
```command
jq -r \
  '.vulnerabilities[0].cve | {published, lastModified, vulnStatus}' \
  evidence/nvd.json
```

The two CVSS scores NVD attached: v3.1 and v2.
```command
jq -r \
  '.vulnerabilities[0].cve.metrics.cvssMetricV31[0].cvssData | {baseScore, baseSeverity}' \
  evidence/nvd.json
jq -r \
  '.vulnerabilities[0].cve.metrics.cvssMetricV2[0].cvssData.baseScore' \
  evidence/nvd.json
```
```output
"published":    "2020-02-24T22:15:12.057"
"lastModified": "2026-06-17T03:02:39.187"
{ "baseScore": 9.8, "baseSeverity": "CRITICAL" }
7.5
```
Three severity claims for one defect: Important, 7.5, 9.8 CRITICAL. Last modified six years after publication.

#### The CPE ranges a finding depends on

Extract the apache:tomcat CPE ranges; a scanner match is a join against exactly these.
```command
jq -r '.vulnerabilities[0].cve.configurations[].nodes[].cpeMatch[]
       | select(.criteria | test("apache:tomcat"))
       | [.criteria, .versionStartIncluding, .versionEndExcluding] \
         | @tsv' evidence/nvd.json
```
```output
cpe:2.3:a:apache:tomcat:*:*:*:*:*:*:*:*    7.0.0    7.0.100
cpe:2.3:a:apache:tomcat:*:*:*:*:*:*:*:*    8.5.0    8.5.51
cpe:2.3:a:apache:tomcat:*:*:*:*:*:*:*:*    9.0.0    9.0.31
```

Count CPE entries by vendor to see who else the record knows embeds Tomcat.
```command
jq -r \
  '[.vulnerabilities[0].cve.configurations[].nodes[].cpeMatch[].criteria
        | split(":")[3]] | group_by(.) | map({(.[0]): length}) | \
          add' evidence/nvd.json
```
```output
{ "apache": 4, "blackberry": 5, "debian": 3, "fedoraproject": 3, "netapp": 2, "opensuse": 1, "oracle": 20 }
```
35 of 38 entries are not apache:tomcat.

#### The record as a changelog

Fetch NVD's full edit history for the CVE.
```command
curl -sS \
  "https://services.nvd.nist.gov/rest/json/cvehistory/2.0?cveId=CVE-2020-1938" \
  -o evidence/nvd-history.json
```

How many edits, then the first few with date, event and number of changed details.
```command
jq -r '.totalResults' evidence/nvd-history.json
jq -r \
  '.cveChanges[].change | [.created[0:10], .eventName, (.details|length)] | @tsv' \
  evidence/nvd-history.json | head -8
```
```output
57

2020-02-25   CVE Modified       2
2020-02-27   Initial Analysis   8
...
```
Key edits: 2022-03-03 KEV added, 2022-04-29 Oracle and Geode CPEs added (26 months late), 2026-06-17 last modified. An Oracle product scanned in March 2022 had no finding; in May 2022 it was CRITICAL.

#### KEV

Read the CISA Known Exploited Vulnerabilities fields NVD embeds.
```command
jq -r \
  '.vulnerabilities[0].cve | {cisaExploitAdd, cisaActionDue, cisaVulnerabilityName}' \
  evidence/nvd.json
```
```output
"cisaExploitAdd": "2022-03-03"
"cisaActionDue":  "2022-03-17"
```
Two years after publication, though proof-of-concept code circulated within days in 2020. KEV dates are catalogue dates.

#### The missing EOL branch

Look for Tomcat 6.x anywhere: CNA versions and the lower bound of every tomcat CPE range.
```command
jq -r '.containers.cna.affected[].versions[].version' \
  evidence/cve-org.json
jq -r '.vulnerabilities[0].cve.configurations[].nodes[].cpeMatch[]
       | select(.criteria | test("apache:tomcat")) | \
         .versionStartIncluding' evidence/nvd.json
```
```output
7.0.0
8.5.0
9.0.0
```
6.x shipped the same AJP connector and went EOL in 2016. It appears nowhere. Scanner silence about EOL software means nobody looked.

#### The named EOL branch, five years later

Fetch a 2025 Tomcat CVE for comparison, where 8.5 is the EOL branch.
```command
curl -sS \
  "https://services.nvd.nist.gov/rest/json/cves/2.0?cveId=CVE-2025-24813" \
  -o evidence/nvd-24813.json
```

Does the prose name the EOL branch?
```command
jq -r '.vulnerabilities[0].cve.descriptions[0].value' \
  evidence/nvd-24813.json | grep -A1 "EOL"
```

Are the CPE ranges bounded below?
```command
jq -r '.vulnerabilities[0].cve.configurations[].nodes[].cpeMatch[]
       | select(.criteria | test("apache:tomcat:\\*"))
       | [(.versionStartIncluding//"UNBOUNDED"), \
         .versionEndExcluding] | @tsv' evidence/nvd-24813.json
```
```output
The following versions were EOL at the time the CVE was created but are
known to be affected: 8.5.0 though 8.5.100.

UNBOUNDED    9.0.99
10.1.1       10.1.35
11.0.1       11.0.3
```
The prose names 8.5; the CPE is unbounded below, so 8.5, 7.0 and 6.x all match, and the "fix" is an upgrade to 9.0.99.

Assert 14 facts about the captured JSON: CNA, dates, scores, ranges, KEV date, edit count, embedding date, EOL handling.
```command
./scripts/proof-check.sh
```
```output
PASS: ...
T10 proof result: 14 passed, 0 failed
RESULT: PASS — the captured evidence still supports LESSON.md.
```

No cleanup. The investigation only reads.

Takeaway: a CVE is a record of an event that keeps evolving, not a point-in-time fact. Every severity number is a producer's claim, a finding is a join against an analyst-typed CPE range, and the record only knows the embeddings someone reported. Silence is the real exposure.

---

## T09 — three scanners, one target (S01)

**Proving:** Grype, Trivy and OSV-Scanner on the same seven boundaries. Identity gaps and database gaps are different failures.

Needs `grype`, `trivy` and `osv-scanner`, plus the S01 prerequisites (JDK 21,
Maven, Node, Docker, jq). Any missing scanner is skipped with a note; two of
three is still a comparison.

Work from the investigation directory.
```command
cd investigations/T09-three-scanners-s01
```

Everything below in one go, with a preflight that refuses rather than producing a half-populated results tree.
```command
./scripts/capture.sh
```

The three stages individually:

Build S01, install the reactor, strip the controlled variant, build the image, record ground truth and the three tool versions.
```command
./scripts/baseline-s01.sh
```

Writes `results/s01/baseline/`. The `mvn install` step matters: S01's own
build only runs `mvn package`, which leaves `normalizer` out of the local
repo, and anything resolving `service/pom.xml` from source then fails on the
missing sibling.

Grype, Trivy and OSV-Scanner across all seven boundaries.
```command
./scripts/run-scanners-s01.sh
```

Writes `results/s01/{grype,trivy,osv}/<boundary>.{json,tracers.txt,vulns.txt}`
for `service-pom`, `frontend-lock`, `normalizer-jar`,
`normalizer-stripped-jar`, `service-jar`, `frontend-dist`, `container-image`.

The comparison. This is the block LESSON.md asks you to paste.
```command
./scripts/compare-s01.sh
```

Prints, and writes to `results/s01/compare/matrix.txt`:

```text
1. IDENTITY      per tracked component per boundary per tool: YES / . / -
2. FINDINGS      how many tracked vulnerabilities each tool reported
3. DISAGREEMENT  CVE IDs one tool reported and another did not
4. THE QUESTIONS seven prompts to read the matrix with
```

Assert the structural claims (control named, differential visible, ...).
```command
./scripts/proof-check.sh
```

Remove results/.
```command
./scripts/clean.sh
```

The sharp instrument is `normalizer-jar` vs `normalizer-stripped-jar`:
identical bytecode, `META-INF/maven/commons-codec/` removed from the second.
Tools whose answer changes are reading metadata.

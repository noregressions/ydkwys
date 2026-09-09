---
id: workshop-04-project-health-eol
oneliner: "Three evidence frameworks that are not CVE data — repository practice, coordinate indexes, and lifecycle/EOL records — and the close of Act 2: three ways the data misleads, on one component."
track: core
status: draft
---

# Part 4 — CVEs Aren't Enough

Part 3 ended with a record that changed its answers for six years. This part
is about the questions that record was never designed to answer at all:

```text
A historical defect record (CVE)  !=  a future maintenance commitment
```

A vulnerability database tells you what has been found and written down. It
does not tell you whether anyone is still looking, still fixing, or still
publishing. For a dependency you are about to ship, that second question is
often the more useful one.

## The subject: `lodash@4.17.21`

A good test case precisely because nothing is obviously wrong with it. Around
71 million npm downloads a week. Version 4.17.21 published February 2021 and
unchanged since. It is in your tree; it is in nearly everyone's tree. We look
at it through three separate evidence frameworks and get three different
pictures — and, as it turns out, a fourth picture depending on *when* you
looked.

## Step 1 — Repository practice (OpenSSF Scorecard)

[OpenSSF Scorecard](https://scorecard.dev) scores a repository's observable
engineering hygiene, automatically.

Evaluate <https://scorecard.dev/viewer/?uri=github.com/lodash/lodash>, or use
the capture in `workshop/evidence/` — every figure in this chapter is captured
there with the date it was taken, and `CAPTURED.md` says how to refresh them.

Aggregate at capture: **7.2 / 10**. The interesting part is not the number,
it is which checks produce it:

- **Maintained: 10/10.** Measures commit and issue activity in the last 90
  days. Commits to the main branch are not releases. A project can score
  perfectly here and not have shipped a consumable artefact in years.
- **Vulnerabilities: 0/10.** An OSV query against the *source repository*.
  Note what that is not: it is not a query about the version you installed.
- **Token-Permissions: 0/10, Pinned-Dependencies: 4/10.** CI/CD hygiene —
  unrestricted `GITHUB_TOKEN`, unpinned actions. These describe the risk of
  a *future* compromise of the release pipeline, which no CVE covers.
- **Signed-Releases, Branch-Protection, Packaging: unknown.** Missing data
  is its own signal; there is no verification path to read.

Scorecard measures how a project is run. It says nothing about whether the
compiled thing in your `node_modules` is safe.

## Step 2 — Coordinate indexing (deps.dev)

A much narrower question than Scorecard's: does an advisory exist against this
exact coordinate?

Open [deps.dev](https://deps.dev/npm/lodash/4.17.21), or query it directly —
it is free and needs no account:

```command
curl -sS https://api.deps.dev/v3/systems/npm/packages/lodash/versions/4.17.21 \
  | jq '{version: .versionKey.version, advisories: [.advisoryKeys[]?.id]}'
```

```output
{
  "version": "4.17.21",
  "advisories": [
    "GHSA-f23m-r3pf-42rh",
    "GHSA-r5fr-rjxr-66jc",
    "GHSA-xxjr-mmjv-4gpg"
  ]
}
```

Three identifiers, and — resolving aliases, as Part 3 taught you to — **two
distinct defects**. The first and third are the same prototype pollution issue
in `_.unset` and `_.omit` under two IDs; the second is a code injection issue
via `_.template`.

Now the part that matters.

### The artefact did not change. The answer did.

`lodash@4.17.21` was published in **February 2021** and has not changed since.
An earlier edition of this chapter queried a different coordinate index,
Sonatype OSS Index, and recorded the result as **zero advisories**. That
capture is in `workshop/evidence/`.

Between that capture and this one:

```text
2021-02   4.17.21 published. Not one byte has changed since.
   ...    clean in every index anyone queried.
2026-01   GHSA-xxjr-mmjv-4gpg published    prototype pollution, _.unset / _.omit
2026-04   GHSA-f23m-r3pf-42rh published    the same defect, second identifier
2026-04   GHSA-r5fr-rjxr-66jc published    code injection via _.template
```

Nothing was discovered about a new version. Something was discovered about a
five-year-old one, and the databases caught up at different times under
different names. Every clean scan run against this package between 2021 and
2026 was accurate on the day and wrong in hindsight — which is the difference
between "not vulnerable" and "not known vulnerable", stated in dates rather
than in the abstract.

Look closely at the third advisory's alias list, too:

```text
GHSA-r5fr-rjxr-66jc   aliases: CVE-2021-23337, CVE-2026-4800, GHSA-35jh-r3h4-6jhm
```

`CVE-2021-23337` is the `_.template` code injection that **4.17.21 was
released to fix**. The record has moved back over a version that never moved.
Part 3 said a CVE is a versioned record of an evolving event; this is that,
landing on a package almost everyone in this room ships.

### And the instrument itself reached end of life

The OSS Index query that produced the original zero cannot be run any more:

```text
https://ossindex.sonatype.org/                    301 -> guide.sonatype.com
POST /api/v3/component-report, unauthenticated    401
```

The free browsable index now redirects to a commercial product, and the API
wants credentials. No announcement reached this repository; the capture simply
stopped being reproducible.

That is worth sitting with, because it is this chapter's subject happening to
this chapter. You are being asked to reason about the support lifecycle of
your dependencies. Your **evidence sources have lifecycles too**, and they end
the same quiet way: not with a notice, but with a redirect.

### What a clean answer is worth

```text
Not vulnerable      nobody can tell you this
Not known          in the database you queried,
  vulnerable        on the day you queried it,
                    using the identity you gave it
```

Which is why the take-home practice in Part 6 says *more than one source*, and
why every answer in it carries a date.

## Step 3 — Lifecycle and EOL

Now the question neither of the above asks: is anyone still committed to
fixing this?

```command
npx @herodevs/cli scan eol --dir .
```

This one is live — there is no captured fallback in the repository, so if the
network is against you, read the results below and move on.

Run against this repository's own dependencies:

| Component | Where it appears | Lifecycle status |
|---|---|---|
| `jackson-databind:2.19.4` | S01 direct dependency | Active upstream maintenance |
| `commons-codec:1.17.1` | S01 shaded dependency | Active upstream maintenance |
| `lodash:4.17.21` | S01 bundled dependency | Superseded — 4.17.23, 4.18.0, 4.18.1 shipped; no published policy |
| `spring-boot:3.5.12` | S01 runtime framework | **OSS support ended 30 June 2026** |
| `apache-tomcat:8.5` | S02 / the Part 3 investigation | **EOL 31 March 2024** |

Three distinct states, and most tooling collapses them into two:

```text
vulnerable            an advisory matched
not known vulnerable  nothing matched in the index queried
unsupported / EOL     nobody upstream is triaging, patching or publishing
```

The third state is the one that matters and the one that renders as green.
When a branch goes end of life, CVE filing against it does not continue at
the previous rate — it largely stops, because the people who would have
filed have moved on to the supported line. **Scanner silence on an EOL
component is evidence about the state of upstream attention, not about the
state of the code.**

`lodash` is the benign version and it is worth saying so plainly: it is being
maintained, the fixes exist, and the answer is simply to upgrade. It earns its
place in this chapter for the *timing* of the advisories, not for neglect.

`spring-boot:3.5.12` and `apache-tomcat:8.5` are the sharp ones. There is no
upgrade inside those lines, because those lines are finished.

## Step 4 — Making lifecycle data machine-readable (OpenEoX)

Support windows today live in blog posts, wiki tables, mailing list threads
and PDFs. That is why lifecycle checks are still a manual step in most
organisations while vulnerability checks are automated.

[OASIS OpenEoX](https://www.oasis-open.org/tc-openeox/) is a technical
committee defining an open schema for publishing end-of-life and
end-of-support records in a form tools can consume. Worth watching: the day
this is widely published is the day the third row of that table becomes
automatable.

---

## Closing Act 2 — three ways the data misleads, one component

This is the synthesis Parts 2, 3 and 4 were built for. Take a single
component — Apache Tomcat 8.5 — and put all three failure modes against it at
once.

**1. Tool capability gap (Part 2).** Tomcat rarely arrives as "Tomcat". It is
embedded in application servers, repackaged into distributions, bundled into
vendor products. Every one of those transformations is a chance for the
identity to be lost — and when it is, no scanner reading the artefact can
raise a Tomcat finding, whatever the CVE record says. Part 3 measured this
from the other end: 20 of Ghostcat's 38 CPE entries are products that embed
Tomcat, and someone had to write each one down by hand.

**2. CVE process failure (Part 3).** For the products in that embedded list,
the entries appeared 26 months after publication. During those 26 months the
software was exactly as vulnerable as it was afterwards, and a scanner
reading NVD would have reported clean. The failure was not in the scanner. It
was upstream of the scanner, in a data-entry backlog.

**3. EOL blind spot (Part 4).** Tomcat 8.5 reached end of life on 31 March
2024. From that date, the flow of new advisories against 8.5 does not reflect
the flow of new defects in the code it shares with 9.0 and 10.1 — it reflects
whether anyone still bothers to file. CVE-2020-1938 had already shown the
pattern in the other direction, omitting the then-EOL 6.x line from its
ranges entirely, despite the vulnerable code being present.

Stack the three and you get the sentence to take home:

```text
A clean scan of an unsupported, repackaged component is three separate
kinds of "we didn't look" wearing one green tick.
```

Everything in Act 3 and Act 4 follows from that. Act 3 is what an attacker
does with it. Act 4 is what you do about it.

## The research note concludes

The three chapters that follow finish the note begun in Part 3.

| Chapter | The question it answers |
|---|---|
| *What Projects Actually Promise About Old Releases* | What major projects say, in their own words, about unsupported releases |
| *Forks, Variants and Embedded Copies* | Where else the vulnerable code lives, and whether anyone checked |
| *Conclusions, and What We Can Defensibly Claim* | The five conclusions, the checklist, and the claims not to overstate |

## You should now be able to

- Name three evidence frameworks that are not vulnerability databases, and
  say what question each answers.
- Explain why a clean coordinate query and a healthy Scorecard can coexist
  with an unsupported component.
- Put a date on any clean result, and say what would have to change for it to
  stop being clean without the artefact changing at all.
- Read scanner silence on an EOL component as an absence of attention rather
  than an absence of defects.

**Next:** everything so far has been accidental — ordinary builds, ordinary
data-entry lag, ordinary abandonment. Part 5 is about the people who do it
on purpose.

## References

- OpenSSF Scorecard checks: <https://github.com/ossf/scorecard/blob/main/docs/checks.md>
- deps.dev: <https://deps.dev>
- OSV: <https://osv.dev>
- Apache Tomcat 8.5 EOL notice: <https://tomcat.apache.org/tomcat-85-eol.html>
- Spring Boot support lifecycle: <https://spring.io/projects/spring-boot#support>
- OASIS OpenEoX Technical Committee: <https://www.oasis-open.org/tc-openeox/>

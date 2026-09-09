---
id: workshop-06-minimum-practice
oneliner: "The short repeatable drill that makes the ship list unsurprising: two inventories, their difference, a lifecycle check, and provenance — run here, then taken home on one card."
track: core
status: draft
---

# Part 6 — The Minimum That Keeps You Honest

Hands-on, and the part you actually use on Monday.

Five parts of this workshop have been about how the picture goes wrong. This
one is the short list of things that keep it approximately right. It is
deliberately small. A heavyweight practice gets adopted once and quietly
abandoned; a lightweight one gets run every release, and the whole value here
is in the repetition.

## The drill

Four questions, asked of every build:

```text
1. What does the resolver say we depend on?          declared inventory
2. What is identifiable in the thing we ship?        shipped inventory
3. Where do those two disagree?                      the gap
4. Is anyone upstream still maintaining any of it?   lifecycle
```

Question 3 is the one nobody asks, and it is the only one that could have
caught anything you saw in Part 2.

Run it now, against a project you have already built:

```command
cd scenarios/S01-spring-node
./scripts/build.sh          # if you have not already
cd ../..
./scripts/ship-check.sh scenarios/S01-spring-node
```

The script is forty lines of shell wrapping tools you already have. Read it —
`scripts/ship-check.sh` — because the point is that you could have written it
and should adapt it. It skips loudly rather than failing quietly when a tool
is missing, and it writes both inventories to `ship-check/` so you can diff
today's against last release's.

What to look at, in order:

- **Section 3, first list — declared but not identifiable.** On S01 this is
  where your shading and bundling show up. Each entry is a component that is
  in your artefact and cannot be matched against any advisory database by
  anything downstream of you.
- **Section 3, second list — in the artefact but not declared.** Point it at
  S04 and this is where the plugin's payload appears. Anything here entered
  your build without passing through your dependency review.
- **Section 4 — lifecycle.** Sorted by "nobody is fixing this any more"
  rather than by CVSS.
- **Section 5 — provenance.** Currently a list of what is missing. S07 is how
  you fill it in.

An empty section 3 is a legitimate and good result. An unexamined section 3
is the state most projects are in.

## Then decide, in this order

Findings without a decision path turn into a backlog nobody reads. Four
outcomes, and every finding gets exactly one:

1. **Upgrade.** The default. Cheapest when it is possible, and it stops being
   possible the moment a component goes end of life — which is the actual
   cost of letting things drift.
2. **Patch in-house.** You can do this. You will then own it forever, and the
   next person to read your dependency tree will have no idea the version
   number is lying to them. Record it somewhere a scanner can see.
3. **Accept, with an expiry date.** A defensible answer when the vulnerable
   path is unreachable. "Accepted" with no date is just "ignored" with better
   paperwork.
4. **Buy support.** For an EOL component you cannot move off, someone else
   maintaining it is a real option — commercially or through the community.
   This is the honest answer to the Part 4 problem when upgrade is off the
   table.

The order matters because each step down costs more to carry and is easier to
forget.

## Take this home

One card. Adapt the commands to your ecosystem; keep the four questions.

```text
EVERY RELEASE
  1. Inventory the artefact, not just the manifest.
     Two SBOMs — one from the resolver, one from the built artefact —
     and diff them. The difference is the part nobody else will tell you.

  2. Scan with more than one source, and read the disagreement.
     Different scanners have different databases, different matching, and
     different blind spots. Agreement is weak evidence; disagreement is
     information.

  3. Check lifecycle separately from vulnerabilities.
     "No known CVEs" and "still supported" are different questions, and
     only one of them is on your dashboard.

  4. Record what BUILT it, not only what ships. A build-aware SBOM (S08)
     costs one plugin and catches what the resolver never saw.

  5. Record provenance at build time, bound to a digest.
     You cannot reconstruct it afterwards. Ask S07.

  6. Give every finding one of four answers, with a date:
     upgrade / patch in-house / accept / buy support.

WHEN CHOOSING SOMETHING NEW
  - OpenSSF Scorecard for how the project is run.
  - deps.dev and OSV for what is known about the coordinates today.
  - A published support policy. If there isn't one, that is the answer.
```

## Where all of it fits

The full picture, with every boundary from Part 2 and every data source from
Parts 3 and 4 in its place:

```text
1. Source declaration       manifests, POMs, package.json
        |
2. Dependency resolution    lockfiles, effective POMs, resolved graphs
        |
3. Build execution          plugin realms, lifecycle hooks, PEP 517 backends
        |
4. Artefact packaging       shaded JARs, bundles, wheels, tarballs
        |
5. Containerisation         base images, OS packages, runtime
        |
6. Provenance               digests, SBOM attestations, signatures
```

And laid over the top of it, four data sources that answer four different
questions and are routinely mistaken for each other:

| Source | Answers | Does not answer |
|---|---|---|
| CVE / NVD / OSV | What has been reported and indexed | What is present but unidentifiable |
| CISA KEV | What is known to be exploited | When exploitation started |
| OpenSSF Scorecard | How the project is run | Whether your version is safe |
| Lifecycle / EOL data | Whether anyone is still fixing it | Whether anything is currently wrong |

## What you should take away

Not that scanners are useless — they are the cheapest security work
available, and you should run more of them, not fewer. The takeaway is
narrower and more useful than that:

```text
Every inventory is evidence from one boundary, produced by one method,
on one date. Treat it as a witness statement, not as the truth.
```

You have spent this workshop finding out what each witness can and cannot
see. The drill above is how you keep asking.

## You should now be able to

- Run a two-inventory diff on your own project and explain every line of the
  difference.
- Say which of the four decisions applies to a finding, and why, with a date.
- Explain to someone who was not here why a green dashboard is a statement
  about a database rather than about their software.

Thank you for working through this. Go and run `ship-check.sh` against
something you actually ship.

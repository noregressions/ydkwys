---
id: front
oneliner: "Welcome to the KCDC 2026 workshop"
track: core
---

# Welcome

You are reading the manual for **You Don't Know What You're Shipping**, a
hands-on workshop given at KCDC 2026 by Steve Poole and Brian Vermeer. The
session runs on **Wednesday 9 September 2026, 8:00 am to 12:00 pm Central
Daylight Time (UTC-05:00)**. This manual is written to be worked through at
the keyboard during the session, and to be worth going back to afterwards,
when you point the same tools at your own projects.

## The session

> Every project has dependencies it knows about. Most have dependencies it
> doesn't.
>
> This session is a guided, demo-and-hands-on tour of the modern dependency
> problem. Using free and free-tier tools and public data, we find what is
> actually in your stack, understand what it is doing, and make an informed
> judgement about whether it should be there at all.
>
> Java, Node, Python, Docker: the techniques apply regardless of what you are
> building.
>
> We use Snyk's free tier and the HeroDevs EOL database to map what you have
> and flag what is past safe support, and coordinate indexes and the OpenSSF
> Scorecard to see whether the project behind a library follows the security
> practices that make future vulnerabilities less likely.
>
> Exploring the CVE process and its data shows how a record does not always
> say what you think it does, and why end-of-life versions are often secretly
> vulnerable. We look at how in-support vulnerability data can signal what is
> lurking in the versions your scanners are not covering.
>
> We also look at how dependencies get hidden: by accident, by design, and
> occasionally by someone who means you harm. We dissect some AI-generated
> malware, show you a few nasty surprises, and explore how easy it is to let
> the bad stuff in.
>
> We wrap up by examining how AI coding tools are quietly making dependency
> trees larger, picking poor libraries, and hallucinating packages that do
> not exist, and how malicious actors have learned to meet those
> hallucinations with real ones.
>
> Some slides. No theory. Demos, tools, and the kind of findings that make
> you want to go back and check your own projects the moment you get home.

## About KCDC

KCDC, the Kansas City Developer Conference, is a community-run conference for
software developers held each year in Kansas City. Its workshop day gives a
topic room to breathe: a laptop, and the space to run things rather than
watch them. This manual is built for that format. Everything in
it is reproducible on your own machine, and every claim points at the command
that produced it.

## What you will leave with

By the end you will have done each of the following yourself, not watched
someone else do it:

- **Traced named components across build boundaries** and seen exactly where
  a dependency stops being identifiable: shading and relocation in Java,
  bundling in JavaScript, plugin execution in Maven, lifecycle hooks in npm,
  build backends in Python.
- **Compared what the resolver says with what the artefact contains**, using
  dependency trees, CycloneDX SBOMs, Syft, and scanners such as Snyk, Trivy,
  Grype and Docker Scout, and learned to read each one as evidence from a
  specific boundary rather than as the truth.
- **Read a real CVE record end to end**, watched it change over six years, and
  worked out what had to be true for a scanner to raise a finding from it on
  any given date.
- **Measured project health beyond CVEs**, with OpenSSF Scorecard, the OSS
  Index and end-of-life data, and seen why a clean vulnerability scan on an
  unsupported component means less than it appears to.
- **Seen where build-time execution lets an attacker in**, how the documented
  incidents actually worked, and how controlled ingress, cache integrity and
  signed provenance close the gap — including an image that can prove where
  it came from.
- **Run the drill you take home**: two inventories of the same build, the
  difference between them, a lifecycle check, and a decision for every
  finding.

The recurring question in every lab is a small one:

```text
is it still identifiable here?
```

The answer, boundary by boundary, is the workshop.

## How it is arranged

The workshop is four acts.

**Act 1 — You can't see what you ship.** Six real builds, six ways a component
you can name stops being identifiable — and one SBOM generator that gets some
of it back.

**Act 2 — The scanner can't either.** What happens when vulnerability data is
laid over an inventory that was already incomplete.

**Act 3 — Someone is counting on that.** The same gaps, used deliberately,
and what actually closes them.

**Act 4 — The minimum that keeps you honest.** The short drill you run every
release, run here first.

```text
Part 1   What is actually in our software?       Act 1
Part 2   Can we identify what we ship?           Act 1   hands-on
Part 3   What does a CVE finding actually mean?  Act 2   guided
Break
Part 4   CVEs aren't enough                      Act 2   guided
Part 5   Someone is counting on that             Act 3   hands-on
Part 6   The minimum that keeps you honest       Act 4   hands-on
```

Part 2 alone is six hands-on labs. Nothing here is optional, so if something
misbehaves on your machine, move on rather than debug it — every lab carries
the output it should have produced, and you can come back to it later.

## How to use this manual

**Start with setup.** Work through *Introduction and Setup*: clone the
repository at <{{ vars.repoUrl }}>, then take one of three routes — install
the tools on your host (`./scripts/tools-check.sh`, then
`./scripts/build-all.sh`), build the workshop container image locally
(`./container/build.sh`), or pull the published one (`./container/run.sh`).
The container has every tool and every build already inside it, which makes it
the quickest way to a working machine; the host route is the one you will
recognise when you point these tools at your own projects. *Getting Started*
has all three, and a good network helps whichever you pick.

**During the session**, work through this manual front to back — it *is* the
route. Each part opens with the commands to run and what you should see, and
is followed by the full lesson for every lab it uses, with every command, its
observed output, and what that output does and does not establish. If you
lose your place after a break, `WORKSHOP.md` in the repository is the same
route on one page.

**Afterwards**, the appendices hold the reference investigations we did not
have time for, one per tool, each asking the same questions of the same
artefacts. They are self-study material, and the
scripts in every lab include a proof check so you can confirm the findings
still hold when you re-run them.

Two conventions run through everything:

- Every lab follows a handful of named dependencies — the **tracked
  components** — from declaration to runtime, so that "the scanner missed it"
  always means a particular thing was missed at a particular boundary.
- Every observed output in this manual was **captured from a real run**, and
  the command that produced it is printed alongside. Versions, counts and
  database dates will drift; the structural findings should not. If one
  does, the proof checks will tell you.

Welcome to KCDC. Let's find out what you're shipping.

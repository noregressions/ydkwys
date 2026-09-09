---
id: workshop-05-attacks-and-provenance
oneliner: "The gaps from Acts 1 and 2 as an attack surface: how code gets in, how it stays invisible, whether a code-reading scanner catches it, and what an artefact needs to prove where it came from."
track: core
status: draft
---

# Part 5 — Someone Is Counting on That

Everything so far has been accidental. Shading strips metadata because that
is what shading does. NVD entries arrive late because a human has to type
them. Branches go quiet because maintainers move on. Nobody meant any harm.

Now assume somebody does. Every gap in Acts 1 and 2 is a property an attacker
can rely on:

| Gap you proved | What it is worth to an attacker |
|---|---|
| Builds execute arbitrary third-party code (S04, S05, S03) | Execution on your build machine, with your credentials |
| Published source ≠ published artefact (S05) | The reviewable thing and the installed thing can differ |
| Identity is lost in transformation (S01) | Code that no scanner can name cannot be matched to an advisory |
| EOL components report clean (Part 4) | A target with no upstream defender and a green dashboard |

None of these is a vulnerability in the sense a CVE describes. They are
properties of how the ecosystem works, and they are exploited by getting your
resolver to fetch the wrong thing.

## Getting in

Three mechanisms account for most of the documented history. None requires a
software defect.

### Dependency confusion

Your organisation has internal packages — `acme-auth-client` — resolved from
an internal registry. That name is unclaimed on the public registry. An
attacker registers it publicly at version `99.0.0`. Now it depends entirely
on your resolver's configuration whether the internal `1.4.2` or the public
`99.0.0` wins, and several ecosystems default to the highest version across
all configured sources.

Alex Birsan demonstrated this at scale in February 2021, getting code
execution inside dozens of major companies purely by registering names their
internal builds asked for. The fix is configuration, not patching: scoped
namespaces, registry pinning, and never letting a public registry answer for
an internal name.

### Typosquatting and name adjacency

Register a name one keystroke or one convention away from a popular package —
a transposed letter, a hyphen where the real package uses a dot, the singular
of a plural. Then wait for a typo, a bad autocomplete, or a copy-paste from a
blog post. Install-time hooks mean the payload runs before anyone opens the
package to look at it, which is the whole point of choosing that ingress.

This is cheap, continuous, and largely automated. Both npm and PyPI remove
such packages routinely; removal happens after publication, which means the
window is never zero.

### Maintainer compromise and handover

The most effective route is the legitimate one. Two documented shapes:

- **Account takeover.** The `ua-parser-js` incident in October 2021: a
  popular package's maintainer account was compromised and malicious versions
  were published under the real name, to the real registry, with the real
  reputation. Everything a consumer could check looked correct.
- **Social engineering of trust.** The `event-stream` incident in 2018: a
  maintainer, burnt out, handed the project to a helpful volunteer who had
  been contributing for months. The volunteer added a dependency that carried
  a payload targeting a specific downstream wallet application.

The `xz-utils` backdoor (CVE-2024-3094, March 2024) is the mature version of
the same play: years of legitimate contribution to earn commit rights,
followed by a backdoor placed **in the release tarball's build scripts but
not in the git repository**. Anyone reading the source on the forge saw clean
code. Anyone building from the released tarball got the backdoor.

Which is exactly the mechanism you built yourself in S05.

## Staying invisible

Look back at the S05 finding with this in mind. `prepack` ran
`generate-dist.js`, and the tarball shipped a `dist/` that exists in no
commit. In S05 the generated output is harmless and the generator is honest.
Change either and nothing else about the shape changes:

```text
source repository  --->  reviewed by humans, scanned by CI, looks clean
       |
       | build-time execution
       v
published artefact --->  installed by everyone, reviewed by nobody
```

The defence is not "read the source". It is to make the artefact, not the
repository, the thing you inspect and the thing you can prove the origin of.
The two labs in this part take those in turn.

## Lab — can a code-reading scanner see it? (T08)

Investigation: *T08 — GuardDog*.

Metadata scanners lost in Part 2 because the metadata was gone. GuardDog
reads the code itself — an AST-level scanner looking for the behaviours
malicious packages exhibit rather than the coordinates they declare. So it is
the fair test of what is recoverable.

Four probes:

1. **The S05 published tarball.** Scores 0.0/10 — clean. Not because the
   scanner is weak, but because `files: ["dist"]` kept the generator script
   out of the tarball. The scanner read everything that shipped; the
   interesting code was not in it.
2. **The S03 source distribution.** Also clean. The PEP 517 backend uses
   entirely standard packaging primitives; there is nothing anomalous to
   find, because generating a package at install time *is* the sanctioned
   behaviour.
3. **The malicious variant, payload in the generator.** Now the rules fire.
4. **The malicious variant, payload in the generated output.** Run this one
   and compare with probe 3 — the difference between the two is the lesson.

**What this proves:** code-level scanning genuinely recovers ground that
metadata scanning cannot, and it is bounded by the same thing everything else
in this workshop is bounded by — what is actually in the artefact you handed
it. A scanner cannot read a file the packaging step excluded.

## Lab — can you prove where it came from? (S07)

Lab: *S07 — Reverse provenance*.

Every part so far asked what is *in* an artefact. This one asks where it
*came from* — which is the question you need answered at 2am when an advisory
lands and you are holding a container image.

```command
cd scenarios/S07-provenance-s01
./scripts/build-baseline.sh
```

Start with S01's finished image and nothing else. Try to answer: which
commit built this? which build? can you prove it? The baseline attempt fails,
and it fails in an instructive way — the image knows what is installed in it
and nothing whatsoever about its own origin.

```command
./scripts/add-provenance.sh
```

Then add the evidence back, one layer at a time, and re-run the audit:

| Layer | Mechanism | What it is worth |
|---|---|---|
| 1 | `git.properties` written into the JAR by `git-commit-id-maven-plugin` | An internal claim. Anyone who can build can write it. |
| 2 | OCI annotations (`org.opencontainers.image.revision`) on the image | An unsigned claim, attached to a mutable tag. |
| 3 | A CycloneDX SBOM from Syft, keyed to the immutable image digest | A content claim, now bound to a specific artefact. |
| 4 | Cosign signature + in-toto attestation over the digest | Cryptographically verifiable: someone with a key asserted this. |

The step from 3 to 4 is the only one that survives an adversary. Layers 1–3
are useful for debugging and worthless against someone who can build images.
And note what layer 4 binds to: the **digest**, not the tag. Verifying a tag
proves nothing, because tags move.

The lesson is explicit about what this does *not* prove — worth reading
before you go home and promise your organisation provenance.

## What actually closes the gaps

Three controls, in the order they pay off:

1. **Controlled ingress.** A proxying repository between your builds and the
   public registries, with namespace reservation for your internal names,
   checksum verification, and a policy gate. This is the single control that
   answers dependency confusion and typosquatting, and it answers both
   completely. It is also the least glamorous item in the workshop.
2. **Integrity of what you cached.** Lockfiles with hashes, verified against
   the registry. A cache nobody verifies is an attack surface with a long
   memory.
3. **Provenance you can verify.** Signed attestations bound to digests, as
   built in S07 — so that when the question is "did this come from our
   pipeline", the answer is evidence rather than assertion.

Notice that none of the three is a scanner. Scanning tells you about known
problems in identifiable components. These three are about the parts of the
problem that scanning has already been shown, twice over, not to reach.

## You should now be able to

- Describe three ingress mechanisms that require no software defect, and
  name the control that stops each.
- Explain why a clean code-scanner result on a published artefact does not
  mean the build was clean.
- State what a signature has to be bound to before it means anything.

**Next:** you now have four parts' worth of ways this goes wrong. Part 6 is
the short list of things you actually do about it, on every release, and you
run it before you leave.

## References

- Alex Birsan, *Dependency Confusion: How I Hacked Into Apple, Microsoft and
  Dozens of Other Companies*, February 2021.
- `ua-parser-js` compromise, October 2021 — see the package's own security
  advisory and GitHub issue history.
- `event-stream` / `flatmap-stream` incident, November 2018 — see the
  `event-stream` issue thread and the subsequent npm post-mortem.
- `xz-utils` backdoor: <https://nvd.nist.gov/vuln/detail/CVE-2024-3094>;
  originally disclosed by Andres Freund to the oss-security mailing list,
  29 March 2024.
- Sigstore / Cosign keyless signing: <https://docs.sigstore.dev>
- in-toto attestation framework: <https://in-toto.io>

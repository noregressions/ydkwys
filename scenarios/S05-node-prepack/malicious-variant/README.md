# S05 malicious variant — the same mechanism, used on purpose

The main S05 scenario is benign: `prepack` generates the runtime `dist/` and
the workshop uses it to show that packaging destroys evidence. This directory
turns that mechanism malicious, so a scanner has something to catch. It exists
for [`investigations/T08-guarddog`](../../../investigations/T08-guarddog/LESSON.md).

## Safety

Read this before running anything.

- **Nothing here is ever installed, imported, or published.** The build script
  only `npm pack`s the packages so they can be scanned. It never runs
  `npm install`.
- The "payload" is a harmless stand-in: an async, fire-and-forget
  `curl` to `https://attacker.example.invalid/…`. The `.invalid` TLD is
  reserved by RFC 6761 and can never resolve, so even case A's prepack
  execution reaches nothing. It is there to trip a static heuristic, not to
  do anything.
- These packages are named `trace-route-package@1.0.0` to match the real
  fixture on purpose. Keep them in this directory; never publish them to any
  registry.

## The two cases

Both use the same `prepack` mechanism and differ only in **where the malicious
code lives**, which decides **who it attacks** and **whether it survives into
the shipped tarball**.

**Case A — payload in the generator** (`case-a-generator-payload/`). The
malicious `curl | sh` sits in `scripts/generate-dist.js`, which runs at
`prepack` time on whoever *publishes* the package. `files: ["dist"]` excludes
the generator from the tarball, so the generated `dist/` a consumer receives
is completely benign. This attacks the **build/publish environment** and
leaves no trace in the published artefact.

**Case B — payload in the generated output** (`case-b-generated-payload/`).
The generator is unremarkable, but it *writes* the `curl | sh` into
`dist/index.js`. That output ships, so it runs when the **consumer** loads the
module. This attacks the consumer and rides inside the tarball.

## Build

```bash
./scripts/build-variants.sh
```

Produces `out/CASE-A-generator-payload.tgz` and
`out/CASE-B-generated-payload.tgz`. Scan them with GuardDog from
[T08](../../../investigations/T08-guarddog/LESSON.md); the point is that
scanning the *published tarball* catches case B and misses case A, because a
code-reading scanner can only judge what survived into the artefact.

---
id: cheatsheet-part6
oneliner: "Part 6: the ship-check drill, and the card to take home."
track: reference
---

# Part 6 — The Minimum That Keeps You Honest

---

## Part 6 — the drill (`ship-check.sh`)

**Proving:** Two inventories of one build, the difference between them, lifecycle, provenance. The part you use on Monday.

The minimum practice, run against any project. Two inventories of the same
build, the difference between them, a lifecycle check, and whatever
provenance the artefact can produce.

From the repo root. Defaults to S01 if you give it no argument.
```command
./scripts/ship-check.sh scenarios/S01-spring-node
```

Build the project first — the declared inventory needs a resolvable reactor
and the shipped inventory needs artefacts to scan. Each section skips loudly
rather than failing when a tool is missing.

```text
=== 1. Declared (resolver view)      what mvn/npm/pip say you asked for
=== 2. Shipped (artefact view)       what syft can identify in the artefacts
=== 3. The gap                       the two lists, subtracted both ways
=== 4. Lifecycle (EOL)               npx @herodevs/cli scan eol --dir .
=== 5. Provenance                    git.properties / OCI labels / signatures
```

Section 3 is the point. The first list — declared but not identifiable — is
where S01's shading and bundling appear. The second — in the artefact but not
declared — is where S04's plugin payload appears; point it at
`scenarios/S04-maven-plugin-hidden-content` to see that half.

Both inventories are written to `<project>/ship-check/`, so you can diff this
release against the last one.

---
id: t11-herodevs-eol-s01
oneliner: "A lifecycle scanner on S01's frontend: five end-of-life components, four of which never ship, one shipped component that is not end of life but is the only row with a support path — and nothing at all to say about the artefact that reaches the browser."
track: core
---

# T11 — HeroDevs EOL / S01 frontend

## The question

Part 4 argues that "not known vulnerable" and "still supported" are different
claims, and that most tooling collapses them. This investigation runs a
lifecycle scanner against a real dependency tree to find out where its answer
comes from.

The instrument reads an SBOM. S01 exists to show that SBOMs disagree with each
other depending on the boundary they were generated at. So the question is not
"does the tool work":

> When the same application is described by a manifest, by a built artefact,
> and by an SBOM someone else generated, does the lifecycle answer change —
> and does it describe the code that ships?

## The instrument

```text
@herodevs/cli 2.0.8          hd scan eol
Node v25.8.1
scans run 2026-09-09
```

`hd scan eol` is not a local database lookup. It generates a CycloneDX SBOM
with a bundled generator (or reads one you supply with `--file`), submits it,
and returns a lifecycle verdict per component. Two consequences worth naming
before any result is read: it needs an authenticated CLI (`hd auth login`),
and the answer is a service response on a date, not a property of the
repository. Every report identifier below is recorded so a re-run can be
compared rather than assumed.

```command
cd investigations/T11-herodevs-eol-s01
./scripts/scan-s01.sh
./scripts/compare-s01.sh
```

---

# Ground truth

Established independently of the tool under investigation, from S01 itself.

## What the frontend declares

Three runtime dependencies and two build dependencies:

```command
cd scenarios/S01-spring-node/frontend && cat package.json
```

```output
  "dependencies": {
    "lodash": "4.17.21",
    "react": "18.3.1",
    "react-dom": "18.3.1"
  },
  "devDependencies": {
    "@vitejs/plugin-react": "4.7.0",
    "vite": "5.4.21"
  }
```

## What it actually ships

The production tree is six components; everything else in `node_modules` is
build tooling that Vite uses and then discards.

```command
npm ls --omit=dev --all
```

```output
checkout-trace-frontend@1.0.0
├── lodash@4.17.21
├─┬ react-dom@18.3.1
│ ├─┬ loose-envify@1.4.0
│ │ └── js-tokens@4.0.0
│ ├── react@18.3.1 deduped
│ └─┬ scheduler@0.23.2
│   └── loose-envify@1.4.0 deduped
└─┬ react@18.3.1
  └── loose-envify@1.4.0 deduped
```

Note `js-tokens@4.0.0`. Nobody declared it; it arrives under `react` and
`react-dom` through `loose-envify`. It is in the production tree.

## What survives the build

S01 has already established this and it is the premise of probe B: Vite
bundles the frontend into a single asset, and `lodash` does not survive as an
identifiable component. The built output carries no package manifest of any
kind, so no generator reading it can name anything at all — not `lodash`, and
not the components that are still perfectly well maintained.

```command
ls dist/assets/
```

```output
index-DVImxnjI.css
index-QMB-eT_H.js
```

---

# Probe A — the declared model

## Question

Given the manifest and the installed tree, what does the scanner report?

## Expectation

The two build dependencies are old release lines: `vite@5.4.21` sits behind
`vite@6`, and `@vitejs/plugin-react@4.7.0` behind `5`. Expect both to be
flagged, and expect the shipped components to be reported clean, because
`react@18.3.1` and `lodash@4.17.21` are both current for their lines.

## Run

```command
hd scan eol --dir scenarios/S01-spring-node/frontend --save
```

## Observed

```output
113 total packages scanned
✗ 5     End-of-Life (EOL)
! 0     EOL Upcoming
✔ 106   Not End-of-Life (EOL)
• 2     Unknown EOL Status
• 1     HeroDevs NES Remediation Available
```

Per component, from `./scripts/compare-s01.sh`:

```output
report=eff80368-bad2-433e-be23-8599f3dfece5
createdOn=2026-09-09T10:57:30.427Z
components=113
eol components:
  pkg:npm/js-tokens@4.0.0  next=9.0.0  cves=0  reasons=version.stale_release_line
  pkg:npm/lru-cache@5.1.1  next=10.0.0  cves=0  reasons=version.stale_release_line
  pkg:npm/yallist@3.1.1  next=4.0.0  cves=0  reasons=version.stale_release_line
  pkg:npm/%40vitejs/plugin-react@4.7.0  next=5.0.0  cves=0  reasons=version.stale_release_line
  pkg:npm/vite@5.4.21  next=6.0.0  cves=3  reasons=version.unpatched_cve_in_version
unknown components:
  pkg:nix/nixpkgs@6b1057b  next=-  cves=0  unknown=unsupported_ecosystem
  pkg:nix/utils@3982c99  next=-  cves=0  unknown=unsupported_ecosystem
nes remediation available:
  pkg:npm/lodash@4.17.21  next=-  cves=2  isEol=false
```

## Verdict

Five end-of-life components out of 113, and the expectation was only half
right. Cross the list against the production tree above:

| Component | Reachable in production? | Why flagged |
| --- | --- | --- |
| `vite@5.4.21` | no — dev only | unpatched CVE in this version |
| `@vitejs/plugin-react@4.7.0` | no — dev only | stale release line |
| `lru-cache@5.1.1` | no — dev only, under Babel | stale release line |
| `yallist@3.1.1` | no — dev only, under `lru-cache` | stale release line |
| `js-tokens@4.0.0` | **yes** — under `react` / `react-dom` | stale release line |

Four of the five findings are about software that never leaves the build
machine. That is not a defect in the tool — the manifest genuinely declares
them — but it is the difference between "this project depends on an
unmaintained thing" and "we ship an unmaintained thing", and the report does
not draw it. Nothing in the output marks the dev/production boundary; the
`npm ls --omit=dev` above is what separates them.

The fifth is the interesting one. `js-tokens@4.0.0` is undeclared, arrives
through React, is on a stale release line eight major versions back, and does
ship. It is the one row here that answers the question Part 4 is actually
asking, and it is indistinguishable in the output from the four that do not.

Two more observations from the same report:

**The scan reached into another ecosystem.** The two `pkg:nix/...` rows are
not npm packages and are not dependencies of anything. They come from a file
the SBOM generator found inside a dependency:

```command
ls scenarios/S01-spring-node/frontend/node_modules/lodash/flake.nix
```

`lodash` ships a Nix flake for its own contributors. The generator catalogued
the flake's inputs as components, and the lifecycle service correctly declined
to judge them (`unsupported_ecosystem`). Inventory noise, harmless here — and
a reminder that an SBOM contains whatever its generator could parse, which is
not the same as what the application consists of.

**`lodash@4.17.21` is reported not end of life, and is the only component in
the scan with a commercial support path.** Both facts at once:

```output
pkg:npm/lodash@4.17.21
isEol=false  cves=2  nes=true
  CVE-2025-13465  CVSS_V4=6.5  2026-04-01
  CVE-2021-23337  CVSS_V3=7.2  2026-04-01
```

This agrees with Part 4: `lodash` is maintained, the fixes exist, and the
answer is to upgrade. It also shows the two axes are independent — a supported
component with CVE records, sitting beside four end-of-life components with
none between them.

---

# Probe B — the artefact that ships

## Question

Ask the identical question of the built output rather than the source tree.

## Expectation

S01 establishes that `lodash` is not identifiable in the bundle. So expect a
report that omits `lodash` — and expect the four dev-only findings to vanish
too, since none of that tooling is in `dist/`.

## Run

```command
hd scan eol --dir scenarios/S01-spring-node/frontend/dist --save
```

## Observed

```output
- Generating SBOM
✔ Generated SBOM
- Cleaning up
No components found in scan. Report not generated.
```

## Verdict

Not a shorter list. No list. The generator found no manifest in `dist/`, so
the SBOM it produced was empty, so there was nothing to ask the lifecycle
service about and no report was created.

The result is correct at every step and useless as an answer about what ships.
Read against probe A, the pair is the whole point:

```text
scan the manifest   5 end-of-life components, 4 of which never ship
scan the artefact   0 components, therefore 0 findings
```

The boundary that knows what the application depends on cannot see what it
ships. The boundary that holds what ships cannot name anything. Lifecycle data
inherits that split exactly as vulnerability data does, and a green result
from the second boundary means "nothing was identifiable", not "nothing is
unsupported".

---

# Probe C — someone else's SBOM

## Question

The CLI accepts an existing CycloneDX or SPDX file. If the SBOM is the input,
is the verdict a property of the application or of the file?

## Run

Probe A saved the SBOM it generated. Re-scan that file directly:

```command
hd scan eol --file results/s01/a-source-manifest/herodevs.sbom.json --save
```

## Observed

```output
report=b8f23708-3b4b-4f86-a9e5-6bcba8238328
createdOn=2026-09-09T10:57:35.254Z
components=113
eol=5
unknown=2
nesAvailable=1
```

Same five components, same two unknowns, same single NES row. A different
report identifier, because it is a different scan.

## Verdict

The verdict is a property of the file. Feed it an SBOM built at the resolver
boundary and you get resolver-boundary lifecycle data; feed it one built from
a finished artefact and you get probe B. This is the useful thing about the
`--file` mode and also the trap: an EOL report is exactly as complete as the
inventory it was handed, and it carries no marker saying which boundary that
inventory came from. If your pipeline generates SBOMs from images, your
lifecycle report describes images. Nobody downstream can tell from the report.

---

# Probe D — control

## Question

Probes B's silence needs a reference. Does this instrument report a hard,
dated end-of-life when one exists?

## Run

Two coordinates with uncontested status — AngularJS, whose maintainers
declared end of life, and `request`, deprecated by its own author:

```command
./scripts/scan-s01.sh    # probe D builds and scans the control workspace
```

## Observed

```output
report=04868d38-8738-44f9-9b56-6843197052af
components=48
eol=5
nesAvailable=1
eol components:
  pkg:npm/request@2.88.2  cves=1  reasons=component.unpatched_cve_in_latest_release_line,version.marked_deprecated,version.release_line_deprecated,component.marked_deprecated
  pkg:npm/har-validator@5.1.5  cves=0  reasons=version.marked_deprecated,component.marked_deprecated,version.release_line_deprecated
  pkg:npm/tough-cookie@2.5.0  next=5.0.0  cves=1  reasons=version.stale_release_line,version.unpatched_cve_in_version
  pkg:npm/uuid@3.4.0  next=11.0.0  cves=1  reasons=version.release_line_deprecated,version.stale_release_line,version.marked_deprecated
  pkg:npm/angular@1.8.3  cves=10  eolAt=2021-12-31  reasons=version.marked_deprecated,version.maintainer_attested_is_eol,component.unpatched_cve_in_latest_release_line,component.repo_archived
```

## Verdict

The control fires, and it distinguishes strength of evidence in a way probe A
did not need. `angular@1.8.3` carries an actual date — `eolAt=2021-12-31` —
from `maintainer_attested_is_eol` and `component.repo_archived`: someone
upstream said so, and the repository is archived. Every S01 finding rested on
`stale_release_line`, which is an inference from release cadence, not a
statement by a maintainer.

That distinction is in the JSON and not in the summary. Both render as
`✗ End-of-Life`:

```text
maintainer_attested_is_eol + repo_archived   upstream said so, with a date
stale_release_line                           nobody has published here lately
unpatched_cve_in_version                     a defect with no fix in this line
```

The first is a fact about a commitment. The second is a heuristic about
silence — the same silence Part 4 warns against reading as safety, pointed the
other way and used as evidence of abandonment. It is usually a fair inference.
It is not the same claim, and a policy that gates a release on "0 EOL
components" cannot tell them apart.

---

# Scorecard

What entered the lifecycle report at each boundary. `seen` means the component
was in the inventory the scanner submitted.

| Boundary | lodash 4.17.21 (ships) | js-tokens 4.0.0 (ships) | vite 5.4.21 (build only) | components | EOL |
| --- | --- | --- | --- | --- | --- |
| manifest + installed tree | seen, not EOL, NES available | seen, **EOL** | seen, **EOL** | 113 | 5 |
| built artefact (`dist/`) | — | — | — | 0 | 0 |
| generated SBOM, re-scanned | seen, not EOL, NES available | seen, **EOL** | seen, **EOL** | 113 | 5 |
| known-EOL control | n/a | n/a | n/a | 48 | 5 |

## What this establishes

- A lifecycle scanner answers at the boundary of the inventory it is given.
  Handed a manifest it describes a dependency graph; handed a built artefact
  with no manifest it describes nothing and says so.
- End of life and known-vulnerable are independent axes. This scan produced a
  supported component with two CVE records (`lodash`), an end-of-life
  component with three (`vite`), and three end-of-life components with none.
- An EOL count over a manifest counts build tooling. Four of five findings
  here are dev-only; separating them needs `npm ls --omit=dev`, which the
  report does not do for you.
- The one shipped end-of-life component was undeclared and arrived
  transitively, which is the ordinary way this happens.
- "End of life" covers both a maintainer's dated declaration and an inference
  from publishing silence. The reasons are in the JSON; the summary line is
  the same for both.

## Limitations

- Every figure here is a service response captured on 2026-09-09, with report
  identifiers recorded above. Lifecycle status changes without any artefact
  changing — which is Part 4's subject, and applies to this page too.
- `hd scan eol` requires an authenticated CLI, so this investigation cannot be
  run offline or from the workshop container without a login. `scan-s01.sh`
  preflights that and says which of auth or network failed.
- The `dist/` result is a property of Vite's output having no manifest, not of
  this scanner. Any SBOM generator reading that directory produces the same
  empty inventory; S01 and T09 establish that independently.
- Probe D's control resolves from the public npm registry, so it needs network
  access and its transitive count may drift.

## References

- HeroDevs EOL CLI: <https://docs.herodevs.com/eol-ds>
- HeroDevs EOL report app: <https://apps.herodevs.com/eol>
- AngularJS end-of-life: <https://blog.angular.dev/discontinued-long-term-support-for-angularjs-cc066b82e65a>
- `request` deprecation: <https://github.com/request/request/issues/3142>
- Part 4 — CVEs Aren't Enough, Step 3, which runs this tool over the whole repository

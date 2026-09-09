---
id: cheatsheet-part4
oneliner: "Part 4 in run order: Scorecard, the deps.dev coordinate query, and the lifecycle sweep — with the captured answers to fall back on."
track: reference
---

# Part 4 — CVEs Aren't Enough

**Proving:** three evidence frameworks that are not vulnerability databases,
and one coordinate whose answer changed while the artefact did not.

Everything here is a live web or network query. Captures for all of it are in
`workshop/evidence/`, with dates in the filenames and a `CAPTURED.md` that
says how to refresh them. Use the captures if the network is against you.

---

## Step 1 — Repository practice (OpenSSF Scorecard)

Open in a browser: <https://scorecard.dev/viewer/?uri=github.com/lodash/lodash>

Capture: `workshop/evidence/openssf-scorecard-lodash-2026-08-18.pdf`

Aggregate at capture: **7.2 / 10**. Read the checks, not the number:

```text
Maintained            10/10   commit activity, not releases
Vulnerabilities        0/10   OSV against the source repo, not your version
Token-Permissions      0/10   unrestricted GITHUB_TOKEN
Pinned-Dependencies    4/10   unpinned CI actions
Signed-Releases            ?  no verification path to read
```

---

## Step 2 — Coordinate indexing (deps.dev)

Free, no account. Browser: <https://deps.dev/npm/lodash/4.17.21> — or the API:

```command
curl -sS \
  https://api.deps.dev/v3/systems/npm/packages/lodash/versions/4.17.21 \
  | jq \
    '{version: .versionKey.version, advisories: [.advisoryKeys[]?.id]}'
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

Three IDs, **two distinct defects** — the first and third are aliases of one
another. Compare with the current release:

```command
curl -sS \
  https://api.deps.dev/v3/systems/npm/packages/lodash/versions/4.18.1 \
  | jq \
    '{version: .versionKey.version, advisories: [.advisoryKeys[]?.id]}'
```

```output
{ "version": "4.18.1", "advisories": [] }
```

### The before-and-after

`4.17.21` was published February 2021 and has not changed since. This
repository's earlier capture, from Sonatype OSS Index, recorded **zero**.

```text
2021-02   4.17.21 published. Not one byte has changed since.
2026-01   GHSA-xxjr-mmjv-4gpg    prototype pollution, _.unset / _.omit
2026-04   GHSA-f23m-r3pf-42rh    the same defect, second identifier
2026-04   GHSA-r5fr-rjxr-66jc    code injection via _.template
```

Check the alias list on the third one:

```command
curl -sS https://api.deps.dev/v3/advisories/GHSA-r5fr-rjxr-66jc | \
  jq '.aliases'
```

```output
["CVE-2021-23337", "CVE-2026-4800", "GHSA-35jh-r3h4-6jhm"]
```

`CVE-2021-23337` is the vulnerability **4.17.21 was released to fix**.

### The instrument that reached end of life

The query that produced the original zero cannot be run any more:

```command
curl -sSI https://ossindex.sonatype.org/ | grep -i '^location'
curl -sS -o /dev/null -w '%{http_code}\n' -X POST \
  https://ossindex.sonatype.org/api/v3/component-report \
  -H 'Content-Type: application/json' \
  -d '{"coordinates":["pkg:npm/lodash@4.17.21"]}'
```

```output
location: https://guide.sonatype.com/
401
```

Capture: `workshop/evidence/ossindex-probe-2026-09-08.txt`

---

## Step 3 — Lifecycle and EOL

```command
npx @herodevs/cli scan eol --dir .
```

Live only — there is no captured fallback. Expected shape:

```text
jackson-databind 2.19.4   S01 direct        active maintenance
commons-codec 1.17.1      S01 shaded        active maintenance
lodash 4.17.21            S01 bundled       superseded: 4.17.23 / 4.18.0 / 4.18.1
spring-boot 3.5.12        S01 runtime       OSS support ended 30 June 2026
apache-tomcat 8.5         S02 / Part 3      EOL 31 March 2024
```

Three states, and most tooling shows two:

```text
vulnerable            an advisory matched
not known vulnerable  nothing matched in the index queried
unsupported / EOL     nobody upstream is triaging, patching or publishing
```

Confirm what npm actually offers, which is what makes lodash the benign case
and Tomcat the sharp one:

```command
npm view lodash version
```

```output
4.18.1
```

### The scan needs an account

`hd scan eol` submits an SBOM to a service, so the CLI has to be logged in.
Without it every scan fails the same way — `Your CI token has expired` — which
is an auth failure, not a scenario failure.

```command
npx @herodevs/cli auth login
```

For a headless or CI run, provision a token instead:

```command
npx @herodevs/cli auth provision-ci-token
```

### T11 — the same question at three boundaries

The investigation behind Step 3: one lifecycle question, asked of a manifest,
of the built artefact, and of an SBOM.

```command
cd investigations/T11-herodevs-eol-s01
./scripts/scan-s01.sh
./scripts/compare-s01.sh
```

Captured 2026-09-09 against S01's frontend:

```text
manifest + installed tree   113 components   5 EOL   2 unknown   1 NES
built artefact (dist/)        0 components   no report generated
generated SBOM, re-scanned  113 components   5 EOL   2 unknown   1 NES
known-EOL control            48 components   5 EOL
```

The four EOL findings that are build tooling, and the one that is not:

```command
(cd scenarios/S01-spring-node/frontend && npm ls --omit=dev --all)
```

```output
checkout-trace-frontend@1.0.0
├── lodash@4.17.21
├─┬ react-dom@18.3.1
│ ├─┬ loose-envify@1.4.0
│ │ └── js-tokens@4.0.0
```

`vite`, `@vitejs/plugin-react`, `lru-cache` and `yallist` are all dev-only.
`js-tokens@4.0.0` is EOL, undeclared, arrives under React — and ships.
`lodash@4.17.21` is **not** EOL, carries two CVE records, and is the only row
in the scan with a support path.

---

## Closing Act 2 — one component, three failure modes

Apache Tomcat 8.5, all at once:

```text
1. Tool capability gap    Tomcat arrives embedded and repackaged; identity is
   (Part 2)               lost, so no scanner can raise the finding.
2. CVE process failure    20 of Ghostcat's 38 CPEs are embedding products,
   (Part 3)               added 26 months after publication.
3. EOL blind spot         EOL 31 March 2024. New advisories reflect who still
   (Part 4)               bothers to file, not what is still broken.
```

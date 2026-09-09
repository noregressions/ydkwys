# Part 4 evidence

Captured for the Part 4 walkthrough so the session does not depend on four
external services behaving. Every file records what a live query returned on
the date in its name.

| File | What it is |
|---|---|
| `openssf-scorecard-lodash-2026-08-18.pdf` | OpenSSF Scorecard report for `lodash/lodash`, Step 1 |
| `depsdev-lodash-4.17.21-2026-09-08.json` | deps.dev version record: three advisory keys |
| `depsdev-lodash-4.18.1-2026-09-08.json` | deps.dev version record for the current release: no advisories |
| `depsdev-lodash-package-2026-09-08.json` | deps.dev package record: every published version |
| `depsdev-advisory-GHSA-*-2026-09-08.json` | The three advisories, with aliases and CVSS |
| `npm-lodash-versions-2026-09-08.json` | Every version npm has published |
| `npm-lodash-latest-2026-09-08.json` | `latest` at capture time, and the registry's last-modified |
| `ossindex-probe-2026-09-08.txt` | Evidence that Sonatype OSS Index is no longer queryable |

## Why OSS Index is not the instrument any more

Earlier editions of Part 4 queried Sonatype OSS Index for
`pkg:npm/lodash@4.17.21` and recorded **zero** results. That query can no
longer be run at all:

```text
https://ossindex.sonatype.org/                     301 -> guide.sonatype.com
POST /api/v3/component-report (unauthenticated)    401
```

The free browsable index redirects to Sonatype's commercial guide, and the API
requires credentials the workshop never asked anyone to create. The chapter
now uses [deps.dev](https://deps.dev), which is free, needs no account, and
has both a web UI and an API.

The disappearance is not an inconvenience to route around — it is Part 4's own
subject happening to Part 4. Evidence sources have lifecycles too, and this one
ended without an announcement.

## Refreshing these

```bash
cd workshop/evidence
D=$(date -u +%Y-%m-%d)
curl -sS "https://api.deps.dev/v3/systems/npm/packages/lodash/versions/4.17.21" \
  -o "depsdev-lodash-4.17.21-$D.json"
curl -sS "https://api.deps.dev/v3/systems/npm/packages/lodash/versions/4.18.1" \
  -o "depsdev-lodash-4.18.1-$D.json"
curl -sS "https://api.deps.dev/v3/systems/npm/packages/lodash" \
  -o "depsdev-lodash-package-$D.json"
npm view lodash versions --json > "npm-lodash-versions-$D.json"
```

Expect the numbers to move. The advisory list against `4.17.21` grew from zero
to three between the 2026-08-18 and 2026-09-08 captures, against an artefact
that has not changed since February 2021.

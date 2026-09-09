#!/usr/bin/env bash
# Put the four probes side by side. The only thing that varies between them is
# what the scanner was allowed to read; the question asked is identical.
set -euo pipefail
source "$(dirname "$0")/common.sh"

# common.sh creates $RESULTS, so its existence proves nothing. A probe
# directory is the evidence that a scan actually ran.
if [[ ! -d "$RESULTS/a-source-manifest" ]]; then
  echo "No probe output. Run ./scripts/scan-s01.sh first." >&2
  exit 1
fi

for probe in a-source-manifest b-built-artefact c-sbom-file d-control; do
  echo "== $probe =="
  if [[ -f "$RESULTS/$probe/report.txt" ]]; then
    # The CLI prints "No components found" instead of writing a report when
    # the SBOM it built is empty; that is a result, not a failure.
    grep -qF 'No components found' "$RESULTS/$probe/report.txt" \
      && echo "  no components: the scan had nothing to ask about"
  fi
  node "$ROOT/scripts/summarise-report.js" "$RESULTS/$probe/herodevs.report.json" 2>/dev/null \
    | sed 's/^/  /' || echo "  (no report file)"
  echo
done

echo "== the shipped component =="
# S01's tracked frontend component. It is not EOL, it does carry CVE records,
# and it is the one row in the whole scan with a commercial support path --
# and probe B shows it is unnameable in the artefact that actually ships.
node -e '
const fs = require("fs");
const f = process.argv[1];
if (!fs.existsSync(f)) { console.log("  (no report)"); process.exit(0); }
const r = JSON.parse(fs.readFileSync(f, "utf8"));
const c = (r.components || []).find((x) => /^pkg:npm\/lodash@/.test(x.purl));
if (!c) { console.log("  lodash: not in this report"); process.exit(0); }
const m = c.metadata || {};
const cves = Array.isArray(m.cveStats) ? m.cveStats : [];
console.log(`  ${c.purl}`);
console.log(`  isEol=${m.isEol}  cves=${cves.length}  nes=${(c.nesRemediation?.remediations || []).length > 0}`);
cves.forEach((v) => console.log(`    ${v.cveId}  ${v.cvssType}=${v.cvssScore ?? "n/a"}  ${String(v.publishedAt).slice(0, 10)}`));
' "$RESULTS/a-source-manifest/herodevs.report.json"

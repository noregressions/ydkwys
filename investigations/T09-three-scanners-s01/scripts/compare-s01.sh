#!/usr/bin/env bash
#
# T09: turn the results/ tree into the comparison this investigation exists
# for — one target, three tools, side by side, and the places they disagree.
#
# Everything printed here is paste-ready for LESSON.md.
set -euo pipefail

source "$(dirname "$0")/common.sh"

RES="$ROOT/results/s01"
OUT="$RES/compare"
mkdir -p "$OUT"

[[ -d "$RES" ]] || { echo "No results. Run baseline-s01.sh then run-scanners-s01.sh." >&2; exit 1; }

TOOLS=(grype trivy osv)
BOUNDARIES=(service-pom frontend-lock normalizer-jar normalizer-stripped-jar service-jar frontend-dist container-image)
TRACERS=(jackson-databind commons-codec normalizer lodash)

# Did <tool> name <component> at <boundary>?
#
# The tools do not agree on how to write a Maven name: grype prints the
# artifactId alone (jackson-databind), trivy and osv-scanner print
# groupId:artifactId (com.fasterxml.jackson.core:jackson-databind). Comparing
# the raw strings would report a capability difference where there is only a
# formatting one, so match on the artifact segment.
# Did the tool run at all at this boundary? The scanners record an exit code
# per probe; osv-scanner records it beside its JSON. "Ran and catalogued
# nothing" and "never ran" are different answers and must not share a symbol.
probe_ran() {
  local tool="$1" boundary="$2"
  [[ -f "$RES/$tool/$boundary.exit" || -f "$RES/$tool/$boundary.json.exit" ]]
}

named() {
  local tool="$1" boundary="$2" tracer="$3"
  local f="$RES/$tool/$boundary.tracers.txt"
  if [[ ! -s "$f" ]]; then
    if probe_ran "$tool" "$boundary"; then echo "."; else echo "-"; fi
    return
  fi
  if awk -F'\t' -v t="$tracer" '
        { n = $1; sub(/^.*:/, "", n) }
        tolower(n) == tolower(t) { found = 1 }
        END { exit !found }' "$f"; then
    echo "YES"
  else
    echo "."
  fi
}

{
  echo "T09 — three scanners, one target (S01)"
  echo
  if [[ -f "$RES/baseline/instruments.txt" ]]; then
    sed 's/^/  /' "$RES/baseline/instruments.txt"
    echo
  fi

  echo "=============================================================="
  echo "1. IDENTITY — could the tool name the tracked component at this boundary?"
  echo "=============================================================="
  echo "   YES = named   . = scanned, nothing named   - = probe did not run"
  echo
  for tracer in "${TRACERS[@]}"; do
    printf '%s\n' "$tracer"
    printf '  %-26s %6s %6s %6s\n' "boundary" "grype" "trivy" "osv"
    for b in "${BOUNDARIES[@]}"; do
      printf '  %-26s' "$b"
      for t in "${TOOLS[@]}"; do printf ' %6s' "$(named "$t" "$b" "$tracer")"; done
      printf '\n'
    done
    echo
  done

  echo "=============================================================="
  echo "2. FINDINGS — how many tracked vulnerabilities did each report?"
  echo "=============================================================="
  printf '  %-26s %6s %6s %6s\n' "boundary" "grype" "trivy" "osv"
  for b in "${BOUNDARIES[@]}"; do
    printf '  %-26s' "$b"
    for t in "${TOOLS[@]}"; do
      f="$RES/$t/$b.vulns.txt"
      if [[ -f "$f" ]]; then printf ' %6s' "$(wc -l <"$f" | tr -d ' ')"; else printf ' %6s' "-"; fi
    done
    printf '\n'
  done
  echo

  echo "=============================================================="
  echo "3. DISAGREEMENT — the same defect, or a different one?"
  echo "=============================================================="
  cat <<'NOTE'
  Advisory identifiers are not one-to-one. The same defect is a CVE in one
  database and a GHSA in another, so comparing raw IDs manufactures
  disagreements. This section resolves aliases first — from grype's
  relatedVulnerabilities and osv-scanner's aliases fields — and only reports
  a difference when no tool-reported ID in an equivalence class was seen by
  the other tool.
NOTE
  python3 - "$RES" <<'PY'
import json, os, sys, glob
res = sys.argv[1]
tools = ["grype", "trivy", "osv"]
boundaries = ["service-pom", "frontend-lock", "normalizer-jar",
              "normalizer-stripped-jar", "service-jar", "frontend-dist",
              "container-image"]

# --- Build a global alias map from whatever the tools volunteered. --------
parent = {}
def find(x):
    parent.setdefault(x, x)
    while parent[x] != x:
        parent[x] = parent[parent[x]]; x = parent[x]
    return x
def union(a, b):
    ra, rb = find(a), find(b)
    if ra != rb: parent[ra] = rb

def load(path):
    try:
        with open(path) as fh: return json.load(fh)
    except Exception: return None

for f in glob.glob(os.path.join(res, "grype", "*.json")):
    d = load(f) or {}
    for m in d.get("matches", []) or []:
        vid = (m.get("vulnerability") or {}).get("id")
        if not vid: continue
        for rel in m.get("relatedVulnerabilities", []) or []:
            if rel.get("id"): union(vid, rel["id"])

for f in glob.glob(os.path.join(res, "osv", "*.json")):
    d = load(f) or {}
    for r in d.get("results", []) or []:
        for p in r.get("packages", []) or []:
            for v in p.get("vulnerabilities", []) or []:
                vid = v.get("id")
                if not vid: continue
                for a in v.get("aliases", []) or []:
                    union(vid, a)

def ids_for(tool, boundary):
    path = os.path.join(res, tool, boundary + ".vulns.txt")
    out = set()
    if os.path.exists(path):
        for line in open(path):
            cols = line.rstrip("\n").split("\t")
            if len(cols) >= 3 and cols[2]: out.add(cols[2])
    return out

def ran(tool, boundary):
    return os.path.exists(os.path.join(res, tool, boundary + ".vulns.txt"))

any_diff = False
for b in boundaries:
    active = [t for t in tools if ran(t, b)]
    if len(active) < 2: continue
    per = {t: ids_for(t, b) for t in active}
    groups = {}
    for t in active:
        for i in per[t]:
            groups.setdefault(find(i), {}).setdefault(t, set()).add(i)
    lines = []
    for key, byTool in sorted(groups.items()):
        if len(byTool) == len(active): continue          # everyone has it
        missing = [t for t in active if t not in byTool]
        shown = "  ".join(f"{t}:{'/'.join(sorted(v))}" for t, v in sorted(byTool.items()))
        lines.append(f"    {shown}\n        not reported by: {', '.join(missing)}")
    agreed = sum(1 for k, v in groups.items() if len(v) == len(active))
    print()
    print(f"  {b}   ({'+'.join(active)})")
    print(f"    {len(groups)} distinct defects after alias resolution; "
          f"{agreed} reported by all {len(active)}")
    if lines:
        any_diff = True
        print("\n".join(lines))
    else:
        print("    no genuine disagreement")
if not any_diff:
    print()
    print("  Every difference in section 2 was an identifier-scheme difference,")
    print("  not a data difference. That is itself the finding.")
PY
  echo

  echo "=============================================================="
  echo "4. THE QUESTIONS THIS RAISES"
  echo "=============================================================="
  cat <<'Q'
  1. Where all three agree, what evidence were they all reading?
  2. normalizer-jar vs normalizer-stripped-jar: the bytecode is identical
     and only META-INF/maven differs. Which tools changed their answer?
     Those are the tools reading metadata rather than code.
  3. Where one tool names a tracked component the others miss, is that a
     better analyser or a different database? Check the ecosystem/purl.
  4. Where the CVE lists differ for the SAME package at the SAME version,
     the disagreement is upstream of the scanner. Which database is each
     one joining against?
  5. frontend-dist holds lodash as code and not as a package. Did any tool
     report it? What would it have had to do to find it?
  6. container-image should be the superset. Is it?
  7. If you had to ship with exactly one of these three, which, and what
     would you have to accept losing?
Q
} | tee "$OUT/matrix.txt"

echo
echo "Written to $OUT/matrix.txt — this is the block LESSON.md asks for."

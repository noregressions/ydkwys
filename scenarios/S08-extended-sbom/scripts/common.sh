#!/usr/bin/env bash
set -euo pipefail

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
REPO_DEFAULT=$(cd "$ROOT/../.." && pwd)
S01="${S01:-$REPO_DEFAULT/scenarios/S01-spring-node}"
S04="${S04:-$REPO_DEFAULT/scenarios/S04-maven-plugin-hidden-content}"
RESULTS="$ROOT/results"

# The two SBOM generators under comparison. Both are Maven plugins invoked
# as bare goals, so neither scenario's POM is modified.
CDX="org.cyclonedx:cyclonedx-maven-plugin:2.9.3"
PLUS_VERSION="1.0.0"
PLUS="dev.noregressions:sbom-plus-maven-plugin:${PLUS_VERSION}"
VENDORED="$ROOT/plugin-repo/dev/noregressions/sbom-plus-maven-plugin/${PLUS_VERSION}"

need() {
  command -v "$1" >/dev/null 2>&1 || { echo "Required command not found: $1" >&2; exit 1; }
}

# ensure_plugin [local-repo]
#
# Make SBOM+ resolvable in the given Maven local repository (default: the
# user's ~/.m2). Order of preference: already present; fetch from the remote
# repositories Maven is configured with; fall back to the copy vendored in
# plugin-repo/. The fallback is what keeps this lab runnable offline and
# before the plugin reaches Maven Central.
ensure_plugin() {
  local repo="${1:-}"
  local -a args=()
  [[ -n "$repo" ]] && args=(-Dmaven.repo.local="$repo")
  local home="${repo:-$HOME/.m2/repository}"
  local jar="$home/dev/noregressions/sbom-plus-maven-plugin/${PLUS_VERSION}/sbom-plus-maven-plugin-${PLUS_VERSION}.jar"

  if [[ -f "$jar" ]]; then
    echo "SBOM+ ${PLUS_VERSION}: present in ${repo:-~/.m2}"
    return 0
  fi
  if mvn -q ${args[@]+"${args[@]}"} dependency:get -Dartifact="$PLUS" >/dev/null 2>&1; then
    echo "SBOM+ ${PLUS_VERSION}: fetched from a remote repository into ${repo:-~/.m2}"
    return 0
  fi
  echo "SBOM+ ${PLUS_VERSION}: not in any remote repository; installing the vendored copy from plugin-repo/"
  mvn -q ${args[@]+"${args[@]}"} install:install-file \
    -Dfile="$VENDORED/sbom-plus-maven-plugin-${PLUS_VERSION}.jar" \
    -DpomFile="$VENDORED/sbom-plus-maven-plugin-${PLUS_VERSION}.pom"
}

# --- reporting helpers (all read the JSON files a scan produced) -------------

# tabulate: align tab-separated stdin into columns (no dependency on `column`,
# which minimal Ubuntu images do not ship).
tabulate() {
  awk -F'\t' '
    { for (i=1;i<=NF;i++) { a[NR,i]=$i; if (length($i)>w[i]) w[i]=length($i) } if (NF>nf) nf=NF }
    END { for (r=1;r<=NR;r++) { line=""; for (i=1;i<=nf;i++) { line=line sprintf("%-" (i<nf ? w[i]+2 : 1) "s", a[r,i]) } sub(/[ ]+$/, "", line); print line } }'
}


# cdx_summary <label> <cyclonedx.json>
cdx_summary() {
  jq -r --arg l "$1" '
    [.components[]? | .scope // "(no scope)"] as $s
    | "\($l): \(.components|length) components  "
      + ([$s | group_by(.)[] | "\(.[0])=\(length)"] | join("  "))
      + "  specVersion=\(.specVersion)"' "$2"
}

# report_origins <plus.report.json>
report_origins() {
  jq -r '
    [.modules[].dependencies[]] as $rows
    | "SBOM+ report: \($rows|length) rows across \(.modules|length) module(s)  "
      + ([$rows | group_by(.origin)[] | "\(.[0].origin)=\(length)"] | join("  "))
      + "  unresolved=\([.modules[].unresolved[]]|length)"' "$1"
}

# report_rows <plus.report.json> <artifactId-regex>
# One line per matching row: module, origin, scope, coordinate, and the
# root-first path that brought it in.
report_rows() {
  jq -r --arg re "$2" '
    .modules[] | .module as $m | .dependencies[]
    | select(.coordinate.artifactId | test($re))
    | [($m|split(":")[1]), .origin, .scope,
       "\(.coordinate.groupId):\(.coordinate.artifactId):\(.coordinate.version)",
       (if (.broughtInBy|length)==0 then "(declared directly)"
        else "via " + (.broughtInBy|map(.artifactId)|join(" > ")) end)]
    | @tsv' "$1" | sort -u | tabulate
}

# cdx_rows <cyclonedx.json> <name-regex>
cdx_rows() {
  jq -r --arg re "$2" '
    .components[]? | select(.name | test($re))
    | [.name, .version, (.scope // "-"), .purl] | @tsv' "$1" | sort -u | tabulate
}

# cdx_gav_list <cyclonedx.json>  -> sorted group:name:version lines
cdx_gav_list() {
  jq -r '.components[]? | "\(.group // "-"):\(.name):\(.version)"' "$1" | sort -u
}

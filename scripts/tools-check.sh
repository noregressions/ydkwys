#!/usr/bin/env bash
#
# tools-check.sh — check every tool the workshop uses.
#
# Reports the version of each tool that is present, flags anything below the
# minimum this repository needs, and prints installation instructions with a
# link for anything missing.
#
# Read-only: installs nothing, downloads nothing, changes nothing.
#
# Exit status:
#   0  every required tool is present and new enough
#   1  something required is missing or too old
#
# The requirements mirror "setup/01 intro.md"; the install commands mirror
# "setup/02 tools.md".

set -uo pipefail

# ---------------------------------------------------------------------------
# Options
# ---------------------------------------------------------------------------

SHOW_ALL_URLS=0
QUIET=0

usage() {
  cat <<'EOF'
Usage: ./scripts/tools-check.sh [options]

Checks for every tool the workshop uses. Prints the version of each tool found,
flags versions below the workshop minimum, and gives installation instructions
plus a link for anything missing.

Installs nothing and changes nothing.

Options:
  --urls        Print installation instructions for every tool, not just the
                ones that are missing. Useful when preparing a machine you do
                not have in front of you.
  --quiet       Print only problems and the final summary.
  -h, --help    Show this help.

Exit status is 0 when every required tool is present and new enough, 1
otherwise. Optional tools never affect the exit status, but the scenario or
investigation that needs them is named so you can decide.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --urls)    SHOW_ALL_URLS=1 ;;
    --quiet)   QUIET=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; echo >&2; usage >&2; exit 2 ;;
  esac
  shift
done

# ---------------------------------------------------------------------------
# Platform
# ---------------------------------------------------------------------------

OS="unknown"
case "$(uname -s)" in
  Darwin) OS="macos" ;;
  Linux)  OS="linux" ;;
esac

HAVE_BREW=0
command -v brew >/dev/null 2>&1 && HAVE_BREW=1

# ---------------------------------------------------------------------------
# State
#
# Findings accumulate into newline-delimited strings rather than associative
# arrays, so this works on the Bash 3.2 that macOS ships.
# ---------------------------------------------------------------------------

PROBLEMS=""       # lines of: <tool>|<state>|<detail>
N_OK=0
N_OLD=0
N_MISSING=0
N_OPT_MISSING=0

C_RESET=""; C_BOLD=""; C_RED=""; C_YEL=""; C_GRN=""; C_DIM=""
if [[ -t 1 ]]; then
  C_RESET=$'\033[0m'; C_BOLD=$'\033[1m'
  C_RED=$'\033[31m'; C_YEL=$'\033[33m'; C_GRN=$'\033[32m'; C_DIM=$'\033[2m'
fi

say()     { [[ "$QUIET" == 1 ]] || printf '%s\n' "$*"; }
section() { [[ "$QUIET" == 1 ]] || { printf '\n%s%s%s\n' "$C_BOLD" "$*" "$C_RESET"; }; }

have() { command -v "$1" >/dev/null 2>&1; }

# ---------------------------------------------------------------------------
# Version helpers
# ---------------------------------------------------------------------------

# first_version <string> -> first dotted-numeric run, e.g. "3.9.16"
first_version() {
  printf '%s' "$1" | tr -c '0-9.\n' ' ' \
    | tr ' ' '\n' | grep -E '^[0-9]+(\.[0-9]+)*$' | head -1
}

# ver_ge <have> <want>  -> 0 if have >= want, numeric field-by-field
ver_ge() {
  local have="$1" want="$2" i h w
  local -a H W
  IFS='.' read -r -a H <<< "$have"
  IFS='.' read -r -a W <<< "$want"
  i=0
  while [[ $i -lt ${#W[@]} ]]; do
    h="${H[$i]:-0}"; w="${W[$i]:-0}"
    h=$((10#${h:-0} )) 2>/dev/null || h=0
    w=$((10#${w:-0} )) 2>/dev/null || w=0
    if [[ $h -gt $w ]]; then return 0; fi
    if [[ $h -lt $w ]]; then return 1; fi
    i=$((i + 1))
  done
  return 0
}

record_problem() {
  PROBLEMS="${PROBLEMS}$1|$2|$3
"
}

# report <tool> <state> <version-or-reason> <requirement>
report() {
  local tool="$1" state="$2" detail="$3" req="${4:-}"
  local mark colour
  case "$state" in
    ok)       mark="ok     "; colour="$C_GRN" ;;
    old)      mark="OLD    "; colour="$C_YEL" ;;
    missing)  mark="MISSING"; colour="$C_RED" ;;
    optional) mark="absent "; colour="$C_DIM" ;;
    info)     mark="       "; colour="$C_DIM" ;;
  esac
  if [[ "$QUIET" != 1 || "$state" == old || "$state" == missing ]]; then
    printf '  %s%s%s  %-14s %-28s %s\n' \
      "$colour" "$mark" "$C_RESET" "$tool" "$detail" "${req:+$C_DIM($req)$C_RESET}"
  fi
}

# ---------------------------------------------------------------------------
# Install instructions
#
# Primary URL is the project's own site or repository — those are the most
# stable links available. The commands mirror setup/02 tools.md.
# ---------------------------------------------------------------------------

install_help() {
  case "$1" in
    git)
      echo "https://git-scm.com/downloads"
      [[ "$OS" == macos ]] && echo "  xcode-select --install    # or: brew install git"
      [[ "$OS" == linux ]] && echo "  sudo apt-get install -y git"
      ;;
    java|javac|jar|javap)
      echo "https://adoptium.net/temurin/releases/"
      [[ "$OS" == macos ]] && echo "  brew install openjdk@21"
      [[ "$OS" == linux ]] && echo "  install temurin-21-jdk from the Adoptium repository"
      echo "  JDK 21 or newer. jar and javap ship with the JDK."
      ;;
    mvn)
      echo "https://maven.apache.org/install.html"
      [[ "$OS" == macos ]] && echo "  brew install maven"
      [[ "$OS" == linux ]] && echo "  sudo apt-get install -y maven"
      echo "  Maven 3.9+. If your distribution ships an older Maven, install a"
      echo "  current 3.9.x binary distribution instead."
      ;;
    node|npm)
      echo "https://nodejs.org/en/download"
      [[ "$OS" == macos ]] && echo "  brew install node"
      echo "  Or via nvm (avoids old distribution packages):"
      echo "  https://github.com/nvm-sh/nvm#installing-and-updating"
      echo "  nvm install 24"
      echo "  npm ships with Node.js. npm audit needs no separate install."
      ;;
    python3|pip|venv)
      echo "https://www.python.org/downloads/"
      [[ "$OS" == macos ]] && echo "  brew install python"
      [[ "$OS" == linux ]] && echo "  sudo apt-get install -y python3 python3-pip python3-venv"
      echo "  Python 3.11+. pip and venv ship with it."
      ;;
    pipx)
      echo "https://pipx.pypa.io/"
      [[ "$OS" == macos ]] && echo "  brew install pipx"
      [[ "$OS" == linux ]] && echo "  sudo apt-get install -y pipx"
      echo "  pipx ensurepath"
      ;;
    pip-audit)
      echo "https://github.com/pypa/pip-audit"
      echo "  pipx install pip-audit"
      ;;
    docker)
      echo "https://docs.docker.com/get-docker/"
      [[ "$OS" == macos ]] && echo "  Install Docker Desktop."
      [[ "$OS" == linux ]] && echo "  Docker Desktop for Linux, or Docker Engine:"
      [[ "$OS" == linux ]] && echo "  https://docs.docker.com/engine/install/"
      echo "  Docker is the canonical container engine for this workshop."
      ;;
    docker-scout)
      echo "https://docs.docker.com/scout/install/"
      echo "  Docker Desktop already includes Docker Scout."
      echo "  Required by T02. Podman does not provide it."
      ;;
    syft)
      echo "https://github.com/anchore/syft"
      [[ "$OS" == macos ]] && echo "  brew install syft"
      echo "  curl -sSfL https://get.anchore.io/syft | sudo sh -s -- -b /usr/local/bin"
      ;;
    grype)
      echo "https://github.com/anchore/grype"
      [[ "$OS" == macos ]] && echo "  brew install grype"
      echo "  curl -sSfL https://get.anchore.io/grype | sudo sh -s -- -b /usr/local/bin"
      ;;
    trivy)
      echo "https://github.com/aquasecurity/trivy"
      [[ "$OS" == macos ]] && echo "  brew install trivy"
      [[ "$OS" == linux ]] && echo "  Use Aqua Security's package repository for your distribution."
      echo "  Docs: https://trivy.dev/"
      ;;
    osv-scanner)
      echo "https://google.github.io/osv-scanner/"
      [[ "$OS" == macos ]] && echo "  brew install osv-scanner"
      echo "  go install github.com/google/osv-scanner/v2/cmd/osv-scanner@latest"
      echo "  Required by T09, the three-scanner comparison."
      ;;
    snyk)
      echo "https://docs.snyk.io/snyk-cli/install-or-update-the-snyk-cli"
      echo "  npm install -g snyk"
      echo "  Then authenticate:  snyk auth"
      ;;
    cosign)
      echo "https://docs.sigstore.dev/cosign/system_config/installation/"
      [[ "$OS" == macos ]] && echo "  brew install cosign"
      [[ "$OS" == linux ]] && echo "  Download the cosign-linux-<arch> release binary to /usr/local/bin/cosign"
      echo "  Required by S07 (signing and attestation)."
      ;;
    guarddog)
      echo "https://github.com/DataDog/guarddog"
      echo "  pipx install guarddog"
      echo "  Required by T08."
      ;;
    jq)
      echo "https://jqlang.github.io/jq/download/"
      [[ "$OS" == macos ]] && echo "  brew install jq"
      [[ "$OS" == linux ]] && echo "  sudo apt-get install -y jq"
      ;;
    curl)
      echo "https://curl.se/download.html"
      [[ "$OS" == linux ]] && echo "  sudo apt-get install -y curl"
      ;;
    zip|unzip|tar)
      echo "https://infozip.sourceforge.net/"
      [[ "$OS" == linux ]] && echo "  sudo apt-get install -y zip unzip tar"
      [[ "$OS" == macos ]] && echo "  Ships with macOS."
      ;;
    brew)
      echo "https://brew.sh"
      ;;
    disk)
      echo "(free up disk space — no URL for that)"
      echo "  Big reclaim candidates: docker system df && docker system prune;"
      echo "  old container images; ~/Library/Caches. The workshop wants ~20GB"
      echo "  free: two container images plus build headroom, or local builds"
      echo "  plus scanner databases."
      ;;
    nvd-key)
      echo "https://nvd.nist.gov/developers/request-an-api-key"
      echo "  export NVD_API_KEY=<your key>"
      echo "  Without it T06 falls back to Dependency-Check 12.2.2 and the NVD"
      echo "  download is slower. See setup/03 ACCOUNTS-AND-KEYS.md"
      ;;
    snyk-auth)
      echo "https://docs.snyk.io/snyk-cli/authenticate-the-cli-with-your-account"
      echo "  snyk auth"
      echo "  Required by T01."
      ;;
    *)
      echo "(no installation notes recorded for '$1')"
      ;;
  esac
}

# ---------------------------------------------------------------------------
# Checks
# ---------------------------------------------------------------------------

# check_required <label> <command> <min-version|-> <version-command> <help-key>
check_required() {
  local label="$1" cmd="$2" min="$3" vercmd="$4" key="$5"
  local raw ver req=""
  [[ "$min" != "-" ]] && req="needs $min+"

  if ! have "$cmd"; then
    report "$label" missing "not on PATH" "$req"
    record_problem "$key" missing "required"
    N_MISSING=$((N_MISSING + 1))
    return 1
  fi

  raw=$(eval "$vercmd" 2>&1)
  ver=$(first_version "$raw")

  if [[ -z "$ver" ]]; then
    report "$label" ok "present (version unknown)" ""
    N_OK=$((N_OK + 1))
    return 0
  fi

  if [[ "$min" != "-" ]] && ! ver_ge "$ver" "$min"; then
    report "$label" old "$ver" "$req"
    record_problem "$key" old "have $ver, need $min+"
    N_OLD=$((N_OLD + 1))
    return 1
  fi

  report "$label" ok "$ver" "$req"
  N_OK=$((N_OK + 1))
  return 0
}

# check_optional <label> <command> <version-command> <help-key> <needed-by>
check_optional() {
  local label="$1" cmd="$2" vercmd="$3" key="$4" needed="$5"
  local raw ver

  if ! have "$cmd"; then
    report "$label" optional "not on PATH" "$needed"
    record_problem "$key" optional "$needed"
    N_OPT_MISSING=$((N_OPT_MISSING + 1))
    return 1
  fi

  raw=$(eval "$vercmd" 2>&1)
  ver=$(first_version "$raw")
  report "$label" ok "${ver:-present}" "$needed"
  N_OK=$((N_OK + 1))
  return 0
}

say "${C_BOLD}Workshop tools check${C_RESET}"
say "  platform: $OS$( [[ $HAVE_BREW == 1 ]] && printf ' (homebrew present)' )"
say "  requirements: setup/01 intro.md    install guide: setup/02 tools.md"

# --- core toolchain --------------------------------------------------------

section "Core toolchain"

check_required "git"     git     -     'git --version'          git
check_required "bash"    bash    -     'bash --version'         bash
check_required "java"    java    21    'java -version'          java
check_required "javac"   javac   21    'javac -version'         java
check_required "mvn"     mvn     3.9   'mvn --version'          mvn
check_required "node"    node    20    'node --version'         node
check_required "npm"     npm     -     'npm --version'          node
check_required "python3" python3 3.11  'python3 --version'      python3
check_required "pip"     pip3    -     'python3 -m pip --version' pip

if python3 -c 'import venv' >/dev/null 2>&1; then
  report "venv" ok "module present" ""
  N_OK=$((N_OK + 1))
else
  report "venv" missing "python3 venv module not importable" ""
  record_problem venv missing "required"
  N_MISSING=$((N_MISSING + 1))
fi

# JDK extras used directly by the labs
for t in jar javap; do
  if have "$t"; then
    report "$t" ok "present" "from the JDK"
    N_OK=$((N_OK + 1))
  else
    report "$t" missing "not on PATH" "from the JDK"
    record_problem java missing "required"
    N_MISSING=$((N_MISSING + 1))
  fi
done

# --- container tooling -----------------------------------------------------

section "Container tooling"

if check_required "docker" docker - 'docker version --format "{{.Client.Version}}"' docker; then
  if docker info >/dev/null 2>&1; then
    report "docker daemon" ok "reachable" ""
    N_OK=$((N_OK + 1))
  else
    report "docker daemon" old "installed but not running" "start Docker"
    record_problem docker old "the daemon is not running — start Docker Desktop"
    N_OLD=$((N_OLD + 1))
  fi

  if docker scout version >/dev/null 2>&1; then
    sv=$(docker scout version 2>/dev/null | grep -i '^version:' | head -1)
    report "docker scout" ok "$(first_version "${sv:-}")" "needed by T02"
    N_OK=$((N_OK + 1))
  else
    report "docker scout" optional "not available" "needed by T02"
    record_problem docker-scout optional "needed by T02"
    N_OPT_MISSING=$((N_OPT_MISSING + 1))
  fi
fi

if have podman; then
  report "podman" info "$(first_version "$(podman --version 2>&1)") — partial substitute" ""
  say "         ${C_DIM}The scripts invoke docker directly; podman is not a"
  say "         transparent replacement, and does not provide Docker Scout.${C_RESET}"
fi

# --- SBOM and scanners ----------------------------------------------------

section "SBOM and vulnerability tooling"

check_optional "syft"      syft      'syft version'      syft      "S01, S02, T03, ship-check"
check_optional "grype"     grype     'grype version'     grype     "T04, T09"
check_optional "trivy"     trivy     'trivy --version'   trivy     "T03, T09"
check_optional "osv-scanner" osv-scanner 'osv-scanner --version' osv-scanner "T09"
check_optional "pip-audit" pip-audit 'pip-audit --version' pip-audit "T05"
check_optional "cosign"    cosign    'cosign version 2>&1 | grep -i "^GitVersion"' cosign "S07"
check_optional "guarddog"  guarddog  'guarddog --version'  guarddog  "T08"

if check_optional "snyk" snyk 'snyk --version' snyk "T01"; then
  if snyk whoami >/dev/null 2>&1; then
    report "snyk auth" ok "authenticated as $(snyk whoami 2>/dev/null | head -1)" "needed by T01"
    N_OK=$((N_OK + 1))
  else
    report "snyk auth" optional "not authenticated" "needed by T01"
    record_problem snyk-auth optional "needed by T01"
    N_OPT_MISSING=$((N_OPT_MISSING + 1))
  fi
fi

say ""
say "  ${C_DIM}npm audit (T07) ships with npm. The CycloneDX, Shade, Spring Boot,"
say "  esbuild and OWASP Dependency-Check Maven plugins are resolved by Maven"
say "  and need no local install.${C_RESET}"

# --- utilities ------------------------------------------------------------

section "Utilities"

check_required "jq"    jq    - 'jq --version'    jq
check_required "curl"  curl  - 'curl --version'  curl
check_required "unzip" unzip - 'unzip -v'        unzip
check_required "zip"   zip   - 'zip -v 2>&1 | grep -o "Zip [0-9][0-9.]*" | head -1' zip
check_required "tar"   tar   - 'tar --version'   tar

for t in grep find sort diff tee sed awk; do
  if have "$t"; then
    report "$t" ok "present" "system"
    N_OK=$((N_OK + 1))
  else
    report "$t" missing "not on PATH" "system"
    record_problem "$t" missing "required"
    N_MISSING=$((N_MISSING + 1))
  fi
done

# --- machine ----------------------------------------------------------------

section "Machine"

# The workshop needs real disk headroom: two container images plus build
# space (~20GB), or the scenario builds + scanner DBs locally (~10GB).
# A full disk doesn't fail politely — Docker's VM goes read-only.
# Check the repo's filesystem AND the home filesystem (Docker Desktop's
# disk image lives under the home volume) — they are often different disks.
check_disk() { # check_disk <label> <path>
  local label="$1" path="$2" free_kb free_gb
  free_kb=$(df -k "$path" 2>/dev/null | awk 'NR==2{print $4}')
  [[ -n "${free_kb:-}" ]] || return 0
  free_gb=$(( free_kb / 1024 / 1024 ))
  if [[ $free_gb -ge 20 ]]; then
    report "$label" ok "${free_gb}GB free" "20GB+ recommended"
    N_OK=$((N_OK + 1))
  elif [[ $free_gb -ge 8 ]]; then
    report "$label" old "${free_gb}GB free" "20GB+ recommended"
    record_problem disk old "have ${free_gb}GB free on ${path}; images plus build headroom want ~20GB"
    N_OLD=$((N_OLD + 1))
  else
    report "$label" missing "${free_gb}GB free — too little" "20GB+ recommended"
    record_problem disk missing "required"
    N_MISSING=$((N_MISSING + 1))
  fi
}
repo_dev=$(df -k . 2>/dev/null | awk 'NR==2{print $1}')
home_dev=$(df -k "$HOME" 2>/dev/null | awk 'NR==2{print $1}')
check_disk "disk (repo)" .
if [[ -n "$home_dev" && "$home_dev" != "$repo_dev" ]]; then
  check_disk "disk (home)" "$HOME"
fi

# --- credentials ----------------------------------------------------------

section "Accounts and keys"

if [[ -n "${NVD_API_KEY:-}" ]]; then
  report "NVD_API_KEY" ok "configured" "T06 uses Dependency-Check 13.0.0"
  N_OK=$((N_OK + 1))
else
  report "NVD_API_KEY" optional "not set" "T06 falls back to 12.2.2"
  record_problem nvd-key optional "T06 falls back to Dependency-Check 12.2.2"
  N_OPT_MISSING=$((N_OPT_MISSING + 1))
fi

# ---------------------------------------------------------------------------
# Installation instructions
# ---------------------------------------------------------------------------

print_help_for() {
  local key="$1" state="$2" detail="$3"
  local heading
  case "$state" in
    missing) heading="${C_RED}missing${C_RESET}" ;;
    old)     heading="${C_YEL}$detail${C_RESET}" ;;
    *)       heading="${C_DIM}optional — $detail${C_RESET}" ;;
  esac
  printf '\n  %s%s%s  %s\n' "$C_BOLD" "$key" "$C_RESET" "$heading"
  install_help "$key" | while IFS= read -r line; do
    case "$line" in
      http*) printf '      %s\n' "$line" ;;
      *)     printf '    %s\n' "$line" ;;
    esac
  done
}

if [[ "$SHOW_ALL_URLS" == 1 ]]; then
  section "Installation instructions (all tools)"
  for k in git java mvn node python3 pipx pip-audit docker docker-scout \
           syft grype trivy osv-scanner snyk cosign guarddog jq curl zip brew nvd-key snyk-auth; do
    printf '\n  %s%s%s\n' "$C_BOLD" "$k" "$C_RESET"
    install_help "$k" | while IFS= read -r line; do
      case "$line" in
        http*) printf '      %s\n' "$line" ;;
        *)     printf '    %s\n' "$line" ;;
      esac
    done
  done
elif [[ -n "$PROBLEMS" ]]; then
  printf '\n%sHow to fix%s\n' "$C_BOLD" "$C_RESET"
  # Deduplicate keys, preserving first-seen order and worst state.
  printf '%s' "$PROBLEMS" | awk -F'|' '!seen[$1]++' | while IFS='|' read -r key state detail; do
    [[ -z "${key:-}" ]] && continue
    print_help_for "$key" "$state" "$detail"
  done

  if [[ "$OS" == macos && "$HAVE_BREW" != 1 ]]; then
    printf '\n  %sHomebrew%s  %snot installed — most macOS commands above need it%s\n' \
      "$C_BOLD" "$C_RESET" "$C_DIM" "$C_RESET"
    printf '      %s\n' "https://brew.sh"
  fi
fi

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------

printf '\n%sSummary%s\n' "$C_BOLD" "$C_RESET"
printf '  present and new enough : %d\n' "$N_OK"
printf '  too old                : %d\n' "$N_OLD"
printf '  missing (required)     : %d\n' "$N_MISSING"
printf '  missing (optional)     : %d\n' "$N_OPT_MISSING"

echo
if [[ "$N_MISSING" -gt 0 || "$N_OLD" -gt 0 ]]; then
  echo "  ${C_RED}Not ready.${C_RESET} Resolve the required items above, then re-run this check."
  echo "  Full install guide: setup/02 tools.md"
  exit 1
fi

if [[ "$N_OPT_MISSING" -gt 0 ]]; then
  echo "  ${C_YEL}Ready for most of the workshop.${C_RESET} The optional items above will"
  echo "  limit the investigations that named them."
else
  echo "  ${C_GRN}Ready.${C_RESET} Every tool the workshop uses is present."
fi

echo
echo "  Next: warm the machine with  ./scripts/build-all.sh"
exit 0

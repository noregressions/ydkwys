#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

# Builds S01 as it stands (no provenance) into a JAR and a Docker image, then
# asks the reverse-audit question: starting from the artefact alone, what can
# we recover about where it came from?

copy_s01
cd "$SRC"
git init -q && git add -A \
  && git -c user.email=lab@example.com -c user.name=lab commit -qm "S01 baseline" \
  && git remote add origin https://github.com/herodevs/kcdc2026workshop.git

echo "== Build frontend + Maven =="
( cd frontend && npm ci >/dev/null 2>&1 && npm run build >/dev/null 2>&1 )
mvn -q clean package -DskipTests

echo "== Build the baseline image (Dockerfile as shipped, no provenance) =="
docker build -q -t "$IMG:baseline" . >/dev/null

echo
echo "===== REVERSE AUDIT — baseline artefact ====="
echo "-- Which commit produced this? (git.properties in the JAR) --"
if unzip -l service/target/service-1.0.0.jar | grep -q git.properties; then
  echo "   FOUND"
else
  echo "   MISSING — the JAR names no commit"
fi
echo "-- Which repo/commit built this image? (OCI labels) --"
docker image inspect "$IMG:baseline" --format '{{json .Config.Labels}}' | tee "$RESULTS/baseline-labels.json"
echo "   (only the base image's inherited label; nothing of ours)"
echo "-- What is inside? (an SBOM travelling with the image) --"
echo "   NONE — no SBOM was produced or attached"
echo "-- Can we prove the image is what we think? (a signature) --"
echo "   NONE — nothing is signed; only a mutable tag names it"
echo
echo "Baseline verdict: from the artefact alone you cannot name the commit,"
echo "the repository, the dependency inventory, or prove the bytes. Run"
echo "./scripts/add-provenance.sh to record each of those, one layer at a time."

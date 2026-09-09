#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

IMAGE="payara-mvnpm-trace-lab:local"
CONTAINER="payara-mvnpm-trace-lab"

if [[ ! -f target/payara-mvnpm-trace-lab-1.0.0.war ]]; then
  echo "WAR not found; building first..."
  mvn clean package
fi

docker build -t "$IMAGE" .
docker rm -f "$CONTAINER" >/dev/null 2>&1 || true
docker run -d --name "$CONTAINER" -p 8080:8080 "$IMAGE" >/dev/null

echo "Container started. Payara will deploy the WAR as /trace."
echo
echo "Open: http://localhost:8080/trace/"
echo
echo "Logs: docker logs -f $CONTAINER"

#!/usr/bin/env bash
set -euo pipefail

command -v kubectl >/dev/null || { echo "kubectl is required" >&2; exit 1; }

kubectl get deployment checkout-service \
  -o jsonpath='{.spec.template.spec.containers[0].image}{"\\n"}'

kubectl get pods -l app=checkout-service \
  -o jsonpath='{range .items[*]}{.metadata.name}{"\\t"}{.status.containerStatuses[0].image}{"\\t"}{.status.containerStatuses[0].imageID}{"\\n"}{end}'

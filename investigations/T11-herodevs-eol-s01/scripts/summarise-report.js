#!/usr/bin/env node
// Reduce a `hd scan eol --save` report to the few facts this investigation
// argues about: how many components the scan saw at all, which of them are
// end of life and why, which carry CVE records, and which have a commercial
// support path. Everything else in the payload is detail for a different
// question.
'use strict';

const fs = require('fs');

const path = process.argv[2];
if (!path) {
  console.error('usage: summarise-report.js <herodevs.report.json>');
  process.exit(2);
}

if (!fs.existsSync(path)) {
  // Distinct from an empty scan: the CLI writes no report when the SBOM it
  // built had no components, and that is a result. A missing file here just
  // means this probe did not run.
  console.log('(no report file for this probe)');
  process.exit(0);
}

let report;
try {
  report = JSON.parse(fs.readFileSync(path, 'utf8'));
} catch (e) {
  console.log(`(unreadable report: ${e.message})`);
  process.exit(1);
}

const components = report.components || [];
const cves = (c) => (Array.isArray(c.metadata?.cveStats) ? c.metadata.cveStats : []);
const nes = (c) => (c.nesRemediation?.remediations || []);

const eol = components.filter((c) => c.metadata?.isEol === true);
const unknown = components.filter((c) => c.metadata?.isEol === null || c.metadata?.isEol === undefined);
const withNes = components.filter((c) => nes(c).length > 0);

console.log(`report=${report.id}`);
console.log(`createdOn=${report.createdOn}`);
console.log(`components=${components.length}`);
console.log(`eol=${eol.length}`);
console.log(`unknown=${unknown.length}`);
console.log(`nesAvailable=${withNes.length}`);

const line = (c) => {
  const m = c.metadata || {};
  const reasons = (m.eolReasons || [])
    .map((r) => (typeof r === 'string' ? r : r.heuristic || JSON.stringify(r)))
    .join(',');
  const next = m.nextSupportedVersion?.version || '-';
  const parts = [`  ${c.purl}`, `next=${next}`, `cves=${cves(c).length}`];
  if (m.eolAt) parts.push(`eolAt=${m.eolAt.slice(0, 10)}`);
  if (reasons) parts.push(`reasons=${reasons}`);
  if (m.unknownReason) parts.push(`unknown=${m.unknownReason}`);
  return parts.join('  ');
};

if (eol.length) {
  console.log('eol components:');
  eol.forEach((c) => console.log(line(c)));
}
if (unknown.length) {
  console.log('unknown components:');
  unknown.forEach((c) => console.log(line(c)));
}
if (withNes.length) {
  console.log('nes remediation available:');
  withNes.forEach((c) => console.log(`${line(c)}  isEol=${c.metadata?.isEol}`));
}

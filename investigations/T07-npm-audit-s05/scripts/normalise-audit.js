#!/usr/bin/env node
const fs = require("fs");

const file = process.argv[2];
if (!file) {
  console.error("usage: normalise-audit.js <audit.json>");
  process.exit(2);
}

let raw = "";
try {
  raw = fs.readFileSync(file, "utf8");
} catch (e) {
  console.error(`cannot read ${file}: ${e.message}`);
  process.exit(2);
}

let data;
try {
  data = JSON.parse(raw);
} catch (e) {
  console.log("json=false");
  console.log("vulnerabilityRecords=unknown");
  console.log("dependencyTotal=unknown");
  console.log("vulnerabilities:");
  console.log("(unparseable output)");
  process.exit(0);
}

const vulnMap =
  data && typeof data.vulnerabilities === "object" && !Array.isArray(data.vulnerabilities)
    ? data.vulnerabilities
    : {};

const names = Object.keys(vulnMap).sort();
const metadata = data.metadata || {};
const metaVulns = metadata.vulnerabilities || {};
const metaDeps = metadata.dependencies || {};

const vulnTotal =
  Number.isFinite(metaVulns.total)
    ? metaVulns.total
    : names.length;

const depTotal =
  Number.isFinite(metaDeps.total)
    ? metaDeps.total
    : "unknown";

console.log("json=true");
console.log(`vulnerabilityRecords=${vulnTotal}`);
console.log(`dependencyTotal=${depTotal}`);
console.log("vulnerabilities:");

if (names.length === 0) {
  console.log("(none)");
} else {
  for (const name of names) {
    const v = vulnMap[name] || {};
    const via = Array.isArray(v.via) ? v.via : [];
    const viaText = via.map(x => {
      if (typeof x === "string") return x;
      if (x && typeof x === "object") {
        return [x.source, x.name, x.title, x.url].filter(Boolean).join(" | ");
      }
      return String(x);
    }).join(" ; ");
    console.log([
      name,
      v.severity || "",
      v.isDirect === true ? "direct" : (v.isDirect === false ? "transitive" : ""),
      v.range || "",
      viaText
    ].join("\t"));
  }
}

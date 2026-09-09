---
id: workshop-appendix-ai-dependencies
oneliner: "Parked material on AI-generated dependencies: graph expansion, package hallucination, and why none of it changes the boundaries — it only speeds up traffic across them."
track: reference
status: parked
---

# Appendix — AI and the Supply Chain

Parked, and off the route. This material was written for a place in the
running order and pulled out again while the topic is out of scope; the notes
are kept here because the underlying point survives whatever the tooling does
next.

That point: AI-assisted development does not create a new supply chain
boundary. Every dependency an assistant suggests crosses exactly the same
boundaries as one a human chose, and is subject to exactly the same evidence
limits proved in Part 2. What changes is throughput — how many dependency
decisions get made, and who is awake for them.

## Notes

1. **Dependency Profile Shift Under LLM Code Generation:**
   - Expansion of transitive dependency graph depth and package volume.
   - Selection bias toward training set frequency rather than project health, active maintenance, or minimal surface area.

2. **Package Hallucination and Namespace Squatting:**
   - Mechanism: Generative language models predict synthetic package names across ecosystem namespaces (npm, PyPI).
   - Exploitation vector: Registration of predicted package identifiers with malicious payloads.
   - Ingress point: Automated developer tooling executing `npm install` or `pip install` on generated manifests.

3. **Analysis of AI-Generated Malware Fixtures:**
   - Technical dissection of malicious code generation patterns, evasion techniques, and execution triggers.
   - Isolation requirements: Execution within dedicated non-networked containment sandboxes.

4. **Integration with Defensive Supply Chain Controls:**
   - AI-suggested dependencies traverse identical supply chain boundaries (resolution, transformation, runtime packaging) and require the ingress controls established in Part 5.

## Technical Architecture Summary

```text
1. Automated code generation increases dependency ingress velocity.
2. Unregistered hallucinated package identifiers create preemptive registration attack surfaces.
3. Ingress controls, private registries, and explicit pinning must precede automated resolution.
```

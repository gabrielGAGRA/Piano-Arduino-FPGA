---
name: adversarial-review 
description: Independently try to break every diff and retain only evidence-backed findings.
---

# Adversarial Review

## Goal

Challenge the change contract rather than confirming the author's intent. Run before every delivery or git write.

An adversarial reviewer acts as fresh eyes on the work: reading the diff (read-only), with no memory or bias of writing the code, actively probing for ways the changes could fail, break existing functionality, or behave unexpectedly.

## Context isolation

Use a fresh local subagent. Give it the approved task/plan contract if one exists, the diff, and only the repository context needed to test a hypothesis.

## Workflow

	1.	Classify risk — always scope/regression. 
	2.	Create falsifiable break hypotheses from the approved task/plan contract (when present) and diff. 
	3.	Trace each hypothesis through affected code, tests, and boundaries. 
	4.	Attempt to refute each candidate finding with code or executable evidence. Discard a candidate that cannot establish a reachable failure path. 
	5.	Return one verdict:
	⁃	pass — no evidence-backed Required finding remains;
	⁃	blocked — a Required finding has a reproducible impact;
	⁃	needs-human-decision — an unresolved product or risk trade-off blocks a reliable conclusion.

	Example:
	"Use the adversarial-review agent: try to break x before we ship"
	* Agent reads the diff, migration and tests
	"Verdict: tests pass but the y hole is still open. Do not ship."


## Finding requirements

Every retained finding must include severity, location, reproduction scenario, controlled input/state, traced failure path, concrete impact, and the verification needed after remediation. Do not report style preferences, speculative defects, or findings without an attack/regression path.

## Output

```markdown
# Adversarial Review

## Verdict
[pass | blocked | needs-human-decision]

## Context isolation
[fresh subagent | separate chat | same-session fallback]

## Findings
- `path:Lx` — [severity] [scenario, evidence, impact, required verification]

## Checks refuted
- [candidate hypothesis and evidence that disproved it]
```

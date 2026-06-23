## Summary

- what changed
- why it changed

## Validation

- [ ] `./scripts/test-native-editor.sh --no-snapshots`
- [ ] `./scripts/test-markdown-spec-conformance.sh`
- [ ] `./scripts/run-typing-behavior-gate.sh --lane pr`
- [ ] `cd scripts/kern-bench && swift test -c release`
- [ ] benchmark harness changed: `python3 -m unittest discover scripts/tests`
- [ ] cross-editor benchmark harness changed: `./scripts/cross-editor-benchmark.sh --suite benchmark_open_ready --editors "TextKit Baseline" --artifact-dir benchmark-archive/cross-editor-preflight/pr-preflight --preflight-only`
- [ ] performance-sensitive app/rendering change: baseline/candidate A/B artifacts attached or linked
- [ ] not applicable; no editing-behavior change
- [ ] not applicable; no benchmark-harness change
- [ ] not applicable; no performance-sensitive app/rendering change
- [ ] docs-only change; no app/test run required

## Artifacts

List any relevant artifacts when useful:

- screenshots
- snapshot diffs
- benchmark results (`metrics-summary.json`, `summary.md`, `raw.log`, `preflight.json`, `command.txt`, readiness captures, and process-snapshot artifacts)
- strict spec output

For performance-sensitive changes, include the named baseline, candidate run,
fixture-hash compatibility, regression decision, and whether the run was
release-quality or diagnostic-only.

## Checklist

- [ ] tests/docs were updated with the change
- [ ] change is narrow and scoped
- [ ] no sensitive details were posted publicly

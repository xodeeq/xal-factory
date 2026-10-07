## Session S1: Slugs, and the length bound

- risk_class: code-only
- status: passed
- evidence: PR: https://example.invalid/pr/1 · driver run (gate): https://example.invalid/run/1
- depends_on: []
- scope_in: slug.go and its tests — FX-FR-01 and FX-FR-02
- scope_out: anything that stores or serves a slug
- artifacts:
  - slug.go
  - slug_test.go
- gate:
  - command: go test ./...
  - must_not: no name over 64 characters yields a slug
- retry_cap: 2
- on_exhaustion: escalate
- human_only_actions_before: []
- prompt: |
    Build `Slug` per FX-FR-01 and FX-FR-02. Strict TDD: each requirement's failing test is
    committed before the code that satisfies it.

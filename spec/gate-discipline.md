# The gate discipline

A **gate** is a check whose exit code decides whether work is done. Everything else in this
process — the session ritual, the seeding of new repos, continuous deployment — rests on a
gate script whose verdict can be trusted. This document is the set of rules that keeps that
verdict honest. They were each earned by a specific failure, and the failure is recorded
next to the rule so the rule is not mistaken for a preference.

## 1. One script is the Definition of Done

Every repo has **one gate script** (`scripts/check.sh` by convention) that runs every gate,
in order, and exits non-zero at the first failure naming the gate that fired. **CI invokes
that exact script**, so "green locally" equals "green in CI" byte for byte.

- **To change a gate, change the script, not the workflow.** The only thing a workflow may
  add is an *input* a gate needs (a toolchain, a checkout, a credential), never gate logic.
- **A prose list of the gates goes stale the moment a gate is added, and nothing fails when
  it does.** The script is the list. Documentation says "read the gate names off the
  script", not "there are seven gates".

## 2. The gate order is a process decision; the language realizes it

Gates run **cheapest and most localising first**, so a failure names the smallest thing
that could be wrong and a broken tree is reported in seconds, not after an image build.
The order below is the process's; each language overlay maps its own tools onto it.

| # | Gate | What it decides |
|---|---|---|
| 0 | **gate inputs** | every input the script needs is declared, and every caller supplies it (§4) |
| 1 | dependencies | the lock file is verified and is exactly what the resolver would write |
| 2 | format | the formatter reports nothing |
| 3 | compile / static analysis | the code builds and the compiler-grade analyzers pass |
| 4 | lint | the linter passes, at a pinned version |
| 5 | test | the test suite passes, with the race detector on where the language has one, collecting coverage |
| 6 | coverage floors | per-package floors hold (§7) |
| 7 | vulnerability audit | no known-vulnerable dependency |
| 8 | image build | the container image builds |
| 9 | spec drift | the vendored process spec matches the version it is pinned to |

A gate that does not apply to a repo (a documentation repo has no compiler) is omitted, not
stubbed: a gate that always passes is worse than no gate, because it reads as coverage.

## 3. Skippable locally, mandatory in CI

A gate whose input is heavy or ambient (a container daemon, a sibling checkout, a linter
binary) may **skip locally** when the input is absent — printed **loudly**, never silently —
and is **mandatory under `CI=true`**, where it fails instead. A developer without the tool
still gets a useful local run; CI gets no such courtesy.

## 4. Inputs are declared data, and a meta-gate checks every caller

A gate script cannot see its own callers. Twice in four days, a gate was added that needed
something not in the repo — a sibling checkout, a CLI — and one workflow that invoked the
script was not updated to supply it. The first time it blocked production deploys for
hours while CI on the same commit stayed green; the second time, a guardrail saying "grep
every caller before pushing" was already written, and it failed anyway, because a guardrail
is a memory aid attached to nothing. The author's machine satisfied the input ambiently;
CI had to satisfy it explicitly; and the environment that created the obligation was
structurally unable to reveal it.

So inputs are **declared as data** in `.xal/gate-inputs`, one record per line:

```
id | detect | required-in-ci | caller-pattern | expires | description
```

and `.xal/check-gate-inputs.sh` runs as **gate 0**. It derives what the gate script actually
requires (from `command -v NAME` and `VAR="${VAR:-default}"` idioms), fails on anything
undeclared, discovers every workflow that invokes the gate script, and asserts each one
matches every required input's `caller-pattern`. A pattern may be scoped to one workflow
(`deploy.yml:secrets.MY_TOKEN`) for inputs that other workflows consume.

- **Gate 0 requires no inputs of its own.** It reads only files already in the repo. A
  check that catches missing inputs must not itself be able to have one missing.
- **Zero callers is a failure, never a pass.** A renamed gate script would otherwise
  silently empty the check while it kept reporting green.
- **A credential declares its expiry.** A caller-pattern naming `secrets.` is a credential
  by construction, so `expires` must be a real date there; a past date fails, a date within
  thirty days warns. A secret has an expiry whether or not it is written down; putting it in
  the manifest is the difference between a rotation you schedule and one you discover from
  a red checkout.

## 5. Every gate ships with committed failing fixtures

**A gate that has never been seen to fail has not been tested.** A rule matching nothing
and a rule finding nothing emit byte-identical green, and `return 0` passes just as
convincingly as real logic. This has bitten in four distinct ways: a POSIX `awk` reading
`\b` as backspace so a leak pattern matched nothing; `comm` on numerically sorted input
mis-pairing line numbers; a file glob for a language the repo did not contain; and a rule
that was dead on arrival and green for weeks.

So, for every gate:

- **one committed fixture per rule, proving that rule fails** — the clean tree broken in
  exactly one way;
- **assert *which* gate fired**, by matching the gate's own output, not only the exit code —
  a gate can fail for the wrong reason and look right from its exit code alone;
- **a clean fixture too**, proving the chain can still say yes, so "always fails" is caught
  as surely as "never fails";
- where the rules are several, assert each fixture fires **exactly one** rule, so the
  fixtures discriminate between rules rather than merely tripping something.

**The harness is a separate CI step, not a gate inside the gate script.** Proving the chain
means running the chain, and a gate inside `check.sh` that ran the fixtures would recurse
forever. A reduced chain proves something other than what CI runs; an environment-variable
recursion guard makes the fixture run structurally different from the real run, which is
exactly the difference a fixture exists to rule out. The shape that works: the harness
copies the repo to a temporary directory, overlays one fixture, runs **that copy's** gate
script — the real script, the whole chain, in a tree that differs by one file — and asserts
the exit code and the gate name. It runs after the real gate so a genuine failure is
reported before a fixture failure.

**"The build ignores it" and "every tool ignores it" are different claims.** A fixture tree
is exactly where they come apart, because its purpose is to be broken. Hide fixtures from the
build by whatever convention the language offers, then check that convention against *every*
tool in the gate chain, one at a time.

## 6. Exit codes, matching, and the tree

- **Exit 0 is pass, 1 is "found a problem", 2 is "could not run."** They are never
  collapsed. A missing manifest, a bad argument or an absent fixture directory is an
  infrastructure fault, not a pass, and it must not read as the repo having a problem either.
- **Zero matches is never a pass.** A check that iterates an empty list — no language
  overlays, no source files, no callers — refuses to report green over nothing.
- **A gate never edits the tree it judges.** A gate that tidies, formats or regenerates in
  place cannot be run twice and mean the same thing. It reports the diff and leaves the tree
  as committed.
- **Never pipe a deliberately failing command into a test's condition.** With `pipefail` on,
  `check.sh | grep -q` returns the check's status, not grep's. Capture first, match second.
- **Never reuse a regex across two engines** without confirming both support its
  metacharacters. `grep -E` has `\b`; POSIX `awk` does not, and it fails silently.

## 7. Coverage floors are a ratchet, and the floors file is a closed world

Per-package coverage floors live in a committed `coverage-floors` file. A floor is **set from
the measured percentage of the first green build**, never from an aspiration, and it **only
ever goes up**. Guessing produces one of two useless states: so low it gates nothing, or so
high that the first honest commit is red and someone lowers it, which teaches everyone the
number is negotiable.

A floor of **0 is collect-only**: measured and printed, not gated — the honest state for a
package with no tests yet, visible rather than absent. A package with measured statements
and **no record fails the gate**, because "new code arrived ungated" and "coverage held" must
not emit the same green. A package listed with a non-zero floor and **no measured
statements fails**, because "the package vanished" and "the package is fully covered" must
not either.

## 8. Nothing enters without a caller

A script nothing invokes, a fixture tree no harness names, a field no session fills, a
convention nobody follows: each is worse than absent, because every signal a reader checks —
the file is present, the rule is written down — says the work is done. Before adding
anything the question is not "is this good?" but **"what calls it, today?"** If the answer is
"nothing yet", it is not ready to land. Wire it to a caller or delete it; carrying it is not
an option.

The test to apply to a rule that has never been exercised is not "has this been used?" but
"**could** it be, by the people and mechanisms that actually exist?" A rule nothing can
satisfy is not a discipline that slipped; deleting it is the honest fix.

## Checklist (a gate script is trustworthy when…)

- [ ] It is one script, in the gate order above, and CI invokes it verbatim.
- [ ] Gate 0 runs first, needs no inputs, and `.xal/gate-inputs` declares every input with
      an `expires` value.
- [ ] Every gate that can skip locally is mandatory under `CI=true` and prints its skip.
- [ ] A fixture harness, run as its own CI step, proves each gate can fail naming itself,
      and a clean fixture proves the chain can pass.
- [ ] Exit 2 is distinguishable from exit 1; an empty input set is a failure.
- [ ] No gate modifies the working tree.
- [ ] Coverage floors are recorded from measurement and the floors file is a closed world.
- [ ] Every script, fixture and field in the repo has a caller you can name.

# no-plan fixture

`docs/plan/` exists and `plan.md` does not. The gate must exit **2** (could not run), never
0. "The planner has not run yet" and "the plan is clean" must never emit the same verdict —
that is the exact shape that let a vendored checker sit inert for 27 days while every signal
a reader checks said it was covered.

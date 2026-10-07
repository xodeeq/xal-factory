# Lift ledger

Every file in this repo that was lifted from the private estate the factory was extracted
from has one row here: where it came from, at which commit, and what was changed on the way
in. This is the record of how current the factory is, and the input to the next lift.

Gate 8 (`scripts/check.sh`, the strip-terms gate) exempts this file and only this file
outside the fixtures, because naming each file's source is its job.

## Sources

Each source is read at `origin/main`, never at a local branch.

| Source | Commit | Read on |
|---|---|---|
| xal-platform | 62153f5 | 2026-10-05 |
| xal-company | f5aaed1 | 2026-10-05 |
| xal-org | 7737215 | 2026-10-05 |
| xal-auth | 802fc04 | 2026-10-05 |
| xal-invoicing | f271772 | 2026-10-05 |

The first extraction (2026-09-20, commit e651c57 here) predates this ledger. Its sources
are recorded in [`docs/sessions/01.md`](sessions/01.md).

## Rows

Format: `source:path` → `factory path` · stripped · parameterized.

| Source | Factory path | Stripped | Parameterized |
|---|---|---|---|

## Deferred

Things the source has that the factory does not take yet, each with the trigger that would
bring it in. Nothing enters without a caller.

| Source | What | Trigger |
|---|---|---|

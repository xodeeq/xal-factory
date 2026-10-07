#!/usr/bin/env bash
# FIXTURE stub of gates/driver.test.sh: names the scripts rule 5 derives its list from.
bash scripts/driver/preflight.sh; bash scripts/driver/select-next.sh
bash scripts/driver/merge-decision.sh; bash scripts/driver/reader-verdict.sh

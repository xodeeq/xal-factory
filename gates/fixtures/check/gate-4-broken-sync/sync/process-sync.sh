#!/usr/bin/env bash
# FIXTURE: a sync that vendors nothing and reports success.
mkdir -p docs/process
printf "PROCESS_VERSION=%s\n" "$(cat "$1/VERSION")" > docs/process/sync.config
exit 0

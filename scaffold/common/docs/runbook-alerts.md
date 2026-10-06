# Alert runbook: <SERVICE>

**Documents, not wiring.** Each alert below is written down before it is wired, so that
when it is wired the threshold, the reason and the first response already exist. An alert
with no runbook entry is a page nobody knows how to answer. Mark each row `wired` only when
a rule in the monitoring stack actually fires it, with a link to that rule.

| Alert | Signal (from the service conventions) | Threshold | First response | State |
|---|---|---|---|---|
| Not ready | `/health/ready` non-200 from the host's check | 3 consecutive failures | Which hard dependency? Readiness names it; check that dependency first | documented |
| Error rate | 5xx share of requests (`/metrics`) | > 1% over 10 min | Find the code in the problem documents logged with `X-Trace-Id`; roll back if it started with a deploy | documented |
| Latency | p95 request duration (`/metrics`) | above the spec's NFR for 10 min | Compare against the last deploy; check the database pool | documented |
| Smoke failed | `scripts/smoke.sh` in deploy.yml | any failure | The deploy is broken: roll back to the previous release, then read the failing check | wired by deploy.yml |
| Credential expiring | gate 0 warns 30 days before an `expires` date in `.xal/gate-inputs` | 30 days | Rotate, write the new date, re-run the gate | wired by gate 0 |

Add a row per service-specific signal (a queue depth, a feed lag) with the spec clause it
protects.

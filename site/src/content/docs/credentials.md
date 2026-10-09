---
title: Credentials
description: The three repository secrets a service needs, what each one may do, and which kind of token to make.
---

A seeded service needs three repository secrets before its pipeline can run. Each one is a
grant that only a person can make, which is why the seeder prints them and stops. After
setting each one, write its real expiry date into `.xal/gate-inputs`. Gate 0 refuses the
placeholder, and it warns 30 days before a date passes.

| Secret | What uses it | Kind |
|---|---|---|
| `CLAUDE_CODE_OAUTH_TOKEN` | the driver, the reader, `@claude` and the review bot | from `claude setup-token` |
| `FACTORY_READ_TOKEN` | the driver and the reader, to fetch the admitted spec from the ops repo | fine-grained token |
| `FACTORY_WRITE_TOKEN` | opening and merging session PRs, dispatching the chain, the spend ledger, escalation issues | fine-grained token |

## `CLAUDE_CODE_OAUTH_TOKEN`

Run `claude setup-token` and set the token it prints. It lasts one year from when you mint
it, so its expiry is the mint date plus one year. Also install the Claude GitHub App on the
service repo (github.com/apps/claude). The `claude*.yml` workflows stay inert until you do.

## `FACTORY_READ_TOKEN`

A fine-grained personal access token:

- **Repository access:** the ops repo only.
- **Permissions:** Contents: Read-only. Metadata: Read-only is added automatically.

If the ops repo is public, any token with public read works.

## `FACTORY_WRITE_TOKEN`

A fine-grained personal access token on **both** repos, the service and the ops repo:

- **Repository access:** the service repo and the ops repo.
- **Actions:** Read and write. The chain dispatches `driver.yml`, and merge and chain read CI's verdict through the Actions API (`scripts/driver/ci-verdict.sh`).
- **Contents:** Read and write. Pushing the session branch, merging, and the spend ledger in the ops repo.
- **Pull requests:** Read and write. Opening, updating and merging the session PR.
- **Issues:** Read and write. Escalation issues in the ops repo.
- **Commit statuses:** Read-only. The reader's verdict.
- **Metadata:** Read-only, added automatically.

A session was driven, read and merged with no person present under exactly this token on
2026-10-09. If a permission is missing, merge and chain stop at once and name it.

**Repos seeded before 0.2.1** still read CI through the Checks API, which no fine-grained
token can reach. Their merge refuses every session with `Resource not accessible by personal
access token`. Either upgrade them (the [0.2.1 release notes](https://github.com/xodeeq/xal-factory/releases/tag/v0.2.1)
list the files), or use a classic token with the `repo` scope until you do. A classic `repo`
token reaches every private repository its account can reach, so give it a short expiry and
retire it once the repo is upgraded.

## Why the pipeline does not use `GITHUB_TOKEN`

A pull request opened with `GITHUB_TOKEN` never triggers CI. A merge made with it triggers no
workflow, so the chain would never advance. A dispatch made with it does not run at all.
Each of these fails silently, so the gates refuse those shapes (`step-order.sh`,
`merge-check.sh` rule 6, `chain-check.sh`).

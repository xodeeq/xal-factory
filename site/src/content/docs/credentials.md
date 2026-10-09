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
| `FACTORY_WRITE_TOKEN` | opening and merging session PRs, dispatching the chain, the spend ledger, escalation issues | **classic token, for now** |

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

**This one must be a classic token with the `repo` scope, or a token minted by a GitHub
App.** Merge and chain read CI's verdict through the Checks API, and GitHub offers no Checks
permission to fine-grained tokens. With a fine-grained token, `merge.yml` refuses every
session with `Resource not accessible by personal access token`. Moving that read to an API a
fine-grained token can reach is tracked in
[#10](https://github.com/xodeeq/xal-factory/issues/10). This page will change when it lands.

A classic `repo` token reaches every private repository its account can reach. To keep that
blast radius small:

- Mint it from a dedicated machine account that is a collaborator on only the service and ops
  repos, if you can.
- Give it a short expiry and write that date into `.xal/gate-inputs`.
- Revoke it when you retire the pipeline.

What it does, on two repos:

| Repo | What it needs to do |
|---|---|
| the service | push the session branch; open, update and merge the session PR; dispatch `driver.yml` (the chain); read CI's check runs and commit statuses |
| the ops repo | append to the spend ledger (contents write); open escalation issues |

Once #10 lands, a fine-grained token with these permissions will do: Actions, Contents,
Pull requests and Issues set to Read and write, and Commit statuses set to Read-only.

## Why the pipeline does not use `GITHUB_TOKEN`

A pull request opened with `GITHUB_TOKEN` never triggers CI. A merge made with it triggers no
workflow, so the chain would never advance. A dispatch made with it does not run at all.
Each of these fails silently, so the gates refuse those shapes (`step-order.sh`,
`merge-check.sh` rule 6, `chain-check.sh`).

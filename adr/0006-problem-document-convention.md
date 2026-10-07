# ADR-0006: One problem-document convention, with snake_case codes

- **Status:** Accepted
- **Date:** 2026-10-05 (originally decided 2026-10-03 and accepted 2026-10-04, re-recorded here on the second lift)
- **Deciders:** Process maintainer

## Context

Every service returned RFC 9457 problem documents, and every spec agreed on the shape: a
URN `type`, `application/problem+json`, a `field` member on validation. Nothing said how a
code is spelled, so each implementation chose. When it was audited, one service served about
thirty kebab-case codes with one snake_case exception taken literally from its spec, another
served snake_case, a third served no codes at all and returned 422 for validation, and a
fourth had built nothing yet. One service spelled the same idea two ways, snake_case in an
event `reason` and kebab-case in a problem code.

Every code any admitted spec named was snake_case, and so was every event `reason` enum.
And nothing consumed a code yet: no client matched on `type`. A rename cost nothing that day
and would break a client later.

## Decision

1. **The problem document is a service convention**, `spec/service-conventions.md` §10:
   the members; `type` is `urn:<org>:<service>:error:<code>`, derived in one place;
   `about:blank` only for a problem with no code; `title` per type; `detail` per occurrence
   and never reflecting input; `field` named as on the wire.
2. **Codes are snake_case**, `^[a-z][a-z0-9]*(_[a-z0-9]+)*$`, the same rule as every other
   machine-matched value on the wire.
3. **A short shared vocabulary** for what every service meets at its transport layer:
   `validation_failed` 400, `unauthorized` 401, `forbidden` 403, `not_found` 404,
   `method_not_allowed` 405, `rate_limited` 429, `internal` 500, `not_ready` 503. A service
   uses these and mints no synonym.
4. **Every 400 carries `validation_failed`**, covering a request that cannot be read and a
   member that breaks its constraint. `field` names the member whenever one is at fault.
5. **Codes are contract.** Adding one is additive. Renaming or removing one that a released
   contract served is breaking.

## Alternatives considered

- **kebab-case.** The strongest case against snake_case: RFC 9457's own examples spell type
  URIs in kebab-case, and event `type` names are kebab-case too. Rejected because a problem
  code is not a type name. It is a value a client switches on, the same kind of thing as an
  event `reason`, and those were already snake_case. The RFC examples are examples, not a
  rule, and the event `type` is a separate, dotted, versioned namespace a code never shares.
- **Each service chooses.** Rejected: that was the finding. A client composing two services
  meets `not_found` and `not-found` for one idea.
- **Two validation codes** (`invalid_request` for unreadable, `validation_failed` for a
  broken constraint). Costs a distinction no client was known to act on.
- **No shared validation code**, a code per rule. Most specific, least uniform, and the only
  option under which two services can still spell validation differently.

## Consequences

- One spelling across a system, written where every service vendors it, before the first
  client exists. A service's code vocabulary becomes checkable by its own tests.
- A service that predates the convention renames its codes, and because the codes are its
  documented match key, that is a contract-version change for it.
- **Deferred:** a text gate over the API description that every
  `urn:<org>:<service>:error:` literal names its own service and matches the pattern, seeded
  from the scaffold's common tree with failing fixtures. Trigger: the first client that
  matches on `type`, or the next service seeded, whichever comes first.

# Service conventions

A system built from independently versioned services, possibly in several languages, only
stays operable if every service exposes the **same operational and contract surface**. This
document is that contract.

> **LANGUAGE IS AN IMPLEMENTATION DETAIL BEHIND A STANDARD CONTRACT.**

Each convention is stated language-agnostically. A service in any language mirrors the
*intent*; the *realization* is that service's own, recorded in its own repo. **Conform to
this document whenever you create or modify any service.**

Each convention is tagged:
- **[CI-enforceable]** — a machine can verify it; wire it into the service's gate script
  (see [`gate-discipline.md`](gate-discipline.md)).
- **[review-only]** — judgement required; verify in code review.

---

## 1. The API description is the HTTP source of truth — **[CI-enforceable]**
The HTTP surface is declared in `openapi.yaml` at the service root; routes and handlers
conform to it, not the other way round. Generated clients, contract tests and any service
catalogue read this file.
- *Enforce:* lint the description and assert the running app's routes match it (a
  description-vs-routes diff, or a property-based checker driven by the description) in CI.

## 2. Health: `/health/live` + `/health/ready` — **[CI-enforceable]**
- `GET /health/live` → 200 whenever the process is up (liveness; no dependencies).
- `GET /health/ready` → 200 **only** when hard dependencies (e.g. the database) are
  reachable, else 503. Orchestrators gate traffic on readiness.
- *Enforce:* CI or the smoke test hits both endpoints; readiness must be 503 before the
  database is up and 200 after.

## 3. Telemetry: OpenTelemetry + a Prometheus `/metrics` endpoint — **[CI-enforceable]**
Metrics and traces use **OpenTelemetry** (the cross-language standard); metrics are scraped
in Prometheus exposition format at `GET /metrics`.
- *Enforce:* assert `/metrics` returns Prometheus exposition format in CI.

## 4. Structured JSON logs with required fields — **[CI-enforceable]**
One JSON event per line, every line carrying **`service`**, **`environment`**,
**`traceId`** and **`event`**. **Never** log secrets, tokens or credentials.
- *Enforce:* a log-shape test asserting the required keys; the "no secrets" half is
  **[review-only]**.

## 5. `X-Trace-Id` propagation — **[CI-enforceable]**
Read the inbound `X-Trace-Id`; if absent, generate a UUID. Echo it on the response and
propagate it on outbound calls. One request is followable across service boundaries.
- *Enforce:* an integration test — a supplied header is echoed; an absent header yields a
  generated one on the response.

## 6. The container interface — **[CI-enforceable]** (config/port) · **[review-only]** (SIGTERM)
A service is a well-behaved container:
- **config from the environment** (no `.env` files in the image; secrets via env or a
  secret store);
- **listens on a configurable port**;
- **handles SIGTERM with graceful shutdown** (drain in-flight work, bounded).
- *Enforce:* CI builds the image (the image-build gate). SIGTERM drain behaviour is
  **[review-only]**; it is hard to assert cheaply.

## 7. Async-first interaction and the versioned event envelope — **[CI-enforceable]** (envelope) · **[review-only]** (edge declaration)

**Effects travel as events.** Anything that changes another service's state happens by
emitting a domain event, never by a synchronous call out of the service. A publisher never
holds a list of its consumers.

**Reads may be synchronous, narrowly.** A service may make a synchronous call for a **read
only**, when the request cannot be served with acceptable staleness from its own data, and
**one hop deep**. Token verification against an identity provider is the standing example.

**Every synchronous edge is declared.** Wherever the system records a service's
dependencies, each synchronous dependency is listed as a **runtime dependency**, distinct
from event dependencies, with a **timeout** and a **fallback** (serve stale, deny or
degrade). A service that cannot honour its declared fallback must not advertise the edge
(§9).

**Every event is a versioned envelope.** Events are carried in a standard envelope —
CloudEvents v1.0 in structured content mode is the recommended shape — with a versioned
`type` (`orders.order-placed.v1`). Consumers dispatch on the envelope, never on
transport-native metadata. **The transport behind the envelope is a per-system decision**;
the envelope is the contract.

- *Enforce:* schema-validate emitted envelopes; assert `type` is versioned. Edge
  declaration becomes **[CI-enforceable]** once a catalogue validates entries.

## 8. The purity principle — **[review-only]**
The **domain layer never touches wall-clock time, randomness or I/O** — these are
**injected**. Time enters through an explicit `now` parameter; persistence, hashing, signing
and clocks live behind ports implemented in outer layers. This keeps the core deterministic
and unit-testable without mocks of everything.
- *Verify in review:* no wall-clock reads, no RNG, no I/O in the domain layer. Promotable
  to **[CI-enforceable]** via a banned-API list, an import rule or an architecture test.

## 9. Variation behind an invariant contract — **[review-only]**
A service exposes **variation flags**, but each flag sits **behind an invariant contract**:
the core surface is identical across every flag combination; only the explicitly-allowed
slice may differ. The host **fails fast** at boot if it is configured for a profile it
cannot actually serve — a service must never advertise a capability it cannot honour.
Anything that breaks the invariant core is a **contract version bump, not a flag**.

**Every flag ships with a default.** The service's flag table in its spec and its
configuration loader both declare one value per flag, and a deployment that sets nothing
runs the **default profile**, which must be an implemented one, so the fail-fast rule above
applies to it too. A flag that genuinely cannot be defaulted is marked `required` with a
one-line reason in the same table, and that is expected to be rare: a person selecting the
service answers only the required questions. Simplicity on the user's path is a core value;
engineering complexity may be traded for it, never the other way round. The spec-intake
gate enforces the table shape on admission (rule 10); the service's startup test proves the
default profile boots.
- *Verify in review:* the invariant surface is byte-identical across flags; the fail-fast
  validator covers every unimplemented profile; every flag has a default or a `required`
  reason, and the default profile is one of the implemented ones. The fail-fast boot and
  the default-profile boot are partially **[CI-enforceable]** via a startup test per
  profile, the default profile included.

## 10. The problem document — **[CI-enforceable]** (shape, spelling) · **[review-only]** (choice of code, wording)

Every HTTP error a service returns is an **RFC 9457 problem document**, served as
`application/problem+json` and never as `application/json`. Its `type` member is what a
client matches on. Because one client composes many services, a code a client meets in one
service must be spelled the way it is spelled in every other service. The rationale and the
rejected alternatives are in
[ADR-0006](https://github.com/xodeeq/xal-factory/blob/main/adr/0006-problem-document-convention.md).

**The members.** `type`, `title` and `status` are always present. `detail` is optional.
`instance` may be omitted. `field` is the one extension member, defined below. No other
member is added without amending this section.
- `type` is `urn:<org>:<service>:error:<code>`. `<org>` is one namespace for the whole
  system and `<service>` is the same short name the service uses in its event `source`, so
  every service in a system shares a prefix shape. The service derives `type` from the code
  in one place, so a call site names a code and never writes a URI.
- `type` is `about:blank` only for a problem that carries no code, for instance a
  fallback the service did not shape. Then `title` is the HTTP status phrase (RFC 9457
  §4.2.1). Every error a route declares carries a code.
- `title` summarises the problem **type**. It is the same text for every occurrence of a
  code and never names the occurrence.
- `status` is a number and equals the response status.
- `detail` explains this occurrence. It never reflects request input back verbatim and
  never carries a secret, a token or an internal error message.

**The code.** A code is **snake_case**: lower-case ASCII letters and digits in words joined
by single underscores, starting with a letter. As a pattern, `^[a-z][a-z0-9]*(_[a-z0-9]+)*$`.
So `not_found`, `profile_incomplete`, `cap_exceeded`. Never `not-found`, `NotFound` or
`not.found`. The same rule spells every other machine-matched value on the wire (JSON
members, event `data` reason values), so a concept that appears as both a code and a
reason is spelled once.

**Codes are contract.** A code a released contract serves is part of that contract.
Adding a code is additive. Renaming or removing one is breaking, and a contract-version
decision under §9's last rule, not a quiet edit.

**Shared codes.** A service that needs one of these situations uses this code and status
under its own `<service>` prefix, and does not mint a synonym. A client matching a shared
code matches on the code after the last colon.

| Code | Status | Situation |
| :--- | :--- | :--- |
| `validation_failed` | 400 | The request cannot be read against the contract, or a member breaks its declared constraint. **Every 400 carries this code**, and `field` names the member whenever one is at fault |
| `unauthorized` | 401 | No credential this deployment accepts |
| `forbidden` | 403 | An authenticated caller whose role does not permit this |
| `not_found` | 404 | No such resource, or none visible to this caller, and no route matches |
| `method_not_allowed` | 405 | The route exists and the method does not |
| `rate_limited` | 429 | A rate limit refused the request |
| `internal` | 500 | The service failed. `detail` says nothing about why |
| `not_ready` | 503 | Readiness refused because a hard dependency is not answering (§2) |

A refusal of a well-formed request by state, conflict or business rule (409, 422, a
specific 403) names a service-specific code: `not_draft`, `slug_taken`, `cap_exceeded`.

**`field` on validation.** A `validation_failed` problem names the offending request
member in `field` whenever a single member is at fault, and omits `field` otherwise (a
body that is not JSON, an update that names nothing). One document names one member: the
service reports the first failure. The member is named as it appears on the wire. A body
member is its JSON path, dotted, with zero-based array indices (`bill_to.email`,
`lines[0].quantity`). A header is its header name (`X-Idempotency-Key`). A query or path
parameter is its parameter name.

- *Enforce:* **[CI-enforceable]** in each service's own `test` gate: the service's one
  problem constructor refuses a code outside the pattern and a 400 with any code other than
  `validation_failed`, with a committed failing test for each. Request tests assert the full
  `type`, the media type and `field` for every declared error, and that an unmatched route
  answers `not_found`. **[CI-enforceable], not yet built:** a text gate over the API
  description that every `urn:<org>:<service>:error:` literal names this service and
  matches the pattern; it belongs in the scaffold's `common/` gates so a seeded repo
  arrives with it. **[review-only]:** that the right shared code was used rather than a
  synonym, that `title` is per type, and that `detail` reflects no input and leaks nothing.

---

## How to use this document
- **New service:** treat §1–§10 as the acceptance checklist for "conforming". Wire every
  **[CI-enforceable]** item into that service's gate script and CI.
- **Modifying any service:** if a change touches one of these surfaces, re-check it here
  first; if it would break an invariant (especially §1, §2, §5, §7, §9, §10), that is a
  contract-version decision recorded as an ADR, not a quiet edit.
- The **deployment** counterpart to this contract is
  [`deployment-conventions.md`](deployment-conventions.md); the **gate** that enforces both
  is described in [`gate-discipline.md`](gate-discipline.md).

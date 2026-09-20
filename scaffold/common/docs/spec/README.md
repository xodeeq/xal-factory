# `docs/spec/` — what this service must be

The **spec** is the document that says what this service is for, what it owns, what it does
not own, and what "done" means for it. It is the input to planning, not a summary of the
code, and it is written **before** the first implementation session.

Two shapes are acceptable:

- **The spec lives here**, as `service.md`, with a version in its heading. Change it by PR
  like any other file; the plan cites the version it was built from.
- **The spec is admitted elsewhere** (a company repo, a product repo) and this directory
  holds **`service.md` as a pointer**: the service name, the spec version, a digest of the
  admitted file, and a link. Cite the spec by the identity it carries — name plus version —
  never by a filename in prose.

Do not keep a *copy* of a spec that is canonical elsewhere: a second copy that nothing diffs,
in the one place a reader would most reasonably trust, is worse than a pointer.

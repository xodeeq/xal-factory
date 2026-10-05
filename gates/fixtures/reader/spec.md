# fixture-slug 1.0.0 — the reader-eval spec

A synthetic spec, admitted nowhere. It exists so the reader can be run against a pull request
whose defect is known in advance.

## §3 Requirements

- **FX-FR-01** `Slug(name)` returns the name lowercased, with every run of spaces replaced by
  a single hyphen. `Slug("Acme  Corp")` is `acme-corp`.
- **FX-FR-02** `Slug(name)` refuses a name longer than 64 characters with `ErrTooLong` and
  returns no slug. A 65-character name is refused; a 64-character name is accepted.

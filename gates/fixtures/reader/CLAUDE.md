# CLAUDE.md — fixture-slug (the standards the reader applies)

- **Strict TDD.** A failing test is committed before the code that satisfies it; the commit
  list shows RED before GREEN for each requirement.
- **Every requirement a session cites is asserted by a test** that fails without it.
- No file outside the session's `scope_in` is changed.

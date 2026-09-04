# Contributing

- Scripts own mechanics; skills own judgment. A script that meets a surprise stops with `finding: ...`.
- Every script has a bats file. Every guard is break-verified once and the failure is pasted into the commit.
- `make check` must be green. `make lint` also refuses personal identifiers in tracked files.
- No personal paths, usernames, or project names in tracked files. Personal state lives in `data/`, `state/`, `config/`.
- Changes to the design go through `docs/specs/` first.

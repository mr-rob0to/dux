# Contributing

- Scripts own mechanics; skills own judgment. A script that meets a surprise stops with `finding: ...`.
- Every script has a bats file. Every guard is break-verified once and the failure is pasted into the commit.
- `make check` must be green after every task. `make check-branch` runs it again under bash 3.2
  and is the one to run once before `/ship`. `make lint` also refuses personal identifiers in
  tracked files.
- Test files run side by side. `make test JOBS=1` puts them back in a line when a failure is
  easier to read that way, and `bats tests/<file>.bats` runs one on its own.
- No personal paths, usernames, or project names in tracked files. Personal state lives in `data/`, `state/`, `config/`.
- Changes to the design go through `docs/specs/` first.

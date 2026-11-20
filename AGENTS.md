# AGENTS.md

## Keep the repo machine-neutral

This is a public project meant to work on anyone's Mac. Keep the maintainer's personal setup out of code, tests, fixtures and docs: no home-directory paths, no names of their own projects or folders, no settings or themes copied from their editors, no list of apps installed on their machine. Anything about the local machine is discovered at runtime. Test fixtures are generic files made for the test, not copies of real projects. Write examples in docs with neutral names.

## Agent skills

### Issue tracker

GitHub Issues on `mrmikedrum/infiniview`, via the `gh` CLI (account `mrmikedrum`). See `docs/agents/issue-tracker.md`.

### Triage labels

Default vocabulary: `needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `GLOSSARY.md` and `docs/adr/` at the repo root. See `docs/agents/domain.md`.

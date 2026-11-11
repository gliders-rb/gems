# gems — Timeworxs Ruby gems monorepo

One repo, several independently published gems, one docs site.

| Path | Gem |
|---|---|
| `gems/field_struct` | `field_struct` — typed POROs with declared, coerced, validated fields |
| `gems/actionable` | `actionable-rb` — action objects with declared inputs, steps and outcomes |
| `adapters/<name>` | adapter gems that build on the two above |
| `site/` | the documentation site for all of them |


## Conventions

- Ruby >= 3.3. Each gem is self-contained: its own gemspec, Gemfile,
  Rakefile, `spec/`, `.rubocop.yml` inheriting `../../.rubocop.yml`.
- Explicit `require_relative` for every file from the gem's entry point.
  No autoload, no Zeitwerk.
- JSON goes through Oj (`Oj.load` / `Oj.dump`), not the stdlib.
- Public methods get short YARD comments.
- TDD: write the failing spec first.
- Commits: conventional prefix plus gem scope, e.g. `feat(field_struct): ...`.

## Oracle

From a gem directory: `bundle exec rake` (rspec + rubocop). From the repo
root: `bin/oracle` runs every gem's oracle and exits non-zero on any failure.
Nothing is done until the oracle passes.


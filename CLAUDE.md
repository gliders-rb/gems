# gems — Timeworxs Ruby gems monorepo

One repo, several independently published gems, one docs site.

| Path | Gem |
|---|---|
| `gems/field_struct` | `field_struct` — typed POROs with declared, coerced, validated fields |
| `gems/actionable` | `actionable-rb` — action objects with declared inputs, steps and outcomes |
| `adapters/<name>` | adapter gems that build on the two above |
| `site/` | the documentation site for all of them |


## Tenets

These two hold for everything we write here. They are an experiment for now, so each one has a check in CI and we can tell whether it pays off.

1. **Everything is typed.** Every method we write, public or private, has an RBS signature, and Steep checks the code against it. The gems also type what users declare: a user's struct or action gets generated RBS, so editors and consoles can autocomplete it, and a misspelled field, option or keyword fails early instead of passing silently. Typed code is easier to read and use, for people and for AI agents alike.
2. **Document once, where the code is defined.** A field's declaration (name, type, options, `desc:`) and the YARD comment on a method are the one source for users. READMEs, site reference tables, schemas and RBS are generated from that source or checked against it, never copied by hand. Every example runs in CI, so a doc that drifts from the code fails the build.

When you add or change public API, say how it is typed and where its docs come from. Prefer generating a doc over writing a second copy.

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


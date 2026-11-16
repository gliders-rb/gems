# AGENTS.md

Guide for coding agents using the `actionable-rb` gem (`require 'actionable'`). Short on purpose; the details live in
the files below.

## Read these

- [USAGE.md](USAGE.md): the reference. Every public method is named there, with examples that run.
- [docs/getting_started.md](docs/getting_started.md): task-to-API map, what each error means and how to fix it.
- [README.md](README.md): overview.
- [skills/actionable/SKILL.md](skills/actionable/SKILL.md): the same guidance as a Claude Code skill.

## An action in a few lines

```ruby
class ArchiveLog < Actionable::Action
  input { required :imo, :string }
  output { required :archived_imo, :string }

  step :archive

  private

  def archive = @archived_imo = input.imo.delete('-')
end
```

## Gotchas

1. **`fail` records a failure, it does not raise.** Inside an action it is the gem's verb. To raise, use `raise`.
2. **Plain verbs keep running.** `fail(:x) if bad?` followed by more code is almost always a missing bang. Use `fail!`,
   or make the verb the last expression. The first `.run` raises `DefinitionError` listing each offense.
3. **Only declared output reaches the result.** Instance variables that are not in the `output` block are dropped. A
   required field that was never set ends the run as `Failure(:invalid_output)`.
4. **Codes are identifiers.** `fail!(:deck_full)`, never a sentence. Once an action declares any `fails` code it may
   only fail with declared codes (and `:invalid_input`, `:invalid_output`). Skips work the same way.
5. **Keywords after `fail`'s message are errors**, not metadata. Metadata comes from the `fails` declaration.
6. **A positional Hash to `.run` is ignored.** Splat it: `.run(**params)`.
7. **Step and hook options are a closed set**: `if:`, `unless:`, `input:`, `expose:`, `desc:` (plus keys an adapter
   registers). Anything else raises `DefinitionError` at declaration. Describe an action with `desc 'text'`.
8. **Reserved output names**: `code`, `message`, `output`, `history`, `errors`, `metadata`, `result`, `input` and every
   public Result method (`status`, `ok?`, `to_h` and so on) raise at declaration.
9. **A child failure is the parent's failure.** The parent must declare the child's code if it declares any. A child skip
   does not stop the parent.
10. **Adapters are opt-in requires**: `actionable/rails`, `actionable/job`, `actionable/rspec`,
   `actionable/rspec/coverage`, `actionable/rubocop`. Without the Rails one, `transactional` is a plain `NoMethodError`.
11. **Genuine exceptions propagate untouched**, and nothing after the raise runs, `always` hooks included.
12. **JSON goes through Oj.** Use `history.to_json` and `result.to_h`, not `JSON.generate`.
13. **A result is frozen once `.run` returns.** Hooks can still change it; after that, `result.with(...)` gives a copy.
14. **A bare `halt!` in the steps raises** when nothing was recorded yet. A halt that means "nothing to do" is
    `skip!`.

## Working on this gem

```
bundle exec rake                 # specs, adapter specs and RuboCop (fast)
bundle exec rake release:check   # adds doctests, signature checks, the docs check and the YARD build
bundle exec rake sigs:generate   # after changing any YARD comment: regenerate sig/actionable.rbs and commit it
```

Public methods need short YARD comments with types. Write keyword splats as `@param options [Object]` and third-party
types with a leading `::` (`::Prism::DefNode`). `sig/actionable.rbs` is generated, never edited by hand, and the two
other files in `sig/` are hand-written. A change to `lib/` needs a CHANGELOG entry under `[Unreleased]`.
The docs check fails when a public method or a `describe` key isn't named in code on USAGE.md and the site reference;
a method that is public only for the gem's own use gets `# @api private` instead.

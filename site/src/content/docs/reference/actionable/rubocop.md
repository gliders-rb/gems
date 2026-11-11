---
title: "RuboCop cop"
description: "The Actionable/VerbNotLast cop: how to enable it, what it reports, and how it decides which classes are actions."
sidebar:
  order: 11
---

`Actionable/VerbNotLast` flags what the first-run verb check flags (see [Control flow](/reference/actionable/control-flow/#where-a-plain-verb-may-go)), but it does so in your editor and in CI and never executes the code. It looks at one file at a time and shares the Prism-based analyzer with the runtime check (AC §5.15).

Every block on this page is plain code, since the cop needs RuboCop and the site's bundle doesn't include it.

## Enable it

On RuboCop 1.72 or newer, list the plugin in `.rubocop.yml`:

```yaml
plugins:
  - actionable-rb:
      require_path: actionable/rubocop
```

Older versions use `require: [actionable/rubocop]` instead. The gemspec names `Actionable::RubocopPlugin` as its lint_roller plugin, and that plugin only loads when `lint_roller` is around. Without it, an older RuboCop gets the shipped `config.yml` as its default configuration. Once loaded, the cop is on by default.

## Options

| Option | Default | Meaning |
|---|---|---|
| `ActionBaseClasses` | `Actionable::Action`, `ApplicationAction` | full names of the classes whose subclasses count as actions |

```yaml
Actionable/VerbNotLast:
  ActionBaseClasses:
    - Actionable::Action
    - ApplicationAction
    - Harbor::BaseAction
```

Setting `ActionBaseClasses` replaces the defaults, so repeat any you still want. A leading `::` is ignored.

## What it reports

An offense is reported on the call node itself, with line and column, and that holds for files with multibyte characters too:

```
`fail` records the outcome and keeps running, and more code runs after it: use `fail!` to stop here, or make it the method's last expression.
```

The offenses match the runtime ones: a plain verb followed by more code, a verb in a branch whose enclosing construct is followed by more code, a verb on the left of `and` or `or`, a verb nested inside a bigger expression, and a verb in a `begin` body that has an `else`. Bang verbs are never reported, and neither is a verb sent to another receiver.

```ruby
# bad
def board
  fail(:deck_full) if deck.full?
  issue_pass
end

# good
def board
  fail!(:deck_full) if deck.full?
  issue_pass
end
```

## What it checks

The cop checks a class body whose superclass is an action base and which declares `step` or `case_step`. The methods it inspects are those named in `step`, those that case-step branches point to (the second argument of `on`, the first of `default`), and those named in `on_success`, `on_failure`, `on_skip`, `always` and `after_commit`. A `Class.new(Base) do ... end` block counts too. The method that supplies a case step's value is never inspected.

A class is an action base when its name is in `ActionBaseClasses`, or when the same file defines it (`class X < Y` or `X = Class.new(Y)`, at any depth) and its superclass chain leads to a listed name. Names resolve the way Ruby resolves them: start at the enclosing `module` or `class`, move outward to the first match, fall back to top level, and read `::X` as absolute. Inside `module Harbor`, `Base` therefore means `Harbor::Base` when the file defines one, and a `Legacy::ApplicationAction` defined in the file shadows the listed default. A class the file defines speaks for itself, even if its full name is in the list as well. Other classes are left alone (say, one from a transaction library that has its own `step`), and so are classes reopened without a superclass. Cycles in the superclass chain don't loop forever.

A file Prism can't parse produces no offenses.

## See also

- [Control flow](/reference/actionable/control-flow/): the rule the cop enforces
- [Errors and guardrails](/reference/actionable/errors/): the runtime check
- [Actions and steps](/reference/actionable/actions-and-steps/): what counts as a step

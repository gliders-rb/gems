---
title: "How to catch a fail that does not stop the run"
description: "Enable the Actionable/VerbNotLast cop so a plain fail, succeed or skip with code after it is caught in your editor and in CI."
sidebar:
  label: "Lint with the RuboCop cop"
  order: 13
---

A step reads `fail(:deck_full) if deck.full?`, and the line below it runs regardless. Plain verbs only record an outcome and carry on, and the bang forms are the ones that stop. The cop spots the slip without executing anything.

RuboCop is not in the site's bundle, so everything on this page is plain code.

## 1. Enable the cop

On RuboCop 1.72 or newer, load the plugin from `.rubocop.yml`:

```yaml
plugins:
  - actionable-rb:
      require_path: actionable/rubocop
```

Older RuboCop versions take `require: [actionable/rubocop]` instead. Once loaded, the cop is on.

## 2. Tell it about your base classes

Out of the box it treats subclasses of `Actionable::Action` and `ApplicationAction` as actions. Setting the option replaces that list, so repeat any default you still rely on.

```yaml
Actionable/VerbNotLast:
  ActionBaseClasses:
    - Actionable::Action
    - ApplicationAction
    - Harbour::BaseAction
```

A class in the same file counts as well, when its superclass chain reaches one of these.

## 3. Fix what it reports

The offense lands on the call node and carries this message:

```
`fail` records the outcome and keeps running, and more code runs after it: use `fail!` to stop here, or make it the method's last expression.
```

Most of the time the fix is the bang form.

```ruby
# before
def assign_berth
  fail(:deck_full) if deck.full?
  record_boarding
end

# after
def assign_berth
  fail!(:deck_full) if deck.full?
  record_boarding
end
```

A plain verb is fine as the last statement of a method or a branch, after `return`, and on a different receiver. Bang verbs are never flagged.

## 4. Know the runtime check

The same rule also runs without RuboCop. On the first `.run`, the action class reads its step and hook methods and raises `Actionable::DefinitionError` that names every offense, so any spec that runs the action will catch it. The cop's job is to catch it sooner, in the editor and on each pull request.

## See also

- [RuboCop cop](/reference/actionable/rubocop/)
- [Control flow](/reference/actionable/control-flow/#where-a-plain-verb-may-go)
- [Success, failure, skip](/explanation/three-outcomes/)

---
title: "Rails adapter"
description: "Run an action in a database transaction, schedule work after the commit, and validate any object with ActiveModel rules."
sidebar:
  order: 9
---

Three things come with the Rails adapter: `transactional`, `after_commit` and `ProxyValidator`. You have to require it. It never loads itself, not even when ActiveRecord is defined, and without it `transactional` is a plain `NoMethodError` when the class is defined (AC-B#railsload).

```ruby
require 'actionable/rails'
```

ActiveModel and ActiveSupport's string inflections are required. Transactions want ActiveRecord 7.1 or newer, `after_commit` wants 7.2 or newer, and a no-op `Railtie` loads whenever `Rails::Railtie` exists.

:::note
The site doesn't run the examples on this page. Its bundle has no ActiveRecord, so they are plain code blocks. The adapter's own specs cover them against a real in-memory SQLite database.
:::

## `transactional`

```ruby
transactional(model:, **options)
transaction_config # => {model:, options:}, or nil
```

The whole run, hooks included, goes inside `model.transaction(**options) { ... }`. `model:` takes a class, or a Symbol or String that gets camelized and constantized (`:voyage` becomes `Voyage`). A subclass uses the config of the nearest ancestor that set one, and can set its own. `describe[:transactional]` shows it.

```ruby
class LogCrossings < Actionable::Action
  transactional model: :voyage
  step :record
  after_commit :radio_harbour
end

LogCrossings.transaction_config # => {model: :voyage, options: {}}
```

| Outcome of the run | Transaction |
|---|---|
| success | commits |
| skip | commits |
| recorded failure | rolls back, and the failure result is returned |
| failure adopted from a hook (`fail!` in `on_success`) | rolls back |
| exception | rolls back, and the exception propagates |

Every hook kind runs inside the transaction, `always` too, so what they write lives or dies with the run. Rollback on failure works through an internal error that is raised inside the block and swallowed just outside it.

When a transaction is already open (`model.connection.transaction_open?`), the action opens a savepoint (`requires_new: true`) unless you give `requires_new:` yourself. A failing inner action undoes only its own writes, and the outer transaction never commits them. Give `requires_new: false` to join the outer transaction. Options go through as written, and actions without `transactional` are left alone (AC-B#txsavepoint).

## `after_commit`

```ruby
after_commit(target, **options)
after_commit_hooks # => the declared hooks, in order
```

The declaration takes a method name or an action class, with `if:`, `unless:` and `input:`. It relies on `ActiveRecord.after_all_transactions_commit`, so declaring it without ActiveRecord, or on a version before 7.2, raises `DefinitionError`. Subclasses get a copy of the hooks.

A run that ends in success registers its hooks with ActiveRecord. Each fires once, in order, when the outermost open transaction commits (the action's own savepoint doesn't count), or right away if none is open. A failure or a skip never fires them, and neither does a rollback of an enclosing transaction. Nested actions each fire their own hooks once, child first. If a transactional parent fails afterwards, a successful child's pending hook is dropped.

By that point the run is over, so a hook can't alter the result that was returned. A halting verb only stops the `after_commit` hooks still to come. Hooks leave no trace in the history, and guards are evaluated at firing time. An exception propagates from the place the commit happened, with the writes already committed (AC §5.16).

`describe[:hooks][:after_commit]` lists the names and is present whenever the adapter is loaded. `describe_text` prints an `after_commit:` line only when there is something to list. The missing-method and verb-position checks apply to these methods as well.

## `ProxyValidator`

Use `Actionable::ProxyValidator` to validate an object that isn't a model. It includes `ActiveModel::Validations`. You subclass it, write the rules with `validates`, and construct it with `Rules.new(delegate)`. When a rule reads an attribute the delegate responds to, the read is forwarded, and anything else raises as usual.

| Member | Meaning |
|---|---|
| `delegate` | the object being validated |
| `formatted_errors` | runs `valid?`, returns `errors.to_hash` as `{attribute => [messages]}` |
| `model_name` | built from the class name (`ProxyValidator` for an anonymous class), so messages work |

```ruby
class ManifestRules < Actionable::ProxyValidator
  validates :callsign, presence: true
end

rules = ManifestRules.new(manifest)
rules.formatted_errors # => {callsign: ["can't be blank"]}

# in a step, ready to splat into a failure
fail!(:invalid, **rules.formatted_errors)
```

## See also

- [Actions and steps](/reference/actionable/actions-and-steps/): hooks, which run inside the transaction
- [Batches and introspection](/reference/actionable/batches-and-introspection/): `describe` and the transaction config
- [Errors and guardrails](/reference/actionable/errors/): `DefinitionError` cases

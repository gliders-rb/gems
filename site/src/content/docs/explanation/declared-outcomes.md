---
title: "Declared failures and result codes"
description: "Why an action lists the codes it can end with, why metadata stays neutral, and what a complete list makes possible."
sidebar:
  order: 6
---

Picture a caller that has to deal with this failure code.

```ruby
fail!(:fog_bound)
```

Nothing in the class says it can happen. To find out, you read every step and every child action and trust that you saw them all. Codes were free-form, so nobody (a person or a tool) could learn an action's contract without reading its body.

## Declare them

```ruby run
class CastOff < Actionable::Action
  fails :fog_bound, 'harbour closed by fog', retry: false
  fails :gauge_offline, retry: true
  skips :already_underway

  step :go

  private

  def go = fail!(:fog_bound)
end

CastOff.declared_failures   # => {fog_bound: {retry: false}, gauge_offline: {retry: true}}
CastOff.declared_skips      # => {already_underway: {}}
```

That list is the contract, and a reader, a test, a retry policy and a type generator all need the very same thing from it.

## Strict once declared

Declaring any failure code means the action can fail only with those (AC-I7). A typo then raises on the first run, where before it became a result nobody handled.

```ruby run
class Slip < Actionable::Action
  fails :fog_bound
  step :go

  private

  def go = fail!(:fog_bond)
end

begin
  Slip.run
rescue Actionable::DefinitionError => e
  e.message.include?('does not declare')   # => true
end
```

An action that declares nothing is left unchecked, so this is opt-in per action. We lean toward adopting it for anything other code calls and skipping it for a one-off script.

Skips follow the same contract, with no exemption. The gem emits no skip codes of its own, so once you declare any skip, even a bare `skip!` has to be declared. Failures and skips are strict on their own: declaring one kind does not make the other strict. The gem's two failure codes, `:invalid_input` and `:invalid_output`, are always allowed because the gem itself produces them.

## Metadata is neutral

The `retry: false` above is metadata. The core keeps it, shows it in `describe` and puts it on the result, but never interprets it (AC-I7). Two reasons for that. A free-form keyword on `fail` used to collide with error field names, so metadata lives apart from errors. And a core that understands retries ends up with opinions about queues, and those belong in an adapter.

Only one reader exists, and it is opt-in: the job adapter, after `honor_retry_metadata` (see [Run in a background job](/how-to/background-jobs/)). Anything else you attach is yours.

## What a full list buys

When every ending of an action is written down, several things come along for free.

- Tools can tell a model or a client what an action may return
- A retry policy comes from the declaration, so no job needs its own list
- A suite can ask which declared outcomes no spec has reached - that is outcome coverage, and a named baseline keeps a new gap from hiding behind an old one
- Stubs can refuse a code the action can never produce, so a spec can't test a failure that does not exist
- Generated types can name the codes

None of these needed a new idea. They fall out of having the list.

## What it costs

You write the codes down and keep them true. An undeclared code fails loudly, which we think is the right way round, though it does mean adding a line whenever a new case appears. The checks also happen at call time, so a branch that rarely fires is checked the first time it does, not when the class loads. We haven't found a way to check every branch statically without running the code.

## See also

- [Declared outcomes](/reference/actionable/declared-outcomes/)
- [Declare and handle outcomes](/how-to/handle-action-outcomes/)
- [Success, failure, skip](/explanation/three-outcomes/)

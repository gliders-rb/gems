---
title: "How to declare failures and handle each outcome"
description: "Name the ways an action can end, attach messages and metadata, and branch on each outcome at the call site."
sidebar:
  label: "Declare and handle outcomes"
  order: 7
---

An `IssuePass` action has four possible endings, and whoever calls it should tell them apart by code, not by reading text.

## 1. Declare the failures and skips

`fails` and `skips` name the codes the action may end with. A message and metadata are optional. When a call gives no message, the declared one is used.

```ruby run
class IssuePass < Actionable::Action
  input do
    optional :callsign, :string
    optional :boarded, :boolean, default: false
  end

  fails :missing_callsign, 'a pass needs a callsign'
  skips :already_boarded

  step :check

  private

  def check
    skip!(:already_boarded, 'already aboard') if input.boarded
    fail!(:missing_callsign) if input.callsign.nil?
    succeed('pass issued')
  end
end
```

## 2. Know that declaring makes it strict

After an action declares one failure code, it can fail only with declared ones. The gem's own `:invalid_input` and `:invalid_output` stay allowed. Skips work the same way, and declaring one kind never makes the other strict.

```ruby run
class Misspelt < Actionable::Action
  fails :missing_callsign
  step :check

  private

  def check = fail!(:missing_callsgin)
end

begin
  Misspelt.run
rescue Actionable::DefinitionError => e
  e.message.start_with?('Misspelt fails with :missing_callsgin, which it does not declare')   # => true
end
```

So a typo in a code turns into a loud error on the first run, and not into a result nobody handles.

## 3. Read the code

Each result carries a `status` (`:success`, `:failure` or `:skipped`) and a `code` with the specific reason. A skip is not a failure, so `ok?` is true for it.

```ruby run
IssuePass.run(callsign: 'GANNET').status                       # => :success
IssuePass.run.code                                             # => :missing_callsign
IssuePass.run.message                                          # => "a pass needs a callsign"
IssuePass.run(callsign: 'GANNET', boarded: true).skipped?      # => true
IssuePass.run(callsign: 'GANNET', boarded: true).ok?           # => true
IssuePass.run(boarded: 'maybe').code                           # => :invalid_input
```

## 4. Branch at the call site

Results work with `case/in`. The class tells you which outcome it is, and the code tells you why.

```ruby run
def describe_pass(**params)
  case IssuePass.run(**params)
  in Actionable::Success                             then 'aboard'
  in Actionable::Skipped[code: :already_boarded]     then 'nothing to do'
  in Actionable::Failure[code: :missing_callsign]    then 'add a callsign'
  in Actionable::Failure[code: :invalid_input]       then 'bad request'
  end
end

describe_pass(callsign: 'GANNET')                      # => "aboard"
describe_pass(callsign: 'GANNET', boarded: true)       # => "nothing to do"
describe_pass                                          # => "add a callsign"
describe_pass(boarded: 'maybe')                        # => "bad request"
```

Add an `else` if more codes may show up later. Without it, a result that no branch matches raises `NoMatchingPatternError`. In a controller that is usually what you want, since failing loudly beats ignoring it.

## 5. Read the declarations

`declared_failures` and `declared_skips` hand a program the same list a person would read.

```ruby run
IssuePass.declared_failures   # => {missing_callsign: {}}
IssuePass.declared_skips      # => {already_boarded: {}}
```

The [background job adapter](/how-to/background-jobs/) and the test helpers both read that list. Keep it honest, and add a code before you start using it.

## See also

- [Declared outcomes](/reference/actionable/declared-outcomes/)
- [Control flow](/reference/actionable/control-flow/)
- [Declared failures and result codes](/explanation/declared-outcomes/)
- [Compose actions](/how-to/compose-actions/)

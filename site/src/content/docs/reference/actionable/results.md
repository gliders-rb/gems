---
title: "Results"
description: "The Success, Failure and Skipped result classes: attributes, predicates, serialization and equality."
sidebar:
  order: 3
---

A run hands back one result. `Actionable::Result` itself is abstract. The concrete classes are `Success`, `Failure` and `Skipped`, all FieldStruct classes carrying `code`, `message`, `output` and `history`, with `metadata` added on failures and skips. The outcomes exclude each other, so for any concrete result exactly one predicate is true (AC-I3).

## Attributes

| Attribute | Success | Failure | Skipped | Default |
|---|---|---|---|---|
| `code` | yes | yes | yes | `:success`, `:error`, `:skipped` |
| `message` | yes | yes | yes | `nil` |
| `output` | yes | yes | yes | a fresh `{}` |
| `history` | yes | yes | yes | a fresh `[]` |
| `errors` | yes | yes | yes | empty |
| `metadata` | no | yes | yes | a fresh `{}` |

`code` gets coerced to a Symbol. `errors` is the FieldStruct collection and not a field, which means `errors[:field]` gives an Array of Strings and `errors.to_h` and `errors.full_messages` behave as on any struct. A `Success` carries no `metadata`, and asking for it raises `NoMethodError` (AC §5.1).

```ruby run
Actionable::Success.new.code                 # => :success
Actionable::Failure.new.code                 # => :error
Actionable::Skipped.new.code                 # => :skipped
Actionable::Failure.new(code: 'adrift').code  # => :adrift
Actionable::Failure.new.metadata             # => {}
Actionable::Success.new.respond_to?(:metadata) # => false
```

## Predicates

| Method | True for |
|---|---|
| `success?`, `successful?` | `Success` |
| `failure?`, `failed?` | `Failure` |
| `skipped?` | `Skipped` |
| `ok?` | `Success` and `Skipped` (not a failure) |
| `status` | `:success`, `:failure` or `:skipped` |

`status` tells you which outcome it was, and `code` gives the specific reason.

```ruby run
failure = Actionable::Failure.new(code: :adrift)
failure.failure?   # => true
failure.failed?    # => true
failure.ok?        # => false
failure.status     # => :failure
Actionable::Success.new.successful?  # => true
Actionable::Skipped.new.skipped?     # => true
Actionable::Skipped.new.ok?          # => true
```

## Serialization

`to_h` gives `{code:, message:, output:, history:, errors:}`, plus `metadata:` for a failure or skip. A struct output goes through its own `to_h`, the history through `History#as_json`, and `errors` through `errors.to_h`.

`to_api_h(index: nil, id_field: :id)` gives exactly `{index:, status:, id:, errors:}`. For `id` the gem reads `id_field` off the output: a declared field when the output is a struct, a key when it is a Hash, and `nil` otherwise.

```ruby run
failure = Actionable::Failure.new(code: :adrift)
failure.to_h.keys                # => [:code, :message, :output, :history, :errors, :metadata]
failure.to_api_h(index: 2)       # => {index: 2, status: :failure, id: nil, errors: {}}
Actionable::Success.new(output: { id: 31 }).to_api_h # => {index: nil, status: :success, id: 31, errors: {}}
Actionable::Success.new.to_h.key?(:metadata)  # => false
```

`inspect` and `to_s` produce `#<ClassName name=value ...>`, listing every attribute and `errors` sorted by name. That differs from FieldStruct's own `inspect` on purpose.

```ruby run
Actionable::Failure.new(code: :adrift).inspect # => "#<Actionable::Failure code=:adrift errors={} history=[] message=nil metadata={} output={}>"
```

## Output delegation

Any declared field of a struct `output` can be read from the result itself: `result.fare_pence` equals `result.output.fare_pence`, and `respond_to?` says the same. Undeclared names, and outputs that are not FieldStruct instances (a free-form Hash, `{}`), don't delegate and give the usual `NoMethodError`. A name that collides with a Result method can't be an output field at all (see [Input and output](/reference/actionable/input-and-output/)).

`output_fields_set` lists which output fields a run really set (instance variables plus verb keywords). On a hand-built result it is `nil`. It's a plain accessor and not a field, so equality ignores it.

```ruby run
class TallyFare < Actionable::Action
  output { required :fare_pence, :integer }

  step :tally

  private

  def tally = @fare_pence = '350'.to_i + 25
end

result = TallyFare.run
result.fare_pence        # => 375
result.output.fare_pence # => 375
result.output_fields_set # => [:fare_pence]
result.respond_to?(:fare_pence) # => true
Actionable::Success.new.output_fields_set # => nil
```

## Errors

`Failure#absorb_errors_from(source)` takes each `field => messages` pair from `source.errors.to_h`, adds every message to the failure one by one, and returns the failure. Any object whose `errors` answers `to_h` will do.

```ruby run
class Crossing < FieldStruct::Base
  required :harbour, :string
end

failure = Actionable::Failure.new(code: :invalid)
failure.absorb_errors_from(Crossing.new).equal?(failure) # => true
failure.errors.to_h                                      # => {harbour: ["is required"]}
failure.errors.full_messages                             # => ["Harbour is required"]
```

## Equality and pattern matching

Equality looks at the exact class and the attributes. A `Success` is never equal to a `Failure` with matching attributes, while two results built alike are equal. With [typed outcomes](/reference/actionable/declared-outcomes/#typed-outcomes), a result equals only one from its own action's class.

A result is a FieldStruct, so `case/in` can deconstruct `code`, `message`, `output`, `history` (and `metadata` on failures and skips), and class patterns work too. `errors` and `status` are methods rather than fields, so a hash pattern that names either never matches.

```ruby run
Actionable::Success.new == Actionable::Success.new  # => true
Actionable::Success.new == Actionable::Skipped.new  # => false

outcome = case Actionable::Failure.new(code: :adrift)
          in Actionable::Failure(code:) then "failed with #{code}"
          end
outcome # => "failed with adrift"
```

## See also

- [Control flow](/reference/actionable/control-flow/): the verbs that build results
- [Input and output](/reference/actionable/input-and-output/): what ends up in `output`
- [Hooks and history](/reference/actionable/hooks-and-history/): the `history` attribute

---
title: "How to validate request params"
description: "Turn untrusted string-keyed params into a typed struct, report what is wrong as JSON, and do the same through an action's input."
sidebar:
  label: "Validate request params"
  order: 2
---

A form or an API call hands you a Hash of params. Every key is a String, and every value is a String or a list of them. You want either a typed object or a list of what is wrong.

## 1. Declare the shape

List the fields you accept. String keys work as they are, and values are coerced when assigned (see [Types](/reference/field-struct/types/)).

```ruby run
class NewCrossing < FieldStruct::Base
  unknown_attributes :raise

  required :route, :string
  optional :stops, :array, of: :string
  optional :departs_on, :date, format: :iso8601
end

params = { 'route' => 'Quay to Isle', 'stops' => %w[Pier Skerry], 'departs_on' => '2026-07-03' }
crossing = NewCrossing.new(params)

crossing.valid?              # => true
crossing.departs_on.to_s     # => "2026-07-03"
crossing.stops               # => ["Pier", "Skerry"]
```

`unknown_attributes :raise` is optional. We lean on it for params: a key nobody expected is usually a typo, or someone poking around. With the default, `:ignore`, it vanishes quietly.

## 2. Rescue the keys you did not expect

Under `:raise` the whole call fails before any value is assigned, and the error names every unknown key.

```ruby run
begin
  NewCrossing.new('route' => 'Quay to Isle', 'pilot' => 'true', 'flag' => 'x')
rescue FieldStruct::UnknownAttributeError => e
  e.keys      # => [:pilot, :flag]
  e.message   # => "unknown attribute(s) for NewCrossing: :pilot, :flag"
end
```

## 3. Report the errors

A bad value never makes `new` raise. You get an object with `errors`, and the messages never include the input, which makes them safe to log and to send back (FS-I5).

```ruby run
bad = NewCrossing.new('route' => '', 'departs_on' => '2026-02-30')

bad.valid?                        # => false
bad.errors.to_h.keys              # => [:route, :departs_on]
bad.errors[:route]                # => ["is required"]
bad.errors.full_messages.first    # => "Route is required"
Oj.dump(bad.errors.to_h, mode: :compat).start_with?('{"route":["is required"]')  # => true
```

Use `errors.to_h` as the body of a 422, and keep `full_messages` for flash text. Check `valid?` before trusting any value, because with the default `:keep_raw` policy an invalid field may still hold what was sent.

## 4. Do the same through an action

An action's `input` block is the same FieldStruct body. Splat the params so each key turns into a keyword, and a bad value ends the run as `:invalid_input` before a step gets to run.

```ruby run
class ScheduleCrossing < Actionable::Action
  input do
    required :route, :string
    optional :stops, :array, of: :string
    optional :departs_on, :date, format: :iso8601
  end

  step :schedule

  private

  def schedule = succeed("scheduled #{input.route}")
end

ScheduleCrossing.run(**params).message          # => "scheduled Quay to Isle"

result = ScheduleCrossing.run(**{ 'route' => '' })
result.code                                     # => :invalid_input
result.errors.to_h                              # => {route: ["is required"]}
```

:::caution
Write `**params`, never `params`. A positional Hash is ignored without a word, and the run ends as `:invalid_input` with "is required" on every required field. See [Input and output](/reference/actionable/input-and-output/).
:::

## See also

- [Validation and errors](/reference/field-struct/validation-and-errors/)
- [Class macros](/reference/field-struct/class-macros/#unknown_attributes)
- [Input and output](/reference/actionable/input-and-output/)
- [Nested structs and arrays](/how-to/nested-structs-and-arrays/)

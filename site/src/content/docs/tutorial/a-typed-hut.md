---
title: "A typed Hut"
description: "Declare a Hut with typed fields, watch values coerce from strings, and see what happens when they can't."
sidebar:
  label: "1. A typed Hut"
  order: 2
---

We start with the smallest piece of the hut network: one hut. By the end of this chapter we'll have a `Hut` that takes string input from a form, turns it into real Ruby values, and tells us what is wrong when it can't.

## Where we left off

Nothing yet. This is the first chapter and it needs only `field_struct`, so open `irb` with `require 'field_struct'` or put the code in a script.

## Declare the fields

A struct is a class that inherits from `FieldStruct::Base`. Every field has a name and a type, and it is either `required` or `optional`.

```ruby run title="hut.rb"
class Hut < FieldStruct::Base
  required :name, :string
  optional :places, :integer
end

hut = Hut.new(name: 'Larch Col', places: 24)
hut.name     # => "Larch Col"
hut.valid?   # => true
```

`required` means the field has to be present for the hut to be valid. It doesn't stop you from building a hut without it, as we'll see in a moment.

## Coerce strings

Form and query params arrive as strings, and assigning a string to an `:integer` field converts it.

```ruby run
form = { name: 'Larch Col', places: '24' }
Hut.new(**form).places   # => 24
```

The conversion runs on every assignment, in `new` and in the setters, so `hut.places = '30'` leaves `30` behind.

## Add a code, a distance and a season

A distance in kilometres is a measurement, so we use `:decimal`. A float would hand us the `0.1 + 0.2` problem. Four options earn their place here:

- `format:` checks a string against a pattern
- `round:` rounds a number to that many decimal places
- `in:` limits a number to a range
- `default:` fills in a value when none is given

The season is a `:symbol` limited to a list with `enum:`.

```ruby run title="hut.rb"
class Hut < FieldStruct::Base
  required :name, :string
  required :code, :string, format: /\A[A-Z]{2}\d{2}\z/
  required :distance_km, :decimal, round: 1
  optional :places, :integer, in: 1..400
  optional :season, :symbol, enum: %i[summer winter year_round]
  optional :altitude, :integer, in: 0.., default: 0
end
```

:::caution
A bare `0..` at the end of a line makes Ruby read the next line as the end of the range. Here a comma follows it, so we're safe. When an endless range is the last thing on its line, wrap it in parentheses: `in: (0..)`.
:::

Now a hut built from the strings a form would send.

```ruby run
hut = Hut.new(
  name: 'Larch Col',
  code: 'KR12',
  distance_km: '7.25',
  places: '24',
  season: 'summer'
)

hut.distance_km      # => BigDecimal('7.3')
hut.places           # => 24
hut.season           # => :summer
hut.altitude         # => 0
hut.valid?           # => true
```

The distance `7.25` rounded to `7.3`, `'summer'` became the symbol `:summer`, and `altitude` took its default.

## Read the errors

Now we feed it bad input.

```ruby run
bad = Hut.new(name: '  ', code: 'k1', distance_km: '3.5', places: 9_000, season: 'monsoon')

bad.valid?                      # => false
bad.errors.full_messages.size   # => 4
```

`errors.full_messages` gives one sentence per problem: the blank name, the malformed code, the place count outside `1..400` and the season missing from the list. Nothing raised. Building a hut is never the same as validating it.

For one field at a time, use `errors.to_h`.

```ruby run
bad.errors.to_h[:name]    # => ["is required"]
bad.errors.to_h[:places]  # => ["is invalid"]
bad.errors.to_h.keys      # => [:name, :code, :places, :season]
```

A blank string counts as missing, which is why the name reads "is required" and not "is invalid".

## When a value can't be coerced

What if `places` is `'plenty'`? There is no integer to make out of that.

```ruby run
odd = Hut.new(name: 'Larch Col', code: 'KR12', distance_km: '3.5', places: 'plenty')

odd.places                      # => "plenty"
odd.valid?                      # => false
odd.errors.to_h[:places].size   # => 1
```

By default the raw value stays in the field and the error is recorded. The object remains usable, and your code decides whether to show the error, ask again or give up. The messages never echo what was typed.

If you'd rather have an exception, a class can ask for it with `coercion_policy :raise`. We keep the default for the hut network.

## What you built

A `Hut` with required and optional fields, four types (`:string`, `:decimal`, `:integer`, `:symbol`) with the options `format:`, `round:`, `in:`, `enum:` and `default:`, string coercion, and an errors object that reports problems without raising.

Next we'll put huts into bookings and send them as JSON.

## See also

- [Bookings and JSON](/tutorial/bookings-and-json/): the next chapter
- [Fields and options](/reference/field-struct/fields-and-options/)
- [Types](/reference/field-struct/types/)
- [Coercion versus validation](/explanation/coercion-and-validation/)

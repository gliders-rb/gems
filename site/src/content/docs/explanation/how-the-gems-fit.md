---
title: "How the two gems fit together"
description: "Where FieldStruct shows up inside Actionable, why only a success is held to the declared output, and where adapters plug in."
sidebar:
  order: 7
---

Actionable has no type system of its own. Whatever is typed in an action is a FieldStruct, and you can see it in three places.

```ruby run
class ExtendStay < Actionable::Action
  input do
    required :booking_id, :integer
    optional :nights, :integer, default: 2
  end

  output { required :nights_booked, :integer }

  step :lengthen

  private

  def lengthen = @nights_booked = input.nights
end

ExtendStay.input.superclass          # => FieldStruct::Base
ExtendStay.output.superclass         # => FieldStruct::Base

result = ExtendStay.run(booking_id: '7')
result.output.class.superclass       # => FieldStruct::Base
result.nights_booked                 # => 2
```

## Three places

- Input is a struct. `booking_id: '7'` became `7` and was validated before any step ran, using FieldStruct's own messages.
- Output is a struct. Only the fields declared in `output` reach the result (AC-I5).
- The result holds the output struct and forwards its readers, which is why `result.nights_booked` works.

All three share one set of coercion rules, one set of messages and one `errors` object (AC-I9). When input validation fails, `errors.to_h` looks exactly like it would on a failed struct. We didn't add a second schema language. A second one would mean a second set of rules to learn, and the two would drift apart.

## Why the output is declared

An earlier take on this idea swept up every instance variable a step had set and put them in the result. It was easy to write and it leaked: a record loaded only for a check could end up in the result of an unrelated failure.

```ruby run
class CountParty < Actionable::Action
  output { required :headcount, :integer }

  step :count

  private

  def count
    @headcount = 3
    @scratch = 'never shown'
  end
end

CountParty.run.output.to_h   # => {headcount: 3}
```

Declaring the output is a contract: the caller gets this and nothing else. It also means the output can be checked, and a generator can type it.

## Only a success is held to it

If the steps finish without producing what the schema promised, the run turns into an `:invalid_output` failure. Only a success gets this check (AC §5.5). A failure or a skip captures whatever it can, since a failure tends to happen exactly when the output isn't ready, and failing a second time for that same reason would bury the first.

When a failure or a skip should carry data, give that code its own schema (see [Declared outcomes](/reference/actionable/declared-outcomes/#per-code-output-schemas)). That is the opt-in form of the same idea, and it is built only from keywords you pass, never from variables that happen to be lying around.

## Types all the way down

Schemas are structs, so anything that can read a struct can read an action. `describe` lists the fields, RBS is generated from them, and a JSON Schema or a tool definition can be derived from them. This is where adapters plug in: they read a struct's declarations and write some other format, and the classes they read stay untouched.

The seam works in both directions. A struct knows nothing about actions, while an action asks the struct for everything about its shape.

## What we are not sure about

Success-only checking is a judgment call. A stricter rule would catch more, and a looser one would surprise fewer people. We kept the one that never fails twice, and typed outcomes are the way to get more.

## See also

- [Input and output](/reference/actionable/input-and-output/)
- [Validity is computed on assignment](/explanation/validity-on-assignment/)
- [Declared failures and result codes](/explanation/declared-outcomes/)

---
title: "Metadata is the product"
description: "Why a declaration in either gem is data in a fixed shape that other code can read, and how the adapters read one declaration in different ways."
sidebar:
  order: 10
---

A mountain hut has a code on the door and a number of places to sleep. Here is the struct for it:

```ruby run
class Hut < FieldStruct::Base
  required :code, :string, desc: 'Short code painted on the door'
  required :places, :integer, in: 1..60
  optional :altitude, :integer
end
```

That looks like code, and it runs like code: `Hut.new(places: '12')` coerces and validates. But the class body is mostly a list of facts, and the gem keeps those facts as data you can read back.

```ruby run
Hut.metadata.names              # => [:code, :places, :altitude]
Hut.metadata.to_h[:places]      # => {type: "Integer", ruby_type: "Integer", required: true, default: nil, options: {in: 1..60}, description: nil}

code, places, = FieldStruct::Introspection.properties(Hut)
code.key                        # => "code"
code.field.required?            # => true
places.node.options             # => {in: 1..60}
```

`metadata.to_h` is a summary for people and tools. `FieldStruct::Introspection` is the walk an exporter uses: each field with the key it has in JSON and a node that says what kind of value it holds (see the [Introspection reference](/adapters/introspection/)).

## An action is data too

An action declares its input, output, steps, hooks and the ways it can fail. `describe` hands all of it back as a Hash.

```ruby run
class ReservePlaces < Actionable::Action
  input do
    required :hut_code, :string, desc: 'Which hut to stay at'
    required :places, :integer
  end

  output { required :booking_ref, :string }

  fails :fully_booked, 'no places left that night', retry: true
  fails :closed_for_season, 'the hut is shut until spring', retry: false

  step :reserve

  private

  def reserve
    fail!(:closed_for_season) if input.hut_code == 'WINTER'
    fail!(:fully_booked) if input.places > 4
    @booking_ref = "#{input.hut_code}-#{input.places}"
  end
end

shape = ReservePlaces.describe
shape.keys                    # => [:name, :description, :input, :output, :steps, :failures, :skips, :hooks, :measure, :transactional, :calls]
shape[:input].keys            # => [:hut_code, :places]
shape[:failures][:fully_booked]   # => {message: "no places left that night", metadata: {retry: true}, description: nil}
```

The `retry: true` is not a feature of the core gem. It is a key you chose, stored next to the code and handed to anyone who asks. The core never reads it.

## One declaration, several readers

The adapters are the proof that this pays off. None of them asks you to declare anything again. Each one reads the same declarations and writes something else.

The job adapter ships with actionable. Once you load it, it reads the failure metadata to decide whether a queue should retry the job:

```ruby run
require 'actionable/job'

full = ReservePlaces.run(hut_code: 'GRAT', places: 6)
shut = ReservePlaces.run(hut_code: 'WINTER', places: 2)

Actionable::Job.disposition(full)                        # => :retry
Actionable::Job.disposition(shut)                        # => :discard
Actionable::Job.disposition(shut, honor_retry: false)    # => :retry
```

The `retry:` you wrote on the declaration decides. An action that opts out with `honor_retry_metadata(enabled: false)` falls back to the plain rule: every failure outside a short list of permanent codes is retried (see [Jobs](/reference/actionable/jobs/)).

The JSON Schema and tools adapters are separate gems, so this page can't run them. The two examples below are shown, not checked here, and the [adapter pages](/adapters/) run the same calls in CI.

The [JSON Schema adapter](/adapters/json-schema/) turns `Hut` into a schema another service can validate against. The description, the range and the required list all come from the three lines above:

```ruby
require 'field_struct/json_schema'

FieldStruct::JSONSchema.generate(Hut)
# {"$schema" => "https://json-schema.org/draft/2020-12/schema", "title" => "Hut", "type" => "object",
#  "properties" => {"code" => {"description" => "Short code painted on the door", "type" => "string"},
#                   "places" => {"type" => "integer", "minimum" => 1, "maximum" => 60},
#                   "altitude" => {"type" => ["integer", "null"]}},
#  "required" => ["code", "places"]}
```

The [tools adapter](/adapters/tools/) turns `ReservePlaces` into a tool a language model can call. The input schema comes from the `input` block, and the declared failures end up in the description of `code`, so the model knows how a call can go wrong:

```ruby
require 'actionable/tools'

tool = Actionable::Tools.definition(ReservePlaces, description: 'Reserve places in a mountain hut')
tool.name                                  # "reserve_places"
tool.input_schema['required']              # ["hut_code", "places"]
tool.output_schema.dig('properties', 'code', 'description')
# "\"success\", or why the run failed or was skipped. Declared failures: fully_booked, closed_for_season. ..."
```

## Why the core never interprets it

We could have taught the core what `retry:` means, or how to write a schema. We didn't, and the reason is the list above: every reader wants something different from the same facts. A queue cares about retries, a validator about types and ranges, a model about descriptions. If the core picked one meaning, every other reader would have to work around it.

So the core has one job here: keep the declarations in a fixed, documented shape and never act on the parts that belong to someone else. Adapters give those parts a meaning, each in its own gem, and only when you require it. The job adapter's `honor_retry` is the one place the actionable gem reads a metadata key, and only because you loaded `actionable/job`.

The cost is that nothing checks the metadata on a failure or skip code. A typo like `fails :fully_booked, retyr: true` is stored as faithfully as the real thing, and only the adapter that reads it can notice. Field options are different: an unknown key on a field raises when the class loads, and an adapter or your app registers the keys it reads with `FieldStruct.register_option`. Step options work the same way: an unknown key on a step raises, and `Actionable.register_step_option` adds one. If your team relies on a key, a spec that reads `describe` is the cheapest guard we know.

If none of the adapters writes the format you need, the walk is public and an adapter is a small file (see [Build your own adapter](/adapters/build-your-own/)).

## See also

- [How adapters work](/adapters/how-adapters-work/)
- [Batches and introspection](/reference/actionable/batches-and-introspection/)
- [Declared failures and result codes](/explanation/declared-outcomes/)

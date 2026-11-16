---
title: "A result is a report, not a handle"
description: "Why running an action gives you a plain result to read and present, not the action instance, and where that promise holds today."
sidebar:
  label: "A result is a report"
  order: 7
---

A passenger asks what it costs to take two cars across the harbour. The action that works it out does its job, and what comes back is a result:

```ruby run
class QuoteFare < Actionable::Action
  input do
    required :route, :string
    required :cars, :integer
  end

  output { required :fare_cents, :integer }

  fails :no_sailing, 'no sailing on that route', retry: false

  step :price

  private

  def price
    fail!(:no_sailing) if input.route == 'nowhere'
    @fare_cents = 1800 * input.cars
  end
end

quote = QuoteFare.run(route: 'harbour', cars: 2)
quote.status       # => :success
quote.code         # => :success
quote.fare_cents   # => 3600
```

You never get the action instance back. The instance lived for that one run and is gone. What you hold is a report of what happened, and nothing on it reaches back into the action, its input or its steps.

```ruby run
quote.respond_to?(:input)   # => false
quote.respond_to?(:price)   # => false
```

## What a report holds

Every result has the same few things, whatever action made it:

- `status` - `:success`, `:failure` or `:skipped`
- `code` - the specific reason, like `:no_sailing`
- `message` - a sentence for a person, or `nil`
- `output` - the declared output fields
- `errors` - field messages, the same object a struct uses
- `metadata` - what the declaration attached to a failure or skip code

```ruby run
missed = QuoteFare.run(route: 'nowhere', cars: 1)
missed.status     # => :failure
missed.code       # => :no_sailing
missed.message    # => "no sailing on that route"
missed.metadata   # => {retry: false}

rejected = QuoteFare.run(route: 'harbour')
rejected.code          # => :invalid_input
rejected.errors.to_h   # => {cars: ["is required"]}
```

That shape is predictable on purpose. A controller, a job or a tool server can turn any result into a response without knowing which action made it: pick the HTTP status from `status`, show `message`, render `errors` next to the form. See [Results](/reference/actionable/results/) for every reader.

## It is a struct

A result is a FieldStruct, so it behaves like any other value. Two results built the same way are equal, and `as_json` and `to_h` give you plain data.

```ruby run
quote.is_a?(FieldStruct::Base)                         # => true
quote == QuoteFare.run(route: 'harbour', cars: 2)      # => true
quote.as_json   # => {status: "success", code: "success", message: nil, output: {fare_cents: 3600}, history: [], errors: {}}
```

`as_json` carries the whole report, `status` and `errors` included, so you can log it or send it as it is. `to_h` has the same keys with Symbols.

A report doesn't change once it's handed over. `.run` freezes the result after the last hook, so hooks can still adjust it, and from then on its fields, errors and output are read-only. `with` gives you a changed copy, frozen the same way.

```ruby run
quote.frozen?                          # => true
quote.with(message: 'two cars').message # => "two cars"
quote.with(message: 'two cars').frozen? # => true
begin
  quote.message = 'edited'
rescue FrozenError
  :read_only # => :read_only
end
```

The freeze covers plain data only: Strings, Arrays, Hashes and structs. A live object in a `:value` field stays as it was, which is the next section's subject.

## Where the promise holds, and where it does not

A report is powerless as long as its output holds plain data. That part is your choice today, since the gem does not stop you from putting a live object in it.

An output field typed `:value` keeps whatever you give it. Give it an object with methods that change things, like an ActiveRecord record, and anyone holding the result can call them. Here a `Vessel` stands in for the record:

```ruby run
class Vessel
  attr_reader :name, :docked

  def initialize(name)
    @name = name
    @docked = false
  end

  def dock! = @docked = true
  def to_h = { name: name, docked: docked }
end

PUFFIN = Vessel.new('Puffin')

class FindVessel < Actionable::Action
  output { required :vessel, :value }

  step :find

  private

  def find = @vessel = PUFFIN
end

FindVessel.run.vessel.dock!
PUFFIN.docked   # => true
```

A struct-typed field does not save you from this either. A live object there fails the run with `:invalid_output`, but the failure still carries the object as it was given.

```ruby run
class VesselCard < FieldStruct::Base
  required :name, :string
  optional :docked, :boolean
end

class HandOverVessel < Actionable::Action
  output { required :vessel, VesselCard }

  step :find

  private

  def find = @vessel = PUFFIN
end

handed = HandOverVessel.run
handed.code                         # => :invalid_output
handed.output.vessel.equal?(PUFFIN)  # => true
```

Its `as_json` then goes through the object's own serialization. For a record, that means every column, including the ones you never declared. A lazy query left in an output is the same story: it stays unloaded until something serializes the result, and then it runs.

So, for now, it is a convention: hand the output plain data. Give a struct-typed field a Hash, or a record's `attributes`, and only the declared fields come through, as primitives.

```ruby run
class DescribeVessel < Actionable::Action
  output { required :vessel, VesselCard }

  step :find

  private

  def find = @vessel = PUFFIN.to_h
end

card = DescribeVessel.run.vessel
card.class                 # => VesselCard
card.respond_to?(:dock!)   # => false
card.as_json               # => {name: "Puffin", docked: true}
```

We are not sure yet how far the gem should go in enforcing this. Until it does, the edge is yours to keep: the layer that turns a result into a response is where a live object would leak, so that is the place to check.

## See also

- [Results](/reference/actionable/results/)
- [Input and output](/reference/actionable/input-and-output/)
- [How the two gems fit together](/explanation/how-the-gems-fit/)

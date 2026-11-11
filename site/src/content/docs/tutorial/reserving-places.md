---
title: "Reserving places"
description: "Write the first action, with typed input and output, a declared fully_booked failure and a branch on the result."
sidebar:
  label: "3. Reserving places"
  order: 4
---

So far we've only described data. Now something has to happen: a party reserves places in a hut. In this chapter we write our first action, give it typed input and output, make it fail on purpose, and branch on the result.

## Where we left off

We had `Hut`, `Leg` and `Booking` structs. This chapter also needs a count of free places per hut, so a plain hash stands in for a database.

```ruby run title="free_places.rb"
FREE = { 'KR12' => 3, 'EG07' => 0 }
```

## An action with steps

An action is a class that inherits from `Actionable::Action`. Each `step` names an instance method, and the steps run in the order written. We start one with `.run`.

```ruby run title="first_reservation.rb"
class FirstReservation < Actionable::Action
  step :hold
  step :confirm

  private

  def hold
    @held = true
  end

  def confirm
    succeed('places reserved')
  end
end

result = FirstReservation.run
result.success?   # => true
result.message    # => "places reserved"
```

`.run` always hands back a result, never `nil`. `succeed` records a success with a message and ends the run there.

## Typed input

A reservation needs a contact, a hut code and a number of places. An `input` block is a FieldStruct body, so everything from chapter 1 applies: types, options and coercion.

```ruby run
class TypedReservation < Actionable::Action
  input do
    required :contact, :email
    required :hut_code, :string, format: /\A[A-Z]{2}\d{2}\z/
    required :places, :integer, in: 1..10
  end

  step :confirm

  private

  def confirm
    succeed("reserving #{input.places}")
  end
end
```

Steps read the validated struct through `input`, and the count can arrive as a string.

```ruby run
TypedReservation.run(contact: 'lead@example.com', hut_code: 'KR12', places: '2').message   # => "reserving 2"
```

## Bad input never reaches a step

What if someone asks for 99 places? We write no code for that.

```ruby run
bad = TypedReservation.run(contact: 'lead@example.com', hut_code: 'KR12', places: 99)

bad.failure?              # => true
bad.code                  # => :invalid_input
bad.errors.to_h           # => {places: ["is invalid"]}
```

Invalid input ends the run as a failure with the code `:invalid_input` and the struct's errors. No step ran.

## Fail on purpose

Now the real action. Asking for more places than are free is a business failure, not bad input. We declare it with `fails` and end the run with `fail!`. The availability check goes first, so a failure stops the run before `reserve` touches anything.

```ruby run title="reserve_places.rb"
class ReservePlaces < Actionable::Action
  input do
    required :contact, :email
    required :hut_code, :string, format: /\A[A-Z]{2}\d{2}\z/
    required :places, :integer, in: 1..10
  end

  fails :fully_booked, 'not enough places free'

  step :check_availability
  step :reserve

  private

  def check_availability
    fail!(:fully_booked) if FREE.fetch(input.hut_code, 0) < input.places
  end

  def reserve
    FREE[input.hut_code] -= input.places
    succeed("reserved #{input.places}")
  end
end
```

`fail!` records the failure and stops the run, so `reserve` never executes. The plain `fail` records and keeps going, which is almost never what you want in a step.

:::caution
A plain `fail`, `succeed` or `skip` has to be the last thing a method does, because code after it still runs. The first `.run` of a class raises and names the line if a method gets this wrong.
:::

```ruby run
full = ReservePlaces.run(contact: 'lead@example.com', hut_code: 'KR12', places: 4)

full.failure?      # => true
full.code          # => :fully_booked
full.message       # => "not enough places free"
FREE['KR12']       # => 3
```

The message came from the declaration and the free count didn't change. Once an action declares a failure it can only fail with declared codes, so a typo like `:fully_bookd` raises on the first run instead of turning into a result nobody handles.

## A declared output

A success should hand something back. We reopen the class, add an `output` block, and set an instance variable of the same name in `reserve`.

```ruby run
class ReservePlaces
  output do
    required :remaining, :integer
  end

  private

  def reserve
    FREE[input.hut_code] -= input.places
    @remaining = FREE[input.hut_code]
  end
end

done = ReservePlaces.run(contact: 'lead@example.com', hut_code: 'KR12', places: 2)
done.success?    # => true
done.remaining   # => 1
done.code        # => :success
```

Only declared output fields reach the result, so nothing leaks by accident. There was no `succeed` this time, because a run with no recorded outcome succeeds on its own.

## Branch on the result

Calling code asks the result what happened.

```ruby run
def report(**params)
  result = ReservePlaces.run(**params)
  if result.success?
    "reserved, #{result.remaining} free"
  elsif result.code == :fully_booked
    'sorry, no room'
  else
    "check the request: #{result.errors.to_h.keys.join(', ')}"
  end
end

report(contact: 'lead@example.com', hut_code: 'KR12', places: 1)    # => "reserved, 0 free"
report(contact: 'lead@example.com', hut_code: 'KR12', places: 1)    # => "sorry, no room"
report(contact: 'nope', hut_code: 'KR12', places: 1)                # => "check the request: contact"
```

We never rescued anything. All three outcomes are values.

## What you built

A `ReservePlaces` action with typed input, a declared failure, a declared output and a caller that branches on `success?` and `code`. Bad input turned into `:invalid_input` before any step ran.

Next we meet the third outcome, the skip, and find out what a real exception is.

## See also

- [When things go wrong](/tutorial/when-things-go-wrong/): the next chapter
- [Actions and steps](/reference/actionable/actions-and-steps/)
- [Input and output](/reference/actionable/input-and-output/)
- [Declare and handle outcomes](/how-to/handle-action-outcomes/)

---
title: "When things go wrong"
description: "Meet the skip, attach metadata to a failure, match on results, read errors as data and see why exceptions are not outcomes."
sidebar:
  label: "4. When things go wrong"
  order: 5
---

An action ends one of three ways: success, failure or skip. This chapter covers the two that aren't success, plus the one thing that isn't an outcome at all, a real exception.

## Where we left off

We had `ReservePlaces`, which takes free places from a hut and fails with `:fully_booked`. We declare it again, this time with a booking id so a booking can be "already handled".

```ruby run title="reserve_places.rb"
FREE = { 'KR12' => 3 }
HANDLED = []

class ReservePlaces < Actionable::Action
  input do
    required :booking_id, :integer
    required :hut_code, :string, format: /\A[A-Z]{2}\d{2}\z/
    required :places, :integer, in: 1..10
  end

  output do
    required :remaining, :integer
  end

  fails :fully_booked, 'not enough places free'
  skips :already_reserved, 'this booking was handled before'

  step :check_handled
  step :check_availability
  step :reserve

  private

  def check_handled
    skip!(:already_reserved) if HANDLED.include?(input.booking_id)
  end

  def check_availability
    fail!(:fully_booked) if FREE.fetch(input.hut_code, 0) < input.places
  end

  def reserve
    FREE[input.hut_code] -= input.places
    HANDLED << input.booking_id
    @remaining = FREE[input.hut_code]
  end
end
```

## A skip is not a failure

Handling booking 7 twice should not take places twice, and it isn't an error either. There was simply nothing left to do. That is a skip.

```ruby run
first = ReservePlaces.run(booking_id: 7, hut_code: 'KR12', places: 1)
again = ReservePlaces.run(booking_id: 7, hut_code: 'KR12', places: 1)

first.success?       # => true
again.skipped?       # => true
again.code           # => :already_reserved
again.message        # => "this booking was handled before"
again.failure?       # => false
again.ok?            # => true
FREE['KR12']         # => 2
```

`ok?` is true for a success and for a skip, and false only for a failure, so a retry loop can ask `ok?` and stop. Declaring `skips` works like `fails`: the codes are a contract and only declared ones are allowed.

## Metadata on a failure

A failure can carry facts for whoever handles it. We mark `:fully_booked` as worth retrying later, since cancellations free places up.

```ruby run
class ReservePlaces
  fails :fully_booked, 'not enough places free', retry: true
end

late = ReservePlaces.run(booking_id: 8, hut_code: 'KR12', places: 5)
late.code        # => :fully_booked
late.metadata    # => {retry: true}
```

The gem doesn't act on `retry:`. It is data you declare once and read where you need it, and chapter 6 reads it.

## Match on results

Results work with `case/in`. The class says which outcome it was and the code says why.

```ruby run
def describe_result(result)
  case result
  in Actionable::Success                            then "reserved, #{result.remaining} free"
  in Actionable::Skipped[code: :already_reserved]   then 'already done'
  in Actionable::Failure[code: :fully_booked]       then 'no room'
  in Actionable::Failure[code: :invalid_input]      then 'bad request'
  end
end

describe_result(ReservePlaces.run(booking_id: 9, hut_code: 'KR12', places: 1))    # => "reserved, 1 free"
describe_result(ReservePlaces.run(booking_id: 9, hut_code: 'KR12', places: 1))    # => "already done"
describe_result(ReservePlaces.run(booking_id: 10, hut_code: 'KR12', places: 5))   # => "no room"
describe_result(ReservePlaces.run(booking_id: 11, hut_code: 'KR12', places: 0))   # => "bad request"
```

With no `else`, a result that no branch matches raises `NoMatchingPatternError`. In a controller that is often what you want, since a code you forgot about then fails loudly.

## Errors as data

A failure keeps its errors as data, so you can hand them to a person or to an API client.

```ruby run
bad = ReservePlaces.run(booking_id: 12, hut_code: 'k1', places: 0)

bad.code                        # => :invalid_input
bad.errors.to_h.keys            # => [:hut_code, :places]
bad.errors.full_messages.size   # => 2
bad.to_h.keys                   # => [:code, :message, :output, :history, :errors, :metadata]
bad.to_api_h(index: 0)          # => {index: 0, status: :failure, id: nil, errors: {hut_code: ["is invalid"], places: ["is invalid"]}}
```

`to_h` is the whole result as a hash. `to_api_h` is the small shape a batch API wants: an index, a status, an id and the errors.

## An exception is not an outcome

Everything so far was a result. A real bug is something else.

```ruby run
class Broken < Actionable::Action
  step :explode

  private

  def explode
    raise 'the availability service is down'
  end
end

begin
  Broken.run
rescue RuntimeError => e
  e.message   # => "the availability service is down"
end
```

The exception goes straight through `.run`. It is neither a failure nor a skip, so there is no result to branch on. That is deliberate: a failure is something your code expected and named, and an exception is something it didn't. Your app's error handler, or your job queue's retry rules, take it from there.

## What you built

An action that ends as a success, a skip or a failure, a failure with metadata, a `case/in` that handles each outcome, errors as data in `to_h` and `to_api_h`, and a clear line between named outcomes and exceptions.

Next we split the trip planning into small actions that call each other.

## See also

- [Composing actions](/tutorial/composing-actions/): the next chapter
- [Results](/reference/actionable/results/)
- [Success, failure, skip](/explanation/three-outcomes/)
- [Declare and handle outcomes](/how-to/handle-action-outcomes/)

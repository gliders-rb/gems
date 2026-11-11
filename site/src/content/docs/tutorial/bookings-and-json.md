---
title: "Bookings and JSON"
description: "Nest structs inside a booking, send it as JSON with camelCase keys, and keep an access token out of the logs."
sidebar:
  label: "2. Bookings and JSON"
  order: 3
---

Hikers don't book one night at a time, they book a route, and a route is a list of legs. In this chapter we nest structs, see how one invalid leg makes its booking invalid, send a booking to another service as JSON, and keep a secret out of the logs.

## Where we left off

We had a `Hut` with a name, a code, a decimal distance and an altitude. Pages don't share state, so we declare it again here, a little shorter.

```ruby run title="hut.rb"
class Hut < FieldStruct::Base
  required :name, :string
  required :code, :string, format: /\A[A-Z]{2}\d{2}\z/
  required :distance_km, :decimal, round: 1
  optional :altitude, :integer, in: 0.., default: 0
end
```

## A leg

A leg says which hut and for how many nights. Its type is another struct, so we pass the class where a type name would go.

```ruby run title="booking.rb"
class Leg < FieldStruct::Base
  required :hut_code, :string, format: /\A[A-Z]{2}\d{2}\z/
  required :nights, :integer, in: 1..7
end

class Booking < FieldStruct::Base
  required :contact, :email
  required :legs, :array, of: Leg
end
```

An array field takes `of:`, which can be a type name or a struct class. Plain hashes go in and the nested structs come out.

```ruby run
booking = Booking.new(
  contact: 'lead@example.com',
  legs: [{ hut_code: 'KR12', nights: '2' }, { hut_code: 'EG07', nights: 1 }]
)

booking.legs.size              # => 2
booking.legs.first.nights      # => 2
booking.legs.first.class       # => Leg
booking.valid?                 # => true
```

## A bad leg makes a bad booking

Let's push the second leg out of range, to 30 nights.

```ruby run
bad = Booking.new(
  contact: 'lead@example.com',
  legs: [{ hut_code: 'KR12', nights: 2 }, { hut_code: 'EG07', nights: 30 }]
)

bad.valid?                          # => false
bad.errors.to_h                     # => {legs: ["is invalid"]}
bad.legs.last.errors.to_h           # => {nights: ["is invalid"]}
bad.legs.first.valid?               # => true
```

The booking only says that `legs` is invalid. The details live on the child that is wrong, so ask the legs when you need to know which one.

## JSON out and back in

`to_json` writes the booking as JSON and `from_json` reads it back through `new`, so every coercion and validation rule still applies.

```ruby run
json = booking.to_json
json   # => '{"contact":"lead@example.com","legs":[{"hut_code":"KR12","nights":2},{"hut_code":"EG07","nights":1}]}'

copy = Booking.from_json(json)
copy == booking               # => true
copy.legs.last.nights         # => 1
```

Equal structs have equal values all the way down, which makes the round trip easy to test.

## camelCase for another service

The partner desk we meet in chapter 6 wants `contactEmail` and `legList`. We keep snake_case in Ruby and map the names for JSON only. `serialize :json` comes after the fields it names.

```ruby run
class DeskRequest < FieldStruct::Base
  required :contact_email, :email
  required :leg_list, :array, of: Leg
  serialize :json, contact_email: 'contactEmail', leg_list: 'legList'
end

request = DeskRequest.new(contact_email: booking.contact, leg_list: booking.legs.map(&:to_h))
request.as_json.keys                 # => [:contactEmail, :legList]
request.contact_email                # => "lead@example.com"
DeskRequest.from_json(request.to_json) == request   # => true
```

## Keep a token out of the logs

The desk wants an access token. Mark it `sensitive: true` and `inspect`, `pp` and loggers print `[FILTERED]` in its place.

```ruby run
class DeskClient < FieldStruct::Base
  required :base_url, :url
  required :access_token, :string, sensitive: true
end

client = DeskClient.new(base_url: 'https://desk.example.org', access_token: 'tok_ridge_5521')
client.inspect       # => '#<DeskClient base_url: "https://desk.example.org", access_token: [FILTERED]>'
client.access_token  # => "tok_ridge_5521"
```

The reader still returns the real value because your code needs it. The mask is for display only, and `client.to_json` writes the real token too, so don't log that.

## What you built

A `Booking` that nests `Leg` structs, one invalid child making its parent invalid, a JSON round trip, a camelCase mapping for an outside service, and a masked token.

Next we leave plain data and write the first action.

## See also

- [Reserving places](/tutorial/reserving-places/): the next chapter
- [JSON and serialization](/reference/field-struct/json-and-serialization/)
- [Nested structs and arrays](/how-to/nested-structs-and-arrays/)
- [Keep secrets out of logs](/how-to/hide-sensitive-values/)

---
title: "How to handle dates, times and time zones"
description: "Parse dates and timestamps from strings, demand an offset where it matters, and read local wall-clock times in a named zone."
sidebar:
  label: "Dates, times and zones"
  order: 5
---

A `Planting` takes a date and a watering time from a form, and every machine has to read them the same way.

## 1. Pick the format

With no `format:`, a date or time field reads a String through the standard library, and that is lenient. When you know what the input looks like, declare it. A preset such as `:us` or `:eu` is shorthand for a `strptime` String, and a String is used as given.

```ruby run
class Planting < FieldStruct::Base
  required :crop, :string
  required :day, :date, format: :eu
  optional :watering, :time, format: '%H:%M', zone: 'UTC'
end

planting = Planting.new(crop: 'Tulips', day: '14/04/2026')
planting.day.iso8601                                      # => "2026-04-14"
Planting.new(crop: 'Tulips', day: '14/04/2026 ').valid?   # => false
Planting.new(crop: 'Tulips', day: '31/04/2026').valid?    # => false
```

A declared format must match the whole String, so a trailing space fails, and the day must exist on the calendar. `as_json` writes with the same format, which means a JSON round trip keeps it.

## 2. Require an offset with `:iso8601`

For timestamps that travel between systems, use `format: :iso8601`. That means RFC 3339, so a String without an offset is refused, not guessed at.

```ruby run
class Sample < FieldStruct::Base
  required :rain_mm, :float
  required :taken_at, :time, format: :iso8601
end

Sample.new(rain_mm: '4.5', taken_at: '2026-04-14T06:15:00-06:00').taken_at.utc_offset  # => -21600
Sample.new(rain_mm: '4.5', taken_at: '2026-04-14T06:15:00').valid?                     # => false
Sample.new(rain_mm: '4.5', taken_at: '2026-04-14 06:15:00Z').valid?                    # => false
```

:::caution
A `Z` produces a fixed `+00:00` offset, not UTC. The instant is correct and `==` against a UTC time holds, but `utc?` is false. Call `.utc` on the value when you need it.
:::

## 3. Say which zone a local time means

A wall-clock String with no offset is ambiguous. Without `zone:` it lands in whatever zone the process happens to run in. Declare the zone and the gem applies the offset that was in force on that date.

```ruby run
class Watering < FieldStruct::Base
  required :starts, :time, zone: 'America/Chicago'
end

Watering.new(starts: '2026-07-01 10:00').starts.utc_offset          # => -18000
Watering.new(starts: '2026-01-15 10:00').starts.utc_offset          # => -21600
Watering.new(starts: '2026-07-01 10:00 +02:00').starts.utc_offset   # => 7200
```

`zone:` accepts `"UTC"`, a fixed offset like `"-06:00"` (the colon is required) or an IANA name with a slash. An abbreviation such as `"CST"` raises when the class is defined, which beats silently meaning something else. A String or object that carries its own offset keeps it.

## 4. Know the daylight-saving edges

With an IANA zone, a time the clock skips is refused. A time the clock repeats is read at the earlier, daylight offset.

```ruby run
Watering.new(starts: '2026-03-08 02:30').valid?               # => false
Watering.new(starts: '2026-11-01 01:30').starts.utc_offset    # => -18000
```

What you get back is a plain `Time` with the resolved offset. It doesn't remember the zone, so adding days to it won't follow daylight saving. If you need a fresh reading, assign the field again from the String.

## 5. Pin your examples and tests

In tests, use a fixed timestamp and a declared `zone:`. A format that covers only part of a day, like `'%H:%M'` above, fills in today's date, so assert on `hour` and `min` rather than on the whole value.

```ruby run
Planting.new(crop: 'Tulips', day: '14/04/2026', watering: '07:45').watering.hour   # => 7
```

## See also

- [Dates, times and zones](/reference/field-struct/dates-and-times/)
- [JSON and serialization](/reference/field-struct/json-and-serialization/)
- [Coercion versus validation](/explanation/coercion-and-validation/)

---
title: "Dates, times and zones"
description: "How :date, :time and :datetime read strings and objects, the format presets, RFC 3339 rules, and how zone: resolves wall-clock times."
sidebar:
  order: 3
---

Calendar values come in three types. `:date` gives back a `Date`, `:time` a `Time` and `:datetime` a `DateTime`. Each one accepts Strings and temporal objects and turns down anything else, so an Integer is never read as epoch seconds. The result doesn't depend on the process zone, and it doesn't care whether ActiveSupport is loaded.

Rules: FS-B85 to FS-B100, FS-B165, FS-I12, FS-I18. Every input in the examples is pinned, so they print the same thing on any machine.

| Option | Types | Values |
|---|---|---|
| `format:` | all three | a strptime String, or a preset name |
| `in:` | all three | Range (checked with `cover?`) or Array (membership) |
| `zone:` | `:time`, `:datetime` | `"UTC"`, an offset like `"-06:00"`, or an IANA name |

## Reading objects

The type checks the class of the input in this order: String, DateTime, Date, Time.

| Field | From | Result |
|---|---|---|
| `:date` | `Date` | the same object for a plain `Date` |
| `:date` | `DateTime` or `Time` | the calendar day as written, in its own offset |
| `:time` | `Time` | the same object for a plain `Time`, else rebuilt with the same instant and offset |
| `:time` | `DateTime` | a `Time` with the same wall clock, fraction and offset |
| `:time` | `Date` | local midnight in the process zone, or in `zone:` when declared |
| `:datetime` | `Time` | a `DateTime` with the same instant, fraction and offset |
| `:datetime` | `Date` | midnight at offset 0, or at `zone:` when declared |

An object that is already a `Date`, `Time` or `DateTime` is never parsed again, whatever `format:` says. It keeps its own offset, and the declared `zone:` doesn't convert it.

```ruby run
class Bloom < FieldStruct::Base
  optional :opened,  :date
  optional :pruned,  :time
  optional :flagged, :datetime
end

reading = Time.new(2026, 4, 18, 22, 15, 0, '-05:00')
bloom = Bloom.new(opened: reading, pruned: reading, flagged: reading)
bloom.opened.iso8601              # => "2026-04-18"
bloom.pruned.utc_offset           # => -18000
bloom.flagged.offset              # => Rational(-5, 24)
Bloom.new(pruned: Date.new(2026, 4, 18), flagged: Date.new(2026, 4, 18)).flagged.hour   # => 0
Bloom.new(opened: 20_260_418).valid?   # => false
```

## Reading strings without a format

Without a `format:`, a String has to name a full day: year, month and day, and that day has to exist. `'10:30'`, `'July'` and `'12'` fail, and so do `'2026-02-30'` and `'2026-06-31'`. February 29th passes in a leap year. Once the check is done the String goes to `Date.parse`, `Time.parse` or `DateTime.parse`, which makes this path as forgiving as the standard library (`'v1.2.3'` still reads as a date). A blank String, or one that parses to nothing, is a coercion failure, never "missing".

With neither `format:` nor `zone:`, a zone-less `:time` string lands in the process zone and a zone-less `:datetime` string at offset 0. A string that carries its own offset keeps it. Whenever the result matters, pin a `zone:`.

```ruby run
class Sowing < FieldStruct::Base
  optional :planted, :date
  optional :sprouted, :datetime
end

Sowing.new(planted: '2026-09-12').planted.to_s        # => "2026-09-12"
Sowing.new(planted: '2026-02-29').valid?              # => false
Sowing.new(planted: '2032-02-29').valid?              # => true
Sowing.new(planted: '09:45').valid?                   # => false
Sowing.new(planted: '').valid?                        # => false
Sowing.new(sprouted: '2026-09-20 08:05').sprouted.offset   # => 0
Sowing.new(sprouted: '2026-09-20T08:05:00+09:00').sprouted.offset   # => Rational(3, 8)
```

## Formats

`format:` is either a strptime String or the name of a preset standing in for one. It works both ways: input Strings are parsed with it, and `as_json` and `to_json` write with the same `strftime` String. With no format the output is the object's `iso8601`, so `from_json(to_json(x))` round-trips whatever format you choose.

A declared format has to match the entire String. Trailing characters (a trailing space included) and leading whitespace are refused, and the day must exist, so `'2026-06-31'` fails under a format as well. Widths are as loose as `strptime` allows, so `%m` reads one or two digits. A format that covers only part of a day, like `'%H:%M'`, is a choice you made on purpose and it parses, with today's date filled in.

| Preset | `:date` | `:time` and `:datetime` |
|---|---|---|
| `iso8601` | RFC 3339 date, `2026-07-03` | RFC 3339 timestamp |
| `us` | `%m/%d/%Y` | not available |
| `eu` | `%d/%m/%Y` | not available |
| `rfc2822` | not available | `%a, %d %b %Y %H:%M:%S %z` |
| `db` | not available | `%Y-%m-%d %H:%M:%S`, no zone |

`Field#options` keeps the Symbol as you declared it, so tooling can read the preset name. An unknown preset raises when the class is declared, and so does a `format:` that is neither String nor Symbol (a Regexp, say):

```
unknown date format preset :zz. Available: [:iso8601, :us, :eu]
```

A String or Symbol `format:` only drives parsing and rendering. Unlike a Regexp `format:` on a string field, it never adds `"is invalid"`.

```ruby run
class Watering < FieldStruct::Base
  optional :us_day,   :date, format: :us
  optional :eu_day,   :date, format: :eu
  optional :logged,   :time, format: :db, zone: 'UTC'
  optional :reported, :datetime, format: :rfc2822
end

watering = Watering.new(us_day: '11/02/2026', eu_day: '11/02/2026', logged: '2026-11-02 06:45:00', reported: 'Mon, 02 Nov 2026 06:45:00 +0100')
watering.us_day.iso8601           # => "2026-11-02"
watering.eu_day.iso8601           # => "2026-02-11"
watering.as_json[:us_day]         # => "11/02/2026"
watering.as_json[:logged]         # => "2026-11-02 06:45:00"
watering.reported.offset          # => Rational(1, 24)
Watering.new(us_day: '11/02/2026 ').valid?   # => false
Watering.new(us_day: '04/31/2026').valid?    # => false
Watering.metadata[:us_day].options[:format]  # => :us
```

## RFC 3339 and format: :iso8601

`format: :iso8601` means RFC 3339. The gem parses and writes it itself instead of calling `Time.iso8601`, which disagrees with `DateTime.iso8601` and can roll 30 February forward. `:time` and `:datetime` accept and refuse the very same strings.

Accepted: `YYYY-MM-DD` for a date. A timestamp is `YYYY-MM-DD`, then `T` or `t`, then `hh:mm:ss`, an optional fraction of any length, and an offset written `Z`, `z` or `+hh:mm`. Input may drop the colon in the offset (`+0000`), because an older release wrote it that way. Sub-second digits are kept exactly.

Refused: `2026-7-3`, `20260418`, week dates (`2026-W27-5`), ordinal dates (`2026-184`), a timestamp for a `:date` field, a date alone or a time alone for a timestamp, a space in place of `T`, missing seconds, a missing offset, trailing text, hour 24, second 60, an offset hour above 23 or minute above 59, and any day that does not exist. The failure messages are `expected an RFC 3339 date`, `expected an RFC 3339 timestamp`, `invalid time of day`, `invalid UTC offset` and `invalid date`.

Output is `YYYY-MM-DD` for a date. A timestamp is written `YYYY-MM-DDThh:mm:ss`, plus a fraction only when it is non-zero (trimmed, up to nanoseconds), then `Z` at offset 0 or `+hh:mm` otherwise. `+0000` is never written, and the instant survives any change of offset.

:::caution
Under `format: :iso8601`, a `Z` offset yields a fixed `+00:00` offset, not UTC. `utc_offset` is 0 but `utc?` is false, and `zone: 'UTC'` doesn't change that, since a zone only fills in a missing offset and an RFC 3339 string always has one. It is the same instant, and `==` against a UTC time holds. If you need `utc?`, call `.utc` on the value.
:::

```ruby run
class Gauge < FieldStruct::Base
  optional :read_at, :time, format: :iso8601
  optional :day,     :date, format: :iso8601
end

Gauge.new(read_at: '2026-10-05T14:20:00-07:00').read_at.utc_offset   # => -25200
Gauge.new(read_at: '2026-10-05T14:20:00Z').read_at.utc?              # => false
Gauge.new(read_at: '2026-10-05T14:20:00Z').read_at.utc.utc?          # => true
Gauge.new(read_at: '2026-10-05T14:20:00+0000').valid?                # => true
Gauge.new(read_at: '2026-10-05 14:20:00Z').valid?                    # => false
Gauge.new(read_at: '2026-10-05T14:20:00').valid?                     # => false
Gauge.new(read_at: '2026-10-05T14:20:00.250Z').as_json[:read_at]     # => "2026-10-05T14:20:00.25Z"
Gauge.new(read_at: '2026-10-05T21:20:00Z').read_at == Time.utc(2026, 10, 5, 21, 20)   # => true
Gauge.new(day: '2026-02-30').valid?                                  # => false
Gauge.new(day: '2026-10-05T14:20:00Z').valid?                        # => false
```

Loading ActiveSupport changes nothing here. Strings never go through `String#to_time`, `'03 Jul 26'` reads as the year 2026, and a `DateTime` becomes a `Time` built from its components with the offset kept.

## Ranges and lists with in:

`in:` accepts a Range or an Array. A Range is tested with `cover?` against its endpoints and never enumerated, an Array by membership. A `DateTime` inside a range with Date endpoints is valid even when it isn't at midnight. The check runs after coercion, and a miss reports `"is invalid"`.

```ruby run
class Harvest < FieldStruct::Base
  optional :picked, :date, in: Date.new(2026, 5, 1)..Date.new(2026, 10, 31)
  optional :market_day, :date, in: [Date.new(2026, 8, 8), Date.new(2026, 8, 22)]
end

Harvest.new(picked: '2026-08-14').valid?           # => true
Harvest.new(picked: '2026-11-01').errors[:picked]  # => ["is invalid"]
Harvest.new(market_day: '2026-08-22').valid?       # => true
Harvest.new(market_day: '2026-08-23').valid?       # => false
```

## Zones with zone:

Use `zone:` to say which zone a zone-less String means. It is a String in one of three forms:

| Form | Example | Notes |
|---|---|---|
| `"UTC"` | `"UTC"` | yields a UTC time, `utc?` is true |
| fixed offset | `"-06:00"` | colon required, hours 00 to 23, minutes 00 to 59 |
| IANA name | `"America/Denver"` | must contain `/` and be known to the zone database |

It never overrides an offset the input already carries. A `Time` or `DateTime` object keeps its instant and offset, and an Integer is refused.

What it does to a String:

- a zone-less String is the wall clock in that zone, and for an IANA name the offset in force on that date applies, so `'2026-07-01 10:00'` in Chicago is `-05:00` and `'2026-01-15 10:00'` is `-06:00`
- a `format:` without `%z` behaves the same way, and a date the format leaves out means today in that zone
- epoch seconds under `format: '%s'` keep their instant, displayed at the zone's offset
- a String with its own offset (`+02:00`, `Z`, `EST`) keeps that offset
- a String that names a zone without a fixed offset, say `America/Denver` written in the text, is refused: `names a time zone with no fixed offset, which zone: does not override`
- a `Date` becomes midnight at the zone's offset on that day, or the first moment of that day when an IANA zone skips midnight

`zone:` has no effect under `format: :iso8601`.

### Daylight-saving edges

These only apply to IANA names. A wall-clock time the zone skips is refused. One it repeats is read at the earlier, daylight offset.

```ruby run
class Inspection < FieldStruct::Base
  optional :began,  :time, zone: 'America/Chicago'
  optional :fixed,  :time, zone: '-06:00'
  optional :utc,    :time, zone: 'UTC'
  optional :closed, :datetime, zone: 'America/Chicago'
end

Inspection.new(began: '2026-07-01 10:00').began.utc_offset         # => -18000
Inspection.new(began: '2026-01-15 10:00').began.utc_offset         # => -21600
Inspection.new(began: '2026-07-01 10:00 +02:00').began.utc_offset  # => 7200
Inspection.new(fixed: '2026-07-01 10:00').fixed.utc_offset         # => -21600
Inspection.new(utc: '2026-07-01 10:00').utc.utc?                   # => true
Inspection.new(closed: Date.new(2026, 7, 1)).closed.hour           # => 0
Inspection.new(closed: Date.new(2026, 7, 1)).closed.offset         # => Rational(-5, 24)
# Chicago skips 02:30 on 2026-03-08
Inspection.new(began: '2026-03-08 02:30').valid?                   # => false
# and repeats 01:30 on 2026-11-01: the earlier, daylight offset wins
Inspection.new(began: '2026-11-01 01:30').began.utc_offset         # => -18000
```

You get back a plain `Time` or `DateTime` with the resolved offset. It doesn't carry the zone, so `Time#zone` is `nil` and arithmetic won't follow daylight saving. To re-read a value, assign it again.

### Declaration errors

Anything outside the three forms raises `ArgumentError` at declaration: `"utc"`, `"Z"`, `"-0600"`, `"+24:00"`, abbreviations without a slash such as `"MST"` (the database has it as a fixed `-07:00`, so it is refused instead of quietly not meaning Mountain time), Rails names such as `"Mountain Time (US & Canada)"`, and an unknown `Area/Location`. The message starts `zone: on Time expects an IANA name like "America/Denver", "UTC" or a UTC offset like "-06:00", got "MST".` and closes with a hint sentence for the case. `zone:` on `:date` gives the wrong-type error. When the system has no zone data, the message tells you to add the `tzinfo-data` gem.

`tzinfo`, the zone database, loads only when a field names an IANA zone. `"UTC"` and fixed offsets never load it.

```ruby run
begin
  Class.new(FieldStruct::Base) { optional :at, :time, zone: 'MST' }
rescue ArgumentError => e
  e.message.start_with?('zone: on Time expects an IANA name like "America/Denver"')   # => true
end

begin
  Class.new(FieldStruct::Base) { optional :on, :date, zone: 'UTC' }
rescue ArgumentError => e
  e.message   # => "zone: option does not apply to Date fields. It applies to: Time, DateTime."
end
```

## See also

- [Types](/reference/field-struct/types/)
- [JSON and serialization](/reference/field-struct/json-and-serialization/)
- [Dates, times and zones (how-to)](/how-to/dates-and-time-zones/)
- [Coercion versus validation](/explanation/coercion-and-validation/)

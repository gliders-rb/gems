---
title: "Validity is computed on assignment"
description: "Why every setter validates its own field, what that makes cheap, and the one trade-off it costs."
sidebar:
  order: 2
---

Say a `RainLog` holds a rainfall figure and the gauge sends `"soggy"`.

```ruby run
class RainLog < FieldStruct::Base
  required :rain_mm, :float, in: 0.0..500.0
end

log = RainLog.new(rain_mm: 'soggy')
log.valid?                # => false
log.errors[:rain_mm].first.start_with?('could not be coerced')   # => true

log.rain_mm = '12.5'
log.valid?                # => true
log.errors.empty?         # => true
```

Nobody told the object to validate itself. The setter did, for that one field, the moment the value arrived, and the next good value cleared the error in the setter as well. That is the whole idea. The rest of this page covers why we think it pays off, and what it costs.

## What a setter does

A setter coerces the value, stores it, and rewrites that field's errors from scratch. Other fields' errors stay untouched. `new`, `assign_attributes` and `with` are setters called in a loop (FS-I1). The exact steps are in [Validation and errors](/reference/field-struct/validation-and-errors/#the-setter-pipeline).

## Why per field

The other option is a validation pass that walks every field on request. Most Ruby validation works that way and it is fine. We chose differently, for two reasons.

First, validation follows from mutation anyway. A setter that has to coerce already knows the value is bad, and keeping that is cheaper than discarding it and rediscovering it later. Second, reads cost nothing. `valid?` walks nothing and just reads `errors.empty?` (FS-I3). Cross-field validators are the exception, since they can depend on any field, so `valid?` runs them again.

## Building is not validating

`new` returns an instance every time, garbage included, and doesn't raise on a bad value unless you ask for `coercion_policy :raise` (FS-I2). The object lives long enough to say what was wrong, so a form can show all the errors at once and not just the first.

An invalid object never passes for a fine one. The errors can be read, `inspect` prints them, and `full_messages` gives plain sentences. Using the value after ignoring `valid?` is your call, made with the evidence in front of you.

## The cost: in-place changes go stale

Errors are computed at assignment, so a change that skips the setter goes unseen. The usual case is a nested struct changed in place.

```ruby run
class Frond < FieldStruct::Base
  required :length_cm, :integer
end

class Fernery < FieldStruct::Base
  optional :frond, Frond
end

fernery = Fernery.new(frond: { length_cm: 30 })
fernery.frond.length_cm = 'long'   # the child is now invalid

fernery.valid?                     # => true
fernery.frond = fernery.frond      # assign again, so the parent looks
fernery.valid?                     # => false
```

The parent was right when the frond was assigned and wrong a moment later, and it has no way to know. We accepted that. Fixing it means every child reports to its parent: back-references, cycles and a lot of machinery for something one re-assignment solves. Our lean is a simple model with a loud warning, which is why the [nested structs guide](/how-to/nested-structs-and-arrays/) has a step for it.

For now, remember one rule: after changing a child or an array element in place, assign the field again, or use `with`.

## What we are not sure about

We haven't measured how often the stale case shows up in real code. If it turns out to be common, a cheap fix may exist for one level of nesting. We would rather learn that from use than design for it up front.

## See also

- [Validation and errors](/reference/field-struct/validation-and-errors/)
- [Coercion versus validation](/explanation/coercion-and-validation/)
- [Validate nested structs and arrays](/how-to/nested-structs-and-arrays/)

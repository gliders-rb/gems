---
title: "Coercion versus validation"
description: "Why reading a value and judging it are two steps with two kinds of error, and what each coercion policy trades away."
sidebar:
  order: 3
---

Feed a leaf-count field the string `"abc"`. Two separate things can be wrong with that input, and the gem tells them apart.

```ruby run
class Canopy < FieldStruct::Base
  optional :leaves, :integer, in: 1..99
end

Canopy.new(leaves: '12').leaves                 # => 12
Canopy.new(leaves: '500').errors[:leaves]       # => ["is invalid"]
Canopy.new(leaves: 'abc').errors[:leaves].first.start_with?('could not be coerced')   # => true
```

`'500'` was read without trouble and then judged: it is an integer, but outside the range. That is validation, and the message is `"is invalid"`. `'abc'` never got read, so there is no integer to judge. That is coercion, and the message says so.

## Two steps, two errors

Coercion turns input into a value of the type, or fails. Validation judges a value that already exists. They ask different questions and a client needs different answers, since "send a number" is not the advice "send a smaller number" gives. One merged message would lose that.

The order is fixed too. A coercion failure ends the pipeline for that field, so a required field given garbage gets the coercion message alone, without an "is required" stacked on it (FS-B43 to FS-B46).

## What happens when coercion fails

This is where the gem has a policy, with three choices, because outside data is often wrong and the object should live long enough to say why (FS-B43 to FS-B46).

```ruby run
class Keep < FieldStruct::Base
  optional :leaves, :integer
end

class Replace < FieldStruct::Base
  coercion_policy :replace
  optional :leaves, :integer
end

class Strict < FieldStruct::Base
  coercion_policy :raise
  optional :leaves, :integer
end

Keep.new(leaves: 'abc').leaves       # => "abc"
Replace.new(leaves: 'abc').leaves    # => nil

begin
  Strict.new(leaves: 'abc')
rescue FieldStruct::CoercionError => e
  e.field_name   # => :leaves
end

Keep.new(leaves: 'abc').valid?       # => false
Replace.new(leaves: 'abc').valid?    # => false
```

- `:keep_raw` is the default. Nothing gets lost, you can inspect what arrived, and the error records the refusal. The cost is that an invalid object may hold a value of the wrong class, so check `valid?` before using it.
- `:replace` stores `nil`. The field never has the wrong class, but the original input is gone. It always stores `nil`, never a type-specific null, so there is just one thing to remember.
- `:raise` raises `CoercionError` from the setter and keeps the old value. It suits code that would rather stop, and the price is a `rescue` around every build.

One field can override the class policy, which helps when a single field is the odd one out.

## Lenient by default

The defaults follow what ActiveModel readers expect, so a Rails client sees familiar values. That is lenient, on purpose. `strict: true` opts in to narrower `:integer` and string types, and anything it accepts the lenient default accepts too. Our lean is lenient by default and strict on request, and the spec holds the default lenient until a major release.

## Messages never echo input

No error message holds the offending value, only its class (FS-I5). That covers coercion errors, `CoercionError`, union and array messages, `from_json` errors and the `cause` chain. The reason is plain: the bad value is the one that turns out to be a password pasted into the wrong box. Errors get logged and sent back to clients, so they must be safe to log.

The price is a less helpful message, since the value is the first thing you want while debugging. We pay it. Look at the input where it came in.

## See also

- [Validation and errors](/reference/field-struct/validation-and-errors/)
- [Types](/reference/field-struct/types/)
- [Validity is computed on assignment](/explanation/validity-on-assignment/)

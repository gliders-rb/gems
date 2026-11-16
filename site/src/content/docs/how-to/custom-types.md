---
title: "How to add your own field type"
description: "Write a type class for a value the built-ins don't read, register it under a name, and give it an option of its own."
sidebar:
  label: "Add your own type"
  order: 6.5
---

Hut wardens write altitudes as `'2,350 m'`, `'2350m'` or plain `2350`. You want an Integer number of metres every time, and an error for anything else.

## 1. Write the type

Subclass `FieldStruct::Types::Base` and define `coerce` and `ruby_type`. Return `nil` for `nil`, and raise `ArgumentError` to refuse a value. Finish the keywords with `**`, because the setter hands over every option on the field.

```ruby run title="altitude.rb"
class Altitude < FieldStruct::Types::Base
  def coerce(value, **)
    return nil if value.nil?
    return value if value.is_a?(Integer)

    text = value.to_s.delete(',').strip.delete_suffix('m').strip
    raise ArgumentError, 'Altitude fields expect metres, like "2350 m"' unless text.match?(/\A\d+\z/)

    Integer(text)
  end

  def ruby_type = Integer
end
```

The message never repeats the value, the same way the built-in types word theirs.

## 2. Register it under a name

A module that answers `field_types` with a registry lends its names to every struct declared inside it. `new_registry` keeps the built-ins as its parent, so `:string` still works.

```ruby run title="altitude.rb"
module Alpine
  def self.field_types
    @field_types ||= FieldStruct.new_registry { register :altitude, Altitude }
  end

  class Pass < FieldStruct::Base
    required :name, :string
    required :height, :altitude
  end
end

Alpine::Pass.new(name: 'Col Blanc', height: '2,350 m').height   # => 2350
Alpine::Pass.new(name: 'Col Blanc', height: 2350).height        # => 2350
```

If you only need the type in one place, skip the registry and pass the class itself: `required :height, Altitude`.

## 3. Read the error

A refused value is kept and recorded like any other coercion failure, with your message after the standard prefix.

```ruby run title="altitude.rb"
pass = Alpine::Pass.new(name: 'Col Blanc', height: 'very high')
pass.valid?             # => false
pass.errors[:height]    # => ["could not be coerced: Altitude fields expect metres, like \"2350 m\""]
```

## 4. Give it an option

Declare the option in `own_option_schema` and take it as a keyword in `coerce`. A wrong value type now raises when the class is declared, not when it runs.

```ruby run title="altitude.rb"
class CappedAltitude < Altitude
  def self.own_option_schema
    {ceiling: option(type: [Integer])}
  end

  def coerce(value, ceiling: nil, **)
    metres = super
    raise ArgumentError, "Altitude fields expect at most #{ceiling} m" if ceiling && metres && metres > ceiling

    metres
  end
end

class Hut < FieldStruct::Base
  required :height, CappedAltitude, ceiling: 4810
end

Hut.new(height: '3,100 m').height             # => 3100
Hut.new(height: '5000 m').errors[:height]     # => ["could not be coerced: Altitude fields expect at most 4810 m"]

begin
  Class.new(FieldStruct::Base) { required :height, CappedAltitude, ceiling: '4810' }
rescue ArgumentError => e
  e.message   # => 'ceiling: on CappedAltitude expects Integer, got String ("4810")'
end
```

## See also

- [Registries and custom types](/reference/field-struct/registries-and-custom-types/), for `missing?`, `rbs_type`, aliases and changing a built-in's defaults
- [Types](/reference/field-struct/types/), to check a built-in doesn't already read your value
- [Validation and errors](/reference/field-struct/validation-and-errors/), for the coercion policies

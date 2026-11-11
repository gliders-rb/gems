---
title: "How to keep sensitive values out of logs"
description: "Mark passwords and tokens as sensitive so inspect, pp and loggers print a placeholder, and filter the data paths yourself."
sidebar:
  label: "Keep secrets out of logs"
  order: 4
---

A `Gardener` record carries a password and an API token, and sooner or later someone will `inspect` it, `pp` it or pass it to a logger.

## 1. Mark the fields

`sensitive: true` is accepted on every type.

```ruby run
require 'logger'
require 'stringio'

class Gardener < FieldStruct::Base
  required :email, :email
  optional :password, :string, sensitive: true
  optional :api_token, :string, sensitive: true
  optional :allotments, :integer
end

gardener = Gardener.new(email: 'rows@example.org', password: 'compost9', api_token: 'sprout_key_5521')
```

## 2. Check what prints

`inspect` prints `[FILTERED]` for a value that is set and `nil` for one that isn't, so an unset secret still looks different from a set one.

```ruby run
gardener.inspect  # => '#<Gardener email: "rows@example.org", password: [FILTERED], api_token: [FILTERED], allotments: nil>'
Gardener.new(email: 'rows@example.org').inspect.include?('password: nil')   # => true
```

Loggers call `inspect` on what they receive, and `pp` shares the same masking, nested structs and their arrays included.

```ruby run
io = StringIO.new
Logger.new(io).info(gardener)
io.string.include?('sprout_key_5521')   # => false
io.string.include?('[FILTERED]')        # => true
```

## 3. Mind the data paths

The mask is for display only (FS-I15). Readers, `attributes`, `to_h`, `as_json` and `to_json` return the real value, since code that serializes an object has to have it.

```ruby run
gardener.password          # => "compost9"
gardener.to_h[:api_token]  # => "sprout_key_5521"
```

:::caution
`puts gardener.to_h` and `logger.info(gardener.to_json)` both print the secrets. The mask covers `inspect` and `pp`, and nothing more.
:::

## 4. Filter before you log or send a hash

The field metadata knows which fields are sensitive. Filter with it instead of keeping a list by hand.

```ruby run
safe = gardener.to_h.reject { |name, _| Gardener.metadata[name].sensitive? }
safe.keys   # => [:email, :allotments]
```

Error messages never contain the value, only its class, so the `errors:` part of `inspect` is safe as well.

## See also

- [Introspection and tooling](/reference/field-struct/introspection-and-tooling/#sensitive-fields)
- [Instance API](/reference/field-struct/instance-api/)
- [Fields and options](/reference/field-struct/fields-and-options/)

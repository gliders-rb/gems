---
title: "JSON Schema"
description: "Turn the JSON a struct writes into a JSON Schema, for API docs, validators in other services and tool parameters."
sidebar:
  badge:
    text: Unreleased
    variant: caution
  label: "JSON Schema"
  order: 2
---

`field_struct-json_schema` takes the JSON a struct writes with `to_json` and reads with `from_json`, and describes it as a JSON Schema (draft 2020-12). It does not validate anything itself. The schema goes to whatever validator, documentation tool or code generator you already run.

```ruby
gem 'field_struct-json_schema'
```

```ruby
require 'field_struct/json_schema'
```

Requiring it adds `FieldStruct::JSONSchema` and nothing more. Your own classes stay as they were until you opt in (see [How adapters work](/adapters/how-adapters-work/)).

## The schema of a struct

`FieldStruct::JSONSchema.generate` takes a struct class and hands back a Hash with String keys.

```ruby run
require 'field_struct/json_schema'

class CatalogCard < FieldStruct::Base
  required :title, :string
  required :shelfmark, :string, format: /\A\d{6}\z/
  optional :folios, :integer, in: 1..900
  optional :tier, :symbol, enum: %i[open sealed]
  optional :keywords, :array, of: :string
  serialize :json, folios: 'folioCount'
end

schema = FieldStruct::JSONSchema.generate(CatalogCard)
schema['title']                      # => "CatalogCard"
schema['required']                   # => ["title", "shelfmark"]
schema['properties'].keys            # => ["title", "shelfmark", "folioCount", "tier", "keywords"]
schema['properties']['shelfmark']    # => {"type"=>"string", "pattern"=>"^\\d{6}$"}
schema['properties']['folioCount']   # => {"type"=>["integer", "null"], "minimum"=>1, "maximum"=>900}
```

Property names follow what `to_json` writes, which is why `folios` appears as `folioCount`. A field is `required` in the schema when it is required and has no default, since a default fills in a missing key. Optional fields also accept `null`.

Each `generate` call returns a fresh copy, so editing one result never touches another.

If you want `CatalogCard.to_json_schema` as a class method, include the opt-in module.

```ruby run
class Curator < FieldStruct::Base
  include FieldStruct::JSONSchema::Methods

  required :surname, :string
end

Curator.to_json_schema == FieldStruct::JSONSchema.generate(Curator)   # => true
```

## Use case: validate a payload in another service

Say a second service receives what the archive app sends and wants to turn away bad payloads before its own code sees them. Publish the schema as a file and let that service load it into its validator. The validator below is `json_schemer`, a separate gem that this adapter does not depend on.

```ruby run
require 'json_schemer'

validator = JSONSchemer.schema(schema)

good = JSON.parse(CatalogCard.new(title: 'Tide tables', shelfmark: '204117', folios: 88).to_json)
good                    # => {"title"=>"Tide tables", "shelfmark"=>"204117", "folioCount"=>88, "tier"=>nil, "keywords"=>nil}
validator.valid?(good)  # => true

bad = { 'title' => 'Tide tables', 'shelfmark' => 'A12' }
validator.valid?(bad)   # => false
validator.validate(bad).map { |error| error['error'] }   # => ["string at `/shelfmark` does not match pattern: ^\\d{6}$"]
```

For canonical JSON the schema is exact: it accepts what the struct accepts and rejects what the struct rejects. The `to_json` of any valid instance passes.

## Use case: API documentation and nested structs

A nested struct is written once under `$defs` and referenced by name. The root class is referenced as `#`, so a recursive struct works. An anonymous struct is inlined.

```ruby run
class Annotation < FieldStruct::Base
  required :rating, :integer, in: 1..5
  optional :remark, :string
end

class Exhibit < FieldStruct::Base
  required :name, :string
  optional :annotations, :array, of: Annotation
  optional :companion, Exhibit
end

exhibit = FieldStruct::JSONSchema.generate(Exhibit)
exhibit['$defs'].keys                            # => ["Annotation"]
exhibit['properties']['annotations']['items']    # => {"anyOf"=>[{"$ref"=>"#/$defs/Annotation"}, {"type"=>"null"}]}
exhibit['properties']['companion']               # => {"anyOf"=>[{"$ref"=>"#"}, {"type"=>"null"}]}
```

A field's `description:` turns into the schema's `description`, and a default that `to_json` would write turns into `default`. A sensitive field is tagged `x-sensitive`, and its default stays out.

```ruby run
class AccessGrant < FieldStruct::Base
  required :reader, :email, description: 'Address that receives the grant'
  optional :tier, :string, enum: %w[public staff], default: 'public'
  required :vault_code, :string, sensitive: true, default: 'hush'
end

props = FieldStruct::JSONSchema.generate(AccessGrant)['properties']
props['reader']['description']   # => "Address that receives the grant"
props['tier']['default']         # => "public"
props['vault_code']              # => {"x-sensitive"=>true, "type"=>"string"}
```

## Use case: an action's input as tool parameters

An action's `input` block defines a struct, so its schema is a single call away. That schema is what a model needs in order to call the action as a tool. The [tools adapter](/adapters/tools/) wraps this up for you, safety rules included.

```ruby run
class SearchCards < Actionable::Action
  input do
    required :phrase, :string
    optional :max_hits, :integer, in: 1..50
  end
end

params = FieldStruct::JSONSchema.generate(SearchCards.input_schema)
params['properties'].keys   # => ["phrase", "max_hits"]
params['required']          # => ["phrase"]
```

## Overrides

The `json_schema:` option on a field replaces the derived schema. It accepts a Hash, `true` (no constraint) or `false` (nothing validates). A custom type can define a `json_schema` method to the same end, and a type with neither comes out unconstrained and tagged `x-ruby-type`.

```ruby run
class Drawer < FieldStruct::Base
  required :label, :string, json_schema: { 'type' => 'string', 'minLength' => 4 }
  optional :contents, :value, json_schema: false
end

FieldStruct::JSONSchema.generate(Drawer)['properties']['label']   # => {"type"=>"string", "minLength"=>4}
```

A bad override raises `ArgumentError` and names the class and field.

## Regexps with `pattern_for`

Ruby and JavaScript do not treat Regexps the same way. `FieldStruct::JSONSchema.pattern_for` translates a Ruby Regexp into an ECMA-262 pattern that matches exactly the same strings, or returns `nil`. Close enough is never good enough here, so any doubt means `nil`.

```ruby run
FieldStruct::JSONSchema.pattern_for(/\A\d+-\d+\z/)    # => "^\\d+-\\d+$"
FieldStruct::JSONSchema.pattern_for(/\bnote\b/)       # => nil
FieldStruct::JSONSchema.pattern_for(/\A(x+)+\z/)      # => nil
```

The last Regexp has an exact translation, but a backtracking JavaScript engine could spend exponential time on it, so the adapter refuses. In a struct, a `format:` Regexp that can't be translated becomes `x-ruby-pattern`, an annotation that no validator checks.

```ruby run
class Crate < FieldStruct::Base
  required :tag, :string, format: /\A[A-Z]{2}-\d{5}\z/
  required :donor, :string, format: /\A\p{L}+\z/
end

props = FieldStruct::JSONSchema.generate(Crate)['properties']
props['tag']     # => {"type"=>"string", "pattern"=>"^[A-Z]{2}-\\d{5}$"}
props['donor']   # => {"type"=>"string", "x-ruby-pattern"=>"\\A\\p{L}+\\z"}
```

## Options

| Option | On | Meaning |
|---|---|---|
| `serialization:` | `generate` | which `serialize` mapping names the properties; default `:json` |
| `json_schema:` | a field | a Hash, `true` or `false` that replaces the derived schema |
| `description:` | a field | becomes `description` |
| `sensitive:` | a field | adds `x-sensitive` and hides the default |

`FieldStruct::JSONSchema.clear_cache` empties the per-class cache. That cache keeps classes alive, so call it whenever code reloads.

## Limits

When JSON Schema has no way to say a rule, the adapter leaves it out. It never approximates.

- `in:` on dates, times and decimals, and `strict:`, `base:` and `round:`, do not reach the schema. The struct still enforces them.
- A decimal shows up as a string matching a decimal pattern, because `to_json` writes it as a string.
- `format:` on a date or time becomes `format` only for the default or `:iso8601` form.
- An optional string field with `enum:` or `format:` accepts a blank string too, since the struct reads a blank string as missing.
- `unknown_attributes :raise` on a struct adds `additionalProperties: false`.
- The cache notices a new or redeclared field, but not an `enum:` Array edited in place. Redeclare the field instead.

## See also

- [Actions as LLM and MCP tools](/adapters/tools/)
- [How adapters work](/adapters/how-adapters-work/)
- [Adapters overview](/adapters/)

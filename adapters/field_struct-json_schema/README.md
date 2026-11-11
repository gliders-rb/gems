# field_struct-json_schema

JSON Schema (draft 2020-12) for [field_struct](../../gems/field_struct) classes. It describes the JSON a struct writes
with `to_json` and reads with `from_json`, for API docs, validators in other languages, LLM tool parameters and
TypeScript generation. It also translates a Ruby `Regexp` into an ECMA-262 pattern that matches exactly the same strings,
or tells you it cannot.

It is not a validator, and its only runtime dependency is `field_struct`.

## Install

```ruby
gem 'field_struct-json_schema'
```

```ruby
require 'field_struct/json_schema'
```

## Quick start

<!-- doctest -->
```ruby
require 'field_struct/json_schema'

class Exhibit < FieldStruct::Base
  required :name, :string
end

class Curator < FieldStruct::Base
  include FieldStruct::JSONSchema::Methods # opt in to Curator.to_json_schema

  required :given_name, :string
  optional :access, :string, enum: %w[public staff], default: 'public'
  optional :age,  :integer, in: 0..150
  optional :exhibits, :array, of: Exhibit
  serialize :json, given_name: 'givenName'
end

schema = FieldStruct::JSONSchema.generate(Curator) # the same as Curator.to_json_schema
schema['title']                           # => "Curator"
schema['required']                        # => ["givenName"]
schema['properties']['age']               # => {"type"=>["integer", "null"], "minimum"=>0, "maximum"=>150}
schema['properties']['access']['default']   # => "public"
schema['$defs'].keys                      # => ["Exhibit"]
schema['properties']['exhibits']['items']     # => {"anyOf"=>[{"$ref"=>"#/$defs/Exhibit"}, {"type"=>"null"}]}
Curator.to_json_schema == schema            # => true
```

`generate` returns a fresh copy every time, so changing the result changes nothing else. `serialization:` picks the
`serialize` mapping whose names the schema uses (default `:json`, the one `to_json` writes).

## What the schema says

The schema accepts exactly what a struct writes, for canonical JSON. A field is `required` in the schema when it is
required *and* has no default, because a default fills a missing key. An optional field also accepts `null`.

<!-- doctest -->
```ruby
class Dossier < FieldStruct::Base
  required :label, :string
  optional :alias_name, :string
  optional :ratio, :float, in: 0.0...1.0
  required :token, :string, sensitive: true, default: 'secret'
end

props = FieldStruct::JSONSchema.generate(Dossier)['properties']
props['label']    # => {"type"=>"string"}
props['alias_name'] # => {"type"=>["string", "null"]}
props['ratio']    # => {"type"=>["number", "null"], "minimum"=>0.0, "exclusiveMaximum"=>1.0}
props['token']    # => {"x-sensitive"=>true, "type"=>"string"}
FieldStruct::JSONSchema.generate(Dossier)['required'] # => ["label"]
```

A sensitive field's default is left out of the published schema. A blank string counts as missing for the string types, so
an optional string with `enum:` or a `format:` also accepts a blank one:

<!-- doctest -->
```ruby
class Vase < FieldStruct::Base
  optional :color, :string, enum: %w[red green]
end

color = FieldStruct::JSONSchema.generate(Vase)['properties']['color']
color['anyOf'][0] # => {"type"=>["string", "null"], "enum"=>["red", "green", nil]}
color['anyOf'][1] # => FieldStruct::JSONSchema::BLANK_STRING
```

| Type | Schema |
|---|---|
| `:boolean` | `{"type":"boolean"}` |
| `:integer`, `:float` | `integer` / `number`, with `minimum`, `maximum` or `exclusiveMaximum` from `in:` (an Array becomes `enum`) |
| `:big_decimal` | a string matching `DECIMAL_PATTERN`, as `to_json` writes it |
| `:date`, `:time`, `:datetime` | a string with `format` `date` / `date-time` (only for the default or `:iso8601` format) |
| `:symbol` | a string, with `enum` when declared |
| `:string`, `:uuid`, `:url`, `:email`, `:binary` | a string; uuid is `format: uuid`, a Regexp `format:` becomes `pattern` |
| `:value` | `{}` |
| `:array`, unions, nested structs | `items`, `anyOf`, `$ref` into `$defs` |

Things the schema leaves out because JSON Schema cannot say them: `in:` on dates, times and decimals, `strict:`, `base:`
and `round:`. Rules are never approximated.

## Nested structs and recursion

A named nested struct is defined once under `$defs` and referenced; the root class is referenced as `#`. An anonymous
struct is inlined.

<!-- doctest -->
```ruby
class Node < FieldStruct::Base
  required :value, :integer
  optional :next_node, Node
end

tree = FieldStruct::JSONSchema.generate(Node)
tree['properties']['next_node'] # => {"anyOf"=>[{"$ref"=>"#"}, {"type"=>"null"}]}
tree.key?('$defs')              # => false
```

## Overrides and custom types

A field's `json_schema:` option (a Hash, `true` or `false`) replaces the derived schema; a custom type can define a
`json_schema` method for the same purpose. Without either, a custom type is unconstrained and carries
`x-ruby-type`.

<!-- doctest -->
```ruby
class Hosted < FieldStruct::Base
  required :id, :string, json_schema: { 'type' => 'string', 'minLength' => 3 }
  optional :extra, :value, json_schema: false
end

props = FieldStruct::JSONSchema.generate(Hosted)['properties']
props['id']    # => {"type"=>"string", "minLength"=>3}
props['extra'] # => {"anyOf"=>[{"not"=>{}}, {"type"=>"null"}]}
```

A wrong override raises `ArgumentError` naming the class and field.

## Regexps: `pattern_for`

`pattern_for(regexp)` returns an ECMA-262 pattern that matches the same strings under the `u` flag (what JSON Schema
validators use), or `nil`. It is exact or nil: when in doubt it returns nil, and the generator then writes the Ruby
source as an `x-ruby-pattern` annotation that no validator checks.

<!-- doctest -->
```ruby
FieldStruct::JSONSchema.pattern_for(/\A\d+\.\d+\z/)   # => "^\\d+\\.\\d+$"
FieldStruct::JSONSchema.pattern_for(/\A[a-z]{2}\z/i)  # => "^[a-zA-ZſK]{2}$"
FieldStruct::JSONSchema.pattern_for(/\Aa.c\z/)        # => "^a[^\\n]c$"
FieldStruct::JSONSchema.pattern_for(/\bword\b/)       # => nil
```

What changes meaning between the engines is rewritten (`\A` and `\z` become `^` and `$`, `.` stops at a newline, `\s` is
the ASCII set, Ruby's `^` and `$` become lookarounds, `/i` is folded into character classes including the two extra
characters Ruby folds, U+017F and U+212A). What has no equivalent returns nil: `\p{..}`, backreferences, atomic and
possessive forms, `\b`, inline options, `x` and `m` flags, POSIX classes and the like.

A pattern a backtracking JavaScript engine could take exponential or high-polynomial time on is refused too, though Ruby
itself is safe:

<!-- doctest -->
```ruby
FieldStruct::JSONSchema.pattern_for(/\A(a+)+\z/)             # => nil
FieldStruct::JSONSchema.pattern_for(/\A\d*\d*\d*x\z/)        # => nil
FieldStruct::JSONSchema.pattern_for(/\A\d*\d*x\z/)           # => "^\\d*\\d*x$"
FieldStruct::JSONSchema.pattern_for(/\A[^@\s]+@[^@\s]+\z/)   # => "^[^@\\t\\n\\v\\f\\r ]+@[^@\\t\\n\\v\\f\\r ]+$"
```

The check is conservative (a refusal may be unnecessary, an acceptance is never unsafe). In a struct, a `format:` Regexp
becomes `pattern` when translatable and `x-ruby-pattern` otherwise:

<!-- doctest -->
```ruby
class Tablet < FieldStruct::Base
  required :code, :string, format: /\A[A-Z]{3}-\d{4}\z/
  required :name, :string, format: /\A\p{L}+\z/
end

props = FieldStruct::JSONSchema.generate(Tablet)['properties']
props['code'] # => {"type"=>"string", "pattern"=>"^[A-Z]{3}-\\d{4}$"}
props['name'] # => {"type"=>"string", "x-ruby-pattern"=>"\\A\\p{L}+\\z"}
```

The promise is checked against Node's RegExp on every supported Ruby (see Development).

## Caching

`generate` builds once per class and serialization, and rebuilds when a class's fields, `serialize` mapping, name or
`unknown_attributes` change (not when an `enum:` Array or an override Hash is mutated in place: redeclare the field).
A schema that asked a custom type's `json_schema` hook is never cached. `FieldStruct::JSONSchema.clear_cache` empties
the cache, which holds classes alive: call it on code reload.

## Development

```sh
bundle exec rake                   # specs + RuboCop
bundle exec rake release:check     # also doctests, YARD, signature guards (sig/ is generated by Sord)
bundle exec rake differential      # pattern_for against Node's RegExp (needs node)
bundle exec rake sigs:generate     # after changing a YARD comment
```

`spec/differential/` holds the corpus of about 1200 Regexps and a pool of sample strings. Ruby answers are computed on the
running Ruby, never stored. When a bug report shows a wrongly translated Regexp, add it to `corpus.json` with the strings
that disagree.

The type signatures are generated from the YARD comments by Sord. The internal files are excluded in `.yardopts`, so only
the public API is in `sig/`. Types of field_struct that the public API mentions (for example `FieldStruct::Base`) resolve
because `support/sord_gen.rb` feeds field_struct's own `sig/` to Sord's resolver.

## License

MIT.

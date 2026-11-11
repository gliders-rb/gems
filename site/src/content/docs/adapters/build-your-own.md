---
title: "Build your own adapter"
description: "Write a generator for a new format in about 60 lines on top of FieldStruct::Introspection, then test and package it."
sidebar:
  badge:
    text: Unreleased
    variant: caution
  label: "Build your own"
  order: 7
---

Let's write a small adapter that turns a struct into a TypeScript interface, in about 60 lines. The same steps work for any target - a docs table, a GraphQL type, a SQL definition - and the first-party adapters follow them too.

## 1. Look at what the walk gives you

`FieldStruct::Introspection.properties` lists a struct's fields in order. Every property carries the external `key`, the `field` itself, and a `node` that says what kind of type it has. Here is a struct with one of each kind.

```ruby run
class Waypoint < FieldStruct::Base
  optional :label, :string
end

class Trek < FieldStruct::Base
  required :name, :string
  required :days, :integer, in: 1..30
  optional :waypoints, :array, of: Waypoint
  optional :tags, :array, of: :string
  optional :permit, :union, of: %i[integer string]
  optional :starts, :date
  serialize :json, days: 'dayCount'
end

properties = FieldStruct::Introspection.properties(Trek)
properties.map(&:key)   # => ["name", "dayCount", "waypoints", "tags", "permit", "starts"]
properties.map { |p| p.node.class.name.split('::').last }
# => ["ScalarNode", "ScalarNode", "ArrayNode", "ArrayNode", "UnionNode", "ScalarNode"]
properties[1].node.options   # => {in: 1..30}
properties[2].node.element.klass   # => Waypoint
properties[4].node.members.map { |m| m.type.class }.map { |c| c.name.split('::').last }   # => ["Integer", "String"]
```

Nodes come in four kinds: scalar, array, union and struct. A struct node is a reference to the class and is never expanded, so nesting and recursion are yours to handle. The walk reports declarations and nothing else, which leaves what `required` means, what a missing value is and how types map up to your adapter. Every member is in the [introspection reference](/adapters/introspection/).

## 2. Write the adapter

The adapter is a single module function. It dispatches on the node class with `case`, since the node classes have no common base, and it matches scalar types by the node's type class.

```ruby run title="type_script.rb"
module TypeScript
  Types = FieldStruct::Types
  SCALARS = {
    Types::Integer => 'number', Types::Float => 'number', Types::Boolean => 'boolean',
    Types::BigDecimal => 'string', Types::Value => 'unknown'
  }.freeze

  # Returns the interface source for +klass+ and every struct it refers to.
  def self.generate(klass, serialization: :json)
    out = {}
    declare(klass, serialization, out)
    out.values.join("\n")
  end

  def self.declare(klass, serialization, out)
    name = klass.name.split('::').last
    return if out.key?(name)

    out[name] = nil # reserve the name first, so a recursive struct stops here
    lines = FieldStruct::Introspection.properties(klass, serialization: serialization).map do |prop|
      type = prop.field.options[:ts] || type_for(prop.node, serialization, out)
      optional = prop.field.required? ? '' : '?'
      "  #{prop.key}#{optional}: #{type}#{' | null' unless prop.field.required?};"
    end
    out.delete(name) # re-insert at the end, so nested interfaces come first
    out[name] = "interface #{name} {\n#{lines.join("\n")}\n}\n"
  end

  def self.type_for(node, serialization, out)
    case node
    when FieldStruct::Introspection::StructNode
      declare(node.klass, serialization, out)
      node.klass.name.split('::').last
    when FieldStruct::Introspection::ArrayNode
      "#{node.element ? type_for(node.element, serialization, out) : 'unknown'}[]"
    when FieldStruct::Introspection::UnionNode
      node.members.map { |member| type_for(member, serialization, out) }.uniq.join(' | ')
    else
      scalar(node)
    end
  end

  def self.scalar(node)
    return SCALARS.fetch(node.type.class) if SCALARS.key?(node.type.class)

    enum = node.options[:enum]
    enum ? enum.map { |value| "'#{value}'" }.join(' | ') : 'string'
  end
end
```

A field turns into one line. An optional field gets `?` and `| null`, because `to_json` writes `null` for a missing value. A struct node declares its nested interface first and then refers to it by name. Dates, times, UUIDs and the rest of the string family fall through to `string`, which is what `to_json` writes for them.

## 3. Run it

```ruby run
TypeScript.generate(Trek) # => "interface Waypoint {\n  label?: string | null;\n}\n\ninterface Trek {\n  name: string;\n  dayCount: number;\n  waypoints?: Waypoint[] | null;\n  tags?: string[] | null;\n  permit?: number | string | null;\n  starts?: string | null;\n}\n"
```

The key `dayCount` comes from the `serialize :json` mapping. Pass `serialization:` to get another format's names.

## 4. Let fields override the mapping

The generator looks at `prop.field.options[:ts]` before anything else. Unknown options pass through a field declaration untouched, so a field can state what it wants and field_struct needs no change.

```ruby run
class Hut < FieldStruct::Base
  required :code, :string
  optional :season, :symbol, enum: %i[summer winter year_round]
  optional :places, :integer, ts: 'bigint'
end

TypeScript.generate(Hut) # => "interface Hut {\n  code: string;\n  season?: 'summer' | 'winter' | 'year_round' | null;\n  places?: bigint | null;\n}\n"
```

A pass-through option belongs to the whole field. An array element can't carry one, so an override covers the entire field.

## 5. Handle recursion and anonymous structs

A recursive struct would loop if the generator expanded nodes. Struct nodes are references, though, and the generator reserves the name before it walks the fields.

```ruby run
class Junction < FieldStruct::Base
  required :label, :string
  optional :branches, :array, of: Junction
end

TypeScript.generate(Junction) # => "interface Junction {\n  label: string;\n  branches?: Junction[] | null;\n}\n"
FieldStruct::Introspection.named?(Junction)                      # => true
FieldStruct::Introspection.named?(Class.new(FieldStruct::Base))  # => false
```

`Introspection.named?` says whether a class can serve as a definition name. An anonymous class can't, so a real adapter should either raise a clear error for it or inline it.

## 6. Test it

Test the output as text, one struct per example, and test the claim you make about the data. Here the claim is that the interface lists exactly the keys `to_json` writes.

```ruby run
keys = Oj.load(Trek.new(name: 'Haute Route', days: 7).to_json).keys
declared = TypeScript.generate(Trek).scan(/^  (\w+)\??:/).flatten.drop(1)
declared == keys   # => true
```

`declared` drops the first match, which is `label` from the nested `Waypoint`. In a spec that becomes `expect(declared).to eq(keys)`, with one example per type and one per override.

## 7. Package it as a gem

Copy the shape of the first-party adapters.

```ruby
# field_struct-typescript.gemspec
Gem::Specification.new do |spec|
  spec.name = 'field_struct-typescript'
  spec.version = '1.0.0'
  spec.summary = 'TypeScript interfaces for field_struct classes'
  spec.required_ruby_version = '>= 3.3'
  spec.files = Dir['lib/**/*.rb', 'README.md', 'LICENSE.txt']
  spec.add_dependency 'field_struct', '>= 1.0.0.pre1', '< 2'
end
```

- The entry point is `lib/field_struct/typescript.rb`, with an explicit `require_relative` per file.
- Module functions come first. Add an opt-in `Methods` module only if people want `Klass.to_typescript`.
- Requiring the gem must leave your users' classes alone.
- For anything you can't map, raise `ArgumentError` naming the class and field, and don't guess.
- Depend on `field_struct` alone. Any third-party library your format needs becomes a dependency of your gem.

## See also

- [Introspection reference](/adapters/introspection/)
- [How adapters work](/adapters/how-adapters-work/): why adapters are shaped this way
- [JSON Schema](/adapters/json-schema/): a finished adapter to read

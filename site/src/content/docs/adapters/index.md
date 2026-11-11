---
title: "Adapters"
description: "Optional gems that export field_struct classes to JSON Schema, Avro and Protobuf, trace actionable with OpenTelemetry, and expose actions as LLM tools."
sidebar:
  badge:
    text: Unreleased
    variant: caution
  label: "Overview"
  order: 1
---

An adapter is an optional gem on top of `field_struct` or `actionable`, and it handles one format. None is released yet, so each example here runs against the code in this repository.

:::caution[Unreleased]
All the adapters are at `1.0.0.pre1`. Protobuf and tools are previews. Their specs settle the behaviour, but none of it has shipped.
:::

## Choose an adapter

| You want to | Adapter | Gem |
|---|---|---|
| publish a struct's JSON as a schema, for docs or other services | [JSON Schema](/adapters/json-schema/) | `field_struct-json_schema` |
| write structs as Avro binary and read old events | [Avro](/adapters/avro/) | `field_struct-avro` |
| encode Avro faster, with an optional Rust encoder | [Avro native encoder](/adapters/avro-native/) | `field_struct-avro-native` |
| print a `.proto` and encode structs with Protobuf | [Protobuf](/adapters/protobuf/) (preview) | `field_struct-protobuf` |
| trace action runs | [OpenTelemetry](/adapters/opentelemetry/) | `actionable-otel` |
| let a language model call an action | [LLM and MCP tools](/adapters/tools/) (preview) | `actionable-tools` |

## Install

Every adapter is a separate gem, and you load it with an explicit `require`.

```ruby
gem 'field_struct-json_schema'   # require 'field_struct/json_schema'
gem 'field_struct-avro'          # require 'field_struct/avro'
gem 'field_struct-protobuf'      # require 'field_struct/protobuf'
gem 'actionable-otel'            # require 'actionable/otel'
gem 'actionable-tools'           # require 'actionable/tools'
```

Some pull in a library and some leave that to you. Avro depends on `avro` and Protobuf on `google-protobuf`. OpenTelemetry depends on `opentelemetry-api` alone, so the SDK and the exporter are your choice. The tools adapter needs `mcp` or `ruby_llm` only for the wrapper you require.

## How they behave

- **Module functions first.** Each adapter works as plain functions, like `FieldStruct::Avro.schema(Hut)`, and has an opt-in `Methods` module for when you want `Hut.to_avro_schema` on the class.
- **Requiring leaves your classes alone.** OpenTelemetry is the exception: `require 'actionable/otel'` turns tracing on.
- **One shape, many formats.** The three format adapters share a single walk over a struct's fields, [`FieldStruct::Introspection`](/adapters/introspection/). Output names come from `serialize`, so one declaration can call a field something different in `:json`, `:avro` and `:protobuf`.
- **They refuse rather than approximate.** If a format can't hold something exactly, the adapter raises, or leaves it out and documents that.

```ruby run
require 'field_struct/json_schema'

class Hut < FieldStruct::Base
  required :name, :string
end

Hut.respond_to?(:to_json_schema)                  # => false
FieldStruct::JSONSchema.generate(Hut)['required'] # => ["name"]

class Hut
  include FieldStruct::JSONSchema::Methods
end

Hut.respond_to?(:to_json_schema)                  # => true
```

## Go further

- [How adapters work](/adapters/how-adapters-work/): why they are separate gems, and why they never approximate
- [Introspection reference](/adapters/introspection/): the walk all the format adapters share
- [Build your own adapter](/adapters/build-your-own/): a generator for another format in about 60 lines

## See also

- [How the two gems fit together](/explanation/how-the-gems-fit/)
- [Introspection and tooling](/reference/field-struct/introspection-and-tooling/)

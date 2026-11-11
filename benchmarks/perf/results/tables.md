### actionable

| workload | items/call | ips YJIT off | ips YJIT on | us/item (on) | allocs/item |
|---|---:|---:|---:|---:|---:|
| run success, measure none | 1 | 30,714 | 64,786 | 15.4 | 141.0 |
| run success, measure all (history) | 1 | 26,211 | 54,467 | 18.4 | 164.0 |
| run failure (declared fail!) | 1 | 29,928 | 64,100 | 15.6 | 137.0 |
| run failure (invalid input) | 1 | 46,879 | 100,374 | 10.0 | 80.0 |
| run failure, measure all | 1 | 26,933 | 59,403 | 16.8 | 144.0 |
| run_each x100, measure none | 100 | 297.8 | 655.8 | 15.2 | 141.0 |
| run_each x100, measure all | 100 | 255.9 | 548.2 | 18.2 | 164.0 |
| nested action step, measure none | 1 | 20,682 | 43,907 | 22.8 | 190.0 |
| nested action step, measure all | 1 | 18,026 | 37,494 | 26.7 | 212.0 |
| history.to_json (5 steps) | 1 | 176,710 | 221,316 | 4.5 | 20.0 |

### actionable-otel

| workload | items/call | ips YJIT off | ips YJIT on | us/item (on) | allocs/item |
|---|---:|---:|---:|---:|---:|
| 5-step run, success | 1 | 14,463 | 41,515 | 24.1 | 216.0 |
| 5-step run, declared failure | 1 | 18,354 | 48,925 | 20.4 | 158.0 |
| nested action run | 1 | 10,674 | 28,547 | 35.0 | 258.0 |
| 5-step run, success, run span only (step_spans=false) | 1 | 24,373 | 64,104 | 15.6 | 141.0 |

### actionable-otel-untraced

| workload | items/call | ips YJIT off | ips YJIT on | us/item (on) | allocs/item |
|---|---:|---:|---:|---:|---:|
| 5-step run, success | 1 | 37,010 | 82,830 | 12.1 | 124.0 |
| 5-step run, declared failure | 1 | 34,474 | 74,841 | 13.4 | 123.0 |
| nested action run | 1 | 22,161 | 45,463 | 22.0 | 181.0 |

### actionable-tools

| workload | items/call | ips YJIT off | ips YJIT on | us/item (on) | allocs/item |
|---|---:|---:|---:|---:|---:|
| Definition build (cold: schema + envelope) | 1 | 43,546 | 73,892 | 13.5 | 218.0 |
| call, success | 1 | 27,967 | 59,192 | 16.9 | 158.0 |
| call, declared failure | 1 | 25,579 | 53,785 | 18.6 | 162.0 |
| call, invalid input | 1 | 38,504 | 74,397 | 13.4 | 115.0 |
| MCP round trip: server.handle(tools/call) | 1 | 13,273 | 31,206 | 32.0 | 279.0 |
| MCP round trip, JSON in/out (parse + handle + dump) | 1 | 13,061 | 30,054 | 33.3 | 294.0 |

### field_struct

| workload | items/call | ips YJIT off | ips YJIT on | us/item (on) | allocs/item |
|---|---:|---:|---:|---:|---:|
| new from symbol-key Hash | 1 | 14,439 | 27,197 | 36.8 | 294.0 |
| new from string-key Hash | 1 | 14,009 | 24,004 | 41.7 | 294.0 |
| new invalid input (error path) | 1 | 22,903 | 41,583 | 24.0 | 183.0 |
| new LineItem (one nested struct) | 1 | 150,774 | 319,617 | 3.1 | 28.0 |
| from_json | 1 | 11,518 | 21,693 | 46.1 | 365.0 |
| as_json | 1 | 52,636 | 86,835 | 11.5 | 113.0 |
| to_json | 1 | 46,725 | 75,906 | 13.2 | 125.0 |
| valid? | 1 | 5,626,340 | 11,910,952 | 0.1 | 2.0 |
| attribute assignment: 1 setter (integer) | 1 | 1,046,351 | 2,822,366 | 0.4 | 2.0 |
| attribute assignment: 1 setter (time w/ zone) | 1 | 340,952 | 535,460 | 1.9 | 24.0 |
| attribute assignment: assign_attributes x4 | 1 | 147,237 | 340,259 | 2.9 | 31.0 |
| with(total:) | 1 | 436,744 | 901,682 | 1.1 | 13.0 |
| class declaration (Order + LineItem) | 1 | 10,398 | 13,267 | 75.4 | 745.0 |

### field_struct-avro

| workload | items/call | ips YJIT off | ips YJIT on | us/item (on) | allocs/item |
|---|---:|---:|---:|---:|---:|
| schema (cached) | 1 | 39,237 | 78,601 | 12.7 | 272.0 |
| schema (cold: cache cleared) | 1 | 6,314 | 12,884 | 77.6 | 1,091 |
| to_datum | 1 | 23,169 | 38,969 | 25.7 | 374.0 |
| from_datum | 1 | 9,001 | 17,837 | 56.1 | 524.0 |
| encode, 1 order | 1 | 8,678 | 17,670 | 56.6 | 671.0 |
| decode, 1 order | 1 | 6,034 | 13,369 | 74.8 | 622.0 |
| encode, 1000 orders | 1000 | 8.4 | 17.5 | 57.2 | 670.9 |
| decode, 1000 orders | 1000 | 6.0 | 13.4 | 74.7 | 622.0 |

### field_struct-json_schema

| workload | items/call | ips YJIT off | ips YJIT on | us/item (on) | allocs/item |
|---|---:|---:|---:|---:|---:|
| generate (cached, deep copy returned) | 1 | 36,937 | 75,267 | 13.3 | 285.0 |
| generate (cold: cache cleared each call) | 1 | 7,915 | 17,232 | 58.0 | 1,006 |

### field_struct-protobuf

| workload | items/call | ips YJIT off | ips YJIT on | us/item (on) | allocs/item |
|---|---:|---:|---:|---:|---:|
| to_message, 1 order | 1 | 27,903 | 55,311 | 18.1 | 184.0 |
| from_message, 1 order | 1 | 9,447 | 20,403 | 49.0 | 420.1 |
| encode, 1 order | 1 | 28,834 | 53,601 | 18.7 | 185.0 |
| decode, 1 order | 1 | 9,279 | 18,959 | 52.7 | 439.0 |
| to_message, 1000 orders | 1000 | 28.9 | 54.0 | 18.5 | 184.0 |
| from_message, 1000 orders | 1000 | 9.5 | 19.3 | 51.7 | 424.7 |
| encode, 1000 orders | 1000 | 27.4 | 52.4 | 19.1 | 185.0 |
| decode, 1000 orders | 1000 | 9.1 | 18.9 | 52.9 | 439.0 |
| reference: raw message encode (google-protobuf only) | 1 | 3,426,080 | 3,617,536 | 0.3 | 1.0 |
| reference: raw message decode (google-protobuf only) | 1 | 1,186,207 | 1,373,025 | 0.7 | 3.0 |

## Hotspot listing (cpu, YJIT on)

### actionable: nested action step, measure all (8866 samples excl. GC; GC = 8.3% of wall)

| self % | total % | frame | defined at | hottest line |
|---:|---:|---|---|---:|
| 13.6 | 13.6 | `FieldStruct::Field#ivar_name` | gems/field_struct/lib/field_struct/field.rb:84 | 85 |
| 8.1 | 8.1 | `FieldStruct::Field#setter_name` | gems/field_struct/lib/field_struct/field.rb:79 | 80 |
| 6.1 | 6.4 | `Enumerable#filter_map` | <cfunc>: |  |
| 5.2 | 5.3 | `Enumerable#all?` | <cfunc>: |  |
| 4.6 | 12.5 | `Enumerable#flat_map` | <cfunc>: |  |
| 4.5 | 4.5 | `Set#to_a` | <cfunc>: |  |
| 4.1 | 4.1 | `Hash#keys` | <cfunc>: |  |
| 3.6 | 21.8 | `FieldStruct::Base#fs_write` | gems/field_struct/lib/field_struct/base.rb:353 | 358 |
| 3.1 | 47.2 | `FieldStruct::Base#initialize` | gems/field_struct/lib/field_struct/base.rb:137 | 139 |
| 2.9 | 5.3 | `Actionable::Runner#captured_fields` | gems/actionable/lib/actionable/runner.rb:170 | 173 |

### actionable-otel: nested action run (7603 samples excl. GC; GC = 9.7% of wall)

| self % | total % | frame | defined at | hottest line |
|---:|---:|---|---|---:|
| 7.5 | 7.5 | `Actionable::Otel.step_attributes` | adapters/actionable-otel/lib/actionable/otel.rb:109 | 111 |
| 4.9 | 4.9 | `FieldStruct::Field#ivar_name` | gems/field_struct/lib/field_struct/field.rb:84 | 85 |
| 4.3 | 10.0 | `Enumerable#flat_map` | <cfunc>: |  |
| 4.3 | 4.5 | `Enumerable#filter_map` | <cfunc>: |  |
| 4.2 | 4.2 | `Set#to_a` | <cfunc>: |  |
| 4.0 | 4.0 | `FieldStruct::Field#setter_name` | gems/field_struct/lib/field_struct/field.rb:79 | 80 |
| 3.9 | 3.9 | `Enumerable#all?` | <cfunc>: |  |
| 3.1 | 3.3 | `Kernel#dup` | <cfunc>: |  |
| 3.0 | 3.0 | `Hash#keys` | <cfunc>: |  |
| 2.9 | 2.9 | `Hash#merge` | <cfunc>: |  |

### actionable: run success, measure all (history) (5343 samples excl. GC; GC = 9.4% of wall)

| self % | total % | frame | defined at | hottest line |
|---:|---:|---|---|---:|
| 11.1 | 26.2 | `FieldStruct::Base#fs_write` | gems/field_struct/lib/field_struct/base.rb:353 | 358 |
| 10.4 | 10.4 | `FieldStruct::Field#ivar_name` | gems/field_struct/lib/field_struct/field.rb:84 | 85 |
| 6.0 | 6.0 | `Hash#keys` | <cfunc>: |  |
| 5.9 | 5.9 | `FieldStruct::Field#setter_name` | gems/field_struct/lib/field_struct/field.rb:79 | 80 |
| 4.9 | 4.9 | `Kernel#BigDecimal` | <cfunc>: |  |
| 4.1 | 4.6 | `Enumerable#filter_map` | <cfunc>: |  |
| 3.5 | 3.5 | `BigDecimal#round` | <cfunc>: |  |
| 3.0 | 32.5 | `Actionable::Action.typed_input_from` | gems/actionable/lib/actionable/action.rb:183 | 188 |
| 2.8 | 28.1 | `Kernel#public_send` | <cfunc>: |  |
| 2.8 | 2.8 | `Kernel#method` | <cfunc>: |  |

### actionable: run success, measure none (5595 samples excl. GC; GC = 9.5% of wall)

| self % | total % | frame | defined at | hottest line |
|---:|---:|---|---|---:|
| 15.4 | 15.4 | `FieldStruct::Field#ivar_name` | gems/field_struct/lib/field_struct/field.rb:84 | 85 |
| 7.2 | 7.2 | `FieldStruct::Field#setter_name` | gems/field_struct/lib/field_struct/field.rb:79 | 80 |
| 6.3 | 10.0 | `Actionable::Runner#captured_fields` | gems/actionable/lib/actionable/runner.rb:170 | 173 |
| 5.3 | 27.5 | `FieldStruct::Base#fs_write` | gems/field_struct/lib/field_struct/base.rb:353 | 358 |
| 5.1 | 5.6 | `Enumerable#filter_map` | <cfunc>: |  |
| 4.1 | 4.2 | `Enumerable#all?` | <cfunc>: |  |
| 3.4 | 3.4 | `Actionable::Steps::Method#required_methods` | gems/actionable/lib/actionable/steps/method.rb:11 | 11 |
| 3.2 | 9.4 | `Enumerable#flat_map` | <cfunc>: |  |
| 3.2 | 28.8 | `Kernel#public_send` | <cfunc>: |  |
| 3.1 | 3.1 | `Hash#keys` | <cfunc>: |  |

### actionable-tools: MCP round trip, JSON in/out (parse + handle + dump) (6143 samples excl. GC; GC = 10.4% of wall)

| self % | total % | frame | defined at | hottest line |
|---:|---:|---|---|---:|
| 7.0 | 7.0 | `Oj.load` | <cfunc>: |  |
| 5.4 | 5.4 | `Oj.dump` | <cfunc>: |  |
| 5.3 | 14.6 | `FieldStruct::Base#fs_write` | gems/field_struct/lib/field_struct/base.rb:353 | 358 |
| 4.4 | 4.4 | `FieldStruct::Field#setter_name` | gems/field_struct/lib/field_struct/field.rb:79 | 80 |
| 3.8 | 35.3 | `Hash#each` | <cfunc>: |  |
| 3.7 | 4.2 | `JSONSchemer::Output#result` | gems/json_schemer-2.5.0/lib/json_schemer/output.rb:15 | 16 |
| 3.5 | 3.5 | `FieldStruct::Errors#initialize` | gems/field_struct/lib/field_struct/errors.rb:6 | 7 |
| 3.2 | 56.4 | `MCP::Server#call_tool_with_args` | gems/mcp-1.9.0/lib/mcp/server.rb:2011 | 2019 |
| 3.2 | 14.9 | `JSONSchemer::Schema#validate_instance` | gems/json_schemer-2.5.0/lib/json_schemer/schema.rb:132 | 135 |
| 3.1 | 3.1 | `String#strip` | <cfunc>: |  |

### field_struct-avro: decode, 1000 orders (14870 samples excl. GC; GC = 11.8% of wall)

| self % | total % | frame | defined at | hottest line |
|---:|---:|---|---|---:|
| 16.6 | 16.6 | `FieldStruct::Field#ivar_name` | gems/field_struct/lib/field_struct/field.rb:84 | 85 |
| 11.7 | 11.7 | `Array#zip` | <cfunc>: |  |
| 9.3 | 21.9 | `FieldStruct::Avro::Trail#label` | adapters/field_struct-avro/lib/field_struct/avro/trail.rb:45 | 46 |
| 8.3 | 24.5 | `FieldStruct::Base#fs_write` | gems/field_struct/lib/field_struct/base.rb:353 | 358 |
| 6.6 | 12.6 | `Array#join` | <cfunc>: |  |
| 6.1 | 61.8 | `FieldStruct::Avro::DatumReader#property` | adapters/field_struct-avro/lib/field_struct/avro/datum_reader.rb:29 | 32 |
| 6.0 | 6.0 | `Symbol#to_s` | <internal:symbol>:10 | 12 |
| 4.5 | 4.5 | `StringIO#read` | <cfunc>: |  |
| 4.4 | 4.5 | `Enumerable#each_with_index` | <cfunc>: |  |
| 3.4 | 3.4 | `FieldStruct::Field#setter_name` | gems/field_struct/lib/field_struct/field.rb:79 | 80 |

### field_struct-avro: decode, 1 order (12033 samples excl. GC; GC = 11.8% of wall)

| self % | total % | frame | defined at | hottest line |
|---:|---:|---|---|---:|
| 12.3 | 12.3 | `Array#zip` | <cfunc>: |  |
| 10.2 | 10.2 | `FieldStruct::Field#ivar_name` | gems/field_struct/lib/field_struct/field.rb:84 | 85 |
| 9.0 | 18.0 | `Array#join` | <cfunc>: |  |
| 9.0 | 9.0 | `Symbol#to_s` | <internal:symbol>:10 | 12 |
| 7.6 | 66.7 | `FieldStruct::Avro::DatumReader#property` | adapters/field_struct-avro/lib/field_struct/avro/datum_reader.rb:29 | 32 |
| 6.6 | 24.6 | `FieldStruct::Avro::Trail#label` | adapters/field_struct-avro/lib/field_struct/avro/trail.rb:45 | 46 |
| 6.1 | 6.1 | `FieldStruct::Field#setter_name` | gems/field_struct/lib/field_struct/field.rb:79 | 80 |
| 4.4 | 4.4 | `FieldStruct::Avro::Options.read` | adapters/field_struct-avro/lib/field_struct/avro/options.rb:24 | 26 |
| 3.3 | 3.4 | `Enumerable#to_a` | <cfunc>: |  |
| 3.3 | 3.3 | `StringIO#read` | <cfunc>: |  |

### field_struct-avro: encode, 1 order (14796 samples excl. GC; GC = 12.7% of wall)

| self % | total % | frame | defined at | hottest line |
|---:|---:|---|---|---:|
| 11.0 | 11.0 | `Integer#chr` | <cfunc>: |  |
| 9.3 | 52.4 | `FieldStruct::Avro::DatumWriter#struct` | adapters/field_struct-avro/lib/field_struct/avro/datum_writer.rb:20 | 22 |
| 9.1 | 9.1 | `Array#zip` | <cfunc>: |  |
| 8.4 | 23.0 | `Avro::SchemaValidator.validate!` | gems/avro-1.12.2/lib/avro/schema_validator.rb:74 | 75 |
| 7.8 | 18.2 | `FieldStruct::Avro::Trail#label` | adapters/field_struct-avro/lib/field_struct/avro/trail.rb:45 | 46 |
| 6.3 | 10.4 | `Array#join` | <cfunc>: |  |
| 5.6 | 5.7 | `Avro::LogicalTypes::BytesDecimal#to_byte_array` | gems/avro-1.12.2/lib/avro/logical_types.rb:169 | 170 |
| 4.5 | 4.5 | `Array#pack` | <internal:pack>:7 | 8 |
| 4.4 | 41.6 | `FieldStruct::Avro::DatumWriter#property` | adapters/field_struct-avro/lib/field_struct/avro/datum_writer.rb:28 | 31 |
| 4.0 | 4.0 | `Symbol#to_s` | <internal:symbol>:10 | 12 |

### field_struct-avro: schema (cold: cache cleared) (14181 samples excl. GC; GC = 14.8% of wall)

| self % | total % | frame | defined at | hottest line |
|---:|---:|---|---|---:|
| 39.8 | 45.0 | `FieldStruct::Avro::Entry.deep_copy` | adapters/field_struct-avro/lib/field_struct/avro/entry.rb:37 | 41 |
| 6.8 | 6.8 | `JSON::Ext::Parser.parse` | <cfunc>: |  |
| 4.0 | 4.0 | `Symbol#to_s` | <internal:symbol>:10 | 12 |
| 4.0 | 9.9 | `FieldStruct::Avro::Trail#label` | adapters/field_struct-avro/lib/field_struct/avro/trail.rb:45 | 46 |
| 3.7 | 67.9 | `Array#map` | <internal:array>:237 | 246 |
| 3.4 | 16.2 | `Avro::Schema.real_parse` | gems/avro-1.12.2/lib/avro/schema.rb:49 | 112 |
| 3.1 | 6.0 | `Array#join` | <cfunc>: |  |
| 2.8 | 2.8 | `String#split` | <cfunc>: |  |
| 2.2 | 4.2 | `FieldStruct::Avro::ScalarTypes#call` | adapters/field_struct-avro/lib/field_struct/avro/scalar_types.rb:30 | 35 |
| 2.1 | 2.1 | `String#=~` | <cfunc>: |  |

### field_struct: class declaration (Order + LineItem) (15098 samples excl. GC; GC = 19.6% of wall)

| self % | total % | frame | defined at | hottest line |
|---:|---:|---|---|---:|
| 22.1 | 22.1 | `Module#define_method` | <cfunc>: |  |
| 12.6 | 12.6 | `String#split` | <cfunc>: |  |
| 9.1 | 9.1 | `Method#parameters` | <cfunc>: |  |
| 5.4 | 5.4 | `Array#[]` | <cfunc>: |  |
| 5.3 | 5.4 | `FieldStruct::Types::Base.instantiate` | gems/field_struct/lib/field_struct/types/base.rb:51 | 52 |
| 4.3 | 77.7 | `PerfModel.order` | benchmarks/perf/order_model.rb:29 | 30 |
| 3.8 | 3.8 | `Hash#merge` | <cfunc>: |  |
| 3.5 | 54.7 | `FieldStruct::FieldBuilder.call` | gems/field_struct/lib/field_struct/field_builder.rb:15 | 24 |
| 3.2 | 11.9 | `FieldStruct::FieldBuilder.resolve_type` | gems/field_struct/lib/field_struct/field_builder.rb:70 | 77 |
| 2.8 | 2.8 | `FieldStruct::Field#setter_name` | gems/field_struct/lib/field_struct/field.rb:79 | 80 |

### field_struct: from_json (12550 samples excl. GC; GC = 12.0% of wall)

| self % | total % | frame | defined at | hottest line |
|---:|---:|---|---|---:|
| 22.7 | 97.1 | `Hash#each` | <cfunc>: |  |
| 19.3 | 19.3 | `FieldStruct::Field#ivar_name` | gems/field_struct/lib/field_struct/field.rb:84 | 85 |
| 13.8 | 13.8 | `MatchData#captures` | <cfunc>: |  |
| 13.5 | 13.5 | `FieldStruct::Field#setter_name` | gems/field_struct/lib/field_struct/field.rb:79 | 80 |
| 5.4 | 29.4 | `Enumerable#each_with_object` | <cfunc>: |  |
| 2.6 | 2.6 | `String#strip` | <cfunc>: |  |
| 2.4 | 2.4 | `Array#first` | <internal:array>:129 | 137 |
| 2.0 | 63.7 | `FieldStruct::Base#fs_write` | gems/field_struct/lib/field_struct/base.rb:353 | 358 |
| 1.6 | 1.8 | `Enumerable#filter_map` | <cfunc>: |  |
| 1.5 | 1.5 | `Oj.load` | <cfunc>: |  |

### field_struct-json_schema: generate (cached, deep copy returned) (14884 samples excl. GC; GC = 18.6% of wall)

| self % | total % | frame | defined at | hottest line |
|---:|---:|---|---|---:|
| 76.7 | 86.0 | `FieldStruct::JSONSchema::Copy.deep` | adapters/field_struct-json_schema/lib/field_struct/json_schema/copy.rb:12 | 16 |
| 8.6 | 8.6 | `Array#zip` | <cfunc>: |  |
| 5.8 | 86.0 | `Hash#to_h` | <cfunc>: |  |
| 3.5 | 28.2 | `Array#map` | <internal:array>:237 | 246 |
| 2.1 | 2.5 | `Enumerable#to_a` | <cfunc>: |  |
| 0.9 | 12.8 | `Enumerable#all?` | <cfunc>: |  |
| 0.7 | 99.8 | `FieldStruct::JSONSchema::Cache#fetch` | adapters/field_struct-json_schema/lib/field_struct/json_schema/cache.rb:26 | 27 |
| 0.3 | 0.4 | `Hash#each_value` | <cfunc>: |  |
| 0.3 | 0.4 | `Array#all?` | <cfunc>: |  |
| 0.2 | 9.1 | `FieldStruct::JSONSchema::Stamp#same_fields?` | adapters/field_struct-json_schema/lib/field_struct/json_schema/stamp.rb:42 | 43 |

### field_struct-json_schema: generate (cold: cache cleared each call) (14127 samples excl. GC; GC = 15.5% of wall)

| self % | total % | frame | defined at | hottest line |
|---:|---:|---|---|---:|
| 27.2 | 32.9 | `FieldStruct::JSONSchema::Copy.deep` | adapters/field_struct-json_schema/lib/field_struct/json_schema/copy.rb:12 | 16 |
| 6.0 | 6.1 | `FieldStruct::JSONSchema::Builder::Spot#down` | adapters/field_struct-json_schema/lib/field_struct/json_schema/builder.rb:27 | 28 |
| 5.8 | 5.8 | `FieldStruct::JSONSchema::Pattern::CharClass#peek` | adapters/field_struct-json_schema/lib/field_struct/json_schema/pattern/char_class.rb:45 | 46 |
| 4.7 | 4.7 | `FieldStruct::JSONSchema::Pattern::Safety::Paths.variants_of` | adapters/field_struct-json_schema/lib/field_struct/json_schema/pattern/safety/paths.rb:40 | 42 |
| 4.2 | 14.0 | `Array#map` | <internal:array>:237 | 246 |
| 3.7 | 3.7 | `FieldStruct::JSONSchema::Pattern::CharClass#advance` | adapters/field_struct-json_schema/lib/field_struct/json_schema/pattern/char_class.rb:49 | 50 |
| 3.1 | 32.9 | `Hash#to_h` | <cfunc>: |  |
| 2.8 | 6.5 | `Enumerable#flat_map` | <cfunc>: |  |
| 2.5 | 2.6 | `FieldStruct::JSONSchema::Nullable.widen_type` | adapters/field_struct-json_schema/lib/field_struct/json_schema/nullable.rb:54 | 55 |
| 2.4 | 2.4 | `FieldStruct::JSONSchema::Pattern::Item#text` | adapters/field_struct-json_schema/lib/field_struct/json_schema/pattern/item.rb:58 | 59 |

### field_struct: new from symbol-key Hash (7932 samples excl. GC; GC = 11.8% of wall)

| self % | total % | frame | defined at | hottest line |
|---:|---:|---|---|---:|
| 24.2 | 24.2 | `FieldStruct::Field#ivar_name` | gems/field_struct/lib/field_struct/field.rb:84 | 85 |
| 10.1 | 10.1 | `FieldStruct::Field#setter_name` | gems/field_struct/lib/field_struct/field.rb:79 | 80 |
| 9.1 | 85.6 | `FieldStruct::Base#fs_write` | gems/field_struct/lib/field_struct/base.rb:353 | 358 |
| 5.0 | 5.0 | `Kernel#BigDecimal` | <cfunc>: |  |
| 4.3 | 4.8 | `Enumerable#filter_map` | <cfunc>: |  |
| 3.1 | 5.0 | `Date._parse` | <cfunc>: |  |
| 3.0 | 3.0 | `MatchData#captures` | <cfunc>: |  |
| 2.6 | 2.6 | `String#strip` | <cfunc>: |  |
| 2.1 | 99.6 | `FieldStruct::Base#initialize` | gems/field_struct/lib/field_struct/base.rb:137 | 139 |
| 1.9 | 2.0 | `Enumerable#all?` | <cfunc>: |  |

### field_struct-protobuf: decode, 1000 orders (13412 samples excl. GC; GC = 13.4% of wall)

| self % | total % | frame | defined at | hottest line |
|---:|---:|---|---|---:|
| 17.4 | 28.5 | `FieldStruct::Introspection.properties` | gems/field_struct/lib/field_struct/introspection.rb:125 | 129 |
| 9.8 | 9.8 | `Kernel#BigDecimal` | <cfunc>: |  |
| 8.7 | 8.7 | `FieldStruct::Field#ivar_name` | gems/field_struct/lib/field_struct/field.rb:84 | 85 |
| 7.4 | 9.0 | `FieldStruct::Introspection.node` | gems/field_struct/lib/field_struct/introspection.rb:138 | 143 |
| 6.8 | 7.8 | `Enumerable#map` | <cfunc>: |  |
| 4.7 | 4.7 | `Hash#merge` | <cfunc>: |  |
| 4.2 | 4.2 | `Enumerable#all?` | <cfunc>: |  |
| 3.8 | 3.8 | `FieldStruct::Field#setter_name` | gems/field_struct/lib/field_struct/field.rb:79 | 80 |
| 3.0 | 28.5 | `Enumerable#map` | <cfunc>: |  |
| 2.6 | 98.4 | `FieldStruct::Protobuf::Decoder#call` | adapters/field_struct-protobuf/lib/field_struct/protobuf/decoder.rb:15 | 17 |

### field_struct-protobuf: encode, 1 order (20984 samples excl. GC; GC = 15.3% of wall)

| self % | total % | frame | defined at | hottest line |
|---:|---:|---|---|---:|
| 27.0 | 54.6 | `FieldStruct::Introspection.properties` | gems/field_struct/lib/field_struct/introspection.rb:125 | 129 |
| 14.1 | 99.7 | `FieldStruct::Protobuf::Encoder#call` | adapters/field_struct-protobuf/lib/field_struct/protobuf/encoder.rb:14 | 21 |
| 13.5 | 57.7 | `Array#map` | <internal:array>:237 | 246 |
| 13.4 | 54.6 | `Enumerable#map` | <cfunc>: |  |
| 13.4 | 13.7 | `FieldStruct::Introspection.node` | gems/field_struct/lib/field_struct/introspection.rb:138 | 143 |
| 13.1 | 13.1 | `Date#iso8601` | <cfunc>: |  |
| 1.4 | 1.7 | `Google::Protobuf::AbstractMessage#initialize` | <cfunc>: |  |
| 0.6 | 1.0 | `Kernel#public_send` | <cfunc>: |  |
| 0.5 | 0.8 | `FieldStruct::Protobuf::Registry.register` | adapters/field_struct-protobuf/lib/field_struct/protobuf/registry.rb:28 | 34 |
| 0.2 | 41.4 | `Hash#each_value` | <cfunc>: |  |

### field_struct: to_json (13985 samples excl. GC; GC = 9.8% of wall)

| self % | total % | frame | defined at | hottest line |
|---:|---:|---|---|---:|
| 71.9 | 91.9 | `FieldStruct::JsonCodec.convert` | gems/field_struct/lib/field_struct/json_codec.rb:48 | 50 |
| 11.0 | 11.0 | `BigDecimal#to_s` | <cfunc>: |  |
| 2.7 | 4.4 | `Oj.dump` | <cfunc>: |  |
| 2.4 | 3.5 | `FieldStruct::Types::Rfc3339Format#render` | gems/field_struct/lib/field_struct/types/rfc3339_format.rb:40 | 44 |
| 1.9 | 95.4 | `Enumerable#to_h` | <cfunc>: |  |
| 1.7 | 1.7 | `Float#to_s` | <cfunc>: |  |
| 1.3 | 55.6 | `Array#map` | <internal:array>:237 | 246 |
| 1.1 | 2.2 | `Kernel#public_send` | <cfunc>: |  |
| 1.1 | 1.1 | `Kernel#format` | <cfunc>: |  |
| 1.0 | 95.4 | `FieldStruct::JsonCodec.as_json` | gems/field_struct/lib/field_struct/json_codec.rb:13 | 17 |


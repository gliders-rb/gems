# Performance baseline

Measurement only: no library code was changed. This is the starting line for performance work on the field_struct and
actionable-rb gems and their adapters. Scripts: `benchmarks/perf/` (shared harness, driver) and `<gem>/benchmarks/perf.rb`
(one per gem). Raw results: `benchmarks/perf/results/`.

## Machine and method

| | |
|---|---|
| Machine | Apple M4 (10 cores), 32 GB, macOS 26.6.2, arm64. Other work on the machine was idle during the runs. |
| Ruby | 4.0.7 (2026-09-15 revision 229531a6cf) +PRISM, YJIT toggled with `--yjit` / `--disable-yjit` |
| Gems | benchmark-ips 2.15.1, stackprof 0.2.28, oj 3.17.8, bigdecimal 4.1.3, avro 1.12.2, google-protobuf 4.36.2, opentelemetry-sdk 1.13.1, mcp 1.9.0, json_schemer 2.5.0 |
| Code | commit 1122394 plus the benchmark files in this change |
| Throughput | benchmark-ips, 2 s warmup, 5 s run, one process per gem per YJIT setting |
| Allocations | objects allocated per call, from `GC.stat(:total_allocated_objects)` over 200 calls (fewer for 1000-item batches) with GC disabled. memory_profiler is in the `bench` Gemfile group but was not needed: the question was object counts, and `GC.stat` is exact for that. |
| Profiles | StackProf, cpu and wall modes, YJIT on, for the 5 slowest-per-op workloads plus the slowest steady-state workload of each gem and the common paths (`pick_top.rb` chooses) |

The workload is a neutral Order with 15 fields (strings, integers, decimals, a boolean, a date, a time with an IANA zone,
a uuid, an email, a symbol enum, an optional string enum, a float, an array of strings, an array of 5 nested LineItem
structs, and a union), `serialize :json` renames on 4 fields and on LineItem. It is defined once in
`benchmarks/perf/order_model.rb`. The input document is realistic wire-format: numbers and booleans arrive as strings, as
they do from a form or JSON API, so every field goes through coercion.

Things to know before reading the numbers:

- **Protobuf has no union.** `field_struct-protobuf` raises on a union field, so its Order is the same minus `reference`,
  with `proto: {number:}` on every field. Avro runs the full 15-field Order, union included.
- **otel untraced vs traced are different processes.** Requiring `actionable/otel` patches `Action.run` for good, so the
  untraced half runs in a child process (`PERF_OTEL=off`, results in `actionable-otel-untraced-*.json`). Traced runs use the
  SDK with a `SimpleSpanProcessor` and an in-memory exporter, drained every 500 runs so the heap does not grow.
- **"1000 orders" rows** run one call over 1000 distinct orders; `us/item` divides by 1000. They match the single-order
  rows within 1-2%: nothing amortises across a batch in any adapter.
- **A "reference" row** in protobuf is the google-protobuf C extension alone on a prebuilt message, to separate native cost
  from gem cost.
- `valid?` is 0.1 us because validity is computed on assignment; `valid?` re-runs only cross-field validators.
- Headline: **YJIT roughly doubles everything that is Ruby** (1.6x to 2.2x on these workloads; 1.06x on the native
  google-protobuf calls), so the "off" column matters for anyone running without it. Allocation counts are identical with
  YJIT on and off.

## Results by gem

Every number is from one run of `benchmarks/perf/run_all.sh` on the machine above. ips is benchmark-ips central tendency (2 s warmup, 5 s run); `us/item` is time per logical operation (1000-order workloads are divided by 1000); `allocs/item` is `GC.stat(:total_allocated_objects)` per logical operation. Run-to-run noise was 1-5% (the `+-` column in `results/*.json`).

#### actionable

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

#### actionable-otel

| workload | items/call | ips YJIT off | ips YJIT on | us/item (on) | allocs/item |
|---|---:|---:|---:|---:|---:|
| 5-step run, success | 1 | 14,463 | 41,515 | 24.1 | 216.0 |
| 5-step run, declared failure | 1 | 18,354 | 48,925 | 20.4 | 158.0 |
| nested action run | 1 | 10,674 | 28,547 | 35.0 | 258.0 |
| 5-step run, success, run span only (step_spans=false) | 1 | 24,373 | 64,104 | 15.6 | 141.0 |

#### actionable-otel-untraced

| workload | items/call | ips YJIT off | ips YJIT on | us/item (on) | allocs/item |
|---|---:|---:|---:|---:|---:|
| 5-step run, success | 1 | 37,010 | 82,830 | 12.1 | 124.0 |
| 5-step run, declared failure | 1 | 34,474 | 74,841 | 13.4 | 123.0 |
| nested action run | 1 | 22,161 | 45,463 | 22.0 | 181.0 |

#### actionable-tools

| workload | items/call | ips YJIT off | ips YJIT on | us/item (on) | allocs/item |
|---|---:|---:|---:|---:|---:|
| Definition build (cold: schema + envelope) | 1 | 43,546 | 73,892 | 13.5 | 218.0 |
| call, success | 1 | 27,967 | 59,192 | 16.9 | 158.0 |
| call, declared failure | 1 | 25,579 | 53,785 | 18.6 | 162.0 |
| call, invalid input | 1 | 38,504 | 74,397 | 13.4 | 115.0 |
| MCP round trip: server.handle(tools/call) | 1 | 13,273 | 31,206 | 32.0 | 279.0 |
| MCP round trip, JSON in/out (parse + handle + dump) | 1 | 13,061 | 30,054 | 33.3 | 294.0 |

#### field_struct

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

#### field_struct-avro

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

#### field_struct-json_schema

| workload | items/call | ips YJIT off | ips YJIT on | us/item (on) | allocs/item |
|---|---:|---:|---:|---:|---:|
| generate (cached, deep copy returned) | 1 | 36,937 | 75,267 | 13.3 | 285.0 |
| generate (cold: cache cleared each call) | 1 | 7,915 | 17,232 | 58.0 | 1,006 |

#### field_struct-protobuf

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


## Comparisons worth reading side by side

### YJIT effect (ips on / ips off)

| workload | off | on | speedup |
|---|---:|---:|---:|
| field_struct `new` (symbol keys) | 14,439 | 27,197 | 1.88x |
| field_struct `from_json` | 11,518 | 21,693 | 1.88x |
| field_struct `to_json` | 46,725 | 75,906 | 1.62x |
| actionable 5-step run | 30,714 | 64,786 | 2.11x |
| avro encode / decode | 8,678 / 6,034 | 17,670 / 13,369 | 2.04x / 2.22x |
| protobuf encode / decode | 28,834 / 9,279 | 53,601 / 18,959 | 1.86x / 2.04x |
| protobuf raw C-ext encode (reference) | 3,426,080 | 3,617,536 | 1.06x |

### Tracing overhead (actionable-otel, YJIT on, 5-step typed action)

| workload | untraced | traced | overhead |
|---|---:|---:|---:|
| success, run + 5 step spans | 82,830 ips, 12.1 us, 124 allocs | 41,515 ips, 24.1 us, 216 allocs | +12.0 us, 2.00x slower, +92 allocs |
| success, run span only (`step_spans = false`) | 82,830 ips | 64,104 ips, 15.6 us, 141 allocs | +3.5 us (+29%), +17 allocs |
| declared failure | 74,841 ips, 13.4 us | 48,925 ips, 20.4 us | +7.0 us, 1.53x slower |
| nested action | 45,463 ips, 22.0 us | 28,547 ips, 35.0 us | +13.0 us, 1.59x slower |

About 2 us and 15 allocations per span (run span +3.5 us; each of the 5 step spans about 1.7 us). The in-memory exporter
with a synchronous processor is the worst case for the SDK; a `BatchSpanProcessor` moves export off the request path. An
unsampled (no-op) span path was not measured.

### Adapter cost vs the native library underneath (YJIT on)

| | gem | native alone | ratio |
|---|---:|---:|---:|
| protobuf `to_message` / `encode` (1 order) | 18.1 / 18.7 us | 0.29 us (`Message.encode`) | 62x |
| protobuf `from_message` / `decode` | 49.0 / 52.7 us | 0.74 us (`Message.decode`) | 71x |

The wire work is already native C; the gap is all Ruby around it.

### Ruby headroom, measured (`gems/field_struct/benchmarks/headroom.rb`)

A monkeypatch (in the script only; no library file changed) makes `Field#ivar_name` and `#setter_name` return cached
Symbols instead of interpolating a new one on every call:

| | baseline | cached Symbols | gain |
|---|---:|---:|---:|
| `Order.new`, YJIT on | 35.9 us, 294 allocs | 28.9 us, 189 allocs | 1.2x (two runs: 1.24x, 1.20x), -105 allocs (-36%) |
| `Order.new`, YJIT off | 66.7 us | 59.3 us | 1.12x |

This is the single largest item in every profile below, and it is a two-line change.

## Hotspots

CPU profile (StackProf, 200 us interval, 8 s per workload, YJIT on, GC samples excluded; GC is reported separately as a percent of wall time). Frames are the top 10 by self time; `defined at` is the file:line where the method is defined and `hottest line` is the line inside it with the most self samples. A `<cfunc>` frame is a C method (`Hash#each`, `Kernel#BigDecimal`, ...) so it has no Ruby file:line; the caller is named in the hypothesis. Wall-mode profiles (`results/profiles/*-wall.json`) were taken too: no workload does I/O or waits, so they list the same frames with flatter shares and are not repeated here. Raw dumps: `results/profiles/*.dump` (git-ignored; `run_all.sh` regenerates them).

Why GC is excluded: with GC samples included, StackProf attributed 50-70% of every profile to `(sweeping)`, because lazy sweeping keeps the VM in the sweep phase while Ruby code runs. Measured GC time with `GC.stat(:time)` is 8-20% of wall time in these workloads, so the raw profile was not usable.

#### field_struct: new from symbol-key Hash (7932 samples excl. GC; GC = 11.8% of wall)

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

**Hypothesis: per-call Symbol construction and per-call allocations.** `Field#ivar_name` / `#setter_name` (`field.rb:79,84`) build a new Symbol by string interpolation on every call; `fs_apply_defaults` and `fs_write` call them for every field, so 105 of the 294 allocations per `new` come from them (measured, see "Ruby headroom" below: caching those two Symbols alone gives 1.2x with YJIT, 1.12x without; the profile's 34% self share overstates the gain, which is why it is measured and not read off the profile). Next: `fs_write` (`base.rb:353`) splats `**field.options` on every coerce and keeps a `rescue` frame; `fs_apply_defaults` (`base.rb:330`) builds a `given` array with `filter_map` and does `given.include?` per field (O(n^2) on 15 fields); `String#strip` in `Types::String#missing?` (`types/string.rb:31`) allocates a stripped copy just to test blankness; `Kernel#BigDecimal` + `#round` (`types/big_decimal.rb:51`) are genuine leaf work.

#### field_struct: from_json (12550 samples excl. GC; GC = 12.0% of wall)

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

**Hypothesis: same field-pipeline overhead as `new`, plus regex captures.** `ivar_name`/`setter_name` again (33% self together). `MatchData#captures` (14%) is `Rfc3339Format#timestamp_components` (`types/rfc3339_format.rb:54`: `match.captures.first(6).map(&:to_i)` allocates three arrays per timestamp). `Oj.load` itself is under 2%, so parsing is not the cost; building the struct is (46 us of 46 us).

#### field_struct: to_json (13985 samples excl. GC; GC = 9.8% of wall)

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

**Hypothesis (not isolated by an experiment): Ruby dispatch inside the JSON walk.** `JsonCodec.convert` (`json_codec.rb:48`) is 72% self. It does `case value when *PLAIN` (a splatted array of 6 classes tested with `===` in order, for every value) and `renderer_for` (`json_codec.rb:38`) allocates an array and may call `of_type.new` per field per call. `BigDecimal#to_s('F')` (11%) is real leaf work. `Oj.dump` is 2.7%: the serializer is not the problem, the `as_json` walk before it is.

#### field_struct: class declaration (Order + LineItem) (15098 samples excl. GC; GC = 19.6% of wall)

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

**Hypothesis: declaration-time reflection, paid once per class.** `define_method` x2 per field (`base.rb:118`, 22%), `String#split` in `namespace_registry` (`base.rb:79`, name split on every field declaration, 13% + `Array#[]` 6%), and `Method#parameters` in `OptionChecker.resolve` (`option_checker.rb:73`, 8.5%). About 4 us per field, 75 us for the two classes (19 fields). Irrelevant at steady state; it matters only for code that builds classes dynamically (per request or per tenant) or boot time of an app with thousands of structs.

#### actionable: run success, measure none (5595 samples excl. GC; GC = 9.5% of wall)

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

**Hypothesis: Actionable's own cost is small; it is two FieldStruct constructions plus a per-run re-check.** 26% of the run is `typed_input_from` (the input `new`, `action.rb:183`), 33% is `refresh_output` (the output `new`, `runner.rb:119`), and 15% (`check_implemented!`, `action.rb:212`) re-verifies on every `run` that each step method exists (`flat_map` over step sets, then `instance.method(name).owner` per step, `action.rb:232`), although the answer cannot change after the first run of a class. `captured_fields` (`runner.rb:170`) builds an `"@#{name}"` String per declared output field, twice (defined? and get).

#### actionable: run success, measure all (history) (5343 samples excl. GC; GC = 9.4% of wall)

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

**Hypothesis: history costs about 3 us and 23 allocations per 5-step run (+19% time), on top of the same field_struct costs.** Per step: a `History::Step` struct, `Time.now`, two `clock_gettime` calls, and `Measurement.with_open` (`runner.rb:84-103`). Everything else in this profile is the same as the unmeasured run.

#### actionable: nested action step, measure all (8866 samples excl. GC; GC = 8.3% of wall)

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

**Hypothesis: a nested action step is a full second `run`**: its own input `new`, output `new`, `check_implemented!` and result objects. The frames are the same field_struct frames (`ivar_name` 14%, `setter_name` 7.5%); `Hash#keys` / `Enumerable#all?` / `flat_map` are `fs_apply_defaults`, `Errors#empty?` and `check_implemented!`.

#### actionable-otel: nested action run (7603 samples excl. GC; GC = 9.7% of wall)

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

**Hypothesis: tracing cost is the OpenTelemetry SDK's span objects (third party) plus one attribute Hash per step from our wrapper.** `Otel.step_attributes` (`otel.rb:109`, 4.6% self) builds a 4-key Hash with `to_s` conversions for every step on every run, though it is constant per (class, step, section). SDK frames: `Span#initialize`, `TracerProvider#internal_start_span`, `Span#to_span_data` (SimpleSpanProcessor exports synchronously in this setup). The rest is the same field_struct frames as the untraced run.

#### actionable-tools: MCP round trip, JSON in/out (parse + handle + dump) (6143 samples excl. GC; GC = 10.4% of wall)

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

**Hypothesis: JSON Schema validation by json_schemer (third party, 18% total) plus the same input/output constructions.** `JSONSchemer::Schema#validate_instance` / `Output#result` / `Location.join` re-validate the arguments against the input schema on every call (the MCP SDK does this before the action runs, then the action validates the same arguments again with FieldStruct). `Runner#captured_fields` (`runner.rb:170`) is 11.7% self here: the `"@#{name}"` Strings again. `Oj.load`/`Oj.dump` are 3.2% together.

#### field_struct-avro: encode, 1 order (14796 samples excl. GC; GC = 12.7% of wall)

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

**Hypothesis: three layers, roughly a third each.** (1) The `avro` gem's pure-Ruby writer: `SchemaValidator.validate!` (8% self, 23% total) re-walks the datum before writing, and `BinaryEncoder#write_long` calls `Integer#chr` per byte (11%). (2) Adapter bookkeeping on the hot path: `Trail#label` (`trail.rb:45`, 18% total) builds a `"Klass#a.b"` String with `Array#join` and `Symbol#to_s` for every field even though it is only needed for error messages; `Stamp#same_fields?` (`stamp.rb:37`, 9%) does `current.zip(@fields).all?` on every call to check cache freshness. (3) `DatumWriter#struct` (`datum_writer.rb:20`).

#### field_struct-avro: decode, 1 order (12033 samples excl. GC; GC = 11.8% of wall)

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

**Hypothesis: the same eager `Trail#label` (31% total: `trail.rb:45`, `Array#join`, `Symbol#to_s`), then a normal `klass.new` of 15 fields.** `Options.read(field, trail.label(field))` runs in `DatumReader#property` (`datum_reader.rb:29`) for each field. The `avro` gem's reader is a small share here; `setter_name` (10%) and `fs_write` come from rebuilding the struct.

#### field_struct-avro: decode, 1000 orders (14870 samples excl. GC; GC = 11.8% of wall)

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

**Hypothesis: `Stamp#same_fields?` is 16% (`Array#zip`, `stamp.rb:37`) when the loop is hot, because the freshness check runs per struct (an order is 6 structs: the order and 5 line items; this is the likely reason, not isolated).** Also the avro gem's decimal reader, `BytesDecimal#from_byte_array` (`logical_types.rb:146`: `String#bytes`, `each_with_index`, `BigDecimal#coerce` are 32% self together; 6 decimal fields per order) and `Errors#initialize` (8%: one `Errors` + Hash per struct, 6 structs per order). Per-order cost is identical to the single-order run (74.7 vs 74.8 us): nothing amortises across a batch.

#### field_struct-avro: schema (cold: cache cleared) (14181 samples excl. GC; GC = 14.8% of wall)

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

**Hypothesis: defensive deep copies.** `Entry.deep_copy` (`entry.rb:37`) is 38% self: every Hash, Array and String of the schema is copied (38% self, 47% total), and the JSON text is parsed back into an `Avro::Schema` (`JSON::Ext::Parser.parse` 8.5% + `Avro::Schema.real_parse` ~10%). Cold-path only; it runs once per class per process (or after a class change).

#### field_struct-json_schema: generate (cached, deep copy returned) (14884 samples excl. GC; GC = 18.6% of wall)

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

**Hypothesis: the "cached" path is not free because it returns a fresh deep copy by contract.** `Copy.deep` (`copy.rb:12`) is 77% self and 86% total: it rebuilds ~285 Hashes, Arrays and Strings per call (13 us). `Stamp#same_fields?` (zip + all?, 9%) is the freshness check, again per call.

#### field_struct-json_schema: generate (cold: cache cleared each call) (14127 samples excl. GC; GC = 15.5% of wall)

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

**Hypothesis: the same deep copy, done twice (once frozen into the cache, once on return) on top of the real build.** `Copy.deep` is 50% self; `Builder::Spot#down` (`builder.rb:27`) and `Introspection.properties` (`introspection.rb:125`) are the build proper (about 20%).

#### field_struct-protobuf: encode, 1 order (20984 samples excl. GC; GC = 15.3% of wall)

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

**Hypothesis: the adapter re-derives the field list on every call, and the wire work is already native.** `Introspection.properties` (`introspection.rb:125`) allocates a `Property` plus a node tree per field per call and is 55% of the encode (`Encoder#call`, `encoder.rb:17`); `Date#iso8601` (13%, `encoder.rb:40`) is the date field to string. The google-protobuf C extension itself costs 0.29 us for the same message (reference row in the table): the gem's overhead is 60x the native work. Avro caches this list (`Avro::Cache.properties`); protobuf does not.

#### field_struct-protobuf: decode, 1000 orders (13412 samples excl. GC; GC = 13.4% of wall)

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

**Hypothesis: same uncached `Introspection.properties` (28% total, `decoder.rb:18`, called for the order and each of 5 nested line items), then `klass.new` (48% field_struct frames).** Raw `Message.decode` is 0.74 us of the 52.9 us.


## Native candidates

Question: which hotspots are CPU-bound kernels where a Rust extension (magnus / rb-sys) could plausibly give **2x or more
end to end**, and which are Ruby-overhead problems better fixed in Ruby?

The method: take the profile share of the thing a Rust kernel would replace, and apply Amdahl: a kernel that is
infinitely fast on share `s` gives at most `1 / (1 - s)` end to end. Then subtract what a native call cannot avoid: each
call across the boundary still allocates the same Ruby objects (BigDecimal, Time, Date, String, Hash) that the Ruby code
allocates today, and those allocations are what 8-20% of wall time in GC is spent on.

### Verdict by hotspot

| Hotspot | Share of its workload | CPU-bound kernel? | Rust >= 2x end to end? | Better fix |
|---|---|---|---|---|
| `Field#ivar_name` / `#setter_name` Symbol building (`field.rb:79,84`) | 34% of `new` sampled; 1.2x measured | no, allocation | no | **Ruby**: precompute in `Field#initialize`. Flows into every actionable run, tool call and adapter decode (10-24% self in all of them). |
| field_struct `new` leaf kernels: `Kernel#BigDecimal`, `BigDecimal#round`, `Date._parse`, `MatchData#captures`, `String#strip` | about 18% combined (sampled) | yes | **no**: Amdahl cap 1.2x even at zero cost | Ruby: cache a compiled Regexp/format, avoid `strip` copy, `captures` once. |
| Whole `Base#initialize` pipeline (coerce + validate + errors for every field, in one Rust call per struct) | 97% of `new` is field_struct code plus C methods | it is the engine, not a kernel | **plausibly 2-4x** (estimate, no prototype built) | Ruby fixes first (symbols, `**options` splat, `given.include?`; expect 1.3-1.6x), re-measure, then decide. A Rust engine must re-implement every type, policy, nested/union rule and error string; semantic drift is the main risk. |
| `from_json` (Oj parse + canonical rename + `new`) | `Oj.load` is 1.5%; the rest is the `new` pipeline | no | only as part of the engine row above | Ruby |
| `to_json` / `as_json` walk (`json_codec.rb:48`) | 72% self of `to_json` | a tree walk, but its output is Ruby Hash/Strings | possible only if the walk is native end to end; **unmeasured** | Ruby: replace `case ... when *PLAIN`, hoist `renderer_for` per class. Try this first; it is likely 1.5-2x alone (hypothesis). |
| Avro binary writer (`Avro::SchemaValidator.validate!`, `BinaryEncoder#write_long` `Integer#chr`) | 23% + 11% = ~34% of encode | **yes**: validation walk, zigzag varint, decimal bytes | **maybe**: ceiling 1.5x alone; ~2x only together with the Ruby fixes below | Ruby: lazy `Trail#label` (18%), cheaper `Stamp#fresh?` (9%) are another 27% for no native code (1.37x). Both together: ceiling 2.6x, realistic ~2x. |
| Avro decode | avro gem decimal reader (`String#bytes`, `each_with_index`, `BigDecimal#coerce`) is ~32% of the 1000-order profile, ceiling 1.4x; adapter + `new` are the rest | partly | **no** (ceiling 1.4x) | Ruby (`Trail#label` 31% of single decode, `Stamp` zip 16% in the hot loop, then `new`) |
| Protobuf encode / decode wire work | 0.29 / 0.74 us of 18.7 / 52.7 us | already native C | **no** (nothing left to replace) | Ruby: cache `Introspection.properties` per class (55% of encode, 28% of decode; Avro already does), `Date#iso8601` (13%). Ceiling 2.2x on encode from the cache alone. |
| json_schema cached `generate` (`Copy.deep`) | 86% of the call | no, allocation-bound | **no**: Rust would build the same ~285 Ruby objects | Ruby: share a frozen schema (API change from "fresh copy"), or copy on write. Ceiling 7x. |
| json_schema / avro cold builds | one-off per class | no | irrelevant | Ruby, low priority |
| Class declaration (`define_method`, `split`, `Method#parameters`) | one-off, 75 us per Order | no | no | Ruby: memoize `namespace_registry` split and `OptionChecker` arity. Matters only for dynamic class creation. |
| actionable run overhead: `check_implemented!` per run (`action.rb:212`), `captured_fields` Strings (`runner.rb:170`) | 15% and about 6-11% | no | no | Ruby: check once per class (1.18x on a flat run), precompute ivar names. |
| otel span creation | SDK third party; our `step_attributes` is 4.6% | no | no | Ruby: cache attribute Hashes per (class, step, section); document `step_spans = false` (1.5x faster than full tracing). |
| tools / MCP: json_schemer validation | 18% total | yes, a validator | out of scope: third-party gem, and Rust would be a different library, not an optimisation of ours | Validate once, not in the SDK and again in the action. |

### Bottom line

1. **No profiled hotspot is a pure CPU kernel with enough share to carry a 2x end-to-end win.** The leaf kernels
   (BigDecimal parse, RFC 3339 parse, regex, varint) are 10-20% of any workload, so replacing every one with free native
   code caps out at 1.1-1.25x. The time is in Ruby orchestration: Symbol construction, per-call arrays and hashes,
   defensive copies, work repeated on every call that could be done once per class. That is 100-300 object allocations per
   operation, and about 10-15% of wall time in GC on top.
2. **Fix in Ruby first. The measured and bounded Ruby wins are larger than any kernel win:** Symbols (1.2x on `new`, measured),
   uncached `Introspection.properties` in protobuf (ceiling 2.2x encode), `check_implemented!` per run (1.18x on a run),
   eager `Trail#label` and `Stamp` in avro (1.37x), `Copy.deep` in json_schema (ceiling 7x if the contract allows sharing).
   Every field_struct improvement also flows into actionable (input and output structs are 59% of a run), the adapters'
   decode paths and tools.
3. **Two places where a Rust extension has a real chance at >= 2x, both conditional:**
   (a) the Avro binary encode path (validator + varint/zigzag + decimal bytes), as a single `datum -> bytes` call, together with the Ruby fixes above; and
   (b) a native coercion engine behind `Base#initialize` (hash in, attribute values and error list out, one crossing per struct), which is a re-implementation of the type system rather than a kernel. I would only consider (b) after the Ruby fixes land and a re-measurement shows `new` still above roughly 15 us, because it multiplies the surface the specs must cover.
4. **Do not use Rust for:** protobuf (the C extension already does the wire work in under 1 us), json_schema (allocation-bound copy), otel and tools (third-party libraries dominate), anything at declaration time.

Confidence: the profile shares, ips and allocation counts are measured. The Ruby ceilings are Amdahl bounds from those
shares, not experiments, except the Symbol caching, which was run. The Rust figures are estimates: no extension was
prototyped, and the "2-4x" for the engine is a guess from the allocation count and the share of C-method time, not a
measurement.

## Reproduce

```sh
benchmarks/perf/run_all.sh                       # about 25 minutes: both YJIT modes, all 7 gems, then profiles
PERF_TIME=1 PERF_WARMUP=0.5 PERF_PROFILE_SECONDS=2 PERF_OUT=/tmp/perf benchmarks/perf/run_all.sh   # smoke run
cd gems/field_struct && bundle exec ruby --yjit benchmarks/perf.rb        # one gem, one mode
PERF_ONLY='^from_json$' PERF_PROFILE=cpu bundle exec ruby --yjit benchmarks/perf.rb   # profile one workload
PERF_LIST=1 bundle exec ruby benchmarks/perf.rb                           # list a gem's workloads
```

Each gem's `Gemfile` gained a `group :bench` (benchmark-ips, memory_profiler, stackprof). `results/*.json` hold the numbers
behind every table; `results/tables.md` is the generated table dump; `results/profiles/*.json` hold the top-10 frames per
profile, in cpu and wall mode.

Follow-ups, not done here: a before/after harness that diffs two `results/` directories; an unsampled-span otel row; a
`BatchSpanProcessor` otel row; memory (retained size) rather than allocation counts.

## After field_struct pass

Same machine, Ruby and harness as above (`gems/field_struct/benchmarks/perf.rb`, 2 s warmup, 5 s run). Before columns are the numbers in the field_struct table of this file; allocs are objects per call, identical with YJIT on and off. Changes: cached `Field#setter_name`/`#ivar_name`, `fs_apply_defaults` key lookup, non-allocating `Types::String#missing?`, `Rfc3339Format` timestamp parts without arrays, `JsonCodec` literal dispatch / cached renderer / in-place Hash building (`as_json`, key rewrite), `Errors#empty?` without pair arrays.

| workload | ips off before | ips off after | ips on before | ips on after | on speedup | allocs before | allocs after |
|---|---:|---:|---:|---:|---:|---:|---:|
| new from symbol-key Hash | 14,439 | 18,169 | 27,197 | 36,864 | 1.36x | 294 | 144 |
| new from string-key Hash | 14,009 | 17,130 | 24,004 | 31,937 | 1.33x | 294 | 144 |
| new invalid input (error path) | 22,903 | 28,928 | 41,583 | 53,439 | 1.29x | 183 | 106 |
| new LineItem (one nested struct) | 150,774 | 195,610 | 319,617 | 473,185 | 1.48x | 28 | 12 |
| from_json | 11,518 | 14,586 | 21,693 | 29,184 | 1.35x | 365 | 174 |
| as_json | 52,636 | 70,333 | 86,835 | 147,106 | 1.69x | 113 | 27 |
| to_json | 46,725 | 61,849 | 75,906 | 119,365 | 1.57x | 125 | 39 |
| valid? | 5,626,340 | 9,182,111 | 11,910,952 | 32,033,450 | 2.69x | 2 | 0 |
| attribute assignment: 1 setter (integer) | 1,046,351 | 1,171,709 | 2,822,366 | 3,266,379 | 1.16x | 2 | 1 |
| attribute assignment: 1 setter (time w/ zone) | 340,952 | 418,940 | 535,460 | 716,702 | 1.34x | 24 | 16 |
| attribute assignment: assign_attributes x4 | 147,237 | 164,637 | 340,259 | 393,579 | 1.16x | 31 | 22 |
| with(total:) | 436,744 | 488,118 | 901,682 | 968,374 | 1.07x | 13 | 11 |
| class declaration (Order + LineItem) | 10,398 | 10,603 | 13,267 | 13,365 | 1.01x | 745 | 745 |

Not changed, measured and dropped: the `**field.options` splat in `fs_write`. The Hash it appears to allocate is built by the callee's `**` parameter (every `Types::*#coerce` takes `**`), so removing the splat saves nothing without changing the `coerce` signature. A Boolean vocabulary tweak saved one allocation per `new` and was reverted.

Allocation guard: `spec/field_struct/allocations_spec.rb` (tag `:allocations`, runs in the default suite) holds a 9-field struct to at most 74 objects per `new` (measured 67), 25 per `to_json` (measured 22) and 0 per `valid?`.

## After actionable pass

Same machine, Ruby and harness (`gems/actionable/benchmarks/perf.rb`, YJIT on; this pass used 1 s warmup and 3 s runs, so expect 2-3% noise). Before is the tree right after the distance pass, not the first table in this file. Allocs are objects per call.

| workload | ips before | ips after | speedup | allocs before | allocs after |
|---|---:|---:|---:|---:|---:|
| run success, measure none | 81,271 | 103,857 | 1.28x | 89 | 45 |
| run success, measure all (history) | 65,802 | 80,477 | 1.22x | 111 | 63 |
| run failure (declared fail!) | 80,307 | 97,556 | 1.21x | 83 | 45 |
| run failure (invalid input) | 135,223 | 131,914 | 0.98x (noise) | 38 | 38 |
| run failure, measure all | 73,106 | 87,779 | 1.20x | 89 | 51 |
| run_each x100, measure none (per item) | 808 | 1,017 | 1.26x | 89 | 45 |
| run_each x100, measure all (per item) | 661 | 798 | 1.21x | 111 | 63 |
| nested action step, measure none | 52,632 | 63,839 | 1.21x | 123 | 66 |
| nested action step, measure all | 44,195 | 53,391 | 1.21x | 143 | 84 |
| history.to_json (5 steps) | 191,806 | 193,001 | 1.01x | 21 | 21 |

Commits:

- **Missing-method check once per class** (the biggest: 89 -> 61 allocs, +18% on a flat run). A passing check is remembered under a global layout token that changes when a step or hook is declared, or a method is added, removed or undefined on any action. A failing check is never remembered, so the error still raises, with the same message, on every run before anything executes. The first-run verb-position check is unchanged.
- **Runner and output refresh** (61 -> 45 allocs, +6%): ivar names cached per output schema instead of two `"@#{name}"` Strings per field per refresh, a shared frozen idle measurement state and empty keyword Hash, hook-list readers looked up instead of interpolated, and steps without `if:`/`unless:` skip the option lookups. A run that is not measured allocates nothing for history.
- **Measured entries and action steps** (63 allocs measured, 66 nested; throughput gain inside noise): the open history entry is set in place on the run's state, and action steps build their input pairs and `expose` list once.

Not changed, measured and dropped or left alone:

- `run_each` has no per-item overhead of its own: 100 items allocate exactly 100 times one run.
- `History::Step.new(section:, ...)` costs two objects per step (the Struct and its keyword Hash); `keyword_init` is public API, so it stays.
- Input and output `new` are now mostly field_struct's own cost (8 objects in `fs_write` coerce keywords, 3 in `Errors`, BigDecimal parsing); nothing left to gain from Ruby-level changes in actionable.
- Invalid-input failure is unchanged: it never reaches the runner.

Allocation guard: `spec/actionable/allocations_spec.rb` (tag `:allocations`) holds a typed five-step run to at most 52 objects on success and 52 on a declared failure (measured 47 each in the spec's class) and checks that an unmeasured run allocates less than a measured one and keeps no history.

Known unknown: the missing-method check is not re-run for a method added to a module after the module was already included, nor for singleton methods defined on an instance in `initialize`. Both only matter if a step method disappears after a passing run.

## After adapters pass

Same machine, Ruby and harness (each adapter's `benchmarks/perf.rb`, YJIT on, 1 s warmup and 3 s runs, so expect 2-3% noise). Before is the tree right after the base-gem passes, re-measured at the start of this pass (the base gems got faster, so these are not the numbers in the first tables). Allocs are objects per call.

| workload | ips before | ips after | speedup | allocs before | allocs after |
|---|---:|---:|---:|---:|---:|
| protobuf to_message, 1 order | 56,265 | 94,581 | 1.68x | 184 | 47 |
| protobuf encode, 1 order | 54,827 | 93,006 | 1.70x | 185 | 48 |
| protobuf from_message, 1 order | 25,038 | 30,602 | 1.22x | 280 | 153 |
| protobuf decode, 1 order | 22,735 | 27,806 | 1.22x | 299 | 170 |
| avro to_datum | 39,167 | 80,351 | 2.05x | 374 | 147 |
| avro from_datum | 21,318 | 28,635 | 1.34x | 381 | 182 |
| avro encode, 1 order | 17,758 | 23,730 | 1.34x | 671 | 417 |
| avro decode, 1 order | 15,449 | 19,236 | 1.25x | 479 | 253 |
| json_schema generate (cached) | 76,141 | 176,818 | 2.32x | 285 | 112 |
| otel traced 5-step run, success | 50,345 | 49,803 | 1.00x (noise) | 135 | 113 |
| otel traced nested action run | 37,510 | 37,767 | 1.01x (noise) | 144 | 129 |
| tools call, success | 86,258 | not changed | | 68 | 68 |

Commits:

- **protobuf**: property lists cached per (serialization, class) and dropped when the Field objects or the `serialize` mapping change identity (FS-B159), so a field added after registration still reaches the message and fails with google-protobuf's error (PB-B31). `Registry.message_class` has a lock-free path for a registered class (it took the monitor and built a `[class, serialization]` key for each of the 6 structs in an order). Encode went from 55% in `Introspection.properties` to `AbstractMessage#initialize` (29%) and the field loop (28%) being the top frames.
- **avro**: the `Klass#field` label is built only for an error (`Options.read` takes a block, `decimal`/`timestamp`/`ValueJson.load` take the site and call `label` when raising), and `Stamp#fresh?` walks the metadata against the remembered Fields instead of building `to_a` and zip pairs. Invalidation (AV-B50..B57) unchanged.
- **json_schema**: `Copy.fresh` uses `Hash#transform_values`, `Array#map`, `String#dup` (2.3x the old copy alone); `Marshal.load(Marshal.dump)` was measured at 0.27x of the old copy and dropped. Hash keys are shared (a String key is frozen by its Hash). `Stamp#current?` compares in place instead of building a second stamp. The cold path still uses `Copy.deep` for the frozen cache copy.
- **otel**: span name and fixed attribute values prepared once per (step, action label, section); the SDK keeps and mutates the Hash it is given, so each span gets a dup. Throughput is unchanged because the SDK's span objects dominate (untraced 5-step run: 127,314 ips); kept for 16% fewer objects with no slowdown (A/B 49,105 vs 49,803 ips).

Not changed, measured and dropped: tools `Envelope.plain` fast path for nil and empty Hash (+1.7%, inside noise); the Oj round trip in `plain` is ~19% of `call` but needs a different conversion to remove, not a guard. `call` is otherwise 49% `new` of the input struct (field_struct) and 15-20% Oj.

Known unknown, follow-up: avro `Options.read` still runs `transform_keys` per field per call (12% of decode now); caching it needs a rule for a user mutating the `avro:` Hash in place, which the spec does not give.

Remaining time in pure CPU kernels (profile after this pass, estimates from StackProf self time): avro encode ~55-60% (`Integer#chr` varint 18%, `SchemaValidator` 26% self+path, decimal bytes 6%, `pack`/`encode` 8%), avro decode ~50% (decimal reader: `each_with_index` + `BigDecimal#coerce` 34%), protobuf already native (the C extension is 0.27 us of ~11 us). Native candidate for the avro binary encoder is therefore stronger than before: with the Ruby fixes done, the kernels are the majority, ceiling about 2x on encode and 1.6x on decode (the decimal reader). A whole-struct coercion engine looks weaker: in tools `call` and field_struct `new`, `fs_write`, `Errors#initialize` and per-field dispatch dominate, and only BigDecimal and date parsing (~15-25%) are pure kernels; the rest is Ruby callbacks and allocation, which native code would still have to make.

## Native avro encoder (field_struct-avro-native)

Same machine, Ruby 4.0.7, YJIT on. `adapters/field_struct-avro/benchmarks/perf.rb` as is, then with
`-I../field_struct-avro-native/lib -rfield_struct/avro/native`; benchmark-ips 2 s warmup, 5 s runs, two runs each.

| workload | pure | native | speedup | allocs pure | allocs native |
|---|---:|---:|---:|---:|---:|
| avro encode, 1 order | 23,476 | 61,468 | 2.62x | 417 | 155 |
| avro encode, 1000 orders (per call) | 23.2 | 61.6 | 2.66x | 416,936 | 155,000 |

The write step alone (datum to bytes, the part replaced) is 26.4 us pure and 1.9 us native (14x). Encode is now
about 80% `to_datum` (12.6 us). Kept: the keep rule was 1.5x end to end.

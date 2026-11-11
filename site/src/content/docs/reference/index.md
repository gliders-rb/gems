---
title: "Reference"
description: "Exact behaviour of every field_struct and actionable macro, method, option and error, checked against the released versions."
sidebar:
  label: "Overview"
  order: 1
---

Come here to look something up. A page takes one topic and covers all of it: options in a table, an example CI runs for each behaviour, and for each error what raises it. Nothing here teaches. New to the gems? The [tutorial](/tutorial/trek-planner/) comes first, and the [explanation](/explanation/) pages give the reasons behind the design.

## Versions covered

These pages describe field_struct 1.0.0.pre1 and actionable-rb 2.0.0.pre1. The block below is a checked example too, so the build fails if the versions named here drift from the code.

```ruby run title="versions.rb"
FieldStruct::VERSION   # => '1.0.0.pre1'
Actionable::VERSION    # => '2.0.0.pre1'
```

If a page and the code disagree, the code wins and the page has a bug. Where a spec leaves a question open, the page says that and doesn't guess.

## field_struct

Typed plain-Ruby objects. The pages go from declaring a field to the exceptions the gem raises.

- [Fields and options](/reference/field-struct/fields-and-options/) - `field`, `required`, `optional` and the options every type shares
- [Types](/reference/field-struct/types/) - every built-in type and what it coerces
- [Dates, times and zones](/reference/field-struct/dates-and-times/) - parsing, `format:` presets, `zone:`
- [Validation and errors](/reference/field-struct/validation-and-errors/) - the setter pipeline, messages, the `Errors` API
- [Class macros](/reference/field-struct/class-macros/) - `coercion_policy`, `unknown_attributes`, `immutable!`, `validate`, `serialize`
- [Instance API](/reference/field-struct/instance-api/) - building, reading, copying and comparing instances
- [JSON and serialization](/reference/field-struct/json-and-serialization/) - `to_json`, `from_json`, key mappings
- [Registries and custom types](/reference/field-struct/registries-and-custom-types/) - name resolution and writing a type
- [Introspection and tooling](/reference/field-struct/introspection-and-tooling/) - `Metadata`, `describe`, RBS, scaffolding
- [Exceptions](/reference/field-struct/exceptions/) - every error class and what raises it

## actionable

Service objects with declared inputs, steps and outcomes.

- [Actions and steps](/reference/actionable/actions-and-steps/) - `.run`, the step DSL, guards, nesting
- [Control flow](/reference/actionable/control-flow/) - `succeed`, `fail`, `skip` and `halt!`
- [Results](/reference/actionable/results/) - `Success`, `Failure` and `Skipped`
- [Input and output](/reference/actionable/input-and-output/) - typed `input` and `output`
- [Declared failures, skips and typed outcomes](/reference/actionable/declared-outcomes/) - `fails`, `skips`, `typed_outcomes`
- [Hooks and history](/reference/actionable/hooks-and-history/) - `on_success`, `always`, the run history
- [Batches and introspection](/reference/actionable/batches-and-introspection/) - `run_each`, `describe`, the registry
- [Background jobs](/reference/actionable/jobs/) - retry and discard by failure code
- [Rails adapter](/reference/actionable/rails/) - `transactional` and `after_commit`
- [Testing](/reference/actionable/testing/) - matchers, result builders, stubs
- [RuboCop cop](/reference/actionable/rubocop/) - `Actionable/VerbNotLast`
- [RBS for your actions](/reference/actionable/rbs/) - generated signatures
- [Errors and guardrails](/reference/actionable/errors/) - exception classes and the checks that raise them

## Outside this section

Both gems keep a short README in the repository that links back here: [field_struct](https://github.com/gliders-rb/gems/tree/main/gems/field_struct) and [actionable](https://github.com/gliders-rb/gems/tree/main/gems/actionable). The optional format adapters have their own pages under [Adapters](/adapters/), and they are not released yet.

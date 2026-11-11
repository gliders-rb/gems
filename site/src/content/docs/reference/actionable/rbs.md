---
title: "RBS for your actions"
description: "What Actionable::RBS.generate emits for run, input, output, result classes, codes and typed outcomes."
sidebar:
  order: 12
---

`Actionable::RBS.generate(klass)` gives back RBS source for a single named action, derived from its input and output schemas by way of FieldStruct's metadata. A rake task is a good place for it, with the file committed beside your code. Struct types are covered in [Introspection and tooling](/reference/field-struct/introspection-and-tooling/). The gem's own signatures live in its `sig/` directory, and `generate` is the only public contract (AC §5.20).

```ruby
Actionable::RBS.generate(klass) # => String
```

Pass a named subclass of `Actionable::Action`. Anything else raises `ArgumentError`: `Actionable::RBS.generate expects an Actionable::Action subclass, got <inspect>` for a non-action, and `cannot generate RBS for an anonymous action` for an anonymous one.

```ruby run
class ReleaseMooring < Actionable::Action
  input do
    required :voyage_id, :integer
    optional :remark, :string
  end
  output { required :lines_freed, :integer }

  fails :tide_too_low
  skips :already_cast_off
end

rbs = Actionable::RBS.generate(ReleaseMooring)
rbs.lines.first.chomp                              # => "class ReleaseMooring < ::Actionable::Action"
rbs.include?('def self.run: (voyage_id: ::Integer, ?remark: ::String?) -> Result') # => true
rbs.include?('@lines_freed: ::Integer?')            # => true
rbs.include?('type failure_code = :tide_too_low | :invalid_input | :invalid_output') # => true
rbs.include?('type skip_code = :already_cast_off') # => true
rbs.end_with?("end\n")                             # => true
```

## What is emitted

| Part | Emitted |
|---|---|
| ancestors | member-less declarations of every named ancestor between the class and `Actionable::Action`, outermost first; wrapped in their namespaces |
| `def self.run` | keywords from a fixed input schema, plus an overload taking a built `(InputSchema input)` |
| `input` and `InputSchema` | for a fixed input, `def input: () -> InputSchema` and a `FieldStruct::Base` subclass with a reader and writer per field |
| instance variables | one nullable `@field` per output field, so steps that assign them type-check |
| `Output` and `Result` | `Output` with readers and writers; `Result < ::Actionable::Result` with `output` and a reader per field |
| code aliases | `type failure_code` (declared codes, then the gem's two, de-duplicated) and `type skip_code` (declared only) |

How `run` gets its keywords: a required field is `name: Type`, and one that may be left out is `?name: Type`. Optional fields are nullable too (`?name: Type?`), and a required field with a default can be omitted. Free-form actions, and any action using an `input_for` dispatch, get `(*untyped)`. The return type is `Result` when the output has a schema and `::Actionable::Result` when it hasn't. `InputSchema`, `Output` and `Result` exist in RBS only. If Ruby already resolves `InputSchema` on the class, an ancestor or an included module, generation raises `ArgumentError` and asks you to rename that constant. Output is indented two spaces, blank lines are empty, types are fully qualified, and the text ends with a newline.

```ruby run
class Freeform < Actionable::Action; end

Actionable::RBS.generate(Freeform).include?('def self.run: (*untyped) -> ::Actionable::Result') # => true

begin
  Actionable::RBS.generate(Class.new(Actionable::Action))
rescue ArgumentError => e
  e.message # => "cannot generate RBS for an anonymous action"
end
```

## Typed outcomes

[Typed outcomes](/reference/actionable/declared-outcomes/#typed-outcomes) add the result classes to the output: the success `Output` when there is one, an output class for every code that has a schema (`<CamelCode>SkipOutput` or `<CamelCode>FailureOutput`), and the `Success`, `Skipped` and `Failure` classes. `run` returns `(Success | Skipped | Failure)`.

- `Success` has `code: :success`, `output: Output` (or a Hash when there is no schema) and a reader per success field.
- `Skipped` has `code` typed as `skip_code` (or `::Symbol` when none are declared) and `output` as the union of the skip output classes and the Hash.
- `Failure` has `code` typed as `failure_code`, `output` as the union of failure classes, skip classes, `Output` and the Hash, and every reader nullable, since a broken output can lack a required field.
- Bases are the parent action's own classes when the parent has typed outcomes, else the gem classes.

A trailing `?` or `!` on a code turns into `Predicate` or `Bang` in the class name (`:expired?` gives `ExpiredPredicate...`). If two codes of one kind map to the same class name, or a name doesn't begin with an ASCII capital, `ArgumentError` names both codes.

```ruby run
class Charter < Actionable::Action
  typed_outcomes

  input { required :nights, :integer }
  output { required :arrives_in, :integer }

  fails(:over_limit) { required :max_nights, :integer }
end

typed = Actionable::RBS.generate(Charter)
typed.include?('-> (Success | Skipped | Failure)')                  # => true
typed.include?('class OverLimitFailureOutput < ::FieldStruct::Base')  # => true
typed.include?('class Success < ::Actionable::Success')             # => true
typed.include?('def code: () -> failure_code')                      # => true
```

:::caution
The generated types describe valid instances of your classes only. Under typed outcomes, a `Failure` subclass defined by the host passes through the rebuild untouched, and the generator doesn't describe it.
:::

## See also

- [Declared outcomes](/reference/actionable/declared-outcomes/): where codes and typed outcomes are declared
- [Input and output](/reference/actionable/input-and-output/): the schemas the types come from
- [Introspection and tooling](/reference/field-struct/introspection-and-tooling/): `FieldStruct::RBS` for structs

---
title: "How to generate RBS signatures for your classes"
description: "Write RBS for your structs and actions so Steep or Solargraph can type-check the code that uses them."
sidebar:
  label: "Generate RBS signatures"
  order: 12
---

Structs and actions are built from macros, so a type checker can't see their fields. Generate the signatures and skip writing them by hand.

## 1. Generate for a struct

`FieldStruct::RBS.generate` takes a named struct class and returns RBS source with a reader and a writer for each field.

```ruby run
class Fern < FieldStruct::Base
  required :species, :string
  optional :fronds, :integer
  optional :habitats, :array, of: :string
end

fern_rbs = FieldStruct::RBS.generate(Fern)
fern_rbs.include?('attr_reader species: ::String')                # => true
fern_rbs.include?('attr_reader fronds: ::Integer?')               # => true
fern_rbs.include?('def species=: (::String? value) -> ::String?') # => true
```

## 2. Generate for an action

`Actionable::RBS.generate` writes the class with a typed `run`, plus input, output and result classes and aliases for the codes. The class must be named.

```ruby run
class ReleaseBerth < Actionable::Action
  input do
    required :voyage_id, :integer
    optional :remark, :string
  end
  output { required :berths_freed, :integer }

  fails :deck_full
  skips :already_ashore
end

action_rbs = Actionable::RBS.generate(ReleaseBerth)
action_rbs.lines.first.chomp   # => "class ReleaseBerth < ::Actionable::Action"
action_rbs.include?('def self.run: (voyage_id: ::Integer, ?remark: ::String?) -> Result')   # => true
action_rbs.include?('type failure_code = :deck_full | :invalid_input | :invalid_output')     # => true
```

## 3. Write the files

Put both generators in one rake task and commit what they write beside your code. A changed field then shows up in review.

```ruby
# lib/tasks/rbs.rake
task :rbs do
  { Fern => 'fern', ReleaseBerth => 'release_berth' }.each do |klass, file|
    generator = klass < Actionable::Action ? Actionable::RBS : FieldStruct::RBS
    File.write(File.join('sig', "#{file}.rbs"), generator.generate(klass))
  end
end
```

## 4. Remember what the types promise

:::caution
The types describe a valid instance. An invalid struct may hold something else, because the default `:keep_raw` policy keeps the raw input. Check `valid?` before trusting a type.
:::

Required readers carry no `?`, while writers always accept `nil`. A free-form action (no `input` block, or one that dispatches through `input_for`) gets a `run` taking `(*untyped)`.

Generation raises `ArgumentError` for an anonymous class, or when Ruby already resolves `InputSchema` on it, and the message says what to rename.

## See also

- [Introspection and tooling](/reference/field-struct/introspection-and-tooling/#rbs)
- [RBS for your actions](/reference/actionable/rbs/)
- [Declare and handle outcomes](/how-to/handle-action-outcomes/)

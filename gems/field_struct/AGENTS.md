# AGENTS.md

Guide for coding agents using the `field_struct` gem. Short on purpose; the details live in the files below.

## Read these

- [USAGE.md](USAGE.md): the reference. Every type, option and macro, with examples. Read it once before writing a model.
- [docs/getting_started.md](docs/getting_started.md): task-to-API map, what each error means and how to fix it, common mistakes, Rails.
- [README.md](README.md): overview and the type and option tables.
- [skills/field-struct/SKILL.md](skills/field-struct/SKILL.md): the same guidance as a Claude Code skill.

## A model in four lines

```ruby
class Plant < FieldStruct::Base
  required :species, :string
  optional :leaves, :integer, in: 1..5000
end
```

## Gotchas

1. **Setters are permissive.** A bad value is stored as given and recorded in `errors`. Nothing raises unless the class
   says `coercion_policy :raise`. Always check `valid?`.
2. **`required` doesn't mean non-nil.** It means `valid?` fails when the value is missing. An unset required field reads
   as `nil`.
3. **Whitespace-only strings and empty arrays are missing** for `required` (not for `:binary` or `:value`).
4. **`of:` is required** on `:array` and `:union`. A missing one raises at declaration.
5. **Options are scoped to types.** `round:` is for numbers, `format:` for strings and dates, `enum:` for strings and
   symbols. Options for array elements go in `element: {...}`.
6. **Cross-field rules go to `errors[:base]`**, from a `validate` method or block.
7. **JSON goes through Oj.** Use `to_json`, `as_json` and `from_json`; don't use `JSON.generate` on a struct.
8. **Unknown keys are ignored** by default. Use `unknown_attributes :raise` to fail on them.
9. **Messages never echo the value**, only its class. `inspect` does show values unless the field is `sensitive: true`.
10. **Validity goes stale.** It's computed on assignment. Mutating a nested object in place doesn't refresh the parent.
11. **Copy with `with(**changes)`.** It takes keywords, returns a new object, and is the way to "change" an
    `immutable!` or `frozen!` one.

## Working on this gem

```
bundle exec rake                 # specs and RuboCop (fast)
bundle exec rake release:check   # adds doctests, the signature checks, and the YARD build
bundle exec rake sigs:generate   # after changing any YARD comment: regenerate sig/field_struct.rbs and commit it
```

Public methods need short YARD comments with types. Inside `FieldStruct::Types`, write stdlib names with a leading `::`
(`::String`, `::Hash{::Symbol=>::Object}`). The signature file is generated, never edited by hand.

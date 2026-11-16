---
title: "Typed, and documented once"
description: "Two tenets behind everything in Gliders: all code is typed, and each fact is written once, where the code is defined."
sidebar:
  order: 11
---

A weather station reports a temperature. Here is everything we know about that field, written once:

```ruby run
class Reading < FieldStruct::Base
  required :celsius, :decimal, desc: 'Air temperature at the station'
end
```

That one line holds the name, the type, that it is required, and what it means. Everything else should come from it.

The types come from it. Editors, Steep and `irb` read RBS, and the gem writes it for you:

```ruby run
reading_rbs = FieldStruct::RBS.generate(Reading)
reading_rbs.include?('attr_reader celsius: ::BigDecimal') # => true
```

The description comes from it, for a person or an AI agent reading the class:

```ruby run
Reading.describe.include?('Air temperature at the station') # => true
```

## The two tenets

1. **Everything is typed.** Every method we write has an RBS signature, and the gems type what you declare too. A typed class is easier to read and use, for people and for AI agents alike. Your editor and console can complete it, and a misspelled field or keyword fails early instead of passing silently.
2. **Document once, where the code is defined.** A field's declaration and a method's comment are the one source. READMEs, reference tables, schemas and RBS are generated from that source or checked against it, never copied by hand. Every example should run in CI, so a page that drifts from the code fails the build.

## Where we are

This is an experiment for now, and we are partway there. The public API of every gem has generated RBS, and most examples on this site run in CI. What is still missing:

- Steep checks both core gems against their signatures in CI, at the error level; the adapters aren't checked yet, and private methods have no types.
- Generating RBS for your own classes is a [copy-paste rake task](/how-to/generate-rbs/), not a shipped command.
- One reference table (which options each field type takes) is generated; the rest are hand-written, and a docs check fails when a public name is missing from them, but not when a sentence goes stale.

Each of those gets a check in CI, so we can tell whether the tenets pay off. If they don't, we will say so here.

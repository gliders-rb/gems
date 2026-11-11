---
title: "Plan a trek across a hut network"
description: "A six-chapter tutorial that builds a trek planner for a network of mountain huts with field_struct and actionable, one step at a time."
sidebar:
  label: "Overview"
  order: 1
---

In this tutorial we build the booking side of a mountain hut network. We start with a typed `Hut`, nest it into bookings and JSON, write the action that reserves places, handle what goes wrong, split the work into small actions, and put the result behind a controller, a job and a spec.

Checked against `field_struct` 1.0.0.pre1 and `actionable-rb` 2.0.0.pre1, the versions in this repository.

## The six chapters

| Chapter | We make | Gem |
|---|---|---|
| [1. A typed Hut](/tutorial/a-typed-hut/) | a `Hut` with typed, coerced, validated fields | field_struct |
| [2. Bookings and JSON](/tutorial/bookings-and-json/) | nested bookings, JSON round trips, a masked token | field_struct |
| [3. Reserving places](/tutorial/reserving-places/) | the first action, with typed input and a declared failure | actionable |
| [4. When things go wrong](/tutorial/when-things-go-wrong/) | skips, metadata, pattern matching, exceptions | actionable |
| [5. Composing actions](/tutorial/composing-actions/) | a trek plan built from small actions, with an undo | actionable |
| [6. Into an app](/tutorial/into-an-app/) | a controller, a flaky pass-report lookup, a job and a spec | actionable |

Each chapter takes about 20 minutes, and chapters 1 and 2 need only `field_struct`.

## What you need

Ruby 3.3 or newer, and these two gems:

```ruby
gem 'field_struct', '~> 1.0.0.pre1'
gem 'actionable-rb', '~> 2.0.0.pre1'
```

## How to follow along

Type each example into `irb`, or paste a whole chapter into one script. Begin with these two lines.

```ruby
require 'field_struct'
require 'actionable'
```

Every chapter declares the classes it needs again, so you can start at any of them. Inside a chapter the examples build on each other, in order.

A line like `hut.places # => 24` shows the value that expression returns. All of them are checked: the site's build runs every example in order and fails when a result differs from its comment, so the code you read is code that ran.

Where an example needs a web server, a queue or RSpec, the tutorial uses a plain Ruby stand-in or a plain code block, and says so.

## Where to go after

- [How-to guides](/how-to/): one task each
- [Reference](/reference/): every option and method
- [Explanation](/explanation/): why the gems are shaped this way

## See also

- [A typed Hut](/tutorial/a-typed-hut/): chapter 1
- [How the two gems fit together](/explanation/how-the-gems-fit/)
- [Reference overview](/reference/)

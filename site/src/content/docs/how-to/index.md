---
title: "How-to guides"
description: "Short, task-sized guides for validating input, shaping JSON, handling outcomes, and running actions in an app."
sidebar:
  label: "Overview"
  order: 1
---

A guide takes one task, walks it in three to five steps and points to the reference for details. If you are new, do the [tutorial](/tutorial/trek-planner/) first and return when a specific problem comes up.

## Structs (field_struct)

- [Validate request params](/how-to/validate-request-params/): turn untrusted params into a typed struct and report what is wrong
- [Use camelCase JSON keys](/how-to/camelcase-json/): keep snake_case in Ruby and match an outside API
- [Keep secrets out of logs](/how-to/hide-sensitive-values/): mask passwords and tokens in `inspect` and `pp`
- [Dates, times and zones](/how-to/dates-and-time-zones/): parse dates and local times the same way on every machine
- [Nested structs and arrays](/how-to/nested-structs-and-arrays/): find which element is wrong

## Actions (actionable)

- [Declare and handle outcomes](/how-to/handle-action-outcomes/): name the ways an action ends and branch on each
- [Compose actions](/how-to/compose-actions/): use one action as a step of another
- [Run in a background job](/how-to/background-jobs/): retry by failure code
- [Use ActiveRecord transactions](/how-to/activerecord-transactions/): roll back on failure, send effects after the commit
- [Test with RSpec](/how-to/test-with-rspec/): test an outcome in one line
- [Generate RBS signatures](/how-to/generate-rbs/): types for Steep or Solargraph
- [Lint with the RuboCop cop](/how-to/catch-misplaced-verbs/): catch a `fail` that does not stop the run

After an option or a method? That is the [reference](/reference/). Curious why something works the way it does? Read the [explanation](/explanation/) pages.

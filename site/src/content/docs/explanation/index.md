---
title: "Explanation"
description: "The reasoning behind the design of field_struct and actionable, with the trade-offs stated."
sidebar:
  label: "Overview"
  order: 1
---

Each page here answers "why is it like this?". Teaching a task is the job of the [tutorial](/tutorial/trek-planner/) and the [how-to guides](/how-to/), and listing options is the [reference](/reference/)'s. Every page states a lean, gives the reason and names the cost. If the design record gives no reason, the page says that too.

## field_struct

- [Validity is computed on assignment](/explanation/validity-on-assignment/): why every setter validates its own field, and what goes stale
- [Coercion versus validation](/explanation/coercion-and-validation/): two steps, two kinds of error, and three policies

## actionable

- [Success, failure, skip](/explanation/three-outcomes/): why a skip is its own outcome, and why halting is a throw
- [Declared failures and result codes](/explanation/declared-outcomes/): why the codes are a contract

## Both

- [ActiveModel-shaped, framework-free](/explanation/framework-independence/): copy the shape, keep Rails optional
- [How the two gems fit together](/explanation/how-the-gems-fit/): input, output and result are all structs
- [Why these gems](/explanation/why-these-gems/): where they came from

---
title: "Why these gems"
description: "The few rules the gems are built around, and why they stay small on purpose."
sidebar:
  order: 8
---

:::note[Draft]
The author's own story goes here: where the ideas came from and why they kept coming back. The rest of the page is the design reasoning, and every claim in it links to the page that shows it.
:::

Most Ruby apps grow two kinds of code that are hard to trust. One kind carries data in from outside: a form, a webhook, a message off a queue. The other kind does something with that data. These gems are my answer to both, and they are built around a few rules I don't bend.

An action says what it returns. Its output is declared up front, so nothing lands in a result by accident, and a caller can read the declaration to know what comes back ([declared outcomes](/explanation/declared-outcomes/)).

Stopping a run is not an error. A step halts with a `throw`, so a real exception is never mistaken for a planned stop, and a `rescue` meant for something else never swallows one ([success, failure, skip](/explanation/three-outcomes/)).

A struct that gets bad data stays alive to explain it. It doesn't raise on assignment and it doesn't pretend the value was fine. It keeps the errors next to the fields, and you decide what to do with them ([validity on assignment](/explanation/validity-on-assignment/)).

Rails is welcome but not required. A struct answers the same `valid?`, `errors` and `attributes` a Rails developer already knows, and none of it needs Rails. The Rails pieces are opt-in adapters ([framework independence](/explanation/framework-independence/)).

Both gems are small on purpose. I would rather ship two gems that each do one job and say where they stop than one big framework I have to defend. Anything that needs a new idea gets its own adapter gem - JSON Schema, Avro, Protobuf, OpenTelemetry, LLM tools - so the core stays readable in an afternoon.

I'm not sure yet how far the strictness should go. A date in the wrong shape is refused instead of guessed at, and an error message names the class of a bad value but never the value itself ([coercion versus validation](/explanation/coercion-and-validation/)). Both give up some convenience. My lean is that this is the right side to be on, for now, though I would love to hear where it gets in the way.

## See also

- [The Gliders idea](/explanation/gliders/)
- [History](/explanation/history/)
- [How the two gems fit together](/explanation/how-the-gems-fit/)
- [Coercion versus validation](/explanation/coercion-and-validation/)
- [Success, failure, skip](/explanation/three-outcomes/)

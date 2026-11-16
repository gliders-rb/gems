---
title: "Why these gems"
description: "The few rules the gems are built around, and why they stay small on purpose."
sidebar:
  order: 12
---

Most Ruby apps grow two kinds of code that are hard to trust. One kind carries data in from outside: a form, a webhook, a message off a queue. The other kind does something with that data. These gems are my answer to both, and they are built around a few rules I don't bend.

## Where the ideas come from

These ideas are older than this code. I carried them for years, from one codebase to the next, and they kept coming back because the same three questions kept coming back. How does a piece of work run? What does the caller get when it is done? And how much does the rest of the system get to know about it? The gems are my answers, and each answer leans on the one before it.

The first is the runner. An action is a list of declared steps, but that list is not what I value most. What I value is that every action runs on the same railway. The steps run in order on the main track, and any step can leave it early, with a success, a failure or a skip. Each outcome then has its own section of hooks, so the work for "it went well" and the work for "it didn't" never tangle with the steps themselves, and the happy path reads like the happy path ([the runner is a railway](/explanation/the-runner-is-a-railway/)).

Because every run ends in one of those three outcomes, what comes back can be plain. You don't get the action back, and you don't get a handle on anything it touched. You get a result - a report of what happened, with no power to change anything. You present it, log it or send it somewhere, and the action that made it is already gone ([a result is a report](/explanation/a-result-is-a-report/)).

And because the inputs, the steps, the outcomes and the result are all declared, they can be read back. For me that is the biggest value of all. The metadata lets an adapter describe a struct as JSON Schema, Avro or a tool definition without asking you to write it again, and it is the reason the adapters exist ([metadata is the product](/explanation/metadata-is-the-product/)).

Two habits keep those ideas honest. The gems stay plain Ruby: in all my years of using them I never needed to inject a tool into an action, and it calls a `Ledger` or a `Customer` model directly like any other Ruby code. And we document once, where the code is defined, and generate the rest, because I hate writing the same thing in more than one place. The type signatures come from those comments and the examples on this site run as tests. Typing everything is also an experiment I'm running on purpose. I don't have proof yet that it helps, but I hope it makes the gems easier to use, both for people in an editor and for the AI tools that read the code with them ([typed and documented once](/explanation/typed-and-documented-once/)).

The rules below are where those ideas show up in the code.

## The rules they are built around

An action says what it returns. Its output is declared up front, so nothing lands in a result by accident, and a caller can read the declaration to know what comes back ([declared outcomes](/explanation/declared-outcomes/)).

Stopping a run is not an error. A step halts with a `throw`, so a real exception is never mistaken for a planned stop, and a `rescue` meant for something else never swallows one ([success, failure, skip](/explanation/three-outcomes/)).

A struct that gets bad data stays alive to explain it. It doesn't raise on assignment and it doesn't pretend the value was fine. It keeps the errors next to the fields, and you decide what to do with them ([validity on assignment](/explanation/validity-on-assignment/)).

Rails is welcome but not required. A struct answers the same `valid?`, `errors` and `attributes` a Rails developer already knows, and none of it needs Rails. The Rails pieces are opt-in adapters ([framework independence](/explanation/framework-independence/)).

Both gems are small on purpose. I would rather ship two gems that each do one job and say where they stop than one big framework I have to defend. Anything that needs a new idea gets its own adapter gem - JSON Schema, Avro, Protobuf, OpenTelemetry, LLM tools, process pages - so the core stays readable in an afternoon.

I'm not sure yet how far the strictness should go. A date in the wrong shape is refused instead of guessed at, and an error message names the class of a bad value but never the value itself ([coercion versus validation](/explanation/coercion-and-validation/)). Both give up some convenience. My lean is that this is the right side to be on, for now, though I would love to hear where it gets in the way.

## See also

- [The runner is a railway](/explanation/the-runner-is-a-railway/)
- [A result is a report](/explanation/a-result-is-a-report/)
- [Metadata is the product](/explanation/metadata-is-the-product/)
- [The Gliders idea](/explanation/gliders/)
- [History](/explanation/history/)
- [How the two gems fit together](/explanation/how-the-gems-fit/)
- [Coercion versus validation](/explanation/coercion-and-validation/)
- [Success, failure, skip](/explanation/three-outcomes/)

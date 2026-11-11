---
title: "The Gliders idea"
description: "Why the gems live under the Gliders name: work with the forces already in a system instead of fighting them."
sidebar:
  order: 9
---

A glider has no engine. It stays up by reading the air - a thermal, the lift off a ridge - and using what is already there instead of fighting it. That is the idea behind these gems, and why they live under the Gliders name.

It shows up in small decisions. A struct coerces data into shape instead of rejecting it on the first mismatch, and when the data is truly bad, it stays alive to explain it ([validity on assignment](/explanation/validity-on-assignment/)). An action that needs to stop throws, instead of raising an exception that something else has to rescue ([success, failure, skip](/explanation/three-outcomes/)). The adapters describe a struct in the formats the rest of your system already speaks, like JSON Schema, Avro and Protobuf, so you declare your data once instead of again for each one ([how adapters work](/adapters/how-adapters-work/)).

It is not about doing less. A good glider pilot works hard - reading, deciding, staying accurate - so the flight doesn't have to fight the air. Like a martial artist redirecting an attacker's energy, we would rather work with the forces in a system than against them.

FieldStruct and Actionable are the first gliders. More are on the way.

## See also

- [Why these gems](/explanation/why-these-gems/)
- [History](/explanation/history/)

---
title: "ActiveModel-shaped, framework-free"
description: "Why the gems copy the shape of ActiveModel without its code, and why Actionable keeps Rails in opt-in adapters."
sidebar:
  order: 4
---

A `FieldStruct` object answers `valid?`, `errors`, `attributes`, `assign_attributes` and `to_json`. A Rails developer already knows that vocabulary, and none of it needs Rails.

```ruby run
class Hut < FieldStruct::Base
  required :name, :string
  optional :places, :integer
end

hut = Hut.new(name: '', places: '41')
hut.valid?                       # => false
hut.errors.class                 # => FieldStruct::Errors
hut.errors.full_messages         # => ["Name is required"]
hut.attributes                   # => {name: "", places: 41}
defined?(ActiveModel)            # => nil
```

## Mirror the shape, not the code

We took the method names and the behaviour callers depend on, and left the rest. The persistence half (`save`, `new_record?`) isn't there because there is nothing to persist, and no line of ActiveModel's code was reused (FS-I9). The reasons are simple.

- Code that reads `hut.errors[:name]` today keeps working. Form builders, serializers and your own helpers can't tell the difference.
- The gem runs in a script, in a worker, or inside one of your gems that has no Rails to load.
- Our behaviour is ours to fix. A message, a coercion rule or a default can change without waiting on someone else's release.

The cost is that we maintain our own `Errors`, our own `full_messages` and our own humanizing, which does the bare minimum: underscores become spaces and the first letter goes up. There is no inflector and no i18n. A Rails app that wants translated messages has to bridge them itself for now. We would rather ship a small honest version than a big half-compatible one.

## Same behaviour with and without ActiveSupport

Loading ActiveSupport doesn't change what a struct does (FS-I6). A date string is never read through `String#to_time`, and a `DateTime` converts the same way either way. The test is easy to state: a result that depends on whether some library happens to be loaded is a bug, since code that works in your console would act differently in the worker.

## Actionable follows the same rule

Actionable's core is plain Ruby. Rails, RSpec, job queues, coverage and the RuboCop cop each sit behind their own `require`, and nothing loads by itself (AC-I10).

```ruby run
defined?(ActiveRecord)                                  # => nil
Actionable::Action.respond_to?(:transactional)          # => false
Actionable::Action.respond_to?(:honor_retry_metadata)   # => false

require 'actionable/job'
Actionable::Action.respond_to?(:honor_retry_metadata)   # => true
```

We turned down the friendlier option of loading the Rails adapter whenever ActiveRecord is present. Explicit wins here. If `transactional` showed up because of a gem you never meant to depend on, a missing `require` in one file would hide in the one place you want it loud. Without the adapter you get a plain `NoMethodError` when the class is defined.

## What this does not mean

The gems don't avoid Rails users. The adapters exist for them, and [Use ActiveRecord transactions](/how-to/activerecord-transactions/) is the code you would write anyway. The point is that Rails is something you plug in, and not the ground the gems stand on.

## See also

- [Instance API](/reference/field-struct/instance-api/)
- [Rails adapter](/reference/actionable/rails/)
- [How the two gems fit together](/explanation/how-the-gems-fit/)

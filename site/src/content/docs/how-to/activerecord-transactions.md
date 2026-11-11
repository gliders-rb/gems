---
title: "How to run an action in a database transaction"
description: "Roll back every write when an action fails, and run side effects only after the commit."
sidebar:
  label: "Use ActiveRecord transactions"
  order: 10
---

A `MoveCargo` action lifts tonnage out of one hold and adds it to another. When the second step fails, the first write has to vanish, and nobody should get a notice about a move that was rolled back.

The examples here are plain code, because the site's bundle has no ActiveRecord. We ran them against in-memory SQLite, as the adapter's own specs do.

## 1. Load the adapter and wrap the action

The adapter is opt-in. `transactional` takes the model whose connection holds the transaction, either as a class or by name. You need ActiveRecord 7.1 or newer, and 7.2 for `after_commit`.

```ruby
require 'actionable/rails'

class Hold < ActiveRecord::Base; end

class MoveCargo < Actionable::Action
  transactional model: Hold

  input do
    required :source_id, :integer
    required :target_id, :integer
    required :tons, :integer
  end

  fails :hold_overdrawn

  step :lift
  step :stow

  private

  def lift
    @source = Hold.find(input.source_id)
    @source.update!(cargo_tons: @source.cargo_tons - input.tons)
  end

  def stow
    fail!(:hold_overdrawn) if @source.cargo_tons.negative?
    Hold.find(input.target_id).increment!(:cargo_tons, input.tons)
  end
end
```

## 2. Let a failure roll back

A success or a skip commits. A recorded failure rolls everything back and still returns the failure result, while an exception rolls back and keeps propagating.

```ruby
port = Hold.create!(name: 'port', cargo_tons: 5)
starboard = Hold.create!(name: 'starboard', cargo_tons: 0)

MoveCargo.run(source_id: port.id, target_id: starboard.id, tons: 3).success?   # => true
[port.reload.cargo_tons, starboard.reload.cargo_tons]                          # => [2, 3]

MoveCargo.run(source_id: port.id, target_id: starboard.id, tons: 9).code       # => :hold_overdrawn
[port.reload.cargo_tons, starboard.reload.cargo_tons]                          # => [2, 3]
```

The second run pulled 9 tons from the port hold inside `lift`, and `stow` failed, so that write was undone.

## 3. Send side effects after the commit

`after_commit` declares a hook that fires once the outermost transaction has committed, and only following a success. A failure, a skip or a rollback never triggers it.

```ruby
class MoveCargo < Actionable::Action
  after_commit :announce

  private

  def announce
    HarbourMailer.cargo_shifted(input.tons).deliver_later
  end
end
```

The run has already finished when the hook fires, so it can't alter the returned result. If it raises, the exception propagates from the point of the commit, after the writes are saved.

## 4. Nest it in an outer transaction

Inside a transaction that is already open, the action takes a savepoint of its own. A failed inner action undoes only its own writes, and the outer transaction keeps going and can still commit the rest.

```ruby
Hold.transaction do
  MoveCargo.run(source_id: port.id, target_id: starboard.id, tons: 9).code   # => :hold_overdrawn
  # the outer transaction is still open, with the failed move undone
end
```

To have the action join the outer transaction instead, pass `requires_new: false` to `transactional`. Either way, an `after_commit` hook waits for the outermost commit.

## See also

- [Rails adapter](/reference/actionable/rails/)
- [Hooks and history](/reference/actionable/hooks-and-history/)
- [Compose actions](/how-to/compose-actions/)

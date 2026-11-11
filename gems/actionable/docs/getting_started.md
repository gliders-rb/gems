# Getting started

This page maps tasks to the API, explains what each error means and how to fix it, walks through one action end to
end, and lists the mistakes people make first. [USAGE.md](../USAGE.md) is the full reference.

## What do you want to do?

| Task | Use |
|---|---|
| Wrap one piece of logic | `class BookCrossing < Actionable::Action`, then `step :name` and a method per step |
| Take typed, checked input | `input { required :callsign, :string }`, read it as `input.callsign` |
| Return typed data | `output { required :fare, :integer }`, set `@fare` in a step |
| Run it | `BookCrossing.run(callsign: 'ana@example.com')` |
| Tell what happened | `result.success?`, `failure?`, `skipped?`, `ok?`, `code`, `message`, `errors` |
| Stop with a failure | `fail!(:deck_full, 'sold out')` |
| Stop because there is nothing to do | `skip!(:already_done)` |
| Turn a struct's errors into a failure | `fail_with!(struct, code: :invalid)` |
| Announce the codes an action can end with | `fails :deck_full, 'sold out', retry: false` and `skips :already_done` |
| Run another action as a step | `step Claim, input: %i[berth], expose: %i[reservation]` |
| Pick a branch by value | `case_step :channel do on 'callsign', :send_signal; default :send_other end` |
| Do something after, depending on the outcome | `on_success`, `on_failure`, `on_skip`, `always` |
| Run a step only sometimes | `step :audit, if: :audited?` or `unless:` |
| Run one action over many items | `BookCrossing.run_each(rows) { \|row\| { callsign: row } }` |
| Keep a timed record of a run | `measure :all`, then `result.history.to_json` |
| Give failures their own output | `typed_outcomes` and `fails(:code) { required :field, :string }` |
| Wrap a run in a transaction | `require 'actionable/rails'`, `transactional model: :order` |
| Run something after the commit | `after_commit :notify` |
| Decide ack, discard or retry in a job | `Actionable::Job.disposition(result)` or `Actionable::Job::Mixin` |
| Test it | `require 'actionable/rspec'`, `expect(Klass).to perform_actionable(...).and_fail(:code)` |
| Stub a child action | `allow_actionable_failure(Child, code: :deck_full)` |
| Find declared outcomes no spec reached | `require 'actionable/rspec/coverage'` |
| See what an action does | `Klass.describe_text` |
| Get RBS for an action | `Actionable::RBS.generate(Klass)` |

## What an error means

A run does not raise for bad input or a business failure. It returns a `Failure`, and `result.errors.to_h` says which
field. These are the codes the gem itself produces:

| Code or message | Meaning | Fix |
|---|---|---|
| `:invalid_input`, message `input failed validation` | the keywords did not satisfy the `input` schema | read `result.errors.to_h`, send what the field needs |
| `:invalid_input`, message `no input shape for kind "x"` | `input_for` found no branch for the discriminator | send a known value or add a `default` |
| `:invalid_output` | a step left the `output` schema invalid, usually a required field never set | set the variable (`@fare = ...`), or make the field `optional` |

Exceptions are for mistakes in the action itself:

| Exception and message | Meaning | Fix |
|---|---|---|
| `DefinitionError: X declares step(s) calling :a but does not implement them` | a step, hook or branch names a method that does not exist | write the method, or fix the name |
| `DefinitionError: ... calls `fail` with more code after it` | a plain verb is not the last thing in its method | use `fail!`, or move the verb to the end |
| `DefinitionError: X fails with :other, which it does not declare` | the action declares some failures, and this code is not one | add `fails :other` |
| `DefinitionError: X fails with :plain and output, but :plain declares no output schema` | typed outcomes refuse output with nowhere to go | add a block: `fails(:plain) { ... }` |
| `DefinitionError: output field(s) :status conflict with reserved result attributes` | the field name is a Result method | rename the field |
| `DefinitionError: X set @result to a ...` | a step overwrote the reserved `@result` | rename the instance variable |
| `ArgumentError: ... code "..." is not an identifier` | a sentence or odd string was used as a code | use a Symbol like `:deck_full`, and `raise` to raise |
| `ArgumentError: unsupported step target` | `step` got something that is not a Symbol, String or Action class | pass a method name or an action class |
| `ArgumentError: unknown measure mode` | `measure` got a mode other than `:all`, `:none`, `:sampled` | use one of those |
| `NoMethodError: undefined method 'transactional'` | the Rails adapter is not loaded | `require 'actionable/rails'` |
| `UncaughtThrowError` | a bang verb was called outside a run | call the action through `.run` |
| `FieldStruct::UnknownAttributeError` | the input schema says `unknown_attributes :raise` and a keyword was extra | drop the keyword |

## One action, end to end

<!-- doctest -->
```ruby
require 'actionable'

class SendFlare < Actionable::Action
  input do
    required :callsign, :email
    required :signaller, :string
  end

  output do
    required :flare_id, :string
    optional :delivered, :boolean
  end

  fails :blocked, 'that mooring is blocked', retry: false
  skips :already_flared, 'they already have an invite'

  step :screen
  step :create
  on_success :deliver

  def self.blocked = %w[spam@example.com]
  def self.invited = %w[bo@example.com]

  private

  def screen
    skip!(:already_flared) if self.class.invited.include?(input.callsign)
    fail!(:blocked) if self.class.blocked.include?(input.callsign)
  end

  def create
    @flare_id = "inv-#{input.callsign.split('@').first}"
  end

  def deliver
    @delivered = true
  end
end

ok = SendFlare.run(callsign: 'ana@example.com', signaller: 'Cy')
ok.success?          # => true
ok.flare_id         # => "inv-ana"
ok.delivered         # => true

SendFlare.run(callsign: 'spam@example.com', signaller: 'Cy').code   # => :blocked
SendFlare.run(callsign: 'bo@example.com', signaller: 'Cy').skipped? # => true
SendFlare.run(signaller: 'Cy').errors.to_h.keys                  # => [:callsign]
```

Steps run in order. A bang verb stops the main steps but the `on_success` hook only runs after a success, so `deliver`
never runs for the blocked or skipped invite.

## First mistakes

- Treating `fail` as `raise`. It records a failure and the method keeps going.
- Writing `fail(:x) if bad?` and then more code. Use `fail!`.
- Forgetting to declare an output field and wondering why the variable is not on the result.
- Passing a Hash to `.run`. Use `.run(**params)`.
- Declaring `fails` for some codes and then failing with another. Once any are declared, all must be.
- Expecting a skip to stop a parent action. A child skip lets the parent continue.
- Asserting the Rails or job behavior without the adapter require.

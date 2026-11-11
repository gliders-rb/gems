# actionable-rb usage reference

A dense, example-first reference. Every example marked as a doctest runs in the test suite, and every public method of
the API classes is named here (`rake docs:check` enforces it).

- [Declaring an action](#declaring-an-action) · [Control flow](#control-flow) · [Results](#results)
- [Input](#input) · [Output](#output) · [Steps, guards and hooks](#steps-guards-and-hooks) · [Case steps](#case-steps)
- [Nested actions](#nested-actions) · [Declared failures and skips](#declared-failures-and-skips) · [Typed outcomes](#typed-outcomes)
- [History and measurement](#history-and-measurement) · [Batches and the registry](#batches-and-the-registry)
- [Introspection](#introspection) · [Guardrails](#guardrails) · [Rails](#rails) · [Jobs](#jobs) · [RSpec](#rspec) · [Coverage](#coverage)
- [Types with RBS](#types-with-rbs) · [Exceptions](#exceptions)

## Declaring an action

An action is a subclass of `Actionable::Action`. Each step is an instance method, public or private, and `.run`
builds a fresh instance every time, so no state survives between runs.

<!-- doctest -->
```ruby
require 'actionable'

class ArchiveLog < Actionable::Action
  input do
    required :imo, :string
  end

  output do
    required :archived_imo, :string
  end

  step :archive

  private

  def archive
    @archived_imo = input.imo.delete('-')
  end
end

result = ArchiveLog.run(imo: '978-0-13')
result.archived_imo      # => "978013"
ArchiveLog.steps.map(&:name)   # => [:archive]
ArchiveLog.run.code      # => :invalid_input
```

`Action.steps` is the ordered set of step objects, and `success_hooks`, `failure_hooks`, `skip_hooks` and
`always_hooks` are the four hook lists. An action with no `input` block is free-form: `.run(*args, **kwargs)` hands
both to `new`, and the default constructor ignores them.

<!-- doctest -->
```ruby
require 'actionable'

class Hail < Actionable::Action
  def initialize(name)
    super()
    @name = name
  end

  step :greet

  private

  def greet = succeed("ahoy #{@name}")
end

Hail.run('Ana').message   # => "ahoy Ana"
Actionable::Action.run.success?   # => true
```

Subclasses copy everything at the moment they are created: steps, hooks, schemas, declarations, `measure` and
`typed_outcomes`. Later changes to the parent do not reach them, and redeclaring a step in a subclass changes only the
subclass, in place. There is no way to remove an inherited step, so guard it off with `if:` or `unless:`.

## Control flow

| Verb | Records | Returns |
|---|---|---|
| `succeed(message = nil, **output)` | `Success` | `true` |
| `fail(code, message = nil, **errors)` | `Failure` | `false` |
| `skip(code = :skipped, message = nil, **output)` | `Skipped` | `false` |
| `fail_with(source, code: :invalid, message: nil, output: nil)` | `Failure` with `source.errors` | `false` |
| `succeed!`, `fail!`, `skip!`, `fail_with!` | the same, then `halt!` | never |
| `halt!` | nothing | never |

Plain verbs record and keep going, and the last record wins. Bang verbs record and stop the main steps (hooks still
run). With no record at all the run auto-succeeds. All verbs are private, and `result` and `input` are public readers.

<!-- doctest -->
```ruby
require 'actionable'

class Recover < Actionable::Action
  step :first
  step :second

  private

  def first = fail(:adrift)

  def second = succeed('recovered')
end

Recover.run.success?    # => true
Recover.run.message     # => "recovered"
```

The keywords after `fail`'s message are all errors, each `field => message` or `field => [messages]`. Nothing is
reserved for metadata, so `fail!(:x, nil, kind: 'is not valid')` gives `errors[:kind]`. Values are turned into Strings.

<!-- doctest -->
```ruby
require 'actionable'

class Reject < Actionable::Action
  step :sail

  private

  def sail = fail!(:rejected, 'cannot ship', mooring: ['is missing', 'is too short'])
end

result = Reject.run
result.errors.to_h   # => {mooring: ["is missing", "is too short"]}
result.message       # => "cannot ship"
```

`fail_with(source, ...)` copies `source.errors` from any FieldStruct. It is the way to turn a side struct's
validation into a failure.

<!-- doctest -->
```ruby
require 'actionable'

class Mooring < FieldStruct::Base
  required :port, :string
end

class Hoist < Actionable::Action
  step :check

  private

  def check
    fail_with!(Mooring.new, code: :bad_mooring)
  end
end

Hoist.run.errors.to_h   # => {port: ["is required"]}
```

Codes must be identifiers (`/\A[[:alpha:]_][[:alnum:]_]*[?!]?\z/`). A sentence raises `ArgumentError` at the call,
because `fail 'pass expired'` is a `Kernel#fail` habit and recording it as a code would be a trap. Inside an action
`fail` records a failure, it is not `Kernel#fail`: to raise an exception, use `raise`. `Actionable.catch_halt` is the
`catch` the runner uses, and `Actionable::HALT` (`:actionable_halt`) is the tag `halt!` throws.

### The verb must be last

A plain verb that has more code after it in the same method still lets that code run, which is almost always a missing
bang. The first `.run` of a class reads its step and hook methods with Prism and raises `Actionable::DefinitionError`
naming each offense, once per class. A verb is fine when it is the last statement, the last statement of a branch whose
construct is last, returned, or followed by `ensure`.

```ruby
def charge
  fail(:declined) if pass.declined?   # offense: capture still runs
  capture
end

def charge
  fail!(:declined) if pass.declined?  # good
  capture
end
```

`Actionable.verb_position_check = false` turns the check off for the process (the RuboCop cop is then the only guard),
and `Actionable.verb_position_check?` reads it. `Actionable::VerbPosition.prism?` says whether the analyzer can run. The
cop `Actionable/VerbNotLast` reports the same offenses in your editor:

```yaml
plugins:
  - actionable-rb:
      require_path: actionable/rubocop
```

## Results

`Actionable::Result` is abstract, and `Success`, `Failure` and `Skipped` are FieldStruct classes with `code`,
`message`, `output` and `history` (and `metadata` on failures and skips). `errors` is FieldStruct's own collection.

<!-- doctest -->
```ruby
require 'actionable'

failure = Actionable::Failure.new(code: :adrift)
failure.failure?     # => true
failure.failed?      # => true
failure.ok?          # => false
failure.status       # => :failure
Actionable::Success.new.successful?   # => true
Actionable::Skipped.new.skipped?      # => true
Actionable::Skipped.new.ok?           # => true
Actionable::Success.new.code          # => :success
failure.to_h.keys    # => [:code, :message, :output, :history, :errors, :metadata]
failure.to_api_h(index: 2)   # => {index: 2, status: :failure, id: nil, errors: {}}
failure.inspect      # => "#<Actionable::Failure code=:adrift errors={} history=[] message=nil metadata={} output={}>"
```

A declared output field is readable off the result, and `output_fields_set` lists the fields a run actually set (it is
`nil` for a hand-built result). `Failure#absorb_errors_from(source)` copies errors and returns the failure. Results
compare by exact class and attributes, and pattern matching works (`in Actionable::Failure(code:)`).

<!-- doctest -->
```ruby
require 'actionable'

class Count < Actionable::Action
  output { required :fare, :integer }
  step :count

  private

  def count = @fare = '41'.to_i + 1
end

result = Count.run
result.fare                 # => 42
result.output_fields_set     # => [:fare]

case result
in Actionable::Success(code:)
  code   # => :success
end
```

## Input

`input { ... }` takes a FieldStruct body. `.run(**kwargs)` builds it (string keys work), and the steps read it as
`input`. Unknown keywords are dropped, unless the schema says `unknown_attributes :raise`, which makes `.run` itself
raise. Reading `input` or `input_schema` on an action without one gives `nil`.

<!-- doctest -->
```ruby
require 'actionable'

class Moor < Actionable::Action
  input do
    required :pence, :integer
    optional :note, :string
  end

  step :sail

  private

  def sail = succeed("paid #{input.pence}")
end

Moor.run(pence: '1200').message   # => "paid 1200"
bad = Moor.run(note: 'x')
bad.code                         # => :invalid_input
bad.message                      # => "input failed validation"
bad.errors.to_h                  # => {pence: ["is required"]}
Moor.input_schema.attribute_names # => [:pence, :note]
Moor.input.equal?(Moor.input_schema)   # => true
```

A single positional input instance is used as is (`Moor.run(Moor.input.new(pence: 5))`). A positional Hash is silently
ignored, so splat it: `.run(**params)`. An action that overrides `initialize` must accept no required arguments and
call `super`.

`input_for(discriminator)` picks the schema at run time from one keyword. `on` takes a value, an Array of values or a
Regexp, and the first match wins, then `default`. No match is `Failure(:invalid_input)`. When both `input` and
`input_for` are declared, the dispatch decides.

<!-- doctest -->
```ruby
require 'actionable'

class ManifestShape < FieldStruct::Base
  required :tonnage, :integer
end

class CancelShape < FieldStruct::Base
  required :voyage_id, :integer
end

class Record < Actionable::Action
  input_for(:kind) do
    on 'freight', ManifestShape
    on %w[rebate return], CancelShape
  end

  step :sail

  private

  def sail = succeed(input.class.name)
end

Record.run(kind: 'freight', tonnage: 5).message      # => "ManifestShape"
Record.run(kind: 'return', voyage_id: 1).message  # => "CancelShape"
Record.run(kind: 'wat').message                  # => "no input shape for kind \"wat\""

dispatch = Record.input_dispatch
dispatch.discriminator   # => :kind
dispatch.variants        # => ["freight", ["rebate", "return"]]
dispatch.schema_for('rebate')   # => CancelShape
dispatch.schemas         # => [ManifestShape, CancelShape]
dispatch.branches.first  # => ["freight", ManifestShape]
dispatch.default_schema  # => nil
```

`InputDispatch.define(discriminator) { ... }` is what `input_for` calls, and its builder has `on` and `default`.
`Actionable::ValueMatch.matches?(branch_value, value)` is the shared matcher: an Array includes, a Regexp matches the
String form, anything else compares with `==`. A Range never matches a member, so write `(400..499).to_a`.

## Output

Only fields declared in `output` reach the result. After the steps run, each declared field is filled from the
instance variable of the same name (a variable set to `nil` counts as set), `succeed` keywords win over variables, and
the struct is coerced and validated. A struct that is not valid ends the run as `Failure(:invalid_output)` with the
field errors and the invalid struct as `output`, so you can look at it.

<!-- doctest -->
```ruby
require 'actionable'

class Fare < Actionable::Action
  output { required :fare, :integer }
  step :sail

  private

  def sail
    @fare = nil
    @ignored = 'never shown'
  end
end

result = Fare.run
result.code                 # => :invalid_output
result.errors.to_h          # => {fare: ["is required"]}
result.output.valid?        # => false
Fare.output_schema.attribute_names   # => [:fare]
```

Without an output schema the output is whatever `succeed` was given (a Hash, `{}` by default) and fields are not
delegated. A failure or skip captures the declared variables set so far, best effort and never validated.

Field names that clash with a result attribute or any public Result method (`code`, `status`, `ok?`, `to_h`, `result`,
`input`, and so on) raise `Actionable::DefinitionError` at declaration.

## Steps, guards and hooks

`step :name` declares a method step, `step ChildAction` an action step, and `case_step` a case step. Redeclaring the same
step replaces its options in place. Hooks use the same targets and run after the main steps: `on_success`,
`on_failure` and `on_skip` depending on the outcome, and `always` after them.

<!-- doctest -->
```ruby
require 'actionable'

class Announce < Actionable::Action
  step :check
  step :audit, if: :audited?
  step :skipped_step, unless: -> (action) { true }
  on_failure :beacon
  always :close

  attr_reader :log

  def initialize
    super
    @log = []
  end

  private

  def audited? = true

  def check = fail!(:stale)

  def audit = @log << :audit

  def skipped_step = @log << :never

  def beacon = @log << :beacon

  def close = @log << :close
end

Announce.run.code             # => :stale
Announce.failure_hooks.map(&:name)   # => [:beacon]
Announce.always_hooks.map(&:name)    # => [:close]
Announce.success_hooks.size   # => 0
Announce.skip_hooks.size      # => 0
```

The category is picked once from the result at that moment and never re-picked. A bang verb in a hook adopts its result
and stops the rest of that category (`always` still runs), `halt!` keeps the current result and stops the phase, and
`succeed!` in an `on_failure` hook recovers the run. A raised exception propagates immediately and nothing after it
runs, `always` included. `if:` and `unless:` take a method name or a callable that gets the instance, and the guard
method is not covered by the missing-method check.

Before a run, every step, hook and branch method must exist on the instance or `DefinitionError` is raised naming them
(`step :puts` does not pass, since `Kernel` owns `puts`).

## Case steps

`case_step :method do ... end` reads a value from a method and runs the first branch whose value matches. A branch
target is a method name or an action class, and `default` catches the rest. No match is a no-op, and a matched branch
whose guard opts out does not fall through.

<!-- doctest -->
```ruby
require 'actionable'

class Route < Actionable::Action
  input { required :channel, :string }

  case_step :channel do
    on 'callsign', :send_signal
    on %w[sms push], :send_phone
    on(/\Aweb/, :send_web)
    default :send_other
  end

  private

  def channel = input.channel

  def send_signal = succeed('callsign')

  def send_phone = succeed('phone')

  def send_web = succeed('web')

  def send_other = succeed('other')
end

Route.run(channel: 'push').message    # => "phone"
Route.run(channel: 'webhook').message # => "web"
Route.run(channel: 'fax').message     # => "other"
Route.steps.first.kind                # => :case
```

`Steps::Case.define(value_source, **options) { ... }` builds the step, whose `branches` are `[match_value, step]`
pairs and `default_step` the fallback. Step objects have `name`, `kind` (`:method`, `:action` or `:case`) and `options`,
and compare equal when the class and name match. `Steps.build(target, **options)` makes them, and anything that is not
a Symbol, String or Action subclass raises `ArgumentError`.

## Nested actions

`step Child, input: %i[berth], expose: %i[line]` calls `Child.run(berth: @berth)`, passing the parent's instance variable
for each `input:` name, and copies the fields the child actually set back as instance variables (narrowed by `expose:`).
A child failure becomes the parent's failure and halts it: the code, message, errors and metadata are adopted, and the
parent must declare the code if it declares any. A child skip is a non-event for the parent, which keeps going. A
measuring parent attaches the child's history to its step record. See the nested example in the
[README](README.md#composition).

## Declared failures and skips

`fails(code, message = nil, **metadata)` and `skips(...)` announce the codes an action can end with, with a default
message and opaque metadata. Once an action declares any failure it may only fail with declared codes or the gem's
own `:invalid_input` and `:invalid_output`, and the same holds for skips, with no exemptions. The check raises
`DefinitionError` at the call.

<!-- doctest -->
```ruby
require 'actionable'

class Weigh < Actionable::Action
  fails :declined, 'pass declined', retry: false
  fails :gateway_down, retry: true
  skips :already_paid

  step :sail

  private

  def sail = fail!(:declined)
end

result = Weigh.run
result.message    # => "pass declined"
result.metadata   # => {retry: false}
Weigh.declared_failures   # => {declined: {retry: false}, gateway_down: {retry: true}}
Weigh.declared_skips      # => {already_paid: {}}
Weigh.failure_declarations[:declined]   # => {message: "pass declined", metadata: {retry: false}}
Weigh.skip_declarations.keys            # => [:already_paid]
Weigh.allows_failure_code?('declined')  # => true
Weigh.allows_failure_code?(:invalid_input)   # => true
Weigh.allows_failure_code?(:other)      # => false
Weigh.allows_skip_code?(:adrift)          # => false
```

A block on `fails` or `skips` declares that code's output schema (see typed outcomes), read back with
`failure_output_schema(code)` and `skip_output_schema(code)`. Declaring `:invalid_input` or `:invalid_output` attaches
metadata to the failures the gem builds, and a schema block there raises `ArgumentError`. The metadata stays opaque to
the core. The one reader is the job adapter, after an explicit `honor_retry_metadata`.

## Typed outcomes

`typed_outcomes` makes `.run` return the action's own `Success`, `Failure` and `Skipped` classes (constants inside the
action, subclasses of the gem's), and gives every failure and skip code its own output contract. Without a schema a code
carries `{}` as output, and output given to such a code raises `DefinitionError`. `typed_outcomes?` reads the flag and
`typed_outcomes(enabled: false)` turns it off. It is inherited by snapshot.

<!-- doctest -->
```ruby
require 'actionable'

class Disembark < Actionable::Action
  typed_outcomes

  input { required :pence, :integer }
  output { required :ballast, :integer }

  fails(:insufficient) { required :short_by, :integer }

  step :sail

  private

  def sail
    fail!(:insufficient, output: { short_by: 50 }) if input.pence > 100
    @ballast = 100 - input.pence
  end
end

ok = Disembark.run(pence: 30)
ok.class                 # => Disembark::Success
ok.ballast               # => 70

failure = Disembark.run(pence: 150)
failure.class            # => Disembark::Failure
failure.short_by         # => 50
failure.is_a?(Actionable::Failure)   # => true
Disembark.failure_output_schema(:insufficient).attribute_names   # => [:short_by]
```

For a code with a schema, `output:` takes the output on `fail`, `fail!`, `fail_with` and `fail_with!`, with or without
typed outcomes, and the output is built from those keywords only, never from instance variables. A result of a typed
action compares equal only to its own class. A crossed child failure becomes the parent's own failure, judged by the
parent's schema.

## History and measurement

`measure :all` records one `History::Step` per step or hook that ran, `measure :sampled, rate: 0.1` records that
share of runs, and `measure :none` (the default) records nothing, so `history` is `[]`. A measuring run makes the runs
nested inside it measure too. `measure` with no argument reads the mode, and `measure_rate`, `measure_all?`,
`measure_sampled?` and `measure_sample_hit?` are the readers behind it.

<!-- doctest -->
```ruby
require 'actionable'

class Slow < Actionable::Action
  measure :all
  step :one
  on_success :two

  private

  def one = nil

  def two = nil
end

history = Slow.run.history
history.steps.map { |s| [s.section, s.name] }   # => [[:main, :one], [:success, :two]]
history.empty?                                  # => false
history.took.class                              # => Float
history.as_json.first.keys   # => [:section, :name, :started_at, :duration, :code, :history]
history.to_json.class        # => String
Slow.measure                 # => :all
Slow.measure_all?            # => true
Slow.measure_rate            # => nil
Slow.measure_sampled?        # => false
```

`History#<<` appends a step and returns the history, `as_json` is the Array form, and `to_json` goes through Oj. State is
fiber-local, so concurrent runs never interfere. `code` on an entry is set only when the step changed the recorded result.

## Batches and the registry

`Action.run_each(items) { |item| args }` runs the action once per item and returns a `BatchResult`. The block maps an
item to arguments: a Hash is keywords, an Array positionals, anything else one argument. A failure in one item never
touches another.

<!-- doctest -->
```ruby
require 'actionable'

class Double < Actionable::Action
  input { required :n, :integer }
  output { required :doubled, :integer }
  fails :odd

  step :sail

  private

  def sail
    fail!(:odd) if input.n.odd?
    @doubled = input.n * 2
  end
end

batch = Double.run_each([1, 2, 3, 4]) { |n| { n: n } }
batch.size          # => 4
batch.length        # => 4
batch.empty?        # => false
batch.all_ok?       # => false
batch.any_failure?  # => true
batch.partial?      # => true
batch.successes.map(&:doubled)   # => [4, 8]
batch.failures.size              # => 2
batch.skips.size                 # => 0
batch[0].code                    # => :odd
batch[9]                         # => nil
batch.results.size               # => 4
batch.map(&:status)              # => [:failure, :success, :failure, :success]
batch.to_api_h(id_field: :doubled).first   # => {index: 0, status: :failure, id: nil, errors: {}}
```

`Actionable.registry` is a process-wide `Registry` filled when a named subclass is created: `[]` (String or Symbol),
`keys`, `values`, `size`, `empty?`, `each` and `register`. A class named after creation is not registered.

<!-- doctest -->
```ruby
require 'actionable'

class Named < Actionable::Action; end

registry = Actionable.registry
registry[:Named]          # => Named
registry['Named']         # => Named
registry.keys.include?('Named')   # => true
registry.values.include?(Named)   # => true
registry.empty?           # => false
registry.size.positive?   # => true
registry.register(Class.new(Actionable::Action)).equal?(registry)   # => true
registry.each.first.class # => Array
```

## Introspection

`Action.describe` returns a Hash with `name`, `input`, `output`, `steps`, `failures`, `skips`, `hooks`, `measure` and
`transactional`. `describe_text` renders the same as plain text.

<!-- doctest -->
```ruby
require 'actionable'

class Probe < Actionable::Action
  fails :broke, 'it broke'
  step :compute
  always :cleanup

  private

  def compute = nil

  def cleanup = nil
end

Probe.describe.keys.size   # => 9
Probe.describe.keys.first(3)   # => [:name, :input, :output]
Probe.describe[:steps]   # => [{type: :method, name: :compute, options: {}}]
Probe.describe[:hooks][:always]   # => [:cleanup]
puts Probe.describe_text
```

## Guardrails

The first-run verb check is described under [Control flow](#the-verb-must-be-last). The others fire at the call: a bad
code, an undeclared code, output with nowhere to go, a missing step method, and an output field with a reserved name each
raise `DefinitionError` or `ArgumentError` naming the action and the thing. An anonymous class is called `action`.

## Rails

`require 'actionable/rails'` is explicit: it never loads on its own, and `transactional` is a plain `NoMethodError`
without it. It needs ActiveModel, and ActiveRecord for transactions (7.1 or newer) and `after_commit` (7.2 or newer).

```ruby
require 'actionable/rails'

class ImportManifests < Actionable::Action
  transactional model: :voyage        # Voyage.transaction { the whole run, hooks included }
  step :import
  after_commit :notify               # runs once, after the outermost commit, only on success
end

ImportManifests.transaction_config      # => {model: :voyage, options: {}}
ImportManifests.after_commit_hooks      # => the hooks, in order
```

A recorded failure rolls the transaction back, and so does a raised exception (which still propagates). Inside an
already open transaction the action takes its own savepoint unless you pass `requires_new: false`. `after_commit` runs
after the run is over, so it cannot change the result.

`Actionable::ProxyValidator` is an ActiveModel validator over another object:

```ruby
class CrossingRules < Actionable::ProxyValidator
  validates :hull, presence: true
end

rules = CrossingRules.new(voyage)
rules.formatted_errors   # => {hull: ["can't be blank"]}, ready for fail(:invalid, **rules.formatted_errors)
rules.delegate           # => voyage
```

## Jobs

`require 'actionable/job'` needs no queue gem. `Actionable::Job.disposition(result, permanent:, honor_retry:)` answers
`:ack` (success or skip), `:discard` (a failure with a permanent code) or `:retry`. The default permanent codes are
`DEFAULT_PERMANENT_CODES`: `invalid_input`, `invalid_output` and `not_found`.

<!-- doctest -->
```ruby
require 'actionable'
require 'actionable/job'

Actionable::Job.disposition(Actionable::Success.new)                       # => :ack
Actionable::Job.disposition(Actionable::Failure.new(code: :invalid_input)) # => :discard
Actionable::Job.disposition(Actionable::Failure.new(code: :timeout))       # => :retry

flagged = Actionable::Failure.new(code: :invalid_input, metadata: { retry: true })
Actionable::Job.disposition(flagged, honor_retry: true)   # => :retry
Actionable::Job.disposition(flagged)                      # => :discard

class Flaky < Actionable::Action
  honor_retry_metadata
end

Flaky.honor_retry_metadata?   # => true
Actionable::Action.honor_retry_metadata?   # => false
```

Include `Actionable::Job::Mixin` in a Sidekiq or ActiveJob class: `run_actionable(ActionClass, **args)` runs the action,
keeps it in `actionable_result`, and raises `Actionable::Job::RetryableFailure` (it has `result`) when the disposition is
`:retry`. A genuine exception passes through unchanged. Override `actionable_permanent_codes` to change the list. Under
ActiveJob add `retry_on Actionable::Job::RetryableFailure`.

## RSpec

`require 'actionable/rspec'` adds the matcher and the stubs to every example group.

```ruby
require 'actionable/rspec'

RSpec.describe WeighHull do
  it 'declines' do
    expect(WeighHull).to perform_actionable(pass: 'bad').and_fail(:declined, /declined/)
  end

  it 'stubs a child' do
    allow_actionable_failure(Claim, code: :deck_full)
    expect(Embark.run(berth: 'x').code).to eq(:deck_full)
  end
end
```

`perform_actionable(*args, **kwargs)` takes an action class. Bare, it expects a success, and the chains `and_succeed`,
`and_fail(code, message)`, `and_skip(code, message)` and `and_raise(error_class, message)` pick the outcome (messages
match with `===`). Naming a code the action does not declare raises `ArgumentError`, because that spec tests an outcome
that can never happen.

The stubs are `allow_actionable_success`, `allow_actionable_failure` and `allow_actionable_skip` (permit `run`), and
`stub_actionable_success`, `stub_actionable_failure` and `stub_actionable_skip` (also expect it). Each builds a real result, with declared messages and metadata and
the output shaped as a run would shape it. `actionable_success_result`, `actionable_failure_result` and
`actionable_skip_result` build the same results without stubbing.

## Coverage

`require 'actionable/rspec/coverage'` records every real `.run` of a named action as `[name, outcome, code]`. After the
suite it prints which declared outcomes no spec reached.

```ruby
require 'actionable/rspec/coverage'

Actionable::Coverage.baseline = 'spec/coverage_baseline.yml'   # set in CI only
Actionable::Coverage.gem_codes = %i[invalid_input]
Actionable::Coverage.only_observed = true                      # for a local partial run
```

`Coverage.expected_outcomes(action)` lists the keys (`"success"`, `"failure:declined"`, `"skipped:already_paid"`), and
`Coverage.actions` the actions in scope. `Coverage.report!(files:, io:)` builds a `Report` (`rows`, `totals`,
`new_gaps`, `stale`, `passed?`, `baseline_message`, `to_baseline`, `write_baseline`, `to_h`, `to_json`). A baseline
file ratchets by name, so a new gap cannot hide behind a fixed one. `Coverage.write(path)` and `Coverage.read(path)`
handle shard files for parallel suites, and `ACTIONABLE_COVERAGE_FILE` makes the suite hook write one.
The settings are `root`, `include_prefixes`, `exclude_prefixes`, `loader`, `gem_codes`, `only_observed`, `baseline`
and `new_gap_hint`, and `reset_config!` restores the defaults. Recording itself has `observed`, `stubbed`, `record_stub`,
`reset!`, `enable!`, `disable!` and `enabled?`: disabled means recording is a no-op.

## Types with RBS

`Actionable::RBS.generate(Klass)` returns RBS for one named action from its schemas. Keywords of `run` come from the
input, output fields become nullable instance variables so steps type-check, and under typed outcomes you get the
result classes.

<!-- doctest -->
```ruby
require 'actionable'

class Rebate < Actionable::Action
  input { required :voyage_id, :integer }
  output { required :pence, :integer }
  fails :expired
end

puts Actionable::RBS.generate(Rebate)
```

The library's own signatures ship in `sig/`. Run the generator in a rake task and commit the file next to your code.

## Exceptions

| Exception | When |
|---|---|
| `Actionable::Error` | base of everything this gem raises |
| `Actionable::DefinitionError` | a misconfigured action: missing step method, undeclared code, reserved output name, verb position |
| `Actionable::Job::RetryableFailure` | `run_actionable` for a result that should be retried |
| `Actionable::Coverage::BaselineMismatch` | the coverage report differs from its baseline |
| `ArgumentError` | a bad argument: a code that is not an identifier, an unsupported step target, a bad `measure` mode |
| `FieldStruct::UnknownAttributeError` | input with `unknown_attributes :raise` and an extra keyword |

A genuine exception raised in a step, hook or guard leaves `.run` untouched. The runner never rescues one.

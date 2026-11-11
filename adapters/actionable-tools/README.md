# actionable-tools

Let an LLM call an [actionable-rb](../../gems/actionable) action as a tool. The action you already wrote (typed input,
validations, declared failures and skips) becomes the tool. You add a description, and you say which input fields your
server fills in (identity, station) instead of the model.

One form-neutral `Definition`, plus two thin wrappers: the MCP Ruby SDK (`mcp`) and RubyLLM (`ruby_llm`). Neither is a
dependency; each is needed only by its own require.

```ruby
gem 'actionable-tools'
gem 'mcp', '~> 1.8'        # for actionable/tools/mcp
gem 'ruby_llm', '~> 2.1'   # for actionable/tools/ruby_llm
```

Version `1.0.0.pre1`. Ruby 3.3 or newer.

## A tool from an action

Nothing is exposed unless you name it. The input schema comes from the action's `input` block, minus the context
fields; the model never sees them and cannot set them.

<!-- doctest -->
```ruby
require 'actionable/tools'

class ReadGauge < Actionable::Action
  input do
    required :code, :string, description: 'Code of the station'
    required :network_id, :integer
  end

  output do
    required :summary, :string
  end

  fails :unknown_station, 'no such station', suggest: 'check the code'

  step :find

  private

  def find
    fail!(:unknown_station) if input.code == '0000'
    @summary = "Station #{input.code} on network #{input.network_id}"
  end
end

tool = Actionable::Tools.definition(ReadGauge,
                                    description: 'Read the latest level at a station',
                                    context: { network_id: ->(source) { source[:network_id] } })

tool.name                                  # => "read_gauge"
tool.input_schema['properties'].keys       # => ["code"]
tool.input_schema['required']              # => ["code"]
tool.call({ 'code' => '1234', 'network_id' => 999 }, { network_id: 3 })['output'] # => {"summary"=>"Station 1234 on network 3"}
```

Every call returns the same six-key Hash, whether the run succeeded, failed or was skipped. A failure carries the
declared code and its metadata. The tool's `output_schema` describes it, including the declared codes.

<!-- doctest -->
```ruby
require 'actionable/tools'

class ConvertDepth < Actionable::Action
  input do
    required :fathoms, :float
    required :to, :string, enum: %w[feet metres]
  end

  fails :beyond_line, 'that is deeper than the sounding line'

  step :convert

  private

  def convert
    fail!(:beyond_line) if input.fathoms > 1000
    succeed(value: input.to == 'feet' ? input.fathoms * 6 : input.fathoms * 1.8288)
  end
end

tool = Actionable::Tools.definition(ConvertDepth, description: 'Convert a sounding depth')

tool.call({ 'fathoms' => 100.0, 'to' => 'feet' })['output'] # => {"value"=>600.0}
bad = tool.call({ 'fathoms' => 5000.0, 'to' => 'feet' })
bad.keys                              # => ["status", "code", "message", "output", "errors", "metadata"]
[bad['status'], bad['code']]          # => ["failure", "beyond_line"]
tool.error?(bad)                      # => true
tool.output_schema['properties']['code']['description'] # => "\"success\", or why the run failed or was skipped. Declared failures: beyond_line. \"invalid_input\" means the arguments were rejected; see errors."
```

Bad input is a failure too (`invalid_input`, with `errors`). An exception the action raises is not a result: it
propagates.

## MCP

<!-- doctest -->
```ruby
require 'actionable/tools/mcp'

class FathomsToFeet < Actionable::Action
  input do
    required :fathoms, :float
    required :operator_id, :integer
  end

  step :convert

  private

  def convert = succeed(feet: input.fathoms * 6)
end

tool = Actionable::Tools::MCP.tool(FathomsToFeet,
                                   description: 'Fathoms to feet',
                                   context: { operator_id: ->(server_context) { server_context[:operator_id] } },
                                   annotations: { read_only: true })
server = MCP::Server.new(name: 'harbour', tools: [tool], server_context: { operator_id: 7 })

request = { jsonrpc: '2.0', id: 1, method: 'tools/call', params: { name: 'fathoms_to_feet', arguments: { fathoms: 100.0 } } }
reply = server.handle(request)
reply[:result][:isError]                      # => false
reply[:result][:structuredContent]['output']  # => {"feet"=>600.0}
tool.to_h[:annotations]                       # => {destructiveHint: true, idempotentHint: false, openWorldHint: true, readOnlyHint: true}
```

`annotations:` takes `read_only`, `destructive`, `idempotent` and `open_world`; any other key raises when the tool is
built. A failure sets `isError`; a skip does not. The same JSON is in `content` and in `structuredContent`. Wrong-typed
arguments (a number for a decimal, which the schema calls a string) are rejected by the SDK before the action runs.
`examples/stdio_server.rb` is a complete stdio server.

## RubyLLM

The class you get is a `RubyLLM::Tool`; construct it with the object your context procs read (the current operator, say).

<!-- doctest -->
```ruby
require 'actionable/tools/ruby_llm'

class FathomsToFeet < Actionable::Action
  input do
    required :fathoms, :float
    required :operator_id, :integer
  end

  step :convert

  private

  def convert = succeed(feet: input.fathoms * 6)
end

Surveyor = Struct.new(:id)
Tool = Actionable::Tools::RubyLLM.tool(FathomsToFeet,
                                       description: 'Fathoms to feet',
                                       context: { operator_id: ->(surveyor) { surveyor.id } },
                                       approval: true)

tool = Tool.new(Surveyor.new(7))
tool.name                             # => "fathoms_to_feet"
tool.requires_approval?               # => true
tool.call(fathoms: 100.0)['output']   # => {"feet"=>600.0}
```

The tool returns the envelope Hash, and a failure is returned, not raised. `RubyLLM` ignores `annotations:`.

## What is and is not covered

- Actions with a discriminated input (`input_for`) and actions without an `input` block raise `ArgumentError`.
- A descriptive text is required until actions can describe themselves.
- A `big_decimal` is a string in the schema (`"12.50"`); ranges (`in:`) are not in the schema, but the action still
  enforces them.
- Output is checked against the schema only on success.
- Nothing here rescues the action, authenticates, streams or exposes resources.

Signatures are in `sig/`; the library names mcp and ruby_llm return are typed `Class`.

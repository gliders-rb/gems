---
title: "Actions as LLM and MCP tools"
description: "Offer an action to a language model as a tool, with context fields the model never fills in and a single result shape for every outcome."
sidebar:
  badge:
    text: Preview
    variant: caution
  label: "LLM and MCP tools"
  order: 6
---

:::caution[Preview]
`actionable-tools` sits at `1.0.0.pre1`. Its spec settles the behaviour, though no release has gone out yet.
:::

With `actionable-tools`, a language model can call an action as a tool. The action you already have, typed input, validations and declared failures and skips included, becomes the tool. Two things are left to you: a description, and a list of input fields your server supplies in place of the model, like the current user or tenant.

The gem builds one neutral `Definition` and two thin wrappers, one for the MCP Ruby SDK and one for RubyLLM. Neither library is a dependency, and each is needed only by the require that uses it.

```ruby
gem 'actionable-tools'
gem 'mcp', '~> 1.8'        # for actionable/tools/mcp
gem 'ruby_llm', '~> 2.1'   # for actionable/tools/ruby_llm
```

```ruby
require 'actionable/tools'
```

Only what you name gets exposed. Nothing scans your actions and there is no registry, so each tool is built from one action class.

## The tool of an action

The input schema is derived from the action's `input` block through the [JSON Schema adapter](/adapters/json-schema/), with the context fields taken out. The model never sees a context field, so it can't set one.

```ruby run
require 'actionable/tools'

class LogSounding < Actionable::Action
  input do
    required :gauge_code, :string, description: 'Stamped code of the tide gauge'
    required :region_id, :integer
  end

  output do
    required :entry, :string
  end

  fails :unknown_gauge, 'no such gauge', suggest: 'read the code off the housing'
  skips :already_logged

  step :record

  private

  def record
    skip!(:already_logged) if input.gauge_code == '7777'
    fail!(:unknown_gauge) if input.gauge_code == '0000'
    @entry = "Gauge #{input.gauge_code} sounded in region #{input.region_id}"
  end
end

tool = Actionable::Tools.definition(
  LogSounding,
  description: 'Log a sounding from a tide gauge',
  context: { region_id: ->(source) { source[:region_id] } }
)

tool.name                                # => "log_sounding"
tool.input_schema['properties'].keys     # => ["gauge_code"]
tool.input_schema['required']            # => ["gauge_code"]
```

`description:` is mandatory, since the model picks tools by reading it. `context:` maps every hidden input field to a proc, and the proc receives whatever your server passes as the call's source: a session, a token claim, an MCP server context.

## Context fields come from the server

```ruby run
reply = tool.call({ 'gauge_code' => '4821' }, { region_id: 3 })
reply['output']   # => {"entry"=>"Gauge 4821 sounded in region 3"}

sneaky = tool.call({ 'gauge_code' => '4821', 'region_id' => 999 }, { region_id: 3 })
sneaky['output']  # => {"entry"=>"Gauge 4821 sounded in region 3"}
```

The model tried to pass `region_id: 999` and got ignored, because that value only ever comes from the context proc. If a context field names something the action doesn't have, building the tool raises `ArgumentError`.

Arguments still pass through `LogSounding.run`, so coercion and validation happen exactly as before. The schema only advises the model, and the action stays in charge.

## One result shape

Success, failure or skip, every call hands back the same Hash with six keys, in this order.

```ruby run
ok = tool.call({ 'gauge_code' => '4821' }, { region_id: 3 })
ok.keys                             # => ["status", "code", "message", "output", "errors", "metadata"]
[ok['status'], ok['code']]          # => ["success", "success"]

missing = tool.call({ 'gauge_code' => '0000' }, { region_id: 3 })
[missing['status'], missing['code']]   # => ["failure", "unknown_gauge"]
missing['message']                     # => "no such gauge"
missing['metadata']                    # => {"suggest"=>"read the code off the housing"}

logged = tool.call({ 'gauge_code' => '7777' }, { region_id: 3 })
[logged['status'], logged['code']]     # => ["skipped", "already_logged"]
```

A failure brings its declared code and metadata along, so the model can act on `suggest: 'read the code off the housing'` and try again. The tool's `output_schema` describes the whole envelope, declared codes included, which tells the model what `unknown_gauge` might mean.

Invalid input fails too, with the code `invalid_input` and the field errors.

```ruby run
bad = tool.call({}, { region_id: 3 })
[bad['status'], bad['code']]   # => ["failure", "invalid_input"]
bad['errors']                  # => {"gauge_code"=>["is required"]}
```

## A failure is an error and a skip is not

`error?` answers true only for a failure. A skip says there was nothing to do, and that is a fine thing to tell a model.

```ruby run
tool.error?(missing)   # => true
tool.error?(logged)    # => false
tool.error?(ok)        # => false
```

An exception raised inside the action is not a result. It propagates, since this gem rescues nothing from the action, and your server decides how to report the bug.

## MCP

`Actionable::Tools::MCP.tool` builds an `MCP::Tool` class for the MCP Ruby SDK. The server context plays the role of the call source.

```ruby run
require 'actionable/tools/mcp'

class ToFathoms < Actionable::Action
  input do
    required :feet, :float
    required :region_id, :integer
  end

  step :convert

  private

  def convert = succeed(fathoms: input.feet / 6)
end

mcp_tool = Actionable::Tools::MCP.tool(
  ToFathoms,
  description: 'Feet of depth to fathoms',
  context: { region_id: ->(server_context) { server_context[:region_id] } },
  annotations: { read_only: true }
)
server = MCP::Server.new(name: 'depths', tools: [mcp_tool], server_context: { region_id: 7 })

request = { jsonrpc: '2.0', id: 1, method: 'tools/call',
            params: { name: 'to_fathoms', arguments: { feet: 12.0 } } }
response = server.handle(request)

response[:result][:isError]                      # => false
response[:result][:structuredContent]['output']  # => {"fathoms"=>2.0}
mcp_tool.to_h[:annotations]                      # => {destructiveHint: true, idempotentHint: false, openWorldHint: true, readOnlyHint: true}
```

The example drives the server object in-process, so no process starts and no client connects.

- `annotations:` accepts `read_only`, `destructive`, `idempotent` and `open_world`. Any other key raises while the tool is built.
- `isError` is set by a failure and not by a skip.
- `content` and `structuredContent` hold the same JSON.
- Arguments of the wrong type are rejected by the SDK before the action runs, for example a number sent for a decimal, which the schema calls a string.

For a complete stdio server, see the gem's `examples/stdio_server.rb`.

## RubyLLM

`Actionable::Tools::RubyLLM.tool` returns a `RubyLLM::Tool` subclass. Construct it with the object your context procs read, like the current user.

```ruby run
require 'actionable/tools/ruby_llm'

Surveyor = Struct.new(:id)

LlmTool = Actionable::Tools::RubyLLM.tool(
  ToFathoms,
  description: 'Feet of depth to fathoms',
  context: { region_id: ->(surveyor) { surveyor.id } },
  approval: true
)

llm_tool = LlmTool.new(Surveyor.new(7))
llm_tool.name                            # => "to_fathoms"
llm_tool.requires_approval?              # => true
llm_tool.call(feet: 12.0)['output']      # => {"fathoms"=>2.0}
```

What comes back is the envelope Hash, and a failure is returned rather than raised. RubyLLM ignores `annotations:`. No model is involved, so the example stays inside the process.

## What is and isn't covered

- An action with a discriminated input (`input_for`), or with no `input` block, raises `ArgumentError`.
- A description stays mandatory until actions can describe themselves.
- A `big_decimal` appears in the schema as a string like `"12.50"`. An `in:` range does not appear, but the action still enforces it.
- Output is checked against the schema on success only.
- Authentication, streaming and resources are not part of it. Those belong to your server.

## See also

- [JSON Schema](/adapters/json-schema/): where the input schema comes from
- [Declare and handle outcomes](/how-to/handle-action-outcomes/): the codes a model reads
- [How adapters work](/adapters/how-adapters-work/)

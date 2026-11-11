# frozen_string_literal: true

# A complete MCP server over stdio exposing one action as a tool.
#
#   ruby examples/stdio_server.rb
#
# The server fills +operator_id+ itself (here always 7); the model never sees that field.
require 'bundler/setup' if ENV['BUNDLE_GEMFILE']
require 'actionable/tools/mcp'

# Ask a tide station for a sounding window.
class RequestSounding < Actionable::Action
  input do
    required :station, :string, description: 'Code of the station'
    required :hours, :integer, in: 1..4
    required :operator_id, :integer
  end

  output do
    required :ticket_id, :string
    required :window_hours, :integer
  end

  fails :station_offline, 'the station is offline', retry: true

  step :check
  step :lend

  private

  def check
    fail!(:station_offline) if input.station == 'st-00'
  end

  def lend
    @ticket_id = "snd_#{input.operator_id}_#{input.station}"
    @window_hours = input.hours
  end
end

tool = Actionable::Tools::MCP.tool(
  RequestSounding,
  description: 'Request a sounding window of a few hours',
  context: { operator_id: ->(_server_context) { 7 } },
  annotations: { destructive: true, idempotent: false }
)

server = MCP::Server.new(name: 'tides', tools: [tool])
MCP::Server::Transports::StdioTransport.new(server).open

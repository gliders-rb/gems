# frozen_string_literal: true

require 'open3'

# AT-B34: drives examples/stdio_server.rb as a client would, over a pipe.
RSpec.describe 'examples/stdio_server.rb' do
  let(:root) { File.expand_path('..', __dir__) }

  def exchange(messages)
    script = File.join(root, 'examples', 'stdio_server.rb')
    input = messages.map { |message| Oj.dump(message, mode: :compat) }.join("\n") << "\n"
    out, err, status = Open3.capture3(RbConfig.ruby, '-I', File.join(root, 'lib'), script, stdin_data: input, chdir: root)
    expect(status).to be_success, err
    out.lines.map { |line| Oj.load(line, mode: :compat) }.to_h { |reply| [reply['id'], reply] }
  end

  def request(id, method, params = {})
    { 'jsonrpc' => '2.0', 'id' => id, 'method' => method, 'params' => params }
  end

  it 'AT-B34: lists the tool, runs a success and a declared failure' do
    replies = exchange([
                         request(1, 'initialize', { 'protocolVersion' => '2025-06-18', 'capabilities' => {},
                                                    'clientInfo' => { 'name' => 'spec', 'version' => '1' } }),
                         { 'jsonrpc' => '2.0', 'method' => 'notifications/initialized' },
                         request(2, 'tools/list'),
                         request(3, 'tools/call', { 'name' => 'request_sounding', 'arguments' => { 'station' => 'st-14', 'hours' => 2 } }),
                         request(4, 'tools/call', { 'name' => 'request_sounding', 'arguments' => { 'station' => 'st-00', 'hours' => 2 } })
                       ])
    tool = replies[2]['result']['tools'].first
    expect(tool['name']).to eq('request_sounding')
    expect(tool['inputSchema']['required']).to eq(%w[station hours])
    expect(tool['annotations']).to include('destructiveHint' => true, 'idempotentHint' => false)
    success = replies[3]['result']
    expect(success['isError']).to be(false)
    expect(success['structuredContent']['output']).to eq('ticket_id' => 'snd_7_st-14', 'window_hours' => 2)
    failure = replies[4]['result']
    expect(failure['isError']).to be(true)
    expect(failure['structuredContent']).to include('code' => 'station_offline', 'metadata' => { 'retry' => true })
  end
end

# frozen_string_literal: true

require 'open3'
require 'rbconfig'

RSpec.describe 'benchmarks' do
  it 'AC-B#bench: run.rb is a dependency-free script that times each case and honours BENCH_ITERATIONS' do
    root = File.expand_path('..', __dir__)
    out, err, status = Open3.capture3({ 'BENCH_ITERATIONS' => '5' }, RbConfig.ruby, '-I', File.join(root, '..', 'field_struct/lib'),
                                      File.join(root, 'benchmarks/run.rb'))
    expect(status).to be_success, err
    expect(out).to include('5 iterations')
    ['trivial run', '5 steps, measure :none', '5 steps, measure :all', '5-field input coercion', 'nested action',
     'nested action, measured', 'history.to_json', 'fail! action', 'skip! action'].each do |label|
      expect(out).to include(label)
    end
    expect(File.read(File.join(root, 'benchmarks/run.rb'))).to include('CLOCK_MONOTONIC')
  end
end

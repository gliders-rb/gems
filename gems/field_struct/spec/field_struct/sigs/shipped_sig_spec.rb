# frozen_string_literal: true

require 'open3'

RSpec.describe 'the shipped signature' do
  root = File.expand_path('../../..', __dir__)

  it 'loads as a library on its own: sig/manifest.yaml names the standard libraries it refers to' do
    output, status = Open3.capture2e('bundle', 'exec', 'rbs', '--no-collection', '-r', 'field_struct', 'validate', chdir: root)
    expect(status).to be_success, output
  end
end

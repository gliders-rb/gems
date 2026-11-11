# frozen_string_literal: true

RSpec.describe 'actionable-rb.gemspec' do
  let(:root) { File.expand_path('..', __dir__) }
  let(:spec) { Gem::Specification.load(File.join(root, 'actionable-rb.gemspec')) }

  it 'AC-B#gemshape: is named actionable-rb, MIT, needs Ruby 3.3 and asks for MFA' do
    expect(spec.name).to eq('actionable-rb')
    expect(spec.licenses).to eq(['MIT'])
    expect(spec.required_ruby_version).to eq(Gem::Requirement.new('>= 3.3.0'))
    expect(spec.metadata['rubygems_mfa_required']).to eq('true')
    expect(spec.version.to_s).to eq(Actionable::VERSION)
    expect(spec.authors).to eq(['Adrian Madrid'])
  end

  it 'AC-B#gemshape: depends on field_struct, oj >= 3.0 and prism >= 1.0, and nothing from Rails' do
    deps = spec.runtime_dependencies.to_h { |dep| [dep.name, dep.requirement.to_s] }
    expect(deps).to eq('field_struct' => '>= 1.0.0.pre1', 'oj' => '>= 3.0', 'prism' => '>= 1.0')
  end

  it 'AC-B#gemshape: lib/actionable-rb.rb just requires actionable' do
    expect(File.read(File.join(root, 'lib/actionable-rb.rb')).lines.grep_v(/\A(#|\s*$)/).map(&:strip)).to eq(["require 'actionable'"])
  end

  it 'AC-B#gemshape: ships the library, signatures, docs, skill and licence' do
    files = spec.files
    expect(files).to include('lib/actionable.rb', 'lib/actionable-rb.rb', 'lib/actionable/rubocop/config.yml',
                             'sig/actionable.rbs', 'sig/actionable_blocks.rbs', 'sig/actionable_adapters.rbs',
                             'README.md', 'USAGE.md', 'CHANGELOG.md', 'AGENTS.md', 'LICENSE.txt',
                             'docs/getting_started.md', 'skills/actionable/SKILL.md',
                             '.claude-plugin/plugin.json', '.claude-plugin/marketplace.json')
  end

  it 'AC-B#gemshape: leaves out specs, benchmarks, CI, tooling, lint and type config' do
    forbidden = %r{\A(spec/|support/|rakelib/|benchmarks/|gemfiles/|\.github/|\.rubocop|\.rspec|\.yardopts)}
    config = /\A(Gemfile|Rakefile|Steepfile|rbs_collection)/
    expect(spec.files.grep(forbidden) + spec.files.grep(config)).to be_empty
  end

  it 'AC-B#gemshape: ships every file it lists' do
    expect(spec.files.reject { |path| File.file?(File.join(root, path)) }).to be_empty
  end
end

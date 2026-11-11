# frozen_string_literal: true

RSpec.describe 'field_struct.gemspec' do
  let(:spec) { Gem::Specification.load(FieldStruct.root.join('field_struct.gemspec').to_s) }

  it 'is MIT licensed, needs Ruby 3.3 and asks for MFA on publish' do
    expect(spec.licenses).to eq(['MIT'])
    expect(spec.required_ruby_version).to eq(Gem::Requirement.new('>= 3.3'))
    expect(spec.metadata['rubygems_mfa_required']).to eq('true')
    expect(spec.version.to_s).to eq(FieldStruct::VERSION)
  end

  it 'declares oj, bigdecimal and tzinfo ~> 2.0, and nothing from Rails' do
    deps = spec.runtime_dependencies.to_h { |dep| [dep.name, dep.requirement.to_s] }
    expect(deps).to eq('bigdecimal' => '>= 3.0', 'oj' => '>= 3.11.2', 'tzinfo' => '~> 2.0')
  end

  it 'ships the library, signatures, docs and agent assets' do
    files = spec.files
    expect(files).to include('lib/field_struct.rb', 'sig/field_struct.rbs', 'README.md', 'USAGE.md', 'CHANGELOG.md', 'LICENSE.txt')
    expect(files).to include('AGENTS.md', 'docs/getting_started.md', 'skills/field-struct/SKILL.md')
    expect(files).to include('.claude-plugin/plugin.json', '.claude-plugin/marketplace.json')
  end

  it 'leaves out specs, tooling, benchmarks, CI and lint config' do
    forbidden = %r{\A(spec/|support/|rakelib/|benchmarks/|gemfiles/|\.github/|\.rubocop|\.rspec|Gemfile|Rakefile)}
    forbidden_config = /\A(Steepfile|rbs_collection|\.yardopts)/
    expect(spec.files.grep(forbidden_config)).to be_empty
    expect(spec.files.grep(forbidden)).to be_empty
  end

  it 'ships every file it lists' do
    missing = spec.files.reject { |path| FieldStruct.root.join(path).file? }
    expect(missing).to be_empty
  end
end

# frozen_string_literal: true

RSpec.describe 'gemspec' do
  let(:spec) { Gem::Specification.load(File.expand_path('../actionable-otel.gemspec', __dir__)) }
  let(:deps) { spec.runtime_dependencies.to_h { |d| [d.name, d.requirement] } }

  it 'OT-B30: depends on opentelemetry-api ~> 1.7 and rejects 1.6.0' do
    requirement = deps.fetch('opentelemetry-api')
    expect(requirement).to eq(Gem::Requirement.new('~> 1.7'))
    expect(requirement).not_to be_satisfied_by(Gem::Version.new('1.6.0'))
    expect(requirement).to be_satisfied_by(Gem::Version.new('1.7.0'))
  end

  it 'OT-I4: actionable-rb is bounded >= 2.0.0.pre1, < 3' do
    requirement = deps.fetch('actionable-rb')
    expect(requirement.requirements.map { |op, v| [op, v.to_s] }).to contain_exactly(['>=', '2.0.0.pre1'], ['<', '3'])
    expect(requirement).not_to be_satisfied_by(Gem::Version.new('3.0.0'))
  end

  it 'OT-I2: the SDK is not a runtime dependency' do
    expect(deps.keys).to contain_exactly('actionable-rb', 'opentelemetry-api')
  end

  it 'ships only lib, sig, README, CHANGELOG and LICENSE' do
    expect(spec.files).to all(match(%r{\A(lib/.*\.rb|sig/.*\.rbs|README\.md|CHANGELOG\.md|LICENSE\.txt)\z}))
    expect([spec.version.to_s, spec.metadata['rubygems_mfa_required']]).to eq(['1.0.0.pre1', 'true'])
  end
end

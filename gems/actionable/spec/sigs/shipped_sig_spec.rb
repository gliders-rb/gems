# frozen_string_literal: true

require 'open3'
require 'rbs'
require 'tmpdir'

RSpec.describe 'shipped signatures' do
  root = File.expand_path('../..', __dir__)
  libraries = %w[date time bigdecimal pathname pp field_struct].flat_map { |name| ['-r', name] }

  it 'AC-B#rbsshipped: ships the generated sig and the two hand-written files' do
    %w[actionable.rbs actionable_blocks.rbs actionable_adapters.rbs].each do |name|
      expect(File.file?(File.join(root, 'sig', name))).to be(true), name
    end
  end

  it 'AC-B#rbsshipped: declares block-self overloads for the DSL methods that evaluate their block elsewhere' do
    text = File.read(File.join(root, 'sig/actionable_blocks.rbs'))
    %w[output input fails skips case_step input_for].each do |name|
      expect(text).to match(/def (self\.)?#{name}: .*\[self: /), name
    end
    expect(text.scan('def self.define').size).to eq(2)
  end

  it 'AC-B#rbsshipped: declares the AfterCommit extension even though the adapter may not be loaded' do
    expect(File.read(File.join(root, 'sig/actionable_adapters.rbs'))).to include('extend Actionable::Rails::AfterCommit')
  end

  it 'AC-B#rbsshipped: the block overloads merge with the generated ones' do
    loader = RBS::EnvironmentLoader.new
    %w[date time bigdecimal pathname pp field_struct].each { |name| loader.add(library: name) }
    loader.add(path: Pathname(File.join(root, 'sig')))
    loader.add(path: Pathname(File.join(root, 'support/external')))
    env = RBS::Environment.from_loader(loader).resolve_type_names
    definition = RBS::DefinitionBuilder.new(env: env).build_singleton(RBS::TypeName.parse('::Actionable::Action'))
    expect(definition.methods[:output].method_types.size).to eq(2)
    expect(definition.methods).to include(:after_commit, :transactional, :honor_retry_metadata, :step, :run)
  end

  it 'AC-B#rbsshipped: generated RBS for user actions is valid next to the gem signature' do
    stub_const('Terminal', Module.new)
    stub_const('Terminal::Base', Class.new(Actionable::Action) { typed_outcomes })
    stub_const('Terminal::Embark', Class.new(Terminal::Base) do
      input do
        required :callsign, :string
        optional :note, :string
      end
      output do
        required :fare, :integer
        optional :memo, :string
      end
      fails(:deck_full) { required :berth, :string }
      fails :declined
      skips(:already_paid) { optional :memo, :string }
    end)
    stub_const('Terminal::Plain', Class.new(Actionable::Action) { output { required :id, :integer } })

    Dir.mktmpdir do |dir|
      File.write(File.join(dir, 'actions.rbs'), [Terminal::Embark, Terminal::Plain].map { |k| Actionable::RBS.generate(k) }.join("\n"))
      output, status = Open3.capture2e('bundle', 'exec', 'rbs', '--no-collection', *libraries, '-I', File.join(root, 'sig'),
                                       '-I', File.join(root, 'support/external'), '-I', dir, 'validate', chdir: root)
      expect(status).to be_success, output
    end
  end
end

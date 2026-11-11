# frozen_string_literal: true

require 'tmpdir'
require_relative '../../../support/sig_guards'

RSpec.describe SigGuards do
  def write(dir, name, text)
    File.join(dir, name).tap { |path| File.write(path, text) }
  end

  describe '.count_untyped' do
    it 'counts the word outside comments, across files' do
      Dir.mktmpdir do |dir|
        a = write(dir, 'a.rbs', "# untyped in a comment\nclass A\n  def x: (untyped a) -> untyped\n    # untyped again\nend\n")
        b = write(dir, 'b.rbs', "  Y: untyped\n  Z: untypedness\n")
        expect(described_class.count_untyped([a, b])).to eq(3)
        expect(described_class.count_untyped(a)).to eq(2)
      end
    end
  end

  describe '.untyped_failure' do
    it 'is nil when the count equals the ceiling' do
      expect(described_class.untyped_failure(count: 4, ceiling: 4)).to be_nil
    end

    it 'names the new ones when above' do
      message = described_class.untyped_failure(count: 7, ceiling: 4)
      expect(message).to start_with('sig/ has 7 `untyped` (ceiling 4): 3 new.')
    end

    it 'asks to lower the ceiling when below' do
      message = described_class.untyped_failure(count: 2, ceiling: 4)
      expect(message).to start_with('sig/ has 2 `untyped` (ceiling 4): 2 fewer.')
      expect(message).to include('Lower the ceiling')
    end
  end

  describe '.sord_warnings' do
    let(:log) do
      <<~LOG
        [INFO ] Running YARD...
        [OMIT ] (A#b) lib/a.rb:12: no YARD return type given, using untyped
        [DUCK ] (A#c) lib/a.rb:30: #to_hash looks like a duck type
        [OMIT ] (A#b) lib/a.rb:99: no YARD return type given, using untyped
        [WARN ] (A#d) lib/a.rb:5: Foo wasn't able to be resolved to a constant in this project
        [DONE ] Processed 3 objects
      LOG
    end

    it 'keeps OMIT and DUCK lines without colour or position, unique and sorted' do
      expect(described_class.sord_warnings(log)).to eq(
        ['[DUCK ] (A#c) #to_hash looks like a duck type', '[OMIT ] (A#b) no YARD return type given, using untyped']
      )
    end

    it 'strips ANSI colour' do
      colored = log.sub('[OMIT ]', "\e[33m[OMIT ]\e[0m")
      expect(described_class.sord_warnings(colored)).to include('[OMIT ] (A#b) no YARD return type given, using untyped')
    end
  end

  describe '.unresolved_names' do
    it 'lists names Sord could not resolve, once each' do
      log = "[WARN ] (A#d) lib/a.rb:5: Foo wasn't able to be resolved to a constant in this project\n" \
            "[WARN ] (A#e) lib/a.rb:6: Bar::Baz wasn't able to be resolved to a constant in this project\n" \
            "[WARN ] (A#f) lib/a.rb:7: Foo wasn't able to be resolved to a constant in this project\n"
      expect(described_class.unresolved_names(log)).to eq(%w[Bar::Baz Foo])
    end
  end

  describe 'allowlist' do
    it 'ignores blank lines and comments' do
      expect(described_class.parse_allowlist("# why\n\n[DUCK ] (A#c) x\n  \n")).to eq(['[DUCK ] (A#c) x'])
    end

    it 'passes when warnings equal the allowlist' do
      expect(described_class.allowlist_failure(warnings: %w[a b], allowlist: %w[b a])).to be_nil
    end

    it 'lists new and stale entries' do
      message = described_class.allowlist_failure(warnings: %w[a c], allowlist: %w[a b])
      expect(message).to include('New Sord warnings', '  c', 'Stale allowlist entries', '  b')
      expect(described_class.allowlist_failure(warnings: %w[a], allowlist: %w[a b])).not_to include('New Sord warnings')
    end
  end

  describe '.fix_enumerable' do
    it 'types the Enumerable include with Field' do
      expect(described_class.fix_enumerable("  class Metadata\n    include Enumerable\n  end\n")).to include('include ::Enumerable[Field]')
    end
  end

  describe 'the committed data files' do
    it 'holds an integer ceiling and a sorted, duplicate-free allowlist' do
      root = File.expand_path('../../../support', __dir__)
      expect(File.read(File.join(root, 'untyped_ceiling.txt')).strip).to match(/\A\d+\z/)
      entries = described_class.parse_allowlist(File.read(File.join(root, 'sord_allowlist.txt')))
      expect(entries).to eq(entries.uniq.sort)
    end
  end
end

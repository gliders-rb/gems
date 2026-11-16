# frozen_string_literal: true

require 'tmpdir'
require_relative '../../support/sig_guards'

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

  describe '.count_loose' do
    it 'counts Object and top used as types, outside comments, across files' do
      Dir.mktmpdir do |dir|
        a = write(dir, 'a.rbs', <<~RBS)
          # Object and top in a comment
          class Kiln < ::Object
            def fire: (::Object load, ?top: Integer) -> Object
            def glaze: (Integer top) -> top
            def stack: () -> ::Array[::Object?]
          end
        RBS
        b = write(dir, 'b.rbs', "  K: BasicObject\n  L: Pottery::Object\n  M: (top | Object)\n")
        expect(described_class.count_loose(a)).to eq(4)
        expect(described_class.count_loose([a, b])).to eq(6)
      end
    end
  end

  describe '.loose_failure' do
    it 'is nil when the count equals the ceiling' do
      expect(described_class.loose_failure(count: 9, ceiling: 9)).to be_nil
    end

    it 'names the new ones when above' do
      message = described_class.loose_failure(count: 11, ceiling: 9)
      expect(message).to start_with('sig/ has 11 `Object`/`top` types (ceiling 9): 2 new.')
    end

    it 'asks to lower the ceiling when below' do
      message = described_class.loose_failure(count: 6, ceiling: 9)
      expect(message).to start_with('sig/ has 6 `Object`/`top` types (ceiling 9): 3 fewer.')
      expect(message).to include('support/loose_ceiling.txt to 6')
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

  describe '.fix_up' do
    it 'AC-B#sigratchet: types the Enumerable include with the element type of the including class' do
      text = "  class Registry\n    include Enumerable\n  end\n  class BatchResult\n    include Enumerable\n  end\n"
      fixed = described_class.fix_up(text)
      expect(fixed).to include('include ::Enumerable[[String, Class]]', 'include ::Enumerable[Actionable::Result]')
    end

    it 'AC-B#sigratchet: gives a Struct subclass its member type' do
      expect(described_class.fix_up("  class Step < Struct\n  end\n")).to include('class Step < ::Struct[::Object]')
    end

    it 'AC-B#rbsshipped: drops the framework parents, so the sig names no optional gem' do
      text = [
        '  class Railtie < ::Rails::Railtie', '  end', '  class RubocopPlugin < LintRoller::Plugin', '  end',
        '  class ProxyValidator', '    include ActiveModel::Validations', '', '    def formatted_errors: () -> void', '  end',
        '      class VerbNotLast < Base', '        MSG: String', '      end'
      ].map { |line| "#{line}\n" }.join
      fixed = described_class.fix_up(text)
      expect(fixed).to include("  class Railtie\n", "  class RubocopPlugin\n", "      class VerbNotLast\n",
                               "  class ProxyValidator\n    def formatted_errors")
      expect(fixed).not_to match(/Rails::Railtie|LintRoller|ActiveModel|< Base/)
    end

    it 'AC-B#rbsshipped: leaves other parents alone' do
      text = "  class Lantern < Actionable::Action\n  end\n  class Wick < Base\n  end\n"
      expect(described_class.fix_up(text)).to eq(text)
    end
  end

  describe '.add_private_verbs' do
    hidden = "  # The verbs.\n  module Verbs\n  end\n\n  class Action\n  end\n"
    full = <<~RBS
      module Verbs
        NO_KEYWORDS: ::Hash[Symbol, Object]

        # Records a Success and continues.
        def succeed: (?String? message, **Object output) -> bool

        # Records a Failure from +source+.
        def fail_with: (
                         Object source,
                         ?code: (Symbol | String)
                       ) -> bool

        def remember: (Object result) -> Object

        def halt!: () -> void
      end
    RBS

    it 'AC-B#verbsprivate: declares the verbs, and only the verbs, as private members of the empty Verbs module' do
      text = described_class.add_private_verbs(hidden, full.gsub(/^/, '  '), verbs: %w[succeed fail_with halt!])
      verbs = text[/^  module Verbs\n.*?^  end\n/m]
      expect(verbs).to include("    # Records a Success and continues.\n    private def succeed: ")
      expect(verbs).to include("    private def succeed: (?String? message, **Object output) -> bool\n")
      expect(verbs).to include('    private def fail_with: (Object source, ?code: (Symbol | String)) -> bool')
      expect(verbs).to include('    private def halt!: () -> void')
      expect(verbs).not_to include('remember', 'NO_KEYWORDS')
      expect(text).to end_with("  end\n\n  class Action\n  end\n")
    end

    it 'fails loudly when a verb is missing from the full output' do
      expect { described_class.add_private_verbs(hidden, "  module Verbs\n  end\n") }.to raise_error(RuntimeError, /succeed/)
    end
  end

  describe 'the committed data files' do
    it 'holds an integer ceiling and a sorted, duplicate-free allowlist' do
      root = File.expand_path('../../support', __dir__)
      expect(File.read(File.join(root, 'untyped_ceiling.txt')).strip).to match(/\A\d+\z/)
      expect(File.read(File.join(root, 'loose_ceiling.txt')).strip).to match(/\A\d+\z/)
      entries = described_class.parse_allowlist(File.read(File.join(root, 'sord_allowlist.txt')))
      expect(entries).to eq(entries.uniq.sort)
    end
  end
end

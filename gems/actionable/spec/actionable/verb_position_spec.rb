# frozen_string_literal: true

require 'tmpdir'
require 'open3'
require 'rbconfig'

RSpec.describe Actionable::VerbPosition do
  # Offenses (verb names) the analyzer finds in the body of one method.
  def verbs_in(body)
    source = "def run_it\n#{body.lines.map { |line| "  #{line}" }.join}\nend\n"
    described_class.offenses_in_source(source).map(&:verb)
  end

  describe '.prism?' do
    it 'AC-B#prism: is true when prism 1.0 or newer loads' do
      expect(described_class.prism?).to be(true)
    end
  end

  describe 'accepted positions (AC-B#verbtail)' do
    {
      'the last statement' => "log\nfail(:x)",
      'a modifier form as the last statement' => 'fail :x if bad?',
      'an unless modifier as the last statement' => 'skip :x unless good?',
      'the last statement of every if branch' => "if a\n  fail(:x)\nelsif b\n  skip(:y)\nelse\n  succeed\nend",
      'a ternary branch' => 'a ? fail(:x) : skip(:y)',
      'the last statement of unless/else' => "unless a\n  fail(:x)\nelse\n  skip(:y)\nend",
      'case/when branches and else' => "case a\nwhen 1 then fail(:x)\nwhen 2\n  skip(:y)\nelse\n  succeed\nend",
      'case/in branches' => "case a\nin 1 then fail(:x)\nin 2\n  skip(:y)\nend",
      'a rescue branch' => "begin\n  work\nrescue StandardError\n  fail(:x)\nend",
      'an ensure branch' => "begin\n  work\nensure\n  succeed\nend",
      'the right side of &&' => 'ok? && fail(:x)',
      'the right side of ||' => 'ok? || skip(:x)',
      'the right side of and/or' => 'ok? and fail(:x)',
      'a returned verb' => "return fail(:x) if bad?\nwork",
      'a verb followed directly by return' => "fail(:x)\nreturn",
      'a verb followed by return inside a branch' => "if bad?\n  fail(:x)\n  return\nend\nwork",
      'a verb followed by an ensure clause' => "begin\n  fail(:x)\nensure\n  cleanup\nend\nmore",
      'the last statement of a block in tail position' => "items.each do |item|\n  fail(:x) if item\nend",
      'a block verb followed by next, owner in tail position' => "items.each do |item|\n  fail(:x)\n  next\nend",
      'a block verb followed by break, owner in tail position' => "items.each do |item|\n  skip(:x)\n  break\nend",
      'the last statement of a loop body in tail position' => "while go?\n  fail(:x) if bad?\nend",
      'a verb on self' => 'self.fail(:x)',
      'a bang verb in the middle' => "fail!(:x)\nmore",
      'a verb on another receiver' => "gateway.fail(:x)\nitems.skip(1)\nmore",
      'a safe-navigated verb' => "gateway&.fail(:x)\nmore",
      'a local variable named like a verb' => "skip = 1\nmore(skip)",
      'a nested verb inside a tail branch of a tail block' => "items.each do |i|\n  if i\n    skip(:a)\n  end\nend",
      'a method wrapped in rescue as its last statement' => "work\nrescue StandardError\n  fail(:x)"
    }.each do |label, body|
      it "AC-B#verbtail: accepts #{label}" do
        expect(verbs_in(body)).to eq([])
      end
    end
  end

  describe 'offenses (AC-B#verboffense)' do
    {
      'a verb followed by more code' => ["fail(:x)\nmore", [:fail]],
      'skip followed by more code' => ["skip(:x)\nmore", [:skip]],
      'succeed followed by more code' => ["succeed\nmore", [:succeed]],
      'fail_with followed by more code' => ["fail_with(obj)\nmore", [:fail_with]],
      'a modifier verb followed by more code' => ["fail :x if bad?\nmore", [:fail]],
      'a branch whose construct is followed by more code' => ["if a\n  fail(:x)\nend\nmore", [:fail]],
      'a case branch followed by more code' => ["case a\nwhen 1 then skip(:x)\nend\nmore", [:skip]],
      'the end of a block whose call is followed by more code' => ["items.each do |i|\n  fail(:x)\nend\nmore", [:fail]],
      'the end of a loop body followed by more code' => ["while go?\n  fail(:x)\nend\nmore", [:fail]],
      'the left side of and' => ['fail(:x) and return', [:fail]],
      'the left side of &&' => ["fail(:x) && more\nmore", [:fail]],
      'a verb nested in a call argument' => ["log(fail(:x))\nmore", [:fail]],
      'a verb nested in an assignment' => ['@ok = fail(:x)', [:fail]],
      'a verb in a begin body that has an else' => ["begin\n  fail(:x)\nrescue StandardError\n  more\nelse\n  other\nend", [:fail]],
      'a verb in the middle of a branch' => ["if a\n  fail(:x)\n  more\nend", [:fail]],
      'a verb in a block followed by next, owner not in tail position' =>
        ["items.each do |i|\n  fail(:x)\n  next\nend\nmore", [:fail]],
      'two offenses in one method' => ["fail(:a)\nskip(:b)\nmore", %i[fail skip]]
    }.each do |label, (body, expected)|
      it "AC-B#verboffense: flags #{label}" do
        expect(verbs_in(body)).to eq(expected)
      end
    end
  end

  describe 'offense positions' do
    it 'AC-B#cop: reports Prism byte offsets, length and line of the call node' do
      source = "def m\n  fail(:x)\n  more\nend\n"
      offense = described_class.offenses_in_source(source).first
      expect(offense.start_offset).to eq(source.index('fail'))
      expect(offense.byte_length).to eq('fail(:x)'.length)
      expect(offense.line).to eq(2)
      expect(offense.verb).to eq(:fail)
      expect(offense.method_name).to eq(:m)
    end

    it 'AC-B#cop: offsets are bytes, so multibyte source differs from character positions' do
      source = "def m\n  log('héllo')\n  fail(:x)\n  more\nend\n"
      offense = described_class.offenses_in_source(source).first
      expect(offense.start_offset).to eq(source.byteindex('fail'))
      expect(offense.start_offset).not_to eq(source.index('fail'))
    end
  end

  describe 'source files' do
    it 'AC-B#verbonce: yields nothing for a file that does not parse cleanly' do
      expect(described_class.offenses_in_source("def m\n  fail(:x\n  more\n")).to eq([])
    end
  end

  describe 'the first-run check' do
    around do |example|
      Actionable.verb_position_check = true
      example.run
    ensure
      Actionable.verb_position_check = false
    end

    def write_action_file(dir, body)
      path = File.join(dir, 'probe_action.rb')
      File.write(path, <<~RUBY)
        class ProbeAction < Actionable::Action
          step :first
          step :second
          private

          def first
        #{body}
          end

          def second = nil
          def more = nil
        end
      RUBY
      path
    end

    around do |example|
      Dir.mktmpdir { |dir| (@dir = dir) && example.run }
      Object.send(:remove_const, :ProbeAction) if Object.const_defined?(:ProbeAction)
    end

    it 'AC-B#verbcheck: raises a DefinitionError naming action, method, file, line and verb' do
      path = write_action_file(@dir, "    fail(:x)\n    more")
      load path
      expected = "ProbeAction#first (#{path}:7) calls `fail` with more code after it, which still runs: " \
                 'use fail! to stop here, or make it the method\'s last expression'
      expect { ProbeAction.run }.to raise_error(Actionable::DefinitionError, "#{expected}\n(see USAGE, Control flow)")
    end

    it 'AC-B#verbcheck: lists every offense of every checked method together' do
      path = File.join(@dir, 'two.rb')
      File.write(path, <<~RUBY)
        class TwoOffenders < Actionable::Action
          step :a
          step :b
          on_success :c
          def a
            skip
            more
          end

          def b
            succeed
            more
          end

          def c
            fail(:late)
            more
          end
        end
      RUBY
      load path
      expect { TwoOffenders.run }.to raise_error(Actionable::DefinitionError) { |error|
        lines = error.message.lines.map(&:chomp)
        expect(lines.size).to eq(4)
        expect(lines[0]).to include('TwoOffenders#a', ':6)', '`skip`')
        expect(lines[1]).to include('TwoOffenders#b', ':11)', '`succeed`')
        expect(lines[2]).to include('TwoOffenders#c', ':16)', '`fail`')
        expect(lines[3]).to eq('(see USAGE, Control flow)')
      }
    ensure
      Object.send(:remove_const, :TwoOffenders) if Object.const_defined?(:TwoOffenders)
    end

    it 'AC-B#verbonce: a failing check is not cached; a fixed file passes, a changed file is re-read' do
      path = write_action_file(@dir, "    fail(:x)\n    more")
      load path
      expect { ProbeAction.run }.to raise_error(Actionable::DefinitionError)
      expect { ProbeAction.run }.to raise_error(Actionable::DefinitionError)
      File.write(path, File.read(path).sub("    more\n", "    nil\n").sub("fail(:x)\n", "fail!(:x)\n"))
      File.utime(Time.now + 60, Time.now + 60, path)
      expect(ProbeAction.run).to be_failure
    end

    it 'AC-B#verbonce: a passing check is cached per class, and a subclass is checked on its own' do
      path = write_action_file(@dir, '    fail!(:x)')
      load path
      expect(ProbeAction.run.code).to eq(:x)
      File.write(path, File.read(path).sub('fail!(:x)', "fail(:x)\n    more"))
      File.utime(Time.now + 120, Time.now + 120, path)
      expect(ProbeAction.run.code).to eq(:x)
      child = Class.new(ProbeAction)
      expect { child.run }.to raise_error(Actionable::DefinitionError, /action#first/)
    end

    it 'AC-B#verbscope: checks case-step branch targets and hooks, never the value source' do
      path = File.join(@dir, 'scoped.rb')
      File.write(path, <<~RUBY)
        class ScopedProbe < Actionable::Action
          case_step :pick do
            on 'a', :branch_a
            default :fallback
          end
          always :cleanup

          def pick
            skip(:ignored)
            'a'
          end

          def branch_a
            fail(:one)
            more
          end

          def fallback = nil

          def cleanup
            skip(:two)
            more
          end
        end
      RUBY
      load path
      expect { ScopedProbe.run }.to raise_error(Actionable::DefinitionError) { |error|
        expect(error.message).to include('ScopedProbe#branch_a', 'ScopedProbe#cleanup')
        expect(error.message).not_to include('ScopedProbe#pick')
      }
    ensure
      Object.send(:remove_const, :ScopedProbe) if Object.const_defined?(:ScopedProbe)
    end

    it 'AC-B#verbscope: an alias_method step is checked against the original def' do
      path = File.join(@dir, 'aliased.rb')
      File.write(path, <<~RUBY)
        class AliasedProbe < Actionable::Action
          step :renamed
          def original
            fail(:x)
            more
          end
          alias_method :renamed, :original
        end
      RUBY
      load path
      expect { AliasedProbe.run }.to raise_error(Actionable::DefinitionError, /AliasedProbe#renamed \(.*aliased.rb:4\)/)
    ensure
      Object.send(:remove_const, :AliasedProbe) if Object.const_defined?(:AliasedProbe)
    end

    it 'AC-B#verbonce: skips methods without readable source (define_method, eval)' do
      action = build_action do
        step :dynamic
        step :evaled
        define_method(:dynamic) { fail(:x) && nil }
        class_eval("def evaled\n  fail(:y)\n  more\nend\ndef more = nil", __FILE__, __LINE__)
      end
      expect(action.run).to be_failure
    end

    it 'AC-B#verbonce: skips a file that does not parse cleanly' do
      path = File.join(@dir, 'broken_for_prism.rb')
      File.write(path, ['class BrokenProbe < Actionable::Action', '  step :sail', '  def sail', '    fail(:x)', '    more', '  end',
                        '  def more = nil', "end\n"].join("\n"))
      load path
      File.write(path, "class BrokenProbe < Actionable::Action\n  step :sail\n  def sail\n    fail(:x\n    more\n  end\nend\n")
      File.utime(Time.now + 10, Time.now + 10, path)
      expect(BrokenProbe.run).to be_failure
    ensure
      Object.send(:remove_const, :BrokenProbe) if Object.const_defined?(:BrokenProbe)
    end

    it 'AC-B#verbswitch: the switch round-trips, a class run while off is not marked checked' do
      path = write_action_file(@dir, "    fail(:x)\n    more")
      load path
      Actionable.verb_position_check = false
      expect(Actionable.verb_position_check?).to be(false)
      expect(ProbeAction.run).to be_failure
      Actionable.verb_position_check = true
      expect { ProbeAction.run }.to raise_error(Actionable::DefinitionError)
    ensure
      Actionable.verb_position_check = true
    end

    it 'AC-B#verbswitch: with the check off, run never loads Prism' do
      script = <<~RUBY
        require 'actionable'
        Actionable.verb_position_check = false
        klass = Class.new(Actionable::Action) { step :sail; def sail = fail(:x) }
        klass.run
        puts defined?(::Prism).inspect
      RUBY
      lib = File.expand_path('../../lib', __dir__)
      out, status = Open3.capture2(RbConfig.ruby, '-I', lib, '-e', script)
      expect(status).to be_success
      expect(out.strip).to eq('nil')
    end

    it 'AC-B#verbswitch: with the check on, the first run loads Prism lazily' do
      script = <<~RUBY
        require 'actionable'
        before = defined?(::Prism).inspect
        klass = Class.new(Actionable::Action) { step :sail; def sail = nil }
        klass.run
        puts [before, defined?(::Prism).inspect].join(',')
      RUBY
      lib = File.expand_path('../../lib', __dir__)
      out, status = Open3.capture2(RbConfig.ruby, '-I', lib, '-e', script)
      expect(status).to be_success
      expect(out.strip).to eq('nil,"constant"')
    end
  end
end

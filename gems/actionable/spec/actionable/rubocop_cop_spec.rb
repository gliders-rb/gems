# frozen_string_literal: true

require 'rubocop'
require 'rubocop/rspec/support'
require 'actionable/rubocop'
require 'open3'
require 'rbconfig'
require 'tmpdir'
require 'yaml'

RSpec.describe RuboCop::Cop::Actionable::VerbNotLast, :config do
  let(:cop_config) { {} }

  def message(verb)
    "`#{verb}` records the outcome and keeps running, and more code runs after it: use `#{verb}!` to stop here, " \
      "or make it the method's last expression."
  end

  describe 'offenses' do
    it 'AC-B#cop: flags a verb followed by more code, on the call node' do
      expect_offense(<<~RUBY)
        class Probe < Actionable::Action
          step :sail

          def sail
            fail(:adrift)
            ^^^^^^^^^^^^^ #{message(:fail)}
            more
          end
        end
      RUBY
    end

    it 'AC-B#cop: reports each verb and covers a modifier form' do
      expect_offense(<<~RUBY)
        class Probe < Actionable::Action
          step :sail

          def sail
            skip :x if a?
            ^^^^^^^ #{message(:skip)}
            succeed
            ^^^^^^^ #{message(:succeed)}
            fail_with(obj)
            ^^^^^^^^^^^^^^ #{message(:fail_with)}
            more
          end
        end
      RUBY
    end

    it 'AC-B#cop: accepts verbs in tail position and bang verbs' do
      expect_no_offenses(<<~RUBY)
        class Probe < Actionable::Action
          step :sail
          step :other

          def sail
            return fail(:x) if a?
            fail!(:y) if b?
            fail(:z)
          end

          def other
            a ? skip(:x) : succeed
          end
        end
      RUBY
    end

    it 'AC-B#cop: lands on the right line and column in multibyte source' do
      expect_offense(<<~RUBY)
        class Probe < Actionable::Action
          step :sail

          def sail
            log('héllo wörld'); fail(:oops)
                                ^^^^^^^^^^^ #{message(:fail)}
            more
          end
        end
      RUBY
    end

    it 'AC-B#cop: multibyte characters on earlier lines do not shift the offense' do
      expect_offense(<<~RUBY)
        # Café résumé — naïve
        class Probe < Actionable::Action
          step :sail

          def sail
            note = '日本語'
            skip(:later)
            ^^^^^^^^^^^^ #{message(:skip)}
            note
          end
        end
      RUBY
    end
  end

  describe 'what is checked (AC-B#copscope)' do
    it 'checks step, case-step branch targets and hooks, and never a value source or a helper' do
      expect_offense(<<~RUBY)
        class Probe < Actionable::Action
          step :a
          case_step :pick do
            on 'x', :branch
            default :fallback
          end
          on_success :after_ok
          on_failure :after_bad
          on_skip :after_skip
          always :cleanup
          after_commit :notify

          def a
            fail(:a)
            ^^^^^^^^ #{message(:fail)}
            more
          end

          def pick
            skip(:ignored)
            'x'
          end

          def branch
            fail(:b)
            ^^^^^^^^ #{message(:fail)}
            more
          end

          def fallback
            fail(:c)
            ^^^^^^^^ #{message(:fail)}
            more
          end

          def after_ok
            skip(:d)
            ^^^^^^^^ #{message(:skip)}
            more
          end

          def after_bad
            skip(:e)
            ^^^^^^^^ #{message(:skip)}
            more
          end

          def after_skip
            skip(:f)
            ^^^^^^^^ #{message(:skip)}
            more
          end

          def cleanup
            skip(:g)
            ^^^^^^^^ #{message(:skip)}
            more
          end

          def notify
            skip(:h)
            ^^^^^^^^ #{message(:skip)}
            more
          end

          def helper
            fail(:z)
            more
          end
        end
      RUBY
    end

    it 'AC-B#copscope: needs a step or case_step declaration, hooks alone do not qualify' do
      expect_no_offenses(<<~RUBY)
        class Probe < Actionable::Action
          always :cleanup

          def cleanup
            skip(:g)
            more
          end
        end
      RUBY
    end

    it 'AC-B#copscope: checks Class.new(Base) blocks, named or anonymous' do
      expect_offense(<<~RUBY)
        Probe = Class.new(Actionable::Action) do
          step :sail

          def sail
            fail(:x)
            ^^^^^^^^ #{message(:fail)}
            more
          end
        end

        Class.new(Actionable::Action) do
          step :go2

          def go2
            skip(:y)
            ^^^^^^^^ #{message(:skip)}
            more
          end
        end
      RUBY
    end

    it 'AC-B#copscope: an alias_method step is checked against the original def' do
      expect_offense(<<~RUBY)
        class Probe < Actionable::Action
          step :renamed

          def original
            fail(:x)
            ^^^^^^^^ #{message(:fail)}
            more
          end
          alias_method :renamed, :original
        end
      RUBY
    end

    it 'AC-B#copscope: private def and string step names are followed' do
      expect_offense(<<~RUBY)
        class Probe < Actionable::Action
          step 'sail'

          private def sail
            fail(:x)
            ^^^^^^^^ #{message(:fail)}
            more
          end
        end
      RUBY
    end
  end

  describe 'action bases (AC-B#copbases)' do
    it 'defaults to Actionable::Action and ApplicationAction, ignoring a leading ::' do
      expect_offense(<<~RUBY)
        class One < ApplicationAction
          step :sail

          def sail
            fail(:x)
            ^^^^^^^^ #{message(:fail)}
            more
          end
        end

        class Two < ::Actionable::Action
          step :sail

          def sail
            skip(:x)
            ^^^^^^^^ #{message(:skip)}
            more
          end
        end
      RUBY
    end

    it 'leaves other classes alone (a transaction library with its own step)' do
      expect_no_offenses(<<~RUBY)
        class Probe
          include Dry::Transaction

          step :sail

          def sail
            fail(:x)
            more
          end
        end

        class Other < Dry::Something
          step :sail

          def sail
            fail(:x)
            more
          end
        end
      RUBY
    end

    context 'with ActionBaseClasses configured' do
      let(:cop_config) { { 'ActionBaseClasses' => ['::MyBase'] } }

      it 'replaces the default list' do
        expect_offense(<<~RUBY)
          class One < MyBase
            step :sail

            def sail
              fail(:x)
              ^^^^^^^^ #{message(:fail)}
              more
            end
          end

          class Two < ApplicationAction
            step :sail

            def sail
              fail(:x)
              more
            end
          end
        RUBY
      end
    end

    it 'follows classes defined in the same file, at any depth' do
      expect_offense(<<~RUBY)
        class Base < Actionable::Action; end
        Middle = Class.new(Base)

        module Deep
          class Leaf < ::Middle
            step :sail

            def sail
              fail(:x)
              ^^^^^^^^ #{message(:fail)}
              more
            end
          end
        end
      RUBY
    end

    it 'resolves a superclass name from the enclosing scopes outward' do
      expect_offense(<<~RUBY)
        module B
          class Base < Actionable::Action; end

          class Leaf < Base
            step :sail

            def sail
              fail(:x)
              ^^^^^^^^ #{message(:fail)}
              more
            end
          end
        end
      RUBY
    end

    it 'lets the file own namespaced class shadow the listed default' do
      expect_no_offenses(<<~RUBY)
        module Legacy
          class ApplicationAction < Object; end

          class Leaf < ApplicationAction
            step :sail

            def sail
              fail(:x)
              more
            end
          end
        end
      RUBY
    end

    it 'opens only the compact name for class A::B, and treats ::X as absolute' do
      expect_no_offenses(<<~RUBY)
        module A
          class Base < Actionable::Action; end
        end

        class A::Leaf < Base
          step :sail

          def sail
            fail(:x)
            more
          end
        end

        module B
          class Base2 < Actionable::Action; end

          class Leaf < ::Base2
            step :sail

            def sail
              fail(:x)
              more
            end
          end
        end
      RUBY
    end

    it 'ignores a class reopened without naming a superclass' do
      expect_no_offenses(<<~RUBY)
        class Probe < Actionable::Action; end

        class Probe
          step :sail

          def sail
            fail(:x)
            more
          end
        end
      RUBY
    end

    it 'does not loop on superclass cycles' do
      expect_no_offenses(<<~RUBY)
        class A < B; end
        class B < A; end
        class C < C
          step :sail

          def sail
            fail(:x)
            more
          end
        end
      RUBY
    end
  end

  describe 'unparseable files (AC-B#copparse)' do
    it 'yields no offenses when Prism cannot parse the buffer' do
      allow(Actionable::VerbPosition).to receive(:parse).and_return(nil)
      expect_no_offenses(<<~RUBY)
        class Probe < Actionable::Action
          step :sail

          def sail
            fail(:x)
            more
          end
        end
      RUBY
    end
  end
end

RSpec.describe 'the RuboCop plugin' do
  it 'AC-B#copplugin: names the plugin in the gemspec metadata' do
    gemspec = Gem::Specification.load(File.expand_path('../../actionable-rb.gemspec', __dir__))
    expect(gemspec.metadata['default_lint_roller_plugin']).to eq('Actionable::RubocopPlugin')
  end

  it 'AC-B#copplugin: supports the rubocop engine only and points at the shipped config' do
    plugin = Actionable::RubocopPlugin.new
    expect(plugin.supported?(LintRoller::Context.new(engine: :rubocop))).to be(true)
    expect(plugin.supported?(LintRoller::Context.new(engine: :standard))).to be(false)
    rules = plugin.rules(LintRoller::Context.new(engine: :rubocop))
    expect(rules.type).to eq(:path)
    config = YAML.safe_load_file(rules.value)
    expect(config['Actionable/VerbNotLast']).to include('Enabled' => true,
                                                        'ActionBaseClasses' => ['Actionable::Action', 'ApplicationAction'])
    expect(plugin.about.name).to eq('actionable-rb')
  end

  it 'AC-B#copplugin: a real rubocop run with the plugin reports the offense and exits 1' do
    Dir.mktmpdir do |dir|
      File.write(File.join(dir, '.rubocop.yml'), <<~YAML)
        plugins:
          - actionable-rb:
              require_path: actionable/rubocop
        AllCops:
          NewCops: disable
          SuggestExtensions: false
      YAML
      File.write(File.join(dir, 'probe.rb'), <<~RUBY)
        # frozen_string_literal: true

        class Probe < Actionable::Action
          step :sail

          def sail
            fail(:x)
            more
          end
        end
      RUBY
      lib = File.expand_path('../../lib', __dir__)
      out, status = Open3.capture2e(RbConfig.ruby, '-I', lib, '-S', 'rubocop', '--only', 'Actionable/VerbNotLast', '--format',
                                    'emacs', chdir: dir)
      expect(out).to include('probe.rb:7:5: C: Actionable/VerbNotLast: `fail` records the outcome')
      expect(status.exitstatus).to eq(1)
    end
  end
end

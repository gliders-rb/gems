# frozen_string_literal: true

module Actionable
  # The RuboCop plugin (RuboCop 1.72 and newer, through +lint_roller+): points RuboCop at the shipped cop config.
  class RubocopPlugin < LintRoller::Plugin
    # Called by lint_roller only, so it stays out of the shipped sig.
    #
    # @!visibility private
    # @return [::LintRoller::About]
    def about
      LintRoller::About.new(
        name: 'actionable-rb', version: Actionable::VERSION, homepage: 'https://github.com/gliders-rb/gems',
        description: 'Cops for actionable-rb action classes.'
      )
    end

    # Called by lint_roller only, so it stays out of the shipped sig.
    #
    # @!visibility private
    # @param context [::LintRoller::Context]
    # @return [Boolean]
    def supported?(context)
      context.engine == :rubocop
    end

    # Called by lint_roller only, so it stays out of the shipped sig.
    #
    # @!visibility private
    # @param _context [::LintRoller::Context]
    # @return [::LintRoller::Rules]
    def rules(_context)
      LintRoller::Rules.new(type: :path, config_format: :rubocop, value: File.join(__dir__, 'config.yml'))
    end
  end
end

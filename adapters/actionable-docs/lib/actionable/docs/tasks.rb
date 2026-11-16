# frozen_string_literal: true

require 'rake'
require_relative '../docs'

module Actionable
  module Docs
    # Rake tasks for a host app: +actionable:docs+ writes the pages, +actionable:docs:check+ fails when the
    # committed pages differ from fresh ones (AD-B32).
    module Tasks
      module_function

      # Defines the two tasks.
      #
      # @param actions [Array<Class>, Proc] the actions to document, or a callable returning them (called when a task
      #   runs, so an app can load its code first)
      # @param dir [String] the docs folder the pages live in
      # @return [void]
      def define(actions:, dir:)
        list = -> { actions.respond_to?(:call) ? actions.call : actions }
        Rake.application.last_description = "Write the action pages into #{dir}"
        Rake::Task.define_task('actionable:docs') do
          Docs.write(list.call, dir: dir).each { |path| puts "actionable-docs: wrote #{path}" }
        end
        Rake.application.last_description = "Fail when a page in #{dir} is missing or out of date"
        Rake::Task.define_task('actionable:docs:check') { Tasks.check(list.call, dir) }
      end

      # @api private
      # @param actions [Array<Class>]
      # @param dir [String]
      # @return [void]
      def check(actions, dir)
        stale = Docs.stale(actions, dir: dir)
        unless stale.empty?
          abort "actionable-docs: these pages are out of date; run rake actionable:docs and commit them:\n" \
                "#{stale.join("\n")}"
        end
        puts "actionable-docs: #{actions.uniq.size} pages are current"
      end
    end
  end
end

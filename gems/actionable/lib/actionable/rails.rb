# frozen_string_literal: true

require 'active_model'
require 'active_support/core_ext/string/inflections'
require_relative '../actionable'

require_relative 'rails/rollback'
require_relative 'rails/transactions'
require_relative 'rails/after_commit'
require_relative 'rails/runner_transaction'
require_relative 'rails/runner_after_commit'
require_relative 'rails/proxy_validator'

module Actionable
  # Adapter for Rails apps: transactional runs, hooks that wait for commit and an ActiveModel proxy validator.
  # Inside +module Actionable+, +Rails+ means this module; reach the framework as +::Rails+.
  module Rails
  end

  Action.extend(Rails::Transactions)
  # `send` keeps YARD from reading these as mixins of the Actionable module itself.
  Action.singleton_class.send(:prepend, Rails::AfterCommit)
  Action.adapter_step_sets << :after_commit_hooks unless Action.adapter_step_sets.include?(:after_commit_hooks)
  Runner.prepend(Rails::RunnerTransaction)
  Runner.prepend(Rails::RunnerAfterCommit)
end

require_relative 'rails/railtie' if defined?(Rails::Railtie)

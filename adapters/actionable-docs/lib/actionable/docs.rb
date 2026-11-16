# frozen_string_literal: true

require 'fileutils'
require 'actionable'
require_relative 'docs/version'
require_relative 'docs/words'
require_relative 'docs/flowchart'
require_relative 'docs/page'

# The actionable-rb namespace; this gem adds {Docs}.
module Actionable
  # Process pages for actions: Markdown with a Mermaid flowchart, built from +describe+ and the descriptions, for
  # people who read about an action rather than its code. Nothing here runs an action.
  module Docs
    module_function

    # The page for one action.
    #
    # @param action [Class] a named Actionable::Action subclass
    # @return [String] Markdown, ending with one newline
    # @raise [ArgumentError] for anything else
    def markdown(action)
      Page.new(checked(action)).to_s
    end

    # @param action [Class] a named Actionable::Action subclass
    # @return [String] the words of its title, e.g. "Service bike"
    # @raise [ArgumentError] for anything else
    def title(action)
      Words.title(checked(action))
    end

    # @param action [Class] a named Actionable::Action subclass
    # @return [String] the page's path relative to the docs folder, e.g. +workshop/service_bike.md+
    # @raise [ArgumentError] for anything else
    def path_for(action)
      Words.path_for(checked(action))
    end

    # Writes every action's page under +dir+, creating folders.
    #
    # @param actions [Array<Class>] named action classes; a repeat is written once
    # @param dir [String] the docs folder
    # @return [Array<String>] the paths written, in the given order
    def write(actions, dir:)
      actions.uniq.map do |action|
        path = File.join(dir, path_for(action))
        FileUtils.mkdir_p(File.dirname(path))
        File.write(path, markdown(action))
        path
      end
    end

    # The pages under +dir+ that are missing or differ from a fresh one. Writes nothing.
    #
    # @param actions [Array<Class>] named action classes
    # @param dir [String] the docs folder
    # @return [Array<String>] the stale paths, empty when every page is current
    def stale(actions, dir:)
      actions.uniq.filter_map do |action|
        path = File.join(dir, path_for(action))
        path unless File.file?(path) && File.read(path) == markdown(action)
      end
    end

    # @api private
    # @param action [Object]
    # @return [Class] the action, when it is a named Actionable::Action subclass
    # @raise [ArgumentError] for anything else
    def checked(action)
      return action if action.is_a?(Class) && action < Actionable::Action && action.name

      raise ArgumentError, "Actionable::Docs needs a named Actionable::Action subclass, got #{action.inspect}"
    end
  end
end

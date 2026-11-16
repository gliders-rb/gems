# frozen_string_literal: true

require 'did_you_mean'

module FieldStruct
  # Builds the "did you mean" part of a declaration message, shared by field_struct and actionable-rb.
  # @api private
  module Suggestion
    # The likeliest candidates for a misspelled word, at most two, best first.
    #
    # @param word [Symbol, String] what was written
    # @param candidates [Array<Symbol, String>] what could have been meant
    # @return [Array<String>] the picks, empty when nothing is close
    def self.picks(word, candidates)
      dictionary = candidates.map(&:to_s).uniq
      DidYouMean::SpellChecker.new(dictionary: dictionary).correct(word.to_s).first(2)
    end

    # The picks for +word+ as a trailing clause, e.g. +" (did you mean :string?)"+.
    #
    # @param word [Symbol, String] what was written
    # @param candidates [Array<Symbol, String>] what could have been meant
    # @param sigil [String] written before each pick: +":"+ for Symbols, +""+ for option keys
    # @param suffix [String] written after each pick, e.g. +":"+ for an option key
    # @return [String] the clause with its leading space, or +""+ when nothing is close
    def self.clause(word, candidates, sigil: ':', suffix: '')
      found = picks(word, candidates)
      return '' if found.empty?

      " (did you mean #{found.map { |pick| "#{sigil}#{pick}#{suffix}" }.join(' or ')}?)"
    end
  end
end

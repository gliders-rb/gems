# frozen_string_literal: true

module FieldStruct
  # Which fields the caller gave (FS-B34a), and what that means for a nullable field (FS-B34). Included into {Base}.
  module Presence
    # What +given_fields+ returns before anything was given; shared, so a struct built with no input allocates nothing.
    NOTHING_GIVEN = [].freeze
    private_constant :NOTHING_GIVEN

    # The fields the caller gave, through the input, +with+ or a writer; defaults don't count (FS-B34a).
    #
    # @return [Array<Symbol>] frozen, in declaration order
    def given_fields
      given = @__given__
      return NOTHING_GIVEN if given.nil?

      self.class.attribute_names.select { |name| given.include?(name) }.freeze
    end

    private

    # The defaults pass runs setters too; the flag keeps it from marking fields as given (FS-B34a).
    def fs_apply_defaults(input)
      @__defaulting__ = true
      fs_default_each(input)
    ensure
      @__defaulting__ = false
    end

    def fs_mark_given(name)
      given = (@__given__ ||= [])
      given << name unless given.include?(name)
    end

    def fs_given?(name)
      given = @__given__
      given ? given.include?(name) : false
    end

    # A given nil on a nullable field is an answer, not a missing value (FS-B34).
    def fs_null_answer?(field, value)
      field.nullable? && value.nil? && fs_given?(field.name)
    end
  end
end

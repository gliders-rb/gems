# frozen_string_literal: true

module FieldStruct
  module Types
    # How a union picks a struct member for a Hash: the ordered scan (FS-B83a) and the tag (FS-B83b). Internal.
    module UnionPick
      # Returned by {.scan} when every struct member raised.
      NONE = Object.new.freeze

      # Builds each struct member in order; stops at the first valid one with no unknown keys, else keeps the best.
      #
      # @param structs [Array<FieldStruct::Types::Nested>]
      # @param hash [Hash]
      # @param rescuable [Array<Class>] the exceptions that put a member out of the scan
      # @return [FieldStruct::Base, Object] the pick, or {NONE}
      def self.scan(structs, hash, rescuable)
        best = NONE
        best_rank = nil
        structs.each do |member|
          built = member.coerce(hash)
          rank = rank_of(built, unknown_keys(member.struct_class, hash))
          return built if rank == [0, 0]

          next unless best_rank.nil? || (rank <=> best_rank).negative?

          best = built
          best_rank = rank
        rescue *rescuable
          next
        end
        best
      end

      # [0, unknown keys] for a valid struct, [1, message count] for an invalid one; lower is better.
      def self.rank_of(built, unknown)
        errors = built.errors
        errors.empty? ? [0, unknown] : [1, errors.to_h.sum { |_field, messages| messages.size }]
      end

      def self.unknown_keys(struct_class, hash)
        hash.each_key.count { |key| !((key.is_a?(::Symbol) || key.is_a?(::String)) && struct_class.metadata[key]) }
      end

      private_class_method :rank_of, :unknown_keys

      # A union's +discriminator:+, checked at declaration and used to pick by tag.
      class Discriminator
        KEYS = %i[field map default].freeze
        private_constant :KEYS

        # @param declared [Symbol, Hash] the field's +discriminator:+
        # @param members [Array<FieldStruct::Types::Base>] the union's member instances
        # @return [Discriminator]
        # @raise [ArgumentError] for each mistake in FS-B83b's table
        def self.build(declared, members)
          field, map, default = parts(declared)
          structs = members.map { |member| struct_member(member) }
          structs.each { |member| member_field(member, field) }
          tags = map ? mapped(map, structs) : enum_tags(structs, field)
          new(field, tags, default && member_for(default, structs, 'default:'))
        end

        def self.parts(declared)
          return [declared, nil, nil] if declared.is_a?(::Symbol)
          return declared.values_at(*KEYS) if declared.keys.all? { |key| KEYS.include?(key) } && declared[:field].is_a?(::Symbol)

          raise ::ArgumentError, "discriminator: takes field:, map: and default:, got #{declared.inspect}"
        end

        def self.struct_member(member)
          return member if member.is_a?(Nested)

          raise ::ArgumentError, "discriminator: needs every union member to be a FieldStruct class, got #{member.class.short_name}"
        end

        def self.member_field(member, field)
          declared = member.struct_class.metadata[field]
          return declared if declared

          raise ::ArgumentError, "discriminator: #{field.inspect} is not a field of #{member.struct_class.display_name}"
        end

        def self.mapped(map, structs)
          map.each_with_object({}) { |(tag, klass), tags| tags[tag.to_s] = member_for(klass, structs, 'map:') }
        end

        def self.member_for(klass, structs, label)
          found = structs.find { |member| member.struct_class.equal?(klass) }
          return found if found

          name = klass.is_a?(::Class) ? klass.display_name : klass.inspect
          raise ::ArgumentError, "discriminator: #{label} names #{name}, which is not a member of this union"
        end

        def self.enum_tags(structs, field)
          structs.each_with_object({}) do |member, tags|
            enum = member_field(member, field).options[:enum]
            name = member.struct_class.display_name
            raise ::ArgumentError, "discriminator: #{field.inspect} on #{name} needs enum: (or give the union a map:)" unless enum

            enum.each { |tag| claim(tags, tag.to_s, member, field) }
          end
        end

        def self.claim(tags, tag, member, field)
          if tags.key?(tag)
            raise ::ArgumentError, "discriminator: #{field.inspect} tag #{tag.inspect} names both " \
                                   "#{tags[tag].struct_class.display_name} and #{member.struct_class.display_name}"
          end
          tags[tag] = member
        end

        private_class_method :parts, :struct_member, :member_field, :mapped, :member_for, :enum_tags, :claim

        # @param field [Symbol]
        # @param tags [Hash{String=>FieldStruct::Types::Nested}]
        # @param default [FieldStruct::Types::Nested, nil]
        def initialize(field, tags, default)
          @field = field
          @tags = tags.freeze
          @default = default
          @expected = "expected one of #{tags.keys.join(', ')}"
          freeze
        end

        # @param hash [Hash] the input
        # @return [FieldStruct::Base] the member the tag names, built from +hash+
        # @raise [TypeError] for a missing or unknown tag and no +default:+; the message lists the declared tags only
        def pick(hash)
          raw = hash.key?(@field) ? hash[@field] : hash[@field.name]
          member = (@tags[raw.to_s] unless raw.nil?) || @default
          return member.coerce(hash) if member

          raise ::TypeError, "union discriminator #{@field} #{raw.nil? ? 'is missing' : 'names no member'} (#{@expected})"
        end
      end
    end
  end
end

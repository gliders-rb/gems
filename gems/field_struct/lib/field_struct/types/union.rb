# frozen_string_literal: true

module FieldStruct
  module Types
    # One of several types: members are tried in declared order and the first that accepts the value wins.
    class Union < Base
      # Failures that mean "this member refused the value"; anything else is a bug and propagates.
      # @return [::Array<::Class>]
      RESCUABLE = [::ArgumentError, ::TypeError, ::RangeError, FieldStruct::Error].freeze

      # Declaration error for an +:array+ union member.
      # @return [::String]
      ARRAY_MEMBER = 'union `of:` cannot include :array (an array member would have no element type); ' \
                     'give the array its own field or use :value'
      # Declaration error for a +:hash+ union member.
      # @return [::String]
      HASH_MEMBER = 'union `of:` cannot include :hash (a hash member would have no value type); ' \
                    'give the hash its own field or use :value'

      class << self
        # @return [::Hash{::Symbol=>::Hash{::Symbol=>::Object}}]
        def own_option_schema
          { of: option(type: ::Array, required: true), discriminator: option(type: [::Symbol, ::Hash]) }
        end

        # @param _key [::Symbol]
        # @return [::String]
        def required_option_message(_key)
          'union field requires an `of: [...]` option naming the member types'
        end

        # Turns the member names and classes into type instances, in +options[:of]+.
        #
        # @param options [::Hash{::Symbol=>::Object}]
        # @param registry [FieldStruct::Registry]
        # @return [::Hash{::Symbol=>::Object}]
        # @raise [ArgumentError, KeyError] for too few members, an array member, or an unknown name
        def resolve_options(options, registry:, **)
          members = options[:of]
          raise ::ArgumentError, 'union `of:` must have at least two members' if members.size < 2

          options.merge(of: members.map { |member| member_instance(member, registry) })
        end

        # The members live on the instance, so they leave the stored options. A +discriminator:+ is checked here and
        # stays in the options as declared (FS-B83b).
        #
        # @param options [::Hash{::Symbol=>::Object}] resolved options
        # @return [Array(FieldStruct::Types::Union, ::Hash{::Symbol=>::Object})] the instance and the options to store
        # @raise [ArgumentError] for a +discriminator:+ that does not fit the members
        def instantiate(options)
          union = new(options[:of])
          declared = options[:discriminator]
          union.send(:use_discriminator, UnionPick::Discriminator.build(declared, options[:of])) if declared
          [union, options.except(:of)]
        end

        private

        def member_instance(member, registry)
          klass = member.is_a?(::Class) ? member : registry.lookup(member)
          raise ::ArgumentError, ARRAY_MEMBER if klass <= Types::Array
          raise ::ArgumentError, HASH_MEMBER if klass <= Types::Hash
          return Nested.new(klass, reads: false) if klass <= FieldStruct::Base
          unless klass <= Types::Base
            raise ::ArgumentError, "#{klass.inspect} is not a FieldStruct type (subclass FieldStruct::Types::Base)"
          end

          klass.new
        end
      end

      # @return [::Array<FieldStruct::Types::Base>] the member type instances in declared order (read-only)
      attr_reader :member_types

      # @param member_types [::Array<FieldStruct::Types::Base>]
      def initialize(member_types = [])
        super()
        @member_types = member_types
        @discriminator = nil
      end

      # @param value [::Object]
      # @return [::Object, nil] the first member's result
      # @raise [TypeError] for a non-finite number, or when every member refuses
      def coerce(value, **)
        return nil if value.nil?

        refuse_non_finite(value)
        members = member_types
        if value.is_a?(::Hash)
          picked, members = hash_pick(value)
          return picked unless picked.equal?(UnionPick::NONE)
        end
        members.each do |member|
          return member.coerce(value)
        rescue *RESCUABLE
          next
        end
        raise ::TypeError, "no union member (#{member_types.map { |m| m.class.short_name }.join(' | ')}) could coerce #{value.class} input"
      end

      # Internal: {#coerce} with the options as one Hash, no keyword splat (see Types::Base.positional_coerce?).
      #
      # @param value [::Object]
      # @param _options [::Hash{::Symbol=>::Object}] unused: this type takes no options
      # @return [::Object, nil]
      # @api private
      def coerce_positional(value, _options)
        coerce(value)
      end

      # @return [::Array<::Class>] the members' classes, flattened and de-duplicated
      def ruby_type
        member_types.flat_map { |member| [member.ruby_type].flatten }.uniq
      end

      private

      def use_discriminator(discriminator)
        @discriminator = discriminator
      end

      # The tag's member, or the ordered scan's pick among two or more struct members; with the members left to try.
      def hash_pick(value)
        return [@discriminator.pick(value), []] if @discriminator

        structs = member_types.grep(Nested)
        return [UnionPick::NONE, member_types] if structs.size < 2

        [UnionPick.scan(structs, value, RESCUABLE), member_types - structs]
      end

      def refuse_non_finite(value)
        return unless value.is_a?(::Float) || value.is_a?(::BigDecimal)
        return if value.finite?

        raise ::TypeError, "Union fields expect a finite number, got a non-finite #{value.class}"
      end
    end
  end
end

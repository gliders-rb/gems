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

      class << self
        # @return [::Hash{::Symbol=>::Hash{::Symbol=>::Object}}]
        def own_option_schema
          { of: option(type: ::Array, required: true) }
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

        # @param options [::Hash{::Symbol=>::Object}] resolved options
        # @return [::Array(Union, ::Hash)] the instance and the options to store (members live on the instance)
        def instantiate(options)
          [new(options[:of]), options.except(:of)]
        end

        private

        def member_instance(member, registry)
          klass = member.is_a?(::Class) ? member : registry.lookup(member)
          raise ::ArgumentError, ARRAY_MEMBER if klass <= Types::Array
          return Nested.new(klass) if klass <= FieldStruct::Base
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
      end

      # @param value [::Object]
      # @return [::Object, nil] the first member's result
      # @raise [TypeError] for a non-finite number, or when every member refuses
      def coerce(value, **)
        return nil if value.nil?

        refuse_non_finite(value)
        member_types.each do |member|
          return member.coerce(value)
        rescue *RESCUABLE
          next
        end
        raise ::TypeError, "no union member (#{member_types.map { |m| m.class.short_name }.join(' | ')}) could coerce #{value.class} input"
      end

      # @return [::Array<::Class>] the members' classes, flattened and de-duplicated
      def ruby_type
        member_types.flat_map { |member| [member.ruby_type].flatten }.uniq
      end

      private

      def refuse_non_finite(value)
        return unless value.is_a?(::Float) || value.is_a?(::BigDecimal)
        return if value.finite?

        raise ::TypeError, "Union fields expect a finite number, got a non-finite #{value.class}"
      end
    end
  end
end

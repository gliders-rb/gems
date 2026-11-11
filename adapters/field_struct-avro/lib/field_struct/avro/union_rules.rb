# frozen_string_literal: true

module FieldStruct
  module Avro
    # What Avro allows in a union, and what it would silently get wrong (AV-B11, AV-B12).
    class UnionRules
      # Avro types that are not named.
      PRIMITIVES = %w[null boolean int long float double bytes string array map].freeze

      # @param serialization [::Symbol]
      def initialize(serialization)
        @serialization = serialization
      end

      # Refuses two members in one slot, then puts the +long+ slot first.
      #
      # @param types [::Array<::Object>] the members' Avro types, declared order
      # @param frame [Frame] for the namespace of unqualified names
      # @param label [::String]
      # @return [::Array<::Object>]
      # @raise [::ArgumentError] when two members share a slot
      def order(types, frame, label)
        slots = types.map { |type| slot(type, frame) }
        clash = slots.find { |name| slots.count(name) > 1 }
        raise ::ArgumentError, "FieldStruct::Avro can't describe #{label}: two union members both become Avro #{clash}" if clash

        types.zip(slots).sort_by.with_index { |(_, name), index| [name == 'long' ? 0 : 1, index] }.map(&:first)
      end

      # Refuses a struct member that Avro would pick instead of a later one (shape matching).
      #
      # @param classes [::Array<::Class>] the struct members, declared order
      # @param label [::String]
      # @return [void]
      # @raise [::ArgumentError] when a later struct fits an earlier one
      def check_shadowing(classes, label)
        classes.each_with_index do |earlier, index|
          classes.drop(index + 1).each { |later| check_pair(earlier, later, label) }
        end
      end

      private

      def slot(type, frame)
        case type
        when ::String then type == 'bytes' ? 'string' : qualified(type, frame, primitive: PRIMITIVES.include?(type))
        when ::Hash then hash_slot(type, frame)
        else type.to_s
        end
      end

      def hash_slot(type, frame)
        kind = type['type']
        return qualified(type['name'], frame, namespace: type['namespace']) if %w[record enum fixed].include?(kind)

        kind == 'bytes' ? 'string' : kind.to_s
      end

      def qualified(name, frame, primitive: false, namespace: nil)
        return name if primitive || name.include?('.')

        namespace ||= frame.namespace
        namespace ? "#{namespace}.#{name}" : name
      end

      def check_pair(earlier, later, label)
        required = required_keys(earlier)
        later_keys = keys(later)
        return unless required.all? { |key| later_keys.include?(key) }

        names = [later, earlier].map { |klass| klass.name || klass.inspect }
        raise ::ArgumentError, shadow_message(label, names, required.empty?, required_keys(later).all? { |k| keys(earlier).include?(k) })
      end

      def shadow_message(label, names, no_required, swap_useless)
        later, earlier = names
        why = no_required ? "#{earlier} has no required fields, so any record fits it" : "every required field of #{earlier} is in #{later}"
        swap = swap_useless ? '' : ", or put #{later} first"
        "FieldStruct::Avro can't describe #{label}: a #{later} would be written as #{earlier}, which Avro picks by shape (#{why}). " \
          "Give the structs distinct required fields#{swap}"
      end

      def keys(klass)
        FieldStruct::Introspection.properties(klass, serialization: @serialization).map(&:key)
      end

      def required_keys(klass)
        FieldStruct::Introspection.properties(klass, serialization: @serialization).select do |prop|
          prop.field.required? && !overridden?(prop.field)
        end.map(&:key)
      end

      def overridden?(field)
        avro = field.options[:avro]
        avro.is_a?(::Hash) && !(avro[:type] || avro['type']).nil?
      end
    end
  end
end

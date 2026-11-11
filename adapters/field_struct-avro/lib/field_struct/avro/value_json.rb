# frozen_string_literal: true

module FieldStruct
  module Avro
    # The JSON text of a +:value+ field (AV-B24), through Oj in compat mode.
    module ValueJson
      module_function

      # @param value [::Object]
      # @return [::String] the JSON +to_json+ would write for the value
      def dump(value)
        Oj.dump(json_ready(value), mode: :compat)
      end

      # @param text [::String]
      # @param where [Spot] the field being read; its label is built only for the error
      # @return [::Object] numbers with a fraction are BigDecimal; times and decimals stay Strings
      # @raise [::ArgumentError] when the text does not parse (the parse error is not kept: it quotes the text)
      def load(text, where)
        Oj.load(text, mode: :compat, decimal_class: ::BigDecimal)
      rescue ::StandardError => e
        raise ::ArgumentError, "FieldStruct::Avro (#{where.label}) holds :value JSON that doesn't parse (#{e.class.name})", cause: nil
      end

      # @param value [::Object]
      # @return [::Object] the value with Symbols, decimals and times in their JSON forms
      def json_ready(value)
        case value
        when ::Array then value.map { |item| json_ready(item) }
        when ::Hash then value.to_h { |key, item| [key.to_s, json_ready(item)] }
        else scalar_ready(value)
        end
      end

      # @param value [::Object]
      # @return [::Object]
      def scalar_ready(value)
        case value
        when ::Symbol then value.to_s
        when ::BigDecimal then value.to_s('F')
        when ::Date, ::Time then value.iso8601
        else value.respond_to?(:as_json) ? value.as_json : value
        end
      end
    end
  end
end

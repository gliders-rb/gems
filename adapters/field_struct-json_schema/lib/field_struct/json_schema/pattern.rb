# frozen_string_literal: true

require_relative 'pattern/translator'
require_relative 'pattern/safety'

module FieldStruct
  module JSONSchema
    # The Regexp-to-ECMA-262 translator (JS-B50..B55). A Regexp is translated only when the result matches exactly the
    # same strings under the +u+ flag; otherwise {translate} answers nil and the generator falls back to the
    # +x-ruby-pattern+ annotation (JS-I2).
    module Pattern
      ENCODINGS = [::Encoding::UTF_8, ::Encoding::US_ASCII].freeze
      private_constant :ENCODINGS

      module_function

      # @param regexp [::Regexp]
      # @return [::String, nil] the pattern, or nil when there is no exact equivalent
      def translate(regexp)
        return nil if regexp.options.anybits?(::Regexp::EXTENDED | ::Regexp::MULTILINE)

        source = regexp.source
        return nil unless source.valid_encoding? && (ENCODINGS.include?(source.encoding) || source.ascii_only?)

        translator = Translator.new(source, fold_case: regexp.options.anybits?(::Regexp::IGNORECASE))
        text = translator.call
        text if text && Safety.safe?(translator.alternatives)
      end
    end
  end
end

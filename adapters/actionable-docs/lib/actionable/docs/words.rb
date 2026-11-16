# frozen_string_literal: true

require 'pathname'

module Actionable
  module Docs
    # The words a page and its chart use: titles, paths, labels, guard and branch words (AD-B2..AD-B4).
    # @api private
    module Words
      # A guard label that is a method name, as opposed to a description.
      #
      # @return [Regexp]
      METHOD_NAME = /\A[a-z_][A-Za-z0-9_]*[?!]?\z/

      module_function

      # @param klass [Class] a named action
      # @return [String] its last name segment as words, only the first letter upper case
      def title(klass)
        sentence(split_words(klass.name.to_s.split('::').last.to_s, ' ').downcase)
      end

      # @param klass [Class] a named action
      # @return [String] the page's relative path, e.g. +workshop/service_bike.md+
      def path_for(klass)
        "#{klass.name.to_s.split('::').map { |segment| split_words(segment, '_').downcase }.join('/')}.md"
      end

      # @param from [Class] the action whose page holds the link
      # @param to [Class] the linked action
      # @return [String] the relative path from +from+'s page to +to+'s
      def link(from, to)
        Pathname(path_for(to)).relative_path_from(Pathname(path_for(from)).dirname).to_s
      end

      # @param name [Symbol, String] a method or code name
      # @return [String] +fit_brakes+ as "Fit brakes" (a trailing +?+ or +!+ dropped)
      def humanize(name)
        sentence(name.to_s.sub(/[?!]\z/, '').tr('_', ' '))
      end

      # @param entry [Hash{Symbol=>Object}] a step entry from +describe+
      # @return [String] its description, or its humanized name (the title for an action step)
      def plain_label(entry)
        return entry[:description] if entry[:description]

        entry[:name].is_a?(Class) ? title(entry[:name]) : humanize(entry[:name])
      end

      # @param label [String] a +guard:+ label from +describe+
      # @return [String] a method name as lower-case words; a description as it is
      def guard_words(label)
        METHOD_NAME.match?(label) ? label.sub(/[?!]\z/, '').tr('_', ' ') : label
      end

      # @param guard [Hash{Symbol=>String}, nil] an entry's +guard:+
      # @return [String] +" (only when ...)"+, +" (skipped when ...)"+, both joined by +and+, or +""+
      def guard_suffix(guard)
        return '' unless guard

        parts = []
        parts << "only when #{guard_words(guard[:if])}" if guard.key?(:if)
        parts << "skipped when #{guard_words(guard[:unless])}" if guard.key?(:unless)
        " (#{parts.join(' and ')})"
      end

      # @param value [Object] a branch's +on+ value
      # @return [String] an Array joined with +or+, a Regexp as +matching /src/+, anything else as text
      def on_words(value)
        case value
        when Array then value.join(' or ')
        when Regexp then "matching /#{value.source}/"
        else value.to_s
        end
      end

      # @param text [String]
      # @return [String] with only its first letter changed to upper case
      def sentence(text)
        text.empty? ? text : text[0].to_s.upcase + text[1..].to_s
      end

      # @param text [String]
      # @return [String] with only its first letter changed to lower case
      def lower_first(text)
        text.empty? ? text : text[0].to_s.downcase + text[1..].to_s
      end

      # @param segment [String] a constant name segment
      # @param separator [String]
      # @return [String] +ServiceBike+ split before each capital that follows a lower-case letter or digit
      def split_words(segment, separator)
        segment.gsub(/(?<=[a-z0-9])(?=[A-Z])/, separator)
      end
    end
  end
end

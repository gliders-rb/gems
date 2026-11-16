# frozen_string_literal: true

module FieldStruct
  # The per-field checks the setter runs after coercing (section 5.3): missing values, restrictions, invalid nested
  # structs and +element:+ restrictions on array elements and map values. Included into {Base}.
  module FieldChecks
    private

    def fs_validate(field, value)
      errors.clear(field.name)
      if field.type_instance.missing?(value)
        errors.add(field.name, 'is required') if field.required? && !fs_null_answer?(field, value)
      elsif (problem = Restrictions.problem(value, field.options) || ('is invalid' if fs_invalid_struct?(field, value)))
        errors.add(field.name, problem)
      else
        fs_validate_elements(field, value)
      end
    end

    # A nested struct, or an Array or a +:hash+ field's Hash holding at least one, that is itself invalid.
    def fs_invalid_struct?(field, value)
      return value.invalid? if value.is_a?(Base)

      items = value.is_a?(::Array) ? value : fs_map_values(field, value)
      items ? items.any? { |item| item.is_a?(Base) && item.invalid? } : false
    end

    # The values of a +:hash+ field's Hash, or nil for anything else (a Hash elsewhere is not walked, FS-B39).
    def fs_map_values(field, value)
      value.values if value.is_a?(::Hash) && field.type_instance.is_a?(Types::Hash)
    end

    def fs_validate_elements(field, value)
      element = field.options[:element]
      return unless element

      if value.is_a?(::Array)
        fs_validate_array_elements(field, value, element)
      elsif (items = fs_map_values(field, value))
        bad = items.count { |item| Restrictions.problem(item, element) }
        errors.add(field.name, Types::Hash.invalid_entries_message(bad)) if bad.positive?
      end
    end

    def fs_validate_array_elements(field, value, element)
      bad = value.each_index.select { |index| Restrictions.problem(value[index], element) }
      errors.add(field.name, Types::Array.invalid_elements_message(bad)) unless bad.empty?
    end
  end
end

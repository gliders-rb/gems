# frozen_string_literal: true

module Actionable
  # The private verbs an action's steps use to record an outcome. Plain verbs record and continue; bang verbs halt.
  module Verbs
    # What a result with no recorded keywords answers (shared, never mutated).
    NO_KEYWORDS = {}.freeze
    private_constant :NO_KEYWORDS

    private

    # Records a Success and continues.
    def succeed(message = nil, **output)
      @result = remember(Success.new(message: message, output: output), output)
      true
    end

    # Records a Success and halts.
    def succeed!(message = nil, **output)
      succeed(message, **output)
      halt!
    end

    # Records a Failure (keywords are errors) and continues. +output:+ is the failure's output when its code
    # declares an output schema, or under typed outcomes (AC-B#outputkw); otherwise it is an error key.
    def fail(code, message = nil, **errors)
      failure = build_failure(code, message)
      given = errors.key?(:output) && output_keyword?(:failure, failure.code)
      record_output(:failure, failure, errors.delete(:output)) if given
      @result = failure
      add_errors(failure, errors)
      false
    end

    # Records a Failure and halts.
    def fail!(code, message = nil, **errors)
      fail(code, message, **errors)
      halt!
    end

    # Records a Failure that absorbs +source.errors+ and continues.
    def fail_with(source, code: :invalid, message: nil, output: nil)
      failure = build_failure(code, message)
      unless output.nil?
        unless output_keyword?(:failure, failure.code)
          raise ArgumentError, 'fail_with takes output: only under typed_outcomes or for a code that declares an output schema'
        end

        record_output(:failure, failure, output)
      end
      @result = failure.absorb_errors_from(source)
      false
    end

    # Records a Failure from +source+ and halts.
    def fail_with!(source, **)
      fail_with(source, **)
      halt!
    end

    # Records a Skipped and continues.
    def skip(code = :skipped, message = nil, **output)
      skipped = build_skip(code, message, output)
      refuse_output!(:skip, skipped.code) if typed_without_schema?(:skip, skipped.code) && !output.empty?
      @result = remember(skipped, output)
      false
    end

    # Records a Skipped and halts.
    def skip!(code = :skipped, message = nil, **output)
      skip(code, message, **output)
      halt!
    end

    # Stops the main steps without recording anything.
    def halt!
      throw Actionable::HALT
    end

    # Handles a child action's result for an action step: a failure is adopted and halts, anything else is absorbed.
    def take_child_result(child, expose)
      return adopt_child_failure(child) if child.failure?

      absorb_child_output(child, expose)
    end

    # The parent ends with the child's failure (code, message, errors, metadata). Its output stays on the child,
    # except where the parent judges it: under typed outcomes or for a code the parent gives a schema (AC-B#nestedtyped).
    def adopt_child_failure(child)
      declaration = declared_failure(child.code)
      attributes = child.class.attribute_names.to_h { |name| [name, child.public_send(name)] }
      attributes[:message] ||= declaration[:message]
      attributes[:metadata] = declaration.fetch(:metadata, {}).merge(child.metadata)
      failure = child.class.plain_class.new(**attributes.except(:output, :history))
      carry_child_output(failure, child)
      @result = failure.absorb_errors_from(child)
      halt!
    end

    def carry_child_output(failure, child)
      if Action::GEM_FAILURE_CODES.include?(child.code)
        return unless self.class.typed_outcomes?

        failure.output = child.output
        failure.errors.clear(:output)
        failure.output_fields_set = child.output_fields_set
      elsif output_keyword?(:failure, child.code)
        remember(failure, child_fields(child.output, child.output_fields_set))
      end
    end

    # Copies the fields the child set (all of a Hash output) onto this instance as ivars, narrowed by +expose+.
    def absorb_child_output(child, expose)
      fields = child_fields(child.output, child.output_fields_set)
      fields = fields.slice(*expose) if expose
      fields.each { |name, value| instance_variable_set("@#{name}", value) }
      fields
    end

    def child_fields(output, fields_set)
      case output
      when Hash then output.transform_keys(&:to_sym)
      when FieldStruct::Base
        names = fields_set || output.class.attribute_names
        names.to_h { |name| [name.to_sym, output.public_send(name)] }
      else {}
      end
    end

    def check_code!(code, kind, example)
      return code.to_sym if (code.is_a?(Symbol) || code.is_a?(String)) && Action::CODE_FORMAT.match?(code.to_s)

      raise ArgumentError, "#{Actionable.label_for(self.class)}: #{kind} code #{code.inspect} is not an identifier; " \
                           "use a Symbol like #{example}. Inside an action, fail records a failure, it is not " \
                           'Kernel#fail: to raise an exception, use raise'
    end

    def add_errors(failure, errors)
      errors.each do |field, messages|
        (messages.is_a?(Array) ? messages : [messages]).each { |message| failure.errors.add(field, message.to_s) }
      end
    end

    # Remembers the output keywords a verb was given, so every output refresh can overlay them again.
    def remember(result, keywords)
      (@recorded_keywords ||= {}.compare_by_identity)[result] = keywords
      result
    end

    # @return [Hash{Symbol=>Object}] the output keywords recorded with +result+ (empty for results built elsewhere)
    def recorded_keywords_for(result)
      return NO_KEYWORDS unless @recorded_keywords

      @recorded_keywords.fetch(result, NO_KEYWORDS)
    end
  end
end

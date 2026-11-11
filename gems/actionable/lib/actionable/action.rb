# frozen_string_literal: true

module Actionable
  # Subclass to declare steps, then call +.run+. Instances live for exactly one run.
  class Action
    # Failure codes the gem itself emits.
    #
    # @return [Array<Symbol>]
    GEM_FAILURE_CODES = %i[invalid_input invalid_output].freeze
    # What a failure or skip code must look like.
    #
    # @return [Regexp]
    CODE_FORMAT = /\A[[:alpha:]_][[:alnum:]_]*[?!]?\z/

    # Class state a subclass shares with its parent (the schemas and the dispatch).
    #
    # @return [Array<Symbol>]
    SHARED_STATE = %i[@output_schema @input_schema @input_dispatch].freeze
    # Class state a subclass gets by value at creation.
    #
    # @return [Array<Symbol>]
    COPIED_STATE = %i[@measure_mode @measure_rate @typed_outcomes].freeze
    # The ordered step sets a subclass copies (the main steps and the four hook lists).
    #
    # @return [Array<Symbol>]
    STEP_SETS = %i[steps success_hooks failure_hooks skip_hooks always_hooks].freeze

    extend SchemaMacros
    extend MeasureMacros
    extend Introspection
    extend DeclarationMacros
    extend TypedOutcomes
    include Declarations
    include Verbs

    class << self
      # Readers of every ordered step set, the core ones plus any an adapter registered.
      #
      # @return [Array<Symbol>]
      def step_set_readers
        STEP_SETS + Action.adapter_step_sets
      end

      # Step sets adapters add (the Rails +after_commit+ hooks); kept on +Action+ itself.
      #
      # @return [Array<Symbol>]
      def adapter_step_sets
        @adapter_step_sets ||= []
      end

      # Declares a step: a method name, or a child action class (+input:+ and +expose:+ options).
      #
      # @param target [Symbol, String, Class]
      # @param options [Object] +if:+ / +unless:+, and for an action step +input:+ / +expose:+
      # @return [Set<Actionable::Steps::Base>]
      def step(target, **options)
        upsert(steps, Steps.build(target, **options))
      end

      # Declares a case step: reads +value_source+ and runs the first matching branch.
      #
      # @param value_source [Symbol, String] a method returning the switch value
      # @param options [Object] +if:+ / +unless:+ for the whole step
      # @yield the branches, with +on(value, target, **opts)+ and +default(target, **opts)+
      # @return [Set<Actionable::Steps::Base>]
      def case_step(value_source, **options, &block)
        upsert(steps, Steps::Case.define(value_source, **options, &block))
      end

      # Hooks: declared like steps, run after the main steps depending on the outcome.
      # @param target [Symbol, String, Class]
      # @param options [Object]
      # @return [Set<Actionable::Steps::Base>]
      def on_success(target, **options)
        upsert(success_hooks, Steps.build(target, **options))
      end

      # @param target [Symbol, String, Class]
      # @param options [Object] +if:+ / +unless:+, and for an action step +input:+ / +expose:+
      # @return [Set<Actionable::Steps::Base>]
      def on_failure(target, **options)
        upsert(failure_hooks, Steps.build(target, **options))
      end

      # @param target [Symbol, String, Class]
      # @param options [Object] +if:+ / +unless:+, and for an action step +input:+ / +expose:+
      # @return [Set<Actionable::Steps::Base>]
      def on_skip(target, **options)
        upsert(skip_hooks, Steps.build(target, **options))
      end

      # @param target [Symbol, String, Class]
      # @param options [Object] +if:+ / +unless:+, and for an action step +input:+ / +expose:+
      # @return [Set<Actionable::Steps::Base>]
      def always(target, **options)
        upsert(always_hooks, Steps.build(target, **options))
      end

      # @return [Set<Actionable::Steps::Base>] the ordered step set (this class's own copy)
      def steps = (@steps ||= Set.new)

      # @return [Set<Actionable::Steps::Base>]
      def success_hooks = (@success_hooks ||= Set.new)

      # @return [Set<Actionable::Steps::Base>]
      def failure_hooks = (@failure_hooks ||= Set.new)

      # @return [Set<Actionable::Steps::Base>]
      def skip_hooks = (@skip_hooks ||= Set.new)

      # @return [Set<Actionable::Steps::Base>]
      def always_hooks = (@always_hooks ||= Set.new)

      # Runs the action once and returns its result.
      #
      # @param args [Object] forwarded verbatim to the constructor (free-form), or one input instance
      # @param kwargs [Object] forwarded verbatim to the constructor, or the typed input's keywords
      # @return [Actionable::Result]
      def run(*args, **kwargs)
        instance = typed_input? ? typed_instance(args, kwargs) : new(*args, **kwargs)
        return own_result(instance) if instance.is_a?(Result)

        check_implemented!(instance)
        check_verb_positions!
        own_result(Runner.new(instance).run)
      end

      # Runs the action once per item, independently.
      #
      # @param enumerable [Enumerable<Object>]
      # @yieldparam item [Object] maps an item to run arguments: Hash for keywords, Array for positionals
      # @return [Actionable::BatchResult]
      def run_each(enumerable)
        collected = []
        enumerable.each do |item|
          arguments = block_given? ? yield(item) : item
          collected << if arguments.is_a?(Hash)
                         run(**arguments)
                       elsif arguments.is_a?(Array)
                         run(*arguments)
                       else
                         run(arguments)
                       end
        end
        BatchResult.new(collected)
      end

      private

      def inherited(subclass)
        super
        [:failure_declarations, :skip_declarations, *step_set_readers].each do |reader|
          subclass.instance_variable_set(:"@#{reader}", public_send(reader).dup)
        end
        (SHARED_STATE + COPIED_STATE).each do |ivar|
          next unless instance_variable_defined?(ivar)

          subclass.instance_variable_set(ivar, instance_variable_get(ivar))
        end
        subclass.define_result_classes if subclass.typed_outcomes?
        Actionable.registry.register(subclass)
      end

      # Adds +item+, or replaces an equal one in place so the first declaration keeps its position.
      def upsert(set, item)
        Actionable.layout_changed!
        return set << item unless set.include?(item)

        set.replace(set.map { |existing| existing == item ? item : existing })
      end

      def typed_input?
        !input_schema.nil? || !input_dispatch.nil?
      end

      # An instance holding the validated input, or the Failure(:invalid_input) to return instead.
      def typed_instance(args, kwargs)
        input = typed_input_from(args, kwargs)
        return input if input.is_a?(Result)

        return input_failure(input, 'input failed validation') unless input.valid?

        instance = new
        instance.__send__(:assign_input, input)
        instance
      end

      def typed_input_from(args, kwargs)
        given = args.first if args.size == 1
        return given if given && input_schemas.any? { |schema| given.is_a?(schema) }

        schema = input_dispatch ? input_dispatch.schema_for(kwargs[input_dispatch.discriminator]) : input_schema
        schema ? schema.new(kwargs) : unmatched_input(kwargs)
      end

      # The metadata the action declared for a gem failure code, or an empty Hash.
      def gem_failure_metadata(code)
        failure_declarations.dig(code, :metadata) || {}
      end

      def input_schemas
        input_dispatch ? input_dispatch.schemas : [input_schema]
      end

      def unmatched_input(kwargs)
        discriminator = input_dispatch.discriminator
        input_failure(nil, "no input shape for #{discriminator} #{kwargs[discriminator].inspect}")
      end

      def input_failure(source, message)
        failure = Failure.new(code: :invalid_input, message: message, metadata: gem_failure_metadata(:invalid_input))
        failure.absorb_errors_from(source) if source
        failure
      end

      # Raises when a step calls a method the instance does not implement (Kernel and Object do not count).
      # The list of required names is remembered per class until a declaration changes anywhere (see
      # {Actionable.layout_changed!}) or a step set no longer holds the same steps; each run still asks the instance
      # about every name, so methods removed from a module, defined on one instance or added to a step set directly
      # are seen.
      def check_implemented!(instance)
        names = required_method_names
        return if names.all? { |name| implemented?(instance, name) }

        missing = names.reject { |name| implemented?(instance, name) }
        raise DefinitionError, "#{Actionable.label_for(self)} declares step(s) calling #{missing.map(&:inspect).join(', ')} " \
                               'but does not implement them'
      end

      def required_method_names
        token = Actionable.layout_token
        unless @required_token.equal?(token) && same_steps?(@required_steps)
          declared = step_set_readers.flat_map { |reader| public_send(reader).to_a }.freeze
          @required_names = declared.flat_map(&:required_methods).uniq.freeze
          @required_steps = declared
          @required_token = token
        end
        @required_names
      end

      # Whether the step sets still hold exactly +snapshot+'s steps, in order; compared by identity, no allocation.
      def same_steps?(snapshot)
        return false unless snapshot

        seen = 0
        STEP_SETS.each { |reader| (seen = matched_through(snapshot, seen, reader)) || (return false) }
        Action.adapter_step_sets.each { |reader| (seen = matched_through(snapshot, seen, reader)) || (return false) }
        seen == snapshot.size
      end

      # Matches one step set against +snapshot+ from +seen+ on; the next position, or nil on a difference.
      def matched_through(snapshot, seen, reader)
        public_send(reader).each do |step|
          return nil unless snapshot[seen].equal?(step)

          seen += 1
        end
        seen
      end

      # First-run check: plain recording verbs that are not in tail position (AC-B#verbcheck).
      # A passing check is remembered for this class; a failing one is not.
      def check_verb_positions!
        return if !Actionable.verb_position_check? || @verb_positions_checked

        found = VerbPosition.check(self)
        raise DefinitionError, VerbPosition.message(self, found) unless found.empty?

        @verb_positions_checked = true
      end

      # Public or private, on the class, a module, or this instance alone; Kernel, Object and BasicObject do not count.
      def implemented?(instance, name)
        return false unless instance.respond_to?(name, true)
        return true unless Object.method_defined?(name) || Object.private_method_defined?(name)

        ![Kernel, Object, BasicObject].include?(instance.method(name).owner)
      rescue NameError
        false
      end
    end

    # @param _args [Object] ignored; free-form actions override this
    # @param _kwargs [Object] ignored
    def initialize(*_args, **_kwargs); end

    # @return [Actionable::Result, nil] the result recorded so far
    attr_reader :result

    # @return [::FieldStruct::Base, nil] the typed input, nil for a free-form action
    attr_reader :input

    private

    def assign_input(input)
      @input = input
    end
  end
end

# frozen_string_literal: true

module Actionable
  # Static analyzer behind the first-run check and the RuboCop cop: finds plain recording verbs
  # (+fail+, +fail_with+, +skip+, +succeed+) that are not in tail position of their method.
  #
  # Prism is a runtime dependency but is only required on first need ({.prism?}), so a process that never runs the
  # check never loads it. Every position is a Prism byte offset.
  module VerbPosition
    # The verbs that record an outcome and keep running.
    #
    # @return [Array<Symbol>]
    VERBS = %i[fail fail_with skip succeed].freeze

    # One misplaced verb call.
    #
    # @!attribute [r] verb
    #   @return [Symbol]
    # @!attribute [r] method_name
    #   @return [Symbol] the enclosing +def+
    # @!attribute [r] start_offset
    #   @return [Integer] Prism byte offset of the call node
    # @!attribute [r] byte_length
    #   @return [Integer] byte length of the call node
    # @!attribute [r] line
    #   @return [Integer] 1-based line of the call
    Offense = Struct.new(:verb, :method_name, :start_offset, :byte_length, :line)

    # A parsed file with its +def+ nodes indexed by line and name (+nil+ when it did not parse cleanly), stamped for the cache.
    ParsedFile = Struct.new(:mtime, :bytes, :defs)

    @prism = nil
    @cache = {}
    @mutex = Mutex.new

    class << self
      # Whether Prism can be required and is version 1.0 or newer. Decided once.
      #
      # @return [Boolean]
      def prism?
        return @prism unless @prism.nil?

        @prism = load_prism
      end

      # Offenses of every +def+ in +source+ (an empty list when the source does not parse cleanly).
      #
      # @param source [String]
      # @return [Array<Offense>]
      def offenses_in_source(source)
        result = parse(source)
        return [] unless result

        all_defs(result.value).flat_map { |node| offenses_in(node) }
      end

      # Parses +source+ with Prism.
      #
      # @param source [String]
      # @return [::Prism::ParseResult, nil] nil when Prism is unavailable or the source has errors
      def parse(source)
        return nil unless prism?

        result = ::Prism.parse(source)
        result.success? ? result : nil
      end

      # Offenses in one +def+ node.
      #
      # @param def_node [::Prism::DefNode]
      # @return [Array<Offense>]
      def offenses_in(def_node)
        Walker.new(def_node.name).offenses_for(def_node)
      end

      # Offenses in the checked methods of an action class (steps, case-step branch targets, hooks).
      #
      # @param klass [Class] an Action subclass
      # @return [Array<Array(Symbol, String, Offense)>] +[method name, file, offense]+ triples, in declaration order
      def check(klass)
        return [] unless prism?

        method_names(klass).flat_map { |name| method_offenses(klass, name) }
      end

      # The error message for a class's offenses.
      #
      # @param klass [Class]
      # @param found [Array<Array(Symbol, String, Actionable::VerbPosition::Offense)>] what {.check} returned
      # @return [String]
      def message(klass, found)
        lines = found.map do |name, file, offense|
          "#{Actionable.label_for(klass)}##{name} (#{file}:#{offense.line}) calls `#{offense.verb}` with more code " \
            "after it, which still runs: use #{offense.verb}! to stop here, or make it the method's last expression"
        end
        "#{lines.join("\n")}\n(see USAGE, Control flow)"
      end

      private

      def load_prism
        require 'prism'
        Gem::Version.new(::Prism::VERSION) >= Gem::Version.new('1.0')
      rescue LoadError
        false
      end

      def all_defs(node, found = [])
        found << node if node.is_a?(::Prism::DefNode)
        node.compact_child_nodes.each { |child| all_defs(child, found) }
        found
      end

      # Names of the methods the check covers: method steps, case-step branch targets and hooks.
      def method_names(klass)
        steps = klass.step_set_readers.flat_map { |reader| klass.public_send(reader).to_a }
        steps.flat_map { |step| step.kind == :case ? step.branch_steps : [step] }
             .select { |step| step.kind == :method }.map(&:name).uniq
      end

      def method_offenses(klass, name)
        location, original = source_of(klass, name)
        return [] unless location

        file, line = location
        node = parsed_file(file)&.defs&.[]([line, original])
        return [] unless node

        offenses_in(node).map { |offense| [name, file, offense] }
      end

      def source_of(klass, name)
        method = klass.instance_method(name)
        [method.source_location, method.original_name]
      rescue NameError
        nil
      end

      # The parsed file, re-read when its modification time or size changed; nil when unreadable or not clean.
      def parsed_file(path)
        stat = File.stat(path)
        @mutex.synchronize do
          cached = @cache[path]
          return cached if cached && cached.mtime == stat.mtime && cached.bytes == stat.size

          @cache[path] = build_parsed_file(path, stat)
        end
      rescue SystemCallError
        nil
      end

      def build_parsed_file(path, stat)
        result = parse(File.read(path))
        defs = result && all_defs(result.value).to_h { |node| [[node.location.start_line, node.name], node] }
        ParsedFile.new(stat.mtime, stat.size, defs)
      end
    end

    # Walks one method body, tracking whether each node is in tail position.
    class Walker
      # @param method_name [Symbol]
      def initialize(method_name)
        @method_name = method_name
        @offenses = []
      end

      # @param def_node [::Prism::DefNode]
      # @return [Array<Offense>]
      def offenses_for(def_node)
        visit(def_node.body, true, false) if def_node.body
        @offenses
      end

      private

      HANDLERS = {
        statements_node: :visit_statements, call_node: :visit_call, else_node: :visit_else,
        if_node: :visit_branching, unless_node: :visit_branching, case_node: :visit_case, case_match_node: :visit_case,
        begin_node: :visit_begin, and_node: :visit_logical, or_node: :visit_logical, while_node: :visit_loop,
        until_node: :visit_loop, for_node: :visit_loop, return_node: :visit_jump, next_node: :visit_jump,
        break_node: :visit_jump, lambda_node: :visit_lambda, rescue_modifier_node: :visit_rescue_modifier,
        parentheses_node: :visit_parentheses, def_node: :ignore, class_node: :ignore, module_node: :ignore,
        singleton_class_node: :ignore
      }.freeze
      private_constant :HANDLERS

      # +tail+: the node's value is the method's value. +exit_ok+: a following next/break leaves the owning
      # block or loop whose call is itself in tail position.
      def visit(node, tail, exit_ok)
        return if node.nil?

        handler = HANDLERS.fetch(node.type, :visit_children)
        __send__(handler, node, tail, exit_ok)
      end

      def ignore(_node, _tail, _exit_ok); end

      def visit_else(node, tail, exit_ok) = visit(node.statements, tail, exit_ok)

      def visit_logical(node, tail, exit_ok)
        visit(node.left, false, false)
        visit(node.right, tail, exit_ok)
      end

      def visit_lambda(node, tail, _exit_ok) = visit(node.body, tail, tail)

      def visit_rescue_modifier(node, tail, exit_ok)
        visit(node.expression, tail, exit_ok)
        visit(node.rescue_expression, tail, exit_ok)
      end

      def visit_parentheses(node, tail, exit_ok) = visit(node.body, tail, exit_ok)

      # Anything that is not an explicit construct never passes tail position to its parts.
      def visit_children(node, _tail, _exit_ok)
        node.compact_child_nodes.each { |child| visit(child, false, false) }
      end

      def visit_statements(node, tail, exit_ok)
        body = node.body
        body.each_with_index do |statement, index|
          following = body[index + 1]
          last = following.nil?
          leaves = jumps?(following, exit_ok)
          visit(statement, (tail && last) || leaves, exit_ok)
        end
      end

      def jumps?(node, exit_ok)
        node.is_a?(::Prism::ReturnNode) || (exit_ok && (node.is_a?(::Prism::NextNode) || node.is_a?(::Prism::BreakNode)))
      end

      def visit_call(node, tail, _exit_ok)
        record(node) if verb?(node) && !tail
        visit(node.receiver, false, false)
        visit(node.arguments, false, false)
        block = node.block
        if block.is_a?(::Prism::BlockNode)
          visit(block.body, tail, tail)
        else
          visit(block, false, false)
        end
      end

      def verb?(node)
        VERBS.include?(node.name) && !node.safe_navigation? &&
          (node.receiver.nil? || node.receiver.is_a?(::Prism::SelfNode))
      end

      def record(node)
        location = node.location
        @offenses << Offense.new(node.name, @method_name, location.start_offset, location.length, location.start_line)
      end

      def visit_branching(node, tail, exit_ok)
        visit(node.predicate, false, false)
        visit(node.statements, tail, exit_ok)
        visit(subsequent_of(node), tail, exit_ok)
      end

      def subsequent_of(node)
        return node.subsequent if node.respond_to?(:subsequent)

        node.respond_to?(:else_clause) ? node.else_clause : node.consequent
      end

      def visit_case(node, tail, exit_ok)
        visit(node.predicate, false, false)
        node.conditions.each { |clause| visit_clause(clause, tail, exit_ok) }
        visit(node.else_clause, tail, exit_ok)
      end

      def visit_clause(clause, tail, exit_ok)
        parts = clause.is_a?(::Prism::WhenNode) ? clause.conditions : [clause.pattern]
        parts.each { |part| visit(part, false, false) }
        visit(clause.statements, tail, exit_ok)
      end

      def visit_begin(node, tail, exit_ok)
        body_tail = (tail && node.else_clause.nil?) || (node.ensure_clause && node.else_clause.nil?) || false
        visit(node.statements, body_tail, exit_ok)
        visit_rescue(node.rescue_clause, tail, exit_ok)
        visit(node.else_clause, tail, exit_ok)
        visit(node.ensure_clause&.statements, tail, exit_ok)
      end

      def visit_rescue(clause, tail, exit_ok)
        while clause
          clause.exceptions.each { |exception| visit(exception, false, false) }
          visit(clause.statements, tail, exit_ok)
          clause = subsequent_of_rescue(clause)
        end
      end

      def subsequent_of_rescue(clause)
        clause.respond_to?(:subsequent) ? clause.subsequent : clause.consequent
      end

      def visit_loop(node, tail, _exit_ok)
        case node
        when ::Prism::ForNode then visit(node.collection, false, false)
        else visit(node.predicate, false, false)
        end
        visit(node.statements, tail, tail)
      end

      # +return fail(:x)+ is the verb being returned; any other nesting is an offense.
      def visit_jump(node, _tail, _exit_ok)
        arguments = node.arguments&.arguments || []
        arguments.each do |argument|
          verb_call = argument.is_a?(::Prism::CallNode) && verb?(argument)
          visit(argument, verb_call, false)
        end
      end
    end
  end
end

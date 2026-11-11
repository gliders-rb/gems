# frozen_string_literal: true

module Actionable
  module VerbPosition
    # Finds, in one parsed file, the +def+ nodes an action class declares as steps or hooks. This is the static
    # counterpart of the runtime lookup: it reads class bodies, not live classes, so it sees one file only.
    class ClassScan
      # A class definition: +class X < Y+, +X = Class.new(Y)+ or an anonymous +Class.new(Y) { }+.
      Definition = Struct.new(:full_name, :superclass, :crefs, :body)

      # A superclass reference: the written name and whether it began with +::+.
      Reference = Struct.new(:name, :absolute)

      # Hook macros whose method-name targets count as steps.
      #
      # @return [Array<Symbol>]
      HOOKS = %i[on_success on_failure on_skip always after_commit].freeze
      # Bare calls that change the visibility of the defs that follow.
      #
      # @return [Array<Symbol>]
      VISIBILITY = %i[private public protected module_function].freeze

      # @param program [::Prism::ProgramNode]
      # @param bases [Array<String>] full names of the classes that count as action bases
      def initialize(program, bases)
        @bases = bases.map { |name| name.delete_prefix('::') }
        @definitions = []
        @names = []
        collect(program, [])
      end

      # @return [Array<::Prism::DefNode>] the method definitions of every action class that must be checked
      def checked_defs
        @definitions.select { |definition| checked?(definition) }.flat_map { |definition| defs_of(definition.body) }.uniq
      end

      private

      # --- pass 1: the definitions in the file ---

      def collect(node, crefs)
        case node
        when ::Prism::ClassNode then collect_class(node, crefs)
        when ::Prism::ModuleNode then collect_module(node, crefs)
        when ::Prism::ConstantWriteNode, ::Prism::ConstantPathWriteNode then collect_constant(node, crefs)
        when ::Prism::CallNode then collect_call(node, crefs)
        else collect_children(node, crefs)
        end
      end

      def collect_children(node, crefs)
        node.compact_child_nodes.each { |child| collect(child, crefs) }
      end

      def collect_class(node, crefs)
        full = qualify(crefs, path_name(node.constant_path))
        @names << full
        @definitions << Definition.new(full, node.superclass && reference(node.superclass), crefs, node.body)
        collect(node.body, [*crefs, full]) if node.body
      end

      def collect_module(node, crefs)
        full = qualify(crefs, path_name(node.constant_path))
        @names << full
        collect(node.body, [*crefs, full]) if node.body
      end

      def collect_constant(node, crefs)
        value = node.value
        return collect_children(node, crefs) unless class_new?(value)

        full = qualify(crefs, node.respond_to?(:name) && node.is_a?(::Prism::ConstantWriteNode) ? node.name.to_s : path_name(node.target))
        @names << full
        record_class_new(value, full, crefs)
      end

      def collect_call(node, crefs)
        return collect_children(node, crefs) unless class_new?(node)

        record_class_new(node, nil, crefs)
      end

      def record_class_new(call, full, crefs)
        block = call.block
        body = block.is_a?(::Prism::BlockNode) ? block.body : nil
        @definitions << Definition.new(full, reference(call.arguments.arguments.first), crefs, body)
        collect(body, crefs) if body
      end

      def class_new?(node)
        node.is_a?(::Prism::CallNode) && node.name == :new && class_constant?(node.receiver) &&
          node.arguments && reference(node.arguments.arguments.first)
      end

      def class_constant?(node)
        (node.is_a?(::Prism::ConstantReadNode) && node.name == :Class) ||
          (node.is_a?(::Prism::ConstantPathNode) && node.parent.nil? && node.name == :Class)
      end

      def path_name(node)
        node.is_a?(::Prism::ConstantReadNode) ? node.name.to_s : node.full_name.delete_prefix('::')
      rescue ::Prism::ConstantPathNode::DynamicPartsInConstantPathError
        node.slice
      end

      def reference(node)
        case node
        when ::Prism::ConstantReadNode then Reference.new(node.name.to_s, false)
        when ::Prism::ConstantPathNode then path_reference(node)
        end
      end

      def path_reference(node)
        full = node.full_name
        Reference.new(full.delete_prefix('::'), full.start_with?('::'))
      rescue ::Prism::ConstantPathNode::DynamicPartsInConstantPathError
        nil
      end

      def qualify(crefs, name)
        crefs.empty? ? name : "#{crefs.last}::#{name}"
      end

      # --- pass 2: which definitions are action classes ---

      def checked?(definition)
        definition.superclass && definition.body && action_base?(definition.superclass, definition.crefs, [definition.full_name]) &&
          declares_steps?(definition.body)
      end

      # Whether the reference leads, through definitions in this file, to one of the configured bases.
      def action_base?(reference, crefs, seen)
        name = resolve(reference, crefs)
        return false if seen.include?(name)

        own = @definitions.select { |definition| definition.full_name == name && definition.superclass }
        return @bases.include?(name) if own.empty?

        own.any? { |definition| action_base?(definition.superclass, definition.crefs, [*seen, name]) }
      end

      # Ruby's lookup: each enclosing scope outward, the first that has a class, module or base of that name.
      def resolve(reference, crefs)
        return reference.name if reference.absolute

        crefs.reverse_each do |cref|
          candidate = "#{cref}::#{reference.name}"
          return candidate if @names.include?(candidate) || @bases.include?(candidate)
        end
        reference.name
      end

      # --- the class body ---

      def statements_of(body)
        case body
        when ::Prism::StatementsNode then body.body
        when ::Prism::BeginNode then statements_of(body.statements)
        else []
        end
      end

      def calls_of(body)
        statements_of(body).select { |node| node.is_a?(::Prism::CallNode) && node.receiver.nil? }
      end

      def declares_steps?(body)
        calls_of(body).any? { |call| %i[step case_step].include?(call.name) }
      end

      def defs_of(body)
        names = checked_names(body)
        aliases = alias_map(body)
        wanted = names.map { |name| aliases.fetch(name, name) }
        all_defs(body).select { |node| node.receiver.nil? && wanted.include?(node.name) }
      end

      def checked_names(body)
        calls_of(body).flat_map do |call|
          case call.name
          when :step, *HOOKS then [literal_name(first_argument(call))]
          when :case_step then case_targets(call)
          else []
          end
        end.compact
      end

      def case_targets(call)
        body = call.block.is_a?(::Prism::BlockNode) ? call.block.body : nil
        calls_of(body).filter_map do |inner|
          case inner.name
          when :on then literal_name(inner.arguments&.arguments&.[](1))
          when :default then literal_name(first_argument(inner))
          end
        end
      end

      def first_argument(call)
        call.arguments&.arguments&.first
      end

      def literal_name(node)
        node.unescaped.to_sym if node.is_a?(::Prism::SymbolNode) || node.is_a?(::Prism::StringNode)
      end

      # +alias_method :new, :old+ and +alias new old+ as +{new => old}+.
      def alias_map(body)
        statements_of(body).each_with_object({}) do |node, map|
          pair = alias_pair(node)
          map[pair.first] = pair.last if pair
        end
      end

      def alias_pair(node)
        return [literal_name(node.new_name), literal_name(node.old_name)] if node.is_a?(::Prism::AliasMethodNode)
        return unless own_call?(node, :alias_method)

        arguments = node.arguments&.arguments || []
        [literal_name(arguments[0]), literal_name(arguments[1])] if arguments.size == 2
      end

      def own_call?(node, *names)
        node.is_a?(::Prism::CallNode) && node.receiver.nil? && names.include?(node.name)
      end

      # The class's own +def+ nodes: direct statements and +private def x+ forms, never nested classes.
      def all_defs(body)
        statements_of(body).flat_map do |node|
          next [node] if node.is_a?(::Prism::DefNode)

          own_call?(node, *VISIBILITY) ? (node.arguments&.arguments || []).grep(::Prism::DefNode) : []
        end
      end
    end
  end
end

# frozen_string_literal: true

module Actionable
  # Finds the actions an action runs by hand (+Child.run+ inside a method body), for +describe+'s +calls+.
  #
  # Static: it reads the Prism parse VerbPosition caches, starting from the methods the verb check covers and following
  # bare calls into the class's own methods. Dynamic receivers are out of reach by design.
  # @api private
  module HiddenCalls
    # The class methods that start a child action.
    #
    # @return [Array<Symbol>]
    RUNS = %i[run run!].freeze

    class << self
      # The Action subclasses run by hand, in order of first appearance, without repeats.
      #
      # @param klass [Class] an Action subclass
      # @return [Array<Class>]
      def of(klass)
        found = []
        seen = {}
        VerbPosition.checked_method_names(klass).each { |name| read_method(klass, name, found, seen) }
        found
      end

      private

      # Reads one method once, following a bare call into the class's own method where it appears.
      def read_method(klass, name, found, seen)
        return if seen[name]

        seen[name] = true
        node, = VerbPosition.def_node(klass, name)
        collect(node, klass, found, seen) if node
      end

      def collect(node, klass, found, seen)
        if node.is_a?(::Prism::CallNode)
          if RUNS.include?(node.name)
            child = action_constant(node.receiver, klass)
            found << child if child && !found.include?(child)
          elsif own_call?(node, klass)
            read_method(klass, node.name, found, seen)
          end
        end
        node.compact_child_nodes.each { |child| collect(child, klass, found, seen) }
      end

      def own_call?(node, klass)
        return false unless node.receiver.nil? || node.receiver.is_a?(::Prism::SelfNode)

        klass.method_defined?(node.name, true) || klass.private_method_defined?(node.name, true)
      end

      def action_constant(receiver, klass)
        path = constant_path(receiver)
        return nil unless path

        value = resolve(path, klass)
        value.is_a?(::Class) && value < Action ? value : nil
      end

      def constant_path(node)
        case node
        when ::Prism::ConstantReadNode then node.name.to_s
        when ::Prism::ConstantPathNode then node.full_name
        end
      rescue ::Prism::ConstantPathNode::DynamicPartsInConstantPathError
        nil
      end

      # Resolves +path+ the way Ruby would from inside the class body: innermost namespace first, then the top level.
      def resolve(path, klass)
        return lookup(::Object, path.delete_prefix('::')) if path.start_with?('::')

        parts = klass.name.to_s.split('::')
        parts.size.downto(0) do |depth|
          scope = depth.zero? ? ::Object : lookup(::Object, parts.first(depth).join('::'))
          value = scope && lookup(scope, path)
          return value if value
        end
        nil
      end

      def lookup(scope, path)
        path.split('::').reduce(scope) do |owner, part|
          return nil unless owner.is_a?(::Module) && owner.const_defined?(part, false)

          owner.const_get(part, false)
        end
      end
    end
  end
end

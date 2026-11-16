# frozen_string_literal: true

module FieldStruct
  # Per-field validation messages. A plain value object; keys are Symbols.
  class Errors
    # @param owner [FieldStruct::Base, nil] the struct these errors belong to; +paths+ walks it (FS-B40a)
    def initialize(owner = nil)
      @messages = {}
      @owner = owner
      @origins = nil
    end

    # @param field [Symbol, String]
    # @return [Array<String>] the field's messages, or a throwaway empty Array
    def [](field)
      @messages.fetch(field.to_sym) { [] }
    end

    # Appends a message for a field.
    #
    # @param field [Symbol, String]
    # @param message [String]
    # @return [Array<String>] the field's messages
    def add(field, message)
      (@messages[field.to_sym] ||= []) << message
    end

    # Removes all messages for a field.
    #
    # @param field [Symbol, String]
    # @return [nil]
    def clear(field)
      @messages.delete(field.to_sym)
      nil
    end

    # Freezes the messages too, so +add+ and +clear+ raise +FrozenError+; a +dup+ owns unfrozen copies.
    #
    # @return [self]
    def freeze
      @messages.each_value(&:freeze).freeze
      @origins&.freeze
      super
    end

    # @return [Boolean] true when no field has a message
    def empty?
      @messages.each_value { |messages| return false unless messages.empty? }
      true
    end

    # @return [Hash{Symbol=>Array<String>}] only fields that have messages
    def to_h
      present.transform_values(&:dup)
    end

    # Same as {#to_h}.
    #
    # @return [Hash{Symbol=>Array<String>}]
    def messages
      to_h
    end

    # @return [Array<String>] humanized field name plus message; +:base+ is unprefixed
    def full_messages
      present.flat_map do |field, messages|
        field == :base ? messages.dup : messages.map { |message| "#{humanize(field)} #{message}" }
      end
    end

    # @return [String]
    def inspect
      pairs = present.map { |field, messages| "#{field}=#{messages.inspect}" }
      "#<#{FieldStruct.inspect_namespace}::Errors #{pairs.empty? ? 'empty' : pairs.join(' ')}>"
    end

    # Where each message comes from, nested structs included (FS-B40a). Walks the owner's current values and runs no
    # validators; +to_h+ is unchanged.
    #
    # @return [Hash{String=>Array<String>}] a new Hash each call, e.g. +{"parts[1].code" => ["is required"]}+
    def paths
      out = {}
      seen = {}.compare_by_identity
      seen[@owner] = true if @owner
      walk(out, '', seen)
      out
    end

    # Copies every message of +other+ and remembers +other+'s owner as the origin of those keys, so +paths+ walks it.
    #
    # @api private
    # @param other [FieldStruct::Errors]
    # @return [self]
    def absorb(other)
      other.present.each do |field, messages|
        messages.each { |message| add(field, message) }
        origin = other.origin_for(field)
        (@origins ||= {})[field] = origin if origin && !origin.equal?(@owner)
      end
      self
    end

    # A copy owned by +owner+ (what +dup+ of a struct gives its copy).
    #
    # @api private
    # @param owner [FieldStruct::Base]
    # @return [FieldStruct::Errors]
    def copy_for(owner)
      dup.rehome(owner)
    end

    protected

    # @param owner [FieldStruct::Base]
    # @return [self] with +owner+ as the struct +paths+ walks
    def rehome(owner)
      @owner = owner
      self
    end

    # @return [Hash{Symbol=>Array<String>}] the fields that have messages
    def present
      @messages.reject { |_field, messages| messages.empty? }
    end

    # @param field [Symbol]
    # @return [FieldStruct::Base, nil] the struct whose value +field+ names
    def origin_for(field)
      @origins&.[](field) || @owner
    end

    # Appends this object's paths under +prefix+ to +out+.
    #
    # @param out [Hash{String=>Array<String>}]
    # @param prefix [String] '' at the root
    # @param seen [Hash{FieldStruct::Base=>Boolean}] structs already walked (compared by identity)
    # @return [void]
    def walk(out, prefix, seen)
      present.each do |field, messages|
        path = path_for(prefix, field)
        rest = expand(out, field, messages, path, seen)
        (out[path] ||= []).concat(rest) unless rest.empty?
      end
    end

    # Walks the structs that account for an "is invalid" on +field+.
    #
    # @param out [Hash{String=>Array<String>}]
    # @param field [Symbol]
    # @param messages [Array<String>]
    # @param path [String]
    # @param seen [Hash{FieldStruct::Base=>Boolean}]
    # @return [Array<String>] the messages left for the field's own path
    def expand(out, field, messages, path, seen)
      index = messages.index('is invalid')
      children = index ? children_of(origin_for(field), field, path, seen) : []
      return messages.dup if index.nil? || children.empty?

      children.each { |child, child_path| child.errors.walk(out, child_path, seen) }
      messages.dup.tap { |rest| rest.delete_at(index) }
    end

    # The nested structs under +owner+'s +field+ that have errors right now, with their paths; each is marked seen.
    #
    # @param owner [FieldStruct::Base, nil]
    # @param field [Symbol]
    # @param path [String]
    # @param seen [Hash{FieldStruct::Base=>Boolean}]
    # @return [Array<Array(FieldStruct::Base, String)>]
    def children_of(owner, field, path, seen)
      declared = owner && owner.class.metadata[field]
      return [] unless declared

      value = owner.instance_variable_get(declared.ivar_name)
      pairs = child_pairs(value, declared, path)
      pairs.select { |item, _| item.is_a?(Base) && claim(item, seen) }
    end

    # Each candidate child with its path: Array elements by index, a +:hash+ field's values by quoted key.
    #
    # @param value [Object]
    # @param field [FieldStruct::Field]
    # @param path [String]
    # @return [Array<Array(Object, String)>]
    def child_pairs(value, field, path)
      return value.each_with_index.map { |item, index| [item, "#{path}[#{index}]"] } if value.is_a?(::Array)
      return [[value, path]] unless value.is_a?(::Hash) && field.type_instance.is_a?(Types::Hash)

      value.map { |key, item| [item, "#{path}{#{Oj.dump(key.to_s, mode: :compat)}}"] }
    end

    # @param item [FieldStruct::Base]
    # @param seen [Hash{FieldStruct::Base=>Boolean}]
    # @return [Boolean] true when +item+ has errors and was not walked yet; marks it seen
    def claim(item, seen)
      return false if item.errors.empty? || seen[item]

      seen[item] = true
    end

    private

    def initialize_copy(source)
      super
      @messages = source.instance_variable_get(:@messages).transform_values(&:dup)
      @origins = @origins&.dup
    end

    # @param prefix [String]
    # @param field [Symbol]
    # @return [String] the path of +field+ under +prefix+; +:base+ is the prefix itself, or "base" at the root
    def path_for(prefix, field)
      return (prefix.empty? ? 'base' : prefix) if field == :base

      prefix.empty? ? field.to_s : "#{prefix}.#{field}"
    end

    def humanize(field)
      text = field.to_s.tr('_', ' ')
      text.empty? ? text : text[0].upcase + text[1..]
    end
  end
end

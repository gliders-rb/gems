# frozen_string_literal: true

module FieldStruct
  # Naming helpers in the shape Rails-adjacent code expects. Obtained from +Base.model_name+.
  class ModelName
    # @return [String] the full class name
    attr_reader :name
    # @return [String] snake_case of the last name segment
    attr_reader :element
    # @return [String] same as {#element}
    attr_reader :singular
    # @return [String] {#element} plus +"s"+ (no inflection)
    attr_reader :plural

    # @param name [String] the full class name
    def initialize(name)
      @name = name
      @element = snake_case(name.split('::').last)
      @singular = @element
      @plural = "#{@element}s"
      freeze
    end

    # @return [String] the full class name
    def to_s
      name
    end

    # Same as {#to_s}, so a ModelName converts implicitly to a String.
    #
    # @return [String]
    def to_str
      to_s
    end

    private

    def snake_case(segment)
      segment
        .gsub(/(?<=[a-z\d])(?=[A-Z])/, '_')
        .gsub(/(?<=[A-Z])(?=[A-Z][a-z])/, '_')
        .downcase
    end
  end
end

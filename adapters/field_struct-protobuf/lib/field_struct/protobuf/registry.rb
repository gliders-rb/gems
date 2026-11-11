# frozen_string_literal: true

require 'monitor'

module FieldStruct
  module Protobuf
    # The process-wide registry of message classes, keyed by +[class, serialization]+ behind one monitor (PB-B30..B32).
    # Registration into google-protobuf's generated pool is permanent (PB-I7), so nothing here is ever removed.
    module Registry
      @lock = Monitor.new
      @messages = {}
      @by_serialization = {}
      @serializations = {}

      class << self
        # The registered message class of a struct, built and registered (with the messages of every struct it refers to)
        # on first use.
        #
        # @param klass [::Class<FieldStruct::Base>] a checked, named struct class
        # @param serialization [::Symbol]
        # @return [::Class] the message class
        # @raise [::ArgumentError] for a bad field, a cycle or a second serialization
        def message_class(klass, serialization)
          known = @by_serialization[serialization]&.[](klass)
          return known if known

          @lock.synchronize { register(klass, serialization, []) }
        end

        private

        def register(klass, serialization, trail)
          first = @serializations[klass]
          if first && first != serialization
            raise ::ArgumentError, "#{klass} is already registered with serialization #{first.inspect}; " \
                                   "it can't also be registered with #{serialization.inspect}"
          end
          known = @messages[[klass, serialization]]
          return known if known

          build(klass, serialization, trail + [klass])
        end

        def build(klass, serialization, trail)
          file = DescriptorBuilder.new(klass, serialization).call
          References.call(klass, serialization).each do |ref|
            cycle!(trail, ref) if trail.include?(ref)
            register(Check.call(ref), serialization, trail)
          end
          pool = Google::Protobuf::DescriptorPool.generated_pool
          pool.add_serialized_file(Google::Protobuf::FileDescriptorProto.encode(file))
          message = pool.lookup(Names.full_name(klass).delete_prefix('.')).msgclass
          @serializations[klass] = serialization
          (@by_serialization[serialization] ||= {}.compare_by_identity)[klass] = message
          @messages[[klass, serialization]] = message
        end

        def cycle!(trail, repeat)
          chain = (trail + [repeat]).join(' -> ')
          raise ::ArgumentError, "#{chain}: structs that refer to each other would be protobuf files that import each other, " \
                                 "which protobuf doesn't allow"
        end
      end
    end
  end
end

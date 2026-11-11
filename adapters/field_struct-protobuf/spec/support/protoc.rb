# frozen_string_literal: true

require 'open3'
require 'tmpdir'
require 'fileutils'

# The PB-I2 oracle: compile the printed .proto text with grpc-tools' protoc and compare the result with the gem's own
# descriptors, per file: package, dependency, and per message [name, oneof names, [field facts]].
module ProtocCheck
  PROTOC = Gem::Specification.find_by_name('grpc-tools').bin_file('grpc_tools_ruby_protoc')

  module_function

  # @param files [Hash{String=>String}] .proto text by file name
  # @return [Hash{String=>Hash}] normalized facts by file name, from protoc
  def compile(files)
    Dir.mktmpdir('protoc_check') do |dir|
      files.each do |name, text|
        FileUtils.mkdir_p(File.dirname(File.join(dir, name)))
        File.write(File.join(dir, name), text)
      end
      out = File.join(dir, 'out.pb')
      output, status = Open3.capture2e(RbConfig.ruby, PROTOC, "-I#{dir}", "--descriptor_set_out=#{out}", *files.keys, chdir: dir)
      raise "protoc failed:\n#{output}" unless status.success?

      set = Google::Protobuf::FileDescriptorSet.decode(File.binread(out))
      set.file.to_h { |file| [file.name, normalize(file)] }
    end
  end

  # @param file [Google::Protobuf::FileDescriptorProto]
  # @return [Hash]
  def normalize(file)
    {
      package: file.package, syntax: file.syntax, dependency: file.dependency.to_a,
      messages: file.message_type.map do |message|
        [message.name, message.oneof_decl.map(&:name), message.field.map { |f| field_facts(f) }]
      end
    }
  end

  def field_facts(field)
    [field.name, field.number, field.label, field.type, field.type_name, field.proto3_optional,
     field.has_oneof_index? ? field.oneof_index : nil]
  end

  # @param klasses [Array<Class>] a struct and the structs it refers to
  # @return [Hash{String=>Hash}] the gem's own facts by file name
  def ours(klasses)
    klasses.to_h do |klass|
      [FieldStruct::Protobuf.file_name(klass), normalize(FieldStruct::Protobuf.file_descriptor(klass))]
    end
  end

  # @param klasses [Array<Class>]
  # @return [Hash{String=>String}]
  def texts(klasses)
    klasses.to_h { |klass| [FieldStruct::Protobuf.file_name(klass), FieldStruct::Protobuf.proto(klass)] }
  end
end

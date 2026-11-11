# frozen_string_literal: true

require 'rbs'

# The shipped signature must admit nil wherever the runtime can return it: an optional field is nil after `new`.
RSpec.describe 'shipped sig nullability' do
  let(:declarations) do
    source = FieldStruct.root.join('sig/field_struct.rbs').read
    _buffer, _directives, decls = RBS::Parser.parse_signature(source)
    decls
  end

  def find_class(name)
    declarations.each do |decl|
      next unless decl.is_a?(RBS::AST::Declarations::Module)

      decl.members.each do |member|
        return member if member.is_a?(RBS::AST::Declarations::Class) && member.name.name.to_s == name
      end
    end
    raise "class #{name} not in sig"
  end

  def return_type(class_name, method_name)
    member = find_class(class_name).members.find { |m| named?(m, method_name) }
    raise "#{class_name}##{method_name} not in sig" unless member

    member.is_a?(RBS::AST::Members::AttrReader) ? member.type : member.overloads.first.method_type.type.return_type
  end

  def named?(member, method_name)
    case member
    when RBS::AST::Members::MethodDefinition then member.name == method_name && member.kind == :instance
    when RBS::AST::Members::AttrReader then member.name == method_name
    else false
    end
  end

  def admits_nil?(type)
    case type
    when RBS::Types::Optional, RBS::Types::Bases::Nil, RBS::Types::Bases::Any then true
    when RBS::Types::Union then type.types.any? { |member| admits_nil?(member) }
    else false
    end
  end

  def value_type(type)
    type.args.last
  end

  it 'self-test: the helper tells nil-admitting types from the rest' do
    parse = ->(text) { RBS::Parser.parse_type(text) }
    expect(admits_nil?(parse.call('Object?'))).to be(true)
    expect(admits_nil?(parse.call('untyped'))).to be(true)
    expect(admits_nil?(parse.call('(String | nil)'))).to be(true)
    expect(admits_nil?(parse.call('Object'))).to be(false)
  end

  it 'lets attributes, to_h, as_json and deconstruct_keys hold nil values' do
    %i[attributes to_h as_json deconstruct_keys].each do |name|
      expect(admits_nil?(value_type(return_type('Base', name)))).to be(true), "Base##{name}"
    end
  end

  it 'lets deconstruct hold nil elements' do
    expect(admits_nil?(return_type('Base', :deconstruct).args.first)).to be(true)
  end

  it 'lets Field#options hold nil values' do
    expect(admits_nil?(value_type(return_type('Field', :options)))).to be(true)
  end

  it 'lets Metadata#to_h hold nil inside its per-field Hashes' do
    inner = value_type(return_type('Metadata', :to_h))
    expect(admits_nil?(value_type(inner))).to be(true)
  end

  it 'matches the runtime: these really are nil' do
    klass = Class.new(FieldStruct::Base) do
      optional :nickname, :string
      optional :born, :date, format: nil
    end
    instance = klass.new
    expect(instance.attributes[:nickname]).to be_nil
    expect(instance.as_json[:nickname]).to be_nil
    expect(instance.deconstruct_keys(nil)[:nickname]).to be_nil
    expect(instance.deconstruct).to include(nil)
    expect(klass.metadata[:born].options[:format]).to be_nil
    expect(klass.metadata.to_h[:nickname][:default]).to be_nil
  end
end

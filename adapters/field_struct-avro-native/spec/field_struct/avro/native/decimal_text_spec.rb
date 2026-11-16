# frozen_string_literal: true

require 'open3'

# Spec decision N7: the decimal writer must not depend on BigDecimal#to_s's default format, which
# ActiveSupport changes to plain notation. The child process makes that change itself, so this suite
# needs no ActiveSupport and stays unpatched.
RSpec.describe FieldStruct::Avro::Native, 'decimal text' do
  probe = <<~RUBY
    require 'bigdecimal'
    require 'stringio'
    require 'field_struct/avro/native'
    require 'oj'

    BigDecimal.prepend(Module.new { def to_s(format = 'F') = super })

    schema = Avro::Schema.parse(Oj.dump({
      'type' => 'record', 'name' => 'Tide', 'fields' => [
        { 'name' => 'height', 'type' => { 'type' => 'bytes', 'logicalType' => 'decimal', 'precision' => 7, 'scale' => 3 } },
        { 'name' => 'drift', 'type' => { 'type' => 'bytes', 'logicalType' => 'decimal', 'precision' => 9, 'scale' => 4 } }
      ]
    }, mode: :compat))
    datum = { 'height' => BigDecimal('-412.075'), 'drift' => BigDecimal('0.0031') }

    io = StringIO.new(''.b)
    Avro::IO::DatumWriter.new(schema).write(datum, Avro::IO::BinaryEncoder.new(io))
    native = FieldStruct::Avro::Native.encode(schema, datum)
    print Oj.dump({ 'plain' => BigDecimal('-412.075').to_s, 'native' => native&.unpack1('H*'),
                    'pure' => io.string.unpack1('H*') }, mode: :compat)
  RUBY

  it 'writes decimals natively when BigDecimal#to_s defaults to plain notation' do
    out, status = Open3.capture2e('bundle', 'exec', 'ruby', "-I#{File.expand_path('../../../../lib', __dir__)}",
                                  '-e', probe, chdir: File.expand_path('../../../..', __dir__))
    raise "probe failed:\n#{out}" unless status.success?

    report = Oj.load(out)
    expect(report['plain']).to eq('-412.075')
    expect(report['native']).to eq(report['pure'])
  end
end

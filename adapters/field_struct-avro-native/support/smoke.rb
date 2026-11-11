# frozen_string_literal: true

# Dev-only: the encode smoke test run by support/smoke_install.sh against an installed gem. Not packaged with the gem.
require 'field_struct/avro'

# A named class on purpose: Avro schemas are generated from named struct classes.
class Beacon < FieldStruct::Base
  required :id, :integer
  required :tower, :string
end

beacon = Beacon.new(id: 7, tower: 'north')
pure = FieldStruct::Avro.encode(beacon)

require 'field_struct/avro/native'
abort 'FAIL: native encoder is not enabled' unless FieldStruct::Avro::Native.enabled?

native = FieldStruct::Avro.encode(beacon)
abort "FAIL: native bytes #{native.bytes.inspect} differ from pure #{pure.bytes.inspect}" unless native == pure
abort 'FAIL: decode of the native bytes differs' unless FieldStruct::Avro.decode(Beacon, native) == beacon

binary = $LOADED_FEATURES.grep(/field_struct_avro_native\.(so|bundle)\z/).first
puts "ok: ruby #{RUBY_VERSION} #{RUBY_PLATFORM}, bytes #{native.bytes.inspect}"
puts "binary: #{binary}"

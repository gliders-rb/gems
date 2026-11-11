# frozen_string_literal: true

# Indicative timings, not a gate. No dependencies beyond the gem: `bundle exec rake bench`.
require_relative '../lib/field_struct'

class BenchAddress < FieldStruct::Base
  required :habitat, :string
  optional :plot_no, :string
end

class BenchUser < FieldStruct::Base
  required :name,  :string
  required :email, :email
  optional :height, :integer, in: 0..150
  optional :score, :float, round: 2
  optional :seen,  :datetime, format: :iso8601
  optional :border, BenchAddress
  optional :tags, :array, of: :string
end

class BenchLoose < FieldStruct::Base
  required :code, :string
  optional :note, :string
end

class BenchStrict < FieldStruct::Base
  required :code, :string, strict: true
  optional :note, :string, strict: true
end

class BenchChecked < FieldStruct::Base
  required :a, :string, format: /\A[a-z]+\z/, enum: %w[abc def]
  required :b, :integer, in: 1..100
  optional :c, :array, of: :integer, element: { in: 1..100 }
  validate { |record| record.errors.add(:base, 'a and b disagree') if record.a == 'abc' && record.b == 99 }
end

ATTRS = { name: 'Ana', email: 'ana@example.com', height: '31', score: '9.876', seen: '2026-03-04T05:06:07Z',
          border: { habitat: 'Lima', plot_no: '15001' }, tags: %w[a b c] }.freeze
JSON_TEXT = BenchUser.new(ATTRS).to_json
BIG = Array.new(100, &:to_s).freeze
USER = BenchUser.new(ATTRS)
BenchList = Class.new(FieldStruct::Base) { optional :ids, :array, of: :integer }

def measure(label, iterations, &)
  yield # warm up
  started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  iterations.times(&)
  elapsed = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
  puts format('%-34<label>s %9.0<rate>f ops/s  %8.2<micros>f us/op', label: label, rate: iterations / elapsed,
                                                                     micros: elapsed / iterations * 1_000_000)
end

puts "field_struct #{FieldStruct::VERSION} on Ruby #{RUBY_VERSION}"
measure('new (7 fields, nested)', 20_000) { BenchUser.new(ATTRS) }
measure('from_json', 10_000) { BenchUser.from_json(JSON_TEXT) }
measure('to_json', 20_000) { USER.to_json }
measure('as_json', 20_000) { USER.as_json }
measure('nested only', 50_000) { BenchAddress.new(habitat: 'Lima', plot_no: '1') }
measure('array of 100 integers', 5_000) { BenchList.new(ids: BIG) }
measure('default strings', 50_000) { BenchLoose.new(code: 'x', note: 'y') }
measure('strict: true strings', 50_000) { BenchStrict.new(code: 'x', note: 'y') }
measure('validation-heavy (valid)', 20_000) { BenchChecked.new(a: 'abc', b: '50', c: [1, 2, 3]).valid? }
measure('validation-heavy (invalid)', 20_000) { BenchChecked.new(a: 'zzz', b: '500', c: [1, 500]).valid? }

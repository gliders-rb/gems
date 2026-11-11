# frozen_string_literal: true

# FS-I6 static guard: lib/ must not dispatch on predicates a framework (ActiveSupport) can redefine.
RSpec.describe 'ActiveSupport independence guard' do
  forbidden_predicates = %w[to_date to_time to_datetime as_json blank? present? try try! presence in? acts_like?].freeze
  allowed = { 'lib/field_struct/json_codec.rb' => 1 }.freeze

  define_method(:offences) do |source|
    names = forbidden_predicates.map { |name| Regexp.escape(name) }.join('|')
    source.each_line.with_index.select do |line, _|
      line.match?(/respond_to\?\(?\s*:(?:#{names})(?!\w)/) || line.match?(/respond_to\?\(?\s*['"](?:#{names})['"]/)
    end
  end

  it 'self-test: the scan finds what it looks for' do
    expect(offences("x.respond_to?(:to_date)\n").size).to eq(1)
    expect(offences("x.respond_to? :as_json\n").size).to eq(1)
    expect(offences("x.respond_to?('blank?')\n").size).to eq(1)
    expect(offences("x.respond_to?(:blank?)\n").size).to eq(1)
    expect(offences("x.respond_to?(:call)\n")).to be_empty
  end

  it 'finds none in lib/ beyond the allowlisted as_json arm' do
    root = FieldStruct.root.to_s
    Dir[File.join(root, 'lib', '**', '*.rb')].each do |path|
      relative = path.delete_prefix("#{root}/")
      found = offences(File.read(path)).size
      expect(found).to eq(allowed.fetch(relative, 0)), "#{relative}: #{found} respond_to? on a framework-redefinable predicate"
    end
  end

  it 'never requires ActiveSupport or ActiveModel' do
    Dir[File.join(FieldStruct.root.to_s, 'lib', '**', '*.rb')].each do |path|
      expect(File.read(path)).not_to match(/require\s+['"]active_(support|model)/)
    end
  end
end

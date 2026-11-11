# frozen_string_literal: true

RSpec.describe Actionable::ValueMatch do
  it 'AC-B#valuematch: an Array branch matches by inclusion' do
    expect(described_class.matches?(%w[a b], 'b')).to be(true)
    expect(described_class.matches?(%w[a b], 'c')).to be(false)
  end

  it 'AC-B#valuematch: a Regexp branch matches the String form' do
    expect(described_class.matches?(/\Az/, 'zed')).to be(true)
    expect(described_class.matches?(/\d/, 42)).to be(true)
    expect(described_class.matches?(/\Az/, nil)).to be(false)
  end

  it 'AC-B#valuematch: anything else matches by ==, a Range never matches a member' do
    expect(described_class.matches?('a', 'a')).to be(true)
    expect(described_class.matches?(4..6, 5)).to be(false)
    expect(described_class.matches?(4..6, 4..6)).to be(true)
    expect(described_class.matches?(nil, nil)).to be(true)
    expect(described_class.matches?(nil, 'x')).to be(false)
  end
end

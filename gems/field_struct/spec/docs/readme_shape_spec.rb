# frozen_string_literal: true

# The README is a pitch, the install line, one runnable example and links; the reference lives in USAGE and on the
# site, so it isn't written twice by hand.
RSpec.describe 'README shape' do
  readme = File.read(File.expand_path('../../README.md', __dir__))

  it 'has only the expected sections' do
    expect(readme.scan(/^## (.+)$/).flatten).to eq(['A first model', 'Where to go next'])
  end

  it 'has exactly one runnable example' do
    expect(readme.scan(/^```ruby run$/).size).to eq(1)
  end

  it 'links to USAGE, the getting-started guide and the site' do
    expect(readme).to include('(USAGE.md)', '(docs/getting_started.md)', '(https://gliders-rb.github.io/)')
  end
end

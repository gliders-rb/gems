# frozen_string_literal: true

RSpec.describe FieldStruct::ModelName do
  def model_name_for(name)
    klass = Class.new(FieldStruct::Base)
    allow(klass).to receive(:name).and_return(name)
    klass.model_name
  end

  it 'FS-B117: derives name, element, singular, plural and to_s from the class name' do
    model = model_name_for('Nursery::LineItem')
    expect(model.name).to eq('Nursery::LineItem')
    expect(model.element).to eq('line_item')
    expect(model.singular).to eq('line_item')
    expect(model.plural).to eq('line_items')
    expect(model.to_s).to eq('Nursery::LineItem')
    expect(model.to_str).to eq('Nursery::LineItem')
  end

  it 'FS-B117: runs of capitals split as acronyms' do
    expect(model_name_for('HTTPRequest').element).to eq('http_request')
  end

  it 'FS-B117: plural is naive' do
    expect(model_name_for('Cactus').plural).to eq('cactuss')
    expect(model_name_for('Tomato').plural).to eq('tomatos')
  end
end

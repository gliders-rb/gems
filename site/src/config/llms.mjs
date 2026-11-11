// Settings for the llms.txt outputs.
const gemLines = [
  '- `field_struct` is a Ruby gem for typed plain Ruby objects: fields are declared, coerced and validated. Its RubyGems name is `field_struct`.',
  '- `actionable-rb` is a Ruby gem for action objects with declared inputs, steps and three outcomes (success, failure, error). Its RubyGems name is `actionable-rb`; you require it as `actionable`.',
  '- Adapters (JSON Schema, Avro, OpenTelemetry, Protobuf, tools) build on the two gems and are not released yet.',
  '- Every runnable Ruby example in these docs is executed in CI, so a `# => value` comment is a real result, not an illustration.',
];

const set = (label, description, glob) => ({ label, description, paths: [glob] });

export const llmsOptions = {
  projectName: 'FieldStruct and Actionable',
  description:
    'Documentation for field_struct (typed plain-Ruby objects with declared, coerced, validated fields) and actionable-rb (action objects with declared inputs, steps and outcomes), plus their adapters.',
  details: gemLines.join('\n'),
  promote: ['index*', 'tutorial/**'],
  customSets: [
    set('field_struct reference', 'Every public rule of field_struct.', 'reference/field-struct/**'),
    set('actionable reference', 'Every public rule of actionable-rb.', 'reference/actionable/**'),
    set('Adapters', 'Adapters, their introspection and how to build your own.', 'adapters/**'),
  ],
};

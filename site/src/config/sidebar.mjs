// Sidebar layout. Each section is a directory of the docs collection.
const section = (label, directory) => ({ label, items: [{ autogenerate: { directory } }] });

export const sidebar = [
  section('Tutorial', 'tutorial'),
  section('How-to guides', 'how-to'),
  {
    label: 'Reference',
    items: [
      { slug: 'reference' },
      section('field_struct', 'reference/field-struct'),
      section('actionable', 'reference/actionable'),
    ],
  },
  section('Explanation', 'explanation'),
  // Starlight has no group badge, so every adapters page carries the "Unreleased" badge in its front matter.
  section('Adapters', 'adapters'),
];

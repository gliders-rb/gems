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
  // No stage badges: every gem ships as a prerelease, and the adapters overview says which APIs may change.
  // (Starlight 0.42 can badge a group too, should one be needed: `badge` on the group object.)
  section('Adapters', 'adapters'),
];

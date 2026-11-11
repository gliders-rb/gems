import starlight from '@astrojs/starlight';
import starlightLlmsTxt from 'starlight-llms-txt';
import { defineConfig } from 'astro/config';
import { llmsOptions } from './src/config/llms.mjs';
import { sidebar } from './src/config/sidebar.mjs';

// Hosting values: the site is the gliders-rb org root, built from this repo and pushed to
// gliders-rb/gliders-rb.github.io by the site workflow.
const base = '/';
const site = 'https://gliders-rb.github.io';

const gemLink = (name) => ({
  icon: 'github',
  label: `${name} on GitHub`,
  href: `https://github.com/gliders-rb/gems/tree/main/gems/${name}`,
});

const fonts = [
  '@fontsource-variable/jetbrains-mono',
  '@fontsource-variable/instrument-sans',
  '@fontsource-variable/bricolage-grotesque',
];

export default defineConfig({
  base,
  site,
  integrations: [
    starlight({
      title: 'Gliders',
      description: 'Typed plain-Ruby objects and typed service objects, with every example run in CI.',
      logo: {
        alt: 'Gliders',
        light: './src/assets/brand/gliders-mark-light.svg',
        dark: './src/assets/brand/gliders-mark-dark.svg',
      },
      favicon: '/brand/favicon.svg',
      head: [{ tag: 'link', attrs: { href: '/brand/apple-touch-icon.png', rel: 'apple-touch-icon' } }],
      customCss: [...fonts, './src/styles/theme.css'],
      plugins: [starlightLlmsTxt(llmsOptions)],
      social: [gemLink('field_struct'), gemLink('actionable')],
      sidebar,
    }),
  ],
});

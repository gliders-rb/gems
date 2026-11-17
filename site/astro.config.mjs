import starlight from '@astrojs/starlight';
import starlightLlmsTxt from 'starlight-llms-txt';
import { defineConfig } from 'astro/config';
import { llmsOptions } from './src/config/llms.mjs';
import { sidebar } from './src/config/sidebar.mjs';

// Hosting values: the site is the gliders-rb org root, built from this repo and pushed to
// gliders-rb/gliders-rb.github.io by the site workflow.
const base = '/';
const site = 'https://gliders-rb.github.io';

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
      // The home page hero carries the code animation; every other page keeps Starlight's hero. The footer adds the
      // license note to every page.
      components: { Hero: './src/components/Hero.astro', Footer: './src/components/Footer.astro' },
      plugins: [starlightLlmsTxt(llmsOptions)],
      // One link to the monorepo; the home hero links each gem's own directory.
      social: [{ icon: 'github', label: 'Gliders on GitHub', href: 'https://github.com/gliders-rb/gems' }],
      sidebar,
    }),
  ],
});

import { docsSchema } from '@astrojs/starlight/schema';
import { docsLoader } from '@astrojs/starlight/loaders';
import { defineCollection } from 'astro:content';

const docs = defineCollection({
  schema: docsSchema(),
  loader: docsLoader(),
});

export const collections = { docs };

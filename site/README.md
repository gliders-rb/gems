# site

Docs for field_struct, actionable and their adapters, built with Astro 7.4.10 and Starlight 0.42.10. Both are pinned exactly in `package.json` and `package-lock.json`.

You need Node 22+ and Ruby 3.3+.

## Commands

Run each of these from `site/`:

```
npm ci                    # install, from the lockfile
npm run dev               # dev server at http://localhost:4321/gems/
npm run build             # static site into dist/
npm run preview           # serve dist/
bundle install            # once, for the code checker
bin/check-code-blocks     # run every `ruby run` fence (also: npm run check:code)
bin/check-links           # after a build: every internal link in src/content resolves to a built page (also: npm run check:links)
bin/brand-marks           # redraw the placeholder marks (needs npm ci first)
```

The site counts as done when `npm run build`, `bin/check-code-blocks` (both Gemfile lanes) and `bin/check-links` all exit 0.

## Checking code blocks

A fence runs when its language is `ruby` and its meta contains the word `run`:

````
```ruby run title="hut.rb"
Hut.new(name: 'Larch Col').valid?   # => true
```
````

A page's runnable blocks go through one fresh Ruby process in order, sharing classes and locals, while pages stay isolated from each other. `field_struct` and `actionable` come pre-required. Any line shaped like `expr # => expected` is asserted, and plain `ruby` fences are only displayed. Give file names to check just those pages.

`Gemfile` takes the gems from this repo by path. Pages under `adapters/` use `Gemfile.edge` instead, or whatever file `SITE_EDGE_GEMFILE` names, which adds the five adapters by path and the libraries those pages need (`json_schemer`, `opentelemetry-sdk`, `mcp`, `ruby_llm`). For the adapter pages, run `BUNDLE_GEMFILE=Gemfile.edge bundle install` once.

## Layout

- `src/content/docs/` - the pages. A section with no content yet holds a "Coming soon" stub.
- `src/styles/theme.css` - palette, fonts and the small components.
- `ec.config.mjs` - the code themes and the plugin that marks `# =>` results.
- `src/assets/brand/`, `public/brand/` - the Gliders marks (a rising coil for Gliders, top-view spirals with FS and Ac for the gems), drawn by `bin/brand-marks`. Run it again after changing a constant.

## Agent outputs

The `starlight-llms-txt` plugin emits `dist/llms.txt`, `llms-full.txt` and `llms-small.txt`, plus `field_struct-reference.txt`, `actionable-reference.txt` and `adapters.txt` under `dist/_llms-txt/`.

## Not deployed

The site is served at the gliders-rb org root, https://gliders-rb.github.io/, so `base` in `astro.config.mjs` is `/`. GitHub serves an org root only from a repo named `gliders-rb.github.io`, so the source stays here, where the runnable examples are checked against the same commit as the gems, and `.github/workflows/site.yml` pushes each build from `main` to `gliders-rb/gliders-rb.github.io` as one fresh commit. It uses the `SITE_DEPLOY_KEY` secret, a deploy key with write access to that repo only. The deploy job is skipped while this repo is private. To go live, make both repos public, then set the site repo's Pages source to the `main` branch, root folder.

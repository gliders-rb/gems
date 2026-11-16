# site

Docs for field_struct, actionable and their adapters, built with Astro 7.4.10 and Starlight 0.42.10. Both are pinned exactly in `package.json` and `package-lock.json`.

You need Node 22+ and Ruby 3.3+.

## Commands

Run each of these from `site/`:

```
npm ci                    # install, from the lockfile
npm run dev               # dev server at http://localhost:4321/
npm run build             # static site into dist/
npm run preview           # serve dist/
bundle install            # once, for the code checker
bin/check-code-blocks     # run every `ruby run` fence (also: npm run check:code)
bin/check-links           # after a build: every internal link in src/content resolves to a built page (also: npm run check:links)
bin/brand-marks           # redraw the placeholder marks (needs npm ci first)
npm run hero              # regenerate the home page animation from src/hero/storyboard.md
npm run check:hero        # the generator's specs, then: is every shown value asserted, are src/generated/ files current
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

## The home page animation

The figure beside the hero copy is generated from `src/hero/storyboard.md`. Its front matter is the timeline (beats, captions, which call each beat plays, the marks on the code), and its `ruby run` fences are the code the figure shows, checked by `bin/check-code-blocks` like any page. `bin/hero` refuses to render a value that isn't one of those asserted `# =>` lines.

```
bin/hero build                           # write src/generated/hero.html and hero.css (commit both)
bin/hero check                           # fail on an unbacked claim, stale generated files or stale README GIFs
bin/hero readme                          # the README's GIFs in public/hero/ and their stamp (commit all three)
bin/hero pdf out.pdf --pages pngs/       # the storyboard as a PDF, and each page as a PNG
bin/hero gif out.gif --theme light       # one round as a GIF (dark by default)
bin/hero video out.mp4                   # one round as a 4:5 MP4 for sharing, 1080 x 1350
npm run test:hero-browser                # build, then the stepper's behaviour in headless Chromium
```

`readme`, `pdf`, `gif` and `video` need a headless Chromium once: `npx playwright install --only-shell chromium`. It lands in Playwright's own cache, outside the repo; `npx playwright uninstall` removes it. `video` also needs ffmpeg on the PATH, or `FFMPEG=/path/to/ffmpeg`. The PDF, GIFs and video are frame-exact: each step change pauses the CSS transitions and moves them to the frame's time, so a slow machine makes the same file.

Each beat is one step of a stepper. The figure is static HTML that renders as its last step, the finished picture, and `src/components/Hero.astro` adds the controls (previous, the numbered steps, next, play/pause) and autoplay. Autoplay runs while the figure is mostly in view and the tab is visible, holds the last step for 6 s, plays three rounds and rests on the last step. Once the reader picks a step it stops for good; the play button restarts it. With reduced motion asked for there is no autoplay and no play button, but the steps still work; with scripts off the reader gets the finished picture and no controls.

## Agent outputs

The `starlight-llms-txt` plugin emits `dist/llms.txt`, `llms-full.txt` and `llms-small.txt`, plus `field_struct-reference.txt`, `actionable-reference.txt` and `adapters.txt` under `dist/_llms-txt/`.

## Not deployed

The site is served at the gliders-rb org root, https://gliders-rb.github.io/, so `base` in `astro.config.mjs` is `/`. GitHub serves an org root only from a repo named `gliders-rb.github.io`, so the source stays here, where the runnable examples are checked against the same commit as the gems, and `.github/workflows/site.yml` pushes each build from `main` to `gliders-rb/gliders-rb.github.io` as one fresh commit. It uses the `SITE_DEPLOY_KEY` secret, a deploy key with write access to that repo only. The deploy job is skipped while this repo is private. To go live, make both repos public, then set the site repo's Pages source to the `main` branch, root folder.

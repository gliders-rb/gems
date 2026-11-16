# actionable-docs

Turn an [actionable-rb](../../gems/actionable) action into a page someone outside the code can read: what it does,
in what order, why it can stop, and what happens after. The page is Markdown with one Mermaid flowchart, built from
the action's declarations and descriptions. A rake task writes the pages, and a check task fails when they drift.

```ruby
gem 'actionable-docs'
```

Version `1.0.0.pre1`. Ruby 3.3 or newer. Load it with `require 'actionable/docs'`.

## A page from an action

Give the action and its parts a `desc`, and the page uses those words. Anything without one gets words made from its
name.

```ruby run
require 'actionable/docs'

module Framing
  class MountPrint < Actionable::Action
    desc 'Mounts a customer print behind glass.'

    input { required :width_cm, :integer, desc: 'Width of the print' }

    fails :glass_chipped, 'the glass pane is chipped', retry: false

    step :cut_mat, desc: 'Cut the mat to size'
    step :fit_glass, if: :glass_ordered?

    private

    def glass_ordered? = true
    def cut_mat = nil
    def fit_glass = nil
  end
end

page = Actionable::Docs.markdown(Framing::MountPrint)

Actionable::Docs.title(Framing::MountPrint)      # => "Mount print"
Actionable::Docs.path_for(Framing::MountPrint)   # => "framing/mount_print.md"
page.lines.first                                 # => "# Mount print\n"
page.include?('2. Fit glass (only when glass ordered)') # => true
page.include?('- **Glass chipped**: the glass pane is chipped _(don\'t retry)_ `glass_chipped`') # => true
```

The page has, in order: the title and description, the flowchart, the numbered steps, "It can stop because" and
"It can finish early because" (the declared failures and skips), "What happens after" (the hooks), "What it needs"
and "What it produces" (the input and output fields), and "Also runs" for actions found in the source, then a
line saying the page is generated. Empty sections are left out.

In the chart, a child action is one box that links to its own page; it never opens up inline. A guard is a
decision, and a case step is a decision with one edge per branch. Failures and skips hang off Start, since
`describe` doesn't say which step ends with which code.

## Writing and checking pages

Every call needs a named class: an anonymous `Class.new(Actionable::Action)` raises `ArgumentError`.
`Docs.write(actions, dir:)` writes each page and returns the paths. `Docs.stale(actions, dir:)` returns the pages
that are missing or out of date, and writes nothing.

For a Rakefile:

```ruby
require 'actionable/docs/tasks'

Actionable::Docs::Tasks.define(actions: -> { [Framing::MountPrint] }, dir: 'docs/actions')
```

That gives you `rake actionable:docs` (write the pages) and `rake actionable:docs:check` (fail, listing the stale
pages, when they differ from fresh ones; run it in CI). Pass `actions:` as a lambda so your app's code loads first.
Only the actions you list get pages.

## What is and is not covered

- Headings are fixed English.
- No JSON output, no Rails view, and no per-step codes yet.
- A large action gives a large chart; nothing collapses it.

Signatures are in `sig/`.

## Docs

The guide on the docs site, with every example run in CI: https://gliders-rb.github.io/adapters/process-docs/
